import tempfile
import unittest
from pathlib import Path
from verify_windows_engine import scan, verify


class VerifierTests(unittest.TestCase):
    def test_ambiguous_and_overlapping_signatures(self):
        self.assertEqual(scan(b'\x55\x8b\x01\x55\x8b\x02', b'\x55\x8b\x2a'), [0, 3])
        self.assertEqual(scan(b'aaaa', b'aaa'), [0, 1])
        self.assertEqual(scan(b'\x55\x8b', b'\x55\x8b\x2a'), [])

    def test_unknown_identity_rejected_before_pe_parse(self):
        with tempfile.TemporaryDirectory() as directory:
            module = Path(directory) / 'engine.dll'
            for data in (b'', b'MZ' + bytes(256), b'\x7fELF' + bytes(256)):
                module.write_bytes(data)
                with self.assertRaisesRegex(ValueError, 'Unsupported SHA-256'):
                    verify(module)


if __name__ == '__main__':
    unittest.main()
