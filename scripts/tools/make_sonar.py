"""Local Cppcheck and explicit SonarScanner entrypoints, invoked through Make."""
import argparse
import base64
import json
import importlib.util
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SETTINGS = {"SONAR_HOST_URL", "SONAR_PROJECT_KEY", "SONAR_PROJECT_NAME",
            "SONAR_QUALITY_GATE_WAIT", "SONAR_QUALITY_GATE_TIMEOUT",
            "SONAR_COMPILE_COMMANDS", "SONAR_CPPCHECK", "SONAR_SCANNER", "SONAR_COVERAGE_RECEIPT",
            "SONAR_PYTHON_COVERAGE_RECEIPT"}


class SonarError(Exception):
    pass


def setting(line):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        return None
    key, value = (part.strip() for part in line.split("=", 1))
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return key, value


def file_settings(path, allowed):
    if not path.is_file():
        return {}
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        pair = setting(line)
        if pair is None:
            continue
        key, value = pair
        if path.name == ".env" and key == "SONAR_TOKEN":
            raise SonarError("SONAR_TOKEN debe estar en .env.secret o en el entorno.")
        if key in allowed:
            values.setdefault(key, value)
    return values


def configuration(root, *, analyze=True):
    # Explicit environment wins; files remain data, never shell commands.
    env = os.environ.copy()
    for key, value in file_settings(root / ".env", SETTINGS).items():
        env.setdefault(key, value)
    if not analyze or "SONAR_TOKEN" in env:
        return env

    secret = root / ".env.secret"
    if secret.is_file() and os.name == "posix" and secret.stat().st_mode & 0o077:
        raise SonarError("Restringe los permisos del fichero de credenciales a 600.")
    env.update(file_settings(secret, {"SONAR_TOKEN"}))
    return env


def scanner_context(env):
    base = env.get("SONAR_HOST_URL", "").strip().rstrip("/")
    url = urlsplit(base)
    if (url.scheme not in {"https", "http"} or not url.hostname
            or url.username is not None or url.password is not None or url.query or url.fragment):
        raise SonarError("Configura SONAR_HOST_URL con una URL sin credenciales ni query.")
    if url.scheme == "http" and url.hostname not in {"localhost", "127.0.0.1", "::1"}:
        raise SonarError("Usa HTTPS para SonarQube; HTTP solo se admite en loopback.")
    if not env.get("SONAR_TOKEN", "").strip():
        raise SonarError("Falta SONAR_TOKEN en .env.secret o en el entorno.")
    wait = env.get("SONAR_QUALITY_GATE_WAIT", "true")
    timeout = env.get("SONAR_QUALITY_GATE_TIMEOUT", "300")
    if wait not in {"true", "false"} or not timeout.isdecimal() or int(timeout) < 1:
        raise SonarError("La espera del gate debe ser true/false y su timeout un entero positivo.")
    project = env.get("SONAR_PROJECT_KEY", "Custom-Fakelag")
    name = env.get("SONAR_PROJECT_NAME", "Custom-Fakelag")
    if not project.strip() or not name.strip():
        raise SonarError("SONAR_PROJECT_KEY y SONAR_PROJECT_NAME no pueden estar vacíos.")
    return base, project, name, wait, timeout


def product_unit(root, source):
    return (source.is_relative_to(root / "extension")
            and not source.is_relative_to(root / "extension/libudis86")
            and not source.is_relative_to(root / "extension/asm")) or source == root / "diagnostics/steam_lifecycle_debug/extension.cpp"


def compilation_entry(root, entry):
    directory = Path(entry["directory"])
    if not directory.is_absolute():
        raise SonarError("La base debe conservar directorios absolutos del build real.")
    source = (directory / entry["file"]).resolve()
    if not product_unit(root, source):
        return None
    args = entry.get("arguments")
    if args is None:
        args = shlex.split(entry["command"])
    if not isinstance(args, list) or not all(isinstance(v, str) for v in args) or "-m32" not in args:
        raise SonarError("El análisis requiere las órdenes reales de compilación x86 (-m32).")
    result = {**entry, "file": str(source), "arguments": args}
    result.pop("command", None)
    return result


def compilation_database(root, path):
    path = Path(path)
    if not path.is_absolute():
        path = root / path
    if not path.is_file():
        raise SonarError("Falta compile_commands.json; ejecuta make sonar-build primero.")
    entries = json.loads(path.read_text())
    if not isinstance(entries, list):
        raise SonarError("La base de compilación debe ser una lista.")
    selected = {}
    for entry in entries:
        normalized = compilation_entry(root, entry)
        if normalized is not None:
            selected[Path(normalized["file"])] = normalized
    expected = {p.resolve() for area in ("extension", "diagnostics") for p in (root / area).rglob("*")
                if p.suffix in {".c", ".cpp"} and product_unit(root, p.resolve())}
    if not expected or set(selected) != expected:
        raise SonarError("La base no cubre exactamente las unidades C/C++ del producto.")
    return list(selected.values())

