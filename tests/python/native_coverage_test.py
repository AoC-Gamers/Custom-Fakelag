"""Coverage accounting, provenance guards and a real GCC i386 counter smoke test."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_coverage", ROOT / "tests/helpers/native_coverage.py")
coverage = importlib.util.module_from_spec(spec); spec.loader.exec_module(coverage)


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="native coverage ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "extension").mkdir()
        self.source = self.root / "extension/unit.cpp"
        self.source.write_text("int first;\nint second;\nint third;\n")

    def payload(self, rows, path="extension/unit.cpp"):
        return {"current_working_directory": str(self.root), "files": [{"file": path, "lines": rows}]}

    def receipt(self):
        report = self.root / "coverage.xml"
        coverage.write_report(report, {"extension/unit.cpp": {1: True, 2: False}})
        receipt = {"schema": 1, "source_state": coverage.source_state(self.root),
                   "report": report.name, "report_sha256": coverage.digest(report),
                   "all_suites_passed": True, "test_flags": "-m32 --coverage -fprofile-abs-path"}
        path = self.root / "receipt.json"
        path.write_text(json.dumps(receipt))
        return path, receipt

    def test_compiler_zero_lines_remain_uncovered_and_variants_merge(self):
        result = {}
        coverage.merge_lines(self.root, self.payload([{"line_number": 1, "count": 0}, {"line_number": 2, "count": 0}]), result, baseline=True)
        coverage.merge_lines(self.root, self.payload([{"line_number": 2, "count": 4}]), result)
        coverage.merge_lines(self.root, self.payload([{"line_number": 2, "count": 0}]), result)
        self.assertEqual(result, {"extension/unit.cpp": {1: False, 2: True}})

    def test_invalid_lines_and_fake_baseline_hits_are_rejected(self):
        for row in ({"line_number": 4, "count": 1}, {"line_number": 1, "count": -1},
                    {"line_number": True, "count": 1}):
            with self.assertRaises(ValueError): coverage.merge_lines(self.root, self.payload([row]), {})
        with self.assertRaises(ValueError):
            coverage.merge_lines(self.root, self.payload([{"line_number": 1, "count": 2}]), {}, baseline=True)

    def test_no_test_or_external_file_is_misrepresented_as_product(self):
        result = {}
        coverage.merge_lines(self.root, self.payload([{"line_number": 1, "count": 8}], "tests/test.cpp"), result)
        self.assertEqual(result, {})
        with self.assertRaises(ValueError): coverage.write_report(self.root / "bad.xml", result)

    def test_report_and_sources_are_bound(self):
        path, receipt = self.receipt()
        self.assertEqual(coverage.validate_receipt(self.root, path), self.root / "coverage.xml")
        self.source.write_text(self.source.read_text() + "int changed;\n")
        with self.assertRaises(ValueError): coverage.validate_receipt(self.root, path)

    def test_tampered_report_and_failed_tests_are_rejected(self):
        path, receipt = self.receipt()
        (self.root / "coverage.xml").write_text("changed")
        with self.assertRaises(ValueError): coverage.validate_receipt(self.root, path)
        path, receipt = self.receipt()
        receipt['all_suites_passed'] = False; path.write_text(json.dumps(receipt))
        with self.assertRaises(ValueError): coverage.validate_receipt(self.root, path)

    def test_negative_control_binaries_do_not_contribute(self):
        header = bytearray(32); header[:5] = b'\x7fELF\x01'; header[18:20] = b'\x03\x00'
        (self.root/'custom_fakelag_tests').write_bytes(header)
        counter = self.root/'custom_fakelag_tests-source.gcda'; counter.write_bytes(b'counter')
        (self.root/'mutant-source.gcda').write_bytes(b'mutant')
        self.assertEqual(coverage.positive_counters(self.root), [counter])
        counter.unlink()
        with self.assertRaises(ValueError): coverage.positive_counters(self.root)

    def test_real_gcc_x86_counters_distinguish_executed_and_unexecuted(self):
        self.source.write_text('int never() { return 13; }\nint main() { return 0; }\n')
        binary = self.root / 'smoke'
        subprocess.run(['g++','-m32','--coverage','-fprofile-abs-path','-O0',str(self.source),'-o',str(binary)], check=True, capture_output=True)
        subprocess.run([str(binary)],check=True)
        counter = next(self.root.glob('smoke-*.gcda'))
        data = coverage.read_gcov(counter, self.root)
        rows = {}; coverage.merge_lines(self.root, data, rows)
        self.assertFalse(rows['extension/unit.cpp'][1]); self.assertTrue(rows['extension/unit.cpp'][2])
        self.assertEqual(binary.read_bytes()[:5], b'\x7fELF\x01')


if __name__ == '__main__': unittest.main(verbosity=2)
