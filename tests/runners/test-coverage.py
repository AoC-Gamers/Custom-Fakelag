"""Fresh GCC x86 coverage from successful unmodified native tests, via Make."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/helpers"))
import native_coverage as coverage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-commands", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = {k: v for k, v in os.environ.items() if not k.startswith("SONAR_")}
    if any("clang" in env.get(k, "") for k in ("CXX", "CC", "AUTH_BINDING_CXX")):
        raise ValueError("This coverage target requires GCC/gcov, not Clang")
    env.update(CXX=env.get("CXX", "g++"), CC=env.get("CC", "gcc"),
               TEST_COVERAGE_FLAGS="--coverage -fprofile-abs-path")
    start = coverage.source_state(ROOT)
    flags = "-m32 --coverage -fprofile-abs-path"
    integration = output / "native-tests"
    env.update(TEST_BUILD_DIR=str(integration), TEST_ARCH="32", TEST_COVERAGE="1", SANITIZE="1")
    with (output / "integration.log").open("w") as log:
        subprocess.run(["make", "--no-print-directory", "-f", str(ROOT / "Makefile"), "test-exts-linux"],
                       cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    spec = importlib.util.spec_from_file_location("make_sonar", ROOT / "scripts/tools/make_sonar.py")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    entries = module.compilation_database(ROOT, args.compile_commands)
    baseline = output / "unexecuted-product"
    baseline.mkdir()
    merged = {}
    raw = output / "gcov-json"
    raw.mkdir()
    counters = coverage.positive_counters(integration)
    inputs = []
    for index, counter in enumerate(counters):
        payload = coverage.read_gcov(counter, ROOT)
        (raw / f"test-{index}.json").write_text(json.dumps(payload))
        coverage.merge_lines(ROOT, payload, merged)
        inputs.append({"counter": str(counter.relative_to(output)), "sha256": coverage.digest(counter)})
    # Compile the real product commands without executing them. Their gcno data
    # contributes actual executable zero-hit lines, never estimated hits.
    with (output / "baseline-build.log").open("w") as log:
        for index, entry in enumerate(entries):
            command = []
            args_iter = iter(entry["arguments"])
            for value in args_iter:
                if value in {"-o", "-MF", "-MT", "-MQ"}:
                    next(args_iter)
                elif value not in {"-MD", "-MMD", "-MP"}:
                    command.append(value)
            obj = baseline / f"unit-{index}.o"
            command += ["--coverage", "-fprofile-abs-path", "-O0", "-o", str(obj)]
            subprocess.run(command, cwd=entry["directory"], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            payload = coverage.read_gcov(obj.with_suffix(".gcno"), ROOT)
            (raw / f"baseline-{index}.json").write_text(json.dumps(payload))
            coverage.merge_lines(ROOT, payload, merged, baseline=True)
    if coverage.source_state(ROOT) != start:
        raise ValueError("Sources changed during instrumented tests")
    report = output / "coverage.xml"
    coverage.write_report(report, merged)
    receipt = {"schema": 1, "source_state": start, "report": report.name,
               "report_sha256": coverage.digest(report), "all_suites_passed": True,
               "test_flags": flags, "counter_inputs": inputs, "product_units": len(entries),
               "line_count": sum(len(rows) for rows in merged.values()),
               "covered_line_count": sum(sum(rows.values()) for rows in merged.values()),
               "negative_counters_included": False, "runtime_acceptance": False}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"COVERAGE_OK {receipt['covered_line_count']}/{receipt['line_count']} production lines; {len(counters)} positive counters")
    print("SONAR_COVERAGE_RECEIPT=" + str(output / "receipt.json"))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print("Coverage failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
