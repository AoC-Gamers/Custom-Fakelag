"""Export an allowlisted, identifier-free view of private trial receipts.

Raw consoles, registry values and client records are deliberately not exported.
Module file hashes absent from a snapshot are measured at export and labelled.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_trial(path):
    r = json.loads(path.read_text(encoding='utf-8'))
    keys = ('row', 'scenario', 'repeat', 'state', 'server_pid', 'collector_pid',
            'production_source', 'base', 'collector_source_sha256', 'duration_requested', 'started', 'finished',
            'activity_started', 'quit_requested', 'humans_at_activity_start',
            'humans_before_disconnect_or_quit', 'humans_after_disconnect',
            'resolved_human_steam_identity', 'auth_validation_event',
            'effective_components', 'expected_components', 'server_exit_code',
            'server_exit_hex', 'win32_exit_code', 'process_handle_signaled',
            'exit_codes_agree', 'server_exit_seconds', 'who_terminated',
            'forced_termination', 'shutdown_timeout', 'runtime_sha256', 'environment')
    out = {k: r[k] for k in keys if k in r}
    out['trial_id'] = path.name.removesuffix('.state.json')
    out['raw_receipt_sha256'] = sha(path)
    out['registry_restored_verified'] = r.get('registry_original') == r.get('registry_restored')
    out['registry_window_seconds'] = r.get('registry_window_seconds')
    out['runtime_source'] = 'official dedicated bin/steamclient.dll'
    out['instrumentation'] = 'external read-only module/code snapshots; no debugger'
    out['exception'] = None  # Exit code alone is not an exception record.
    out['sequence'] = [{'time': e['time'], 'command': e['command']}
                       for e in r.get('events', [])
                       if e.get('command') and not e['command'].startswith('kickid ')]
    if r.get('scenario') == 'detached':
        out['disconnect_method'] = 'kickid of authenticated real client; zero humans verified'
    out['snapshots'] = {}
    for label in ('ready_observation', 'before_quit_observation'):
        if label not in r:
            continue
        snapshot = r[label]
        modules = []
        for m in snapshot['modules']:
            file = Path(m['path'])
            n = {'name': m['name'], 'base': hex(m['base']), 'bytes': m['bytes']}
            n['path_suffix'] = '/'.join(file.parts[-4:]) if 'addons' in str(file).lower() else m['name']
            if 'sha256' in m:
                n['sha256'] = m['sha256']; n['hash_observed'] = 'during trial'
            elif file.is_file():
                n['sha256'] = sha(file); n['hash_observed'] = 'at export'
            modules.append(n)
        out['snapshots'][label] = {'modules': modules, 'fill': snapshot['fill'], 'lag': snapshot['lag']}
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('private_trials', type=Path)
    p.add_argument('output', type=Path)
    a = p.parse_args()
    rows = [export_trial(f) for f in a.private_trials.glob('*.state.json')]
    rows.sort(key=lambda r: r['started'])
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps({'exported_utc': datetime.now(timezone.utc).isoformat(),
        'status': 'in_progress', 'trials': rows}, indent=2) + '\n', encoding='utf-8')
    for row in rows:
        print(row['trial_id'], row['state'], row.get('server_exit_hex'))


if __name__ == '__main__':
    main()
