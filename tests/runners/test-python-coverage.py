"""Measure canonical Python product sources and subprocesses, invoked via Make."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/helpers"))
import native_coverage as provenance


def product_lines(root, files):
    """Do not alias temporary copies or mutants to canonical production paths."""
    result = {}
    for name, data in files.items():
        path = (root / name).resolve()
        if not path.is_relative_to(root / "scripts") or path.suffix != ".py":
            continue
        executed = set(data["executed_lines"])
        result[path.relative_to(root).as_posix()] = {
            line: line in executed for line in executed | set(data["missing_lines"])}
    return result


def main():
    import coverage
    if coverage.__version__ != "7.13.5":
        raise ValueError("Run make deps-test-coverage for the pinned coverage.py")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    config = output / "coverage.ini"
    config.write_text("[run]\nsource = " + str(ROOT / "scripts") +
                      "\nparallel = True\npatch = subprocess\n" +
                      "data_file = " + str(output / ".coverage") +
                      "\n[report]\ninclude_namespace_packages = True\nexclude_lines =\n")
    start = provenance.source_state(ROOT)
    env = {k: v for k, v in os.environ.items() if not k.startswith("SONAR_")}
    env["PATH"] = str(Path(sys.executable).parent) + os.pathsep + env.get("PATH", os.defpath)
    command = [sys.executable, "-m", "coverage"]
    with (output / "tests.log").open("w") as log:
        subprocess.run([*command, "run", "--rcfile=" + str(config), str(ROOT / "tests/runners/coverage-python-suite.py")],
                       cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    for operation in (["combine", "--keep"], ["json", "-o", str(output / "python.json")]):
        subprocess.run([*command, operation[0], "--rcfile=" + str(config), *operation[1:]],
                       cwd=ROOT, env=env, check=True)
    payload = json.loads((output / "python.json").read_text())
    lines = product_lines(ROOT, payload["files"])
    expected = {p.relative_to(ROOT).as_posix() for p in (ROOT / "scripts").rglob("*.py")}
    if set(lines) != expected:
        raise ValueError("Coverage did not account for every canonical Python source")
    if provenance.source_state(ROOT) != start:
        raise ValueError("Sources changed during Python tests")
    report = output / "coverage.xml"
    provenance.write_report(report, lines)
    receipt = {"schema": 1, "kind": "python", "source_state": start,
               "report": report.name, "report_sha256": provenance.digest(report),
               "all_suites_passed": True, "coverage_version": coverage.__version__,
               "raw_data_sha256": provenance.digest(output / ".coverage"),
               "line_count": sum(len(rows) for rows in lines.values()),
               "covered_line_count": sum(sum(rows.values()) for rows in lines.values()),
               "runtime_acceptance": False}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"PYTHON_COVERAGE_OK {receipt['covered_line_count']}/{receipt['line_count']} canonical product lines")
    print("SONAR_PYTHON_COVERAGE_RECEIPT=" + str(output / "receipt.json"))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print("Python coverage failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
