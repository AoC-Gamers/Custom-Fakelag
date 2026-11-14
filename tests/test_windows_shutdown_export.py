"""Delivery must not export raw player/registry/address data or infer exceptions."""
import json
from pathlib import Path
import tempfile
import unittest
from export_windows_shutdown import export_trial

class ExportPrivacy(unittest.TestCase):
    def test_allowlist_and_numeric_observations(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'F_connected_1.state.json'
            path.write_text(json.dumps({'row': 'F', 'started': 1, 'state': 'collector_error',
                'scenario': 'detached', 'humans_after_disconnect': 1,
                'collector_error': 'Disconnect not confirmed',
                'registry_original': 'SECRET_REGISTRY', 'registry_restored': 'SECRET_REGISTRY',
                'player_name': 'PRIVATE_PLAYER', 'server_exit_code': 0xc0000005,
                'events': [{'time': 2, 'command': 'cf_shutdown_state',
                    'console': 'PRIVATE_PLAYER STEAM_1:1:123456 203.0.113.8\n'
                    '[shutdown] human=1 fake=0 supported=1 profiles=1 has=1 lag=120.000000 loss=10 mode=0\n'
                    'addr=203.0.113.8:27005 lag=120.0ms loss=10% queued=4 reason=lag_queue newdata=1'},
                    {'time': 3, 'command': 'status', 'console': 'map : c1m2_streets\nPRIVATE_PLAYER'},
                    {'time': 4, 'command': 'sv_lan', 'console': '"sv_lan" = "0"'},
                    {'time': 5, 'command': 'kickid 567 private_shutdown_trial'}]}))
            exported = export_trial(path); text = json.dumps(exported)
            for secret in ('PRIVATE_PLAYER', 'STEAM_1:', '203.0.113.8', 'SECRET_REGISTRY', 'kickid 567'):
                self.assertNotIn(secret, text)
            self.assertIsNone(exported['exception'])
            self.assertEqual(exported['server_exit_code'], 0xc0000005)
            self.assertEqual(exported['api_observations'][0]['profiles'], '1')
            self.assertEqual(exported['traffic_observations'][0]['queued'], '4')
            self.assertTrue(exported['registry_restored_verified'])
            self.assertFalse(exported['zero_humans_after_disconnect_verified'])
            self.assertEqual(exported['collector_error'], 'Disconnect not confirmed')
            self.assertEqual(exported['map_observations'][0]['map'], 'c1m2_streets')
            self.assertEqual(exported['lan_observations'][0]['value'], 0)

if __name__ == '__main__': unittest.main()