def executable(name, root):
    if "/" in name or os.sep in name:
        name = str((root / name).resolve())
    result = shutil.which(name)
    if not result:
        raise SonarError(f"Falta {name} en PATH; instala las herramientas explícitamente.")
    return result


def compiler_query(entry):
    # Keep machine, language, feature, optimization and preprocessor flags.
    # Remove only source/output and dependency-file operations.
    command = [entry["arguments"][0]]
    args = iter(entry["arguments"][1:])
    for arg in args:
        if arg in {"-o", "-MF", "-MT", "-MQ"}:
            next(args)
        elif arg in {"-c", "-MD", "-MMD", "-MP"}:
            continue
        elif arg.startswith("-") or (Path(entry["directory"]) / arg).resolve() != Path(entry["file"]).resolve():
            command.append(arg)
    language = "c" if Path(entry["file"]).suffix == ".c" else "c++"
    return [*command, "-dM", "-E", "-v", "-x", language, "-"]


def implicit_includes(stderr, directory):
    includes = []
    searching = False
    for line in stderr.splitlines():
        text = line.strip()
        if text == "#include <...> search starts here:":
            searching = True
        elif text == "End of search list.":
            searching = False
        elif searching:
            path = (Path(directory) / text).resolve()
            if path.is_dir():
                includes.append(str(path))
    if not includes:
        raise SonarError("No se pudieron consultar los includes implícitos del compilador.")
    return includes


IDENTITY_MACROS = {"__GNUC__", "__GNUC_MINOR__", "__GNUC_PATCHLEVEL__", "__GNUG__",
             "__clang__", "__clang_major__", "__clang_minor__", "__clang_patchlevel__",
             "__linux__", "__linux", "linux", "__unix__", "__unix", "unix",
             "__i386__", "__i386", "i386", "__ILP32__", "_ILP32", "__ELF__",
             "__SIZEOF_POINTER__", "__SIZEOF_LONG__", "__SIZEOF_SIZE_T__"}


def query_context(command, directory, env):
    result = subprocess.run(command, input="", cwd=directory, env={**env, "LC_ALL": "C"},
                            capture_output=True, text=True)
    if result.returncode:
        raise SonarError("No se pudieron consultar las macros del compilador real.")
    macros = {name: value for name, value in re.findall(r"^#define (\w+) (\d+)$", result.stdout, re.M)
              if name in IDENTITY_MACROS}
    if "__GNUC__" not in macros and "__clang__" not in macros:
        raise SonarError("El análisis Linux requiere identidad GCC/Clang verificable.")
    predefined = dict(re.findall(r"^#define (\S+) (.*)$", result.stdout, re.M))
    return macros, predefined, implicit_includes(result.stderr, directory)


def append_identity(args, macros):
    for name, value in macros.items():
        if not any(a == "-D" + name or a.startswith("-D" + name + "=") or a == "-U" + name for a in args):
            args.append(f"-D{name}={value}")


def explicit_includes(entry):
    args = iter(entry["arguments"])
    for arg in args:
        option = next((x for x in ("-isystem", "-iquote", "-idirafter", "-I")
                       if arg == x or arg.startswith(x) and len(arg) > len(x)), None)
        if option is None:
            continue
        value = next(args, "") if arg == option else arg[len(option):]
        if value:
            yield str((Path(entry["directory"]) / value).resolve())


def header_context(entries, contexts):
    if not contexts:
        raise SonarError("La base debe incluir unidades C++ de la extensión.")
    common = dict(contexts[0][0])
    for macros, _ in contexts[1:]:
        common = {k: v for k, v in common.items() if macros.get(k) == v}
    directories = [directory for entry in entries for directory in explicit_includes(entry)]
    directories += [directory for _, includes in contexts for directory in includes]
    return {"file": "__global__", "defines": common,
            "includes": [p for p in dict.fromkeys(directories) if Path(p).is_dir()]}


def compiler_identity(entries, env):
    # Cache by full command and cwd: ordered macros and relative includes matter.
    cache = {}
    contexts = []
    for entry in entries:
        command = compiler_query(entry)
        key = (entry["directory"], *command)
        if key not in cache:
            cache[key] = query_context(command, entry["directory"], env)
        macros, predefined, includes = cache[key]
        if Path(entry["file"]).suffix != ".c":
            contexts.append((predefined, includes))
        append_identity(entry["arguments"], macros)
    return entries, header_context(entries, contexts)


def cxx_entry(entry):
    # GCC ignores nonexistent include directories. CXX throws instead. Keep the
    # original compiler/Cppcheck database intact; normalize only the CXX copy.
    args = iter(entry["arguments"])
    result = []
    for arg in args:
        option = next((x for x in ("-isystem", "-iquote", "-idirafter", "-I")
                       if arg == x or arg.startswith(x) and len(arg) > len(x)), None)
        if option:
            value = next(args) if arg == option else arg[len(option):]
            if not (Path(entry["directory"]) / value).is_dir():
                continue
            result.extend([arg, value] if arg == option else [arg])
        else:
            result.append(arg)
    return {**entry, "arguments": result}


