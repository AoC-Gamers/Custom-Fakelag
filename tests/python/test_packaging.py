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
        self.assertIn('addons/sourcemod/extensions/custom_fakelag.ext.so',linux)
        self.assertNotIn('addons/sourcemod/extensions/custom_fakelag.ext.dll',linux)
        self.assertIn('addons/sourcemod/extensions/custom_fakelag.ext.dll',windows)
        self.assertFalse(any('runtime/' in x or x.endswith('.sp') for x in linux))
