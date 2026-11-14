"""Regressions for sanitized exports and interpretation of readable stale chains."""
import json
from pathlib import Path
import tempfile
import unittest
from export_windows_steam_debug import export
from summarize_steam_trace import summarize


class SteamDebugTools(unittest.TestCase):
    def test_export_uses_latest_status_without_private_console(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root / 'private'; source.mkdir()
            status = ('hostname: old\nmap : c1m1_hotel\nplayers : 2 humans\n'
                      '# 2 1 "OLD_NAME" STEAM_1:0:123 00:10 10 0 active\n'
                      'hostname: current\nmap : c1m2_streets\nplayers : 1 humans\n'
                      '# 9 1 "PRIVATE_NAME" STEAM_1:1:456 00:10 10 0 active\n')
            (source / 'state.json').write_text(json.dumps({
                'id': 'C1_fixture', 'row': 'C', 'sv_lan': 1,
                'registry_original': 'PRIVATE_REGISTRY', 'registry_restored': 'PRIVATE_REGISTRY',
                'events': [{'kind': 'console', 'command': 'status', 'console': status},
                           {'kind': 'console', 'command': 'kickid 9 reason', 'userid': 9}]
            }))
            result = export(source, root / 'public')
            self.assertEqual(result['events'][0]['status'], {
                'map': 'c1m2_streets', 'humans': 1,
                'authenticated_humans': 1, 'active_authenticated_humans': 1})
            for secret in ('OLD_NAME', 'PRIVATE_NAME', 'STEAM_1:', 'PRIVATE_REGISTRY', 'kickid 9'):
                self.assertNotIn(secret, json.dumps(result))
            self.assertTrue(result['registry_restored_exactly'])

    def test_readable_chain_outside_steam_is_retained_as_observation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'trace.log'
            records = []
            for seq, healthy in ((1, True), (3, False)):
                records.append(f'unix=1 elapsed_ms={seq} seq={seq} event=sample sv_lan=1 context=identified_windows_server identified=1')
                state = 1 if healthy else 0
                records.append(f'unix=1 elapsed_ms={seq} seq={seq+1} event=context_field offset=4 object=0x1000 vtable=0x2000 method=0x3000 reads=7 vtable_in_steam={state} method_in_steam={state} method_executable={state}')
            path.write_text('\n'.join(records) + '\n')
            result = summarize([path]); field = result['fields']['4']
            self.assertEqual(result['identified_snapshots'], 2)
            self.assertEqual(field['first_nonsteam_after_steam_chain']['reads'], '7')
            self.assertEqual(field['first_nonsteam_after_steam_chain']['parent_snapshot']['seq'], '3')
            self.assertIn('do not alone prove', result['limits'])

    def test_export_rejects_unexpected_sensitive_trace(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root / 'private'; source.mkdir()
            (source / 'state.json').write_text(json.dumps({'id': 'fixture', 'events': []}))
            (source / 'trace.log').write_text('token=PRIVATE_TOKEN\n')
            with self.assertRaises(AssertionError):
                export(source, root / 'public')


if __name__ == '__main__':
    unittest.main()