def redact(text, token):
    if token:
        for secret in (token, base64.b64encode((token + ":").encode()).decode()):
            text = text.replace(secret, "[REDACTED]")
    return text


def validate_cppcheck(result, output, root, token):
    if result.returncode:
        diagnostic = output / "cppcheck.log"
        diagnostic.write_text(redact(result.stdout + result.stderr, token))
        raise SonarError(f"Cppcheck falló; diagnóstico en {diagnostic.relative_to(root)}. No se ejecutó SonarScanner.")
    try:
        xml = ET.fromstring(result.stderr)
        if xml.tag != "results" or xml.find("errors") is None:
            raise ValueError()
    except (ET.ParseError, ValueError):
        raise SonarError("Cppcheck no produjo un informe XML válido; scanner cancelado.") from None
    if any(e.get("id") in {"preprocessorErrorDirective", "syntaxError", "internalError", "cppcheckError"}
           for e in xml.findall("./errors/error")):
        diagnostic = output / "cppcheck.log"
        diagnostic.write_text(redact(result.stderr, token))
        raise SonarError(f"Análisis Cppcheck incompleto; diagnóstico en {diagnostic.relative_to(root)}. Scanner cancelado.")


def coverage_reports(root, env):
    reports = []
    for setting, kind in (("SONAR_COVERAGE_RECEIPT", "native"), ("SONAR_PYTHON_COVERAGE_RECEIPT", "python")):
        if not env.get(setting):
            continue
        spec = importlib.util.spec_from_file_location("native_coverage", root / "tests/helpers/native_coverage.py")
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        reports.append(str(module.validate_receipt(root, env[setting], kind=kind)))
    return reports


def run(action, default_database, root=ROOT):
    env = configuration(root, analyze=action == "analyze")
    context = scanner_context(env) if action == "analyze" else None
    if context:
        coverage_reports(root, env)
    cppcheck = executable(env.get("SONAR_CPPCHECK") or "cppcheck", root)
    scanner = executable(env.get("SONAR_SCANNER") or "sonar-scanner", root) if context else None
    entries = compilation_database(root, env.get("SONAR_COMPILE_COMMANDS") or default_database)
    local_env = {k: v for k, v in env.items() if not k.startswith("SONAR_")}
    entries, global_context = compiler_identity(entries, local_env)
    # Each run gets a private output directory. A failed run cannot reuse old XML.
    parent = root / ".build/sonar"
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
    database = output / "compile_commands.json"
    database.write_text(json.dumps(entries, indent=2) + "\n")
    cxx_database = output / "cxx-compilation.json"
    cxx_database.write_text(json.dumps([global_context, *(cxx_entry(e) for e in entries)], indent=2) + "\n")
    report = output / "cppcheck.xml"
    result = subprocess.run([cppcheck, f"--project={database}", "--platform=unix32",
                             "--enable=warning,style,performance,portability", "--xml", "--xml-version=2"],
                            cwd=root, env=local_env, capture_output=True, text=True)
    validate_cppcheck(result, output, root, env.get("SONAR_TOKEN", ""))
    report.write_text(result.stderr)
    print(f"[sonar] Informe Cppcheck: {report.relative_to(root)}", flush=True)
    if context is None:
        return
    base, project, name, wait, timeout = context
    reports = coverage_reports(root, env)
    coverage_options = ["-Dsonar.coverageReportPaths=" + ",".join(reports)] if reports else []
    # The token travels only in the scanner environment, never in argv/properties.
    result = subprocess.run([scanner, f"-Dsonar.host.url={base}", f"-Dsonar.projectKey={project}",
                             f"-Dsonar.projectName={name}",
                             f"-Dsonar.cxx.jsonCompilationDatabase={cxx_database}",
                             f"-Dsonar.cxx.cppcheck.reportPaths={report}",
                             f"-Dsonar.working.directory={output / 'scanner'}",
                             f"-Dsonar.qualitygate.wait={wait}", f"-Dsonar.qualitygate.timeout={timeout}", *coverage_options],
                            cwd=root, env={**env, "SONAR_HOST_URL": base}, capture_output=True, text=True)
    print(redact(result.stdout + result.stderr, env["SONAR_TOKEN"]))
    coverage_reports(root, env)
    if result.returncode or re.search(r"\bERROR\b", result.stdout + result.stderr):
        raise SonarError("SonarScanner, el parser CXX o el quality gate falló; consulta la salida saneada.")
    print("[sonar] SonarScanner completado" + (" y quality gate aprobado." if wait == "true" else "; gate no esperado."))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("analyze", "cppcheck"))
    parser.add_argument("--compile-commands", required=True)
    args = parser.parse_args()
    try:
        run(args.action, args.compile_commands)
    except (SonarError, OSError, ValueError, KeyError, TypeError):
        # Do not expose configuration values or subprocess output in a traceback.
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, SonarError) else "[sonar] Error local de configuración o ejecución.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
