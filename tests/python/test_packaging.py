import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/package'))
import artifact_contract as c

class PackageTests(unittest.TestCase):
    def test_unsafe_paths(self):
        for value in ('../x','/x','a/../x','a\\x','a//b'):
            with self.assertRaises(ValueError): c.relative(value)
    def test_missing_extra_and_wrong_architecture(self):
        with patch.object(c, 'inventory', return_value={'x.so'}):
            for files in ({}, {'x.so':b'', 'extra':b''}, {'x.so':b'MZ'}):
                with self.assertRaises(ValueError): c.validate(files,'linux')
    def test_platform_inventory(self):
        linux=c.inventory('linux');windows=c.inventory('windows')
        self.assertIn('addons/sourcemod/extensions/custom_fakelag.ext.2.l4d2.so',linux)
        self.assertNotIn('addons/sourcemod/extensions/custom_fakelag.ext.2.l4d2.dll',linux)
        self.assertIn('addons/sourcemod/extensions/custom_fakelag.ext.2.l4d2.dll',windows)
        self.assertFalse(any('runtime/' in x or x.endswith('.sp') for x in linux))

    def test_legacy_binary_is_not_installable(self):
        expected = c.inventory('linux')
        legacy = 'addons/sourcemod/extensions/custom_fakelag.ext.so'
        files = dict.fromkeys(expected, b'')
        files[legacy] = files.pop('addons/sourcemod/extensions/custom_fakelag.ext.2.l4d2.so')
        with self.assertRaisesRegex(ValueError, 'Artifact mismatch'):
            c.validate(files, 'linux')

    def test_observer_accepts_canonical_and_historical_names(self):
        from export_windows_load_order import module
        for name in ('custom_fakelag.ext.dll', 'custom_fakelag.ext.2.l4d2.dll'):
            record = {'name': name}
            self.assertIs(module({'observation': {'modules': [record]}}, 'custom_fakelag.ext.dll'), record)
        self.assertIsNone(module({'observation': {'modules': [{'name': 'other.dll'}]}}, 'custom_fakelag.ext.dll'))

    def test_truncated_native_headers_are_rejected(self):
        for payload in (b'', b'\x7fELF\x01\x01', b'MZ'+bytes(62)):
            with self.assertRaises(ValueError): c.validate_elf(payload)
            with self.assertRaises(ValueError): c.validate_pe(payload)
        pe = bytearray(64); pe[:2] = b'MZ'; pe[60:64] = (65535).to_bytes(4,'little')
        with self.assertRaises(ValueError): c.validate_pe(pe)

    def test_native_headers_validate_machine_and_optional_header(self):
        # Exercise both installer architectures on any host, including PE32
        # success and rejection after a valid DOS/PE signature.
        elf = bytearray(20)
        elf[:6] = b'\x7fELF\x01\x01'
        elf[18:20] = (3).to_bytes(2, 'little')
        c.validate_elf(elf)
        elf[18:20] = (62).to_bytes(2, 'little')
        with self.assertRaisesRegex(ValueError, 'ELF32 i386'):
            c.validate_elf(elf)
        pe = bytearray(90)
        pe[:2] = b'MZ'
        pe[60:64] = (64).to_bytes(4, 'little')
        pe[64:68] = b'PE\0\0'
        pe[68:70] = (0x14c).to_bytes(2, 'little')
        pe[88:90] = (0x10b).to_bytes(2, 'little')
        c.validate_pe(pe)
        pe[88:90] = (0x20b).to_bytes(2, 'little')
        with self.assertRaisesRegex(ValueError, 'PE32 i386'):
            c.validate_pe(pe)
