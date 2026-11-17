"""Export an allowlisted, identifier-free view of private trial receipts.

Raw consoles, registry values and client records are deliberately not exported.
Module file hashes absent from a snapshot are measured at export and labelled.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=None)
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
            'forced_termination', 'shutdown_timeout', 'runtime_sha256', 'environment',
            'collector_error', 'server_still_alive', 'shutdown_trigger')
    out = {k: r[k] for k in keys if k in r}
    out['trial_id'] = path.name.removesuffix('.state.json')
    out['raw_receipt_sha256'] = sha(path)
    out['registry_restored_verified'] = r.get('registry_original') == r.get('registry_restored')
    out['registry_window_seconds'] = r.get('registry_window_seconds')
    out['runtime_source'] = ('official dedicated bin/steamclient.dll' if r.get('runtime_sha256') ==
        'b593058386086c3c1feecf9a9228f43872419bcb5ab7e45662cfbf7a9fe6993f' else 'experimental runtime; see annotation and hash')
    out['instrumentation'] = 'external read-only module/code snapshots; no debugger'
    out['collector_exit_code'] = None  # Not independently retained by the detached launcher.
    out['debugger_exit_code'] = None
    out['exception'] = None  # Exit code alone is not an exception record.
    annotation = path.with_name(path.name.replace('.state.json', '.annotation.json'))
    if annotation.is_file():
        notes = json.loads(annotation.read_text(encoding='utf-8-sig'))
        for key in ('experiment_label', 'instrumentation', 'debugger_exit_code', 'experimental_variables',
                    'evidence_references', 'limitations', 'outcome_note', 'interruption_note',
                    'exception', 'first_chance_exception', 'supplemental_exit'):
            if key in notes: out[key] = notes[key]
    out['sequence'] = [{'time': e['time'], 'command': e['command']}
                       for e in r.get('events', [])
                       if e.get('command') and not e['command'].startswith('kickid ')]
    # Extract numeric observations, never whole log lines containing addresses.
    text = '\n'.join(e.get('console', '') for e in r.get('events', []))
    out['authentication_event_in_console'] = 'STEAM USERID validated' in text
    out['map_observations'] = []
    out['lan_observations'] = []
    for e in r.get('events', []):
        if e.get('command') == 'status':
            maps = re.findall(r'map\s*:\s*(\w+)', e.get('console', ''))
            if maps: out['map_observations'].append({'time': e['time'], 'map': maps[-1]})
        if e.get('command') == 'sv_lan':
            values = re.findall(r'"sv_lan"\s*=\s*"([01])"', e.get('console', ''))
            if values: out['lan_observations'].append({'time': e['time'], 'value': int(values[-1])})
    api_pattern = r'\[shutdown\] human=(\d+) fake=(\d+) supported=(\d+) profiles=(\d+) has=(\d+) lag=([\d.]+) loss=(\d+) mode=(\d+)'
    api_pattern = api_pattern.replace(' ', r'\s+')  # Native console wraps long lines.
    out['api_observations'] = [dict(zip(('human_slot', 'fake', 'supported', 'profiles', 'has', 'lag_ms', 'loss_percent', 'mode'), match))
                               for match in re.findall(api_pattern, text)]
    traffic_pattern = r'lag=([\d.]+)ms loss=(\d+)% queued=(\d+) reason=(lag_queue|packet_loss) newdata=1'
    traffic_pattern = traffic_pattern.replace(' ', r'\s+')
    out['traffic_observations'] = [dict(zip(('lag_ms', 'loss_percent', 'queued', 'reason'), match))
                                   for match in re.findall(traffic_pattern, text)]
    out['code_observations'] = [{'time': e['time'], 'command': e['command'],
                                'fill': e['observation'].get('fill'), 'lag': e['observation'].get('lag'),
                                'custom_fakelag_loaded': any(m['name'].lower() == 'custom_fakelag.ext.dll' for m in e['observation'].get('modules', []))}
                               for e in r.get('events', []) if e.get('command') and e.get('observation')
                               and not e['command'].startswith('kickid ')]
    if r.get('scenario') == 'detached':
        out['disconnect_method'] = 'kickid of authenticated real client'
        out['zero_humans_after_disconnect_verified'] = r.get('humans_after_disconnect') == 0
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
    p.add_argument('--status', choices=('in_progress', 'complete_with_documented_limits'), default='in_progress')
    a = p.parse_args()
    rows = [export_trial(f) for f in a.private_trials.glob('*.state.json')]
    rows.sort(key=lambda r: r['started'])
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps({'exported_utc': datetime.now(timezone.utc).isoformat(),
        'status': a.status, 'trials': rows}, indent=2) + '\n', encoding='utf-8')
    for row in rows:
        print(row['trial_id'], row['state'], row.get('server_exit_hex'))


if __name__ == '__main__':
    main()
