"""Export owned-session evidence with client identifiers and public IPs removed.

Summary observations are not an automatic acceptance decision. Review command
results and live functional checks alongside the retained sequence.
"""
import argparse
import ipaddress
import json
from pathlib import Path
import re

def redact(text, names=()):
    for name in names:
        text = text.replace(name, '[PLAYER]')
    # Remove whole identity events, including names, rather than just SteamIDs.
    lines = []
    for line in text.splitlines():
        if re.search(r'STEAM_[0-5]:[01]:\d+|\[[UA]:1:\d+\]|7656119\d{10}|steamid\s*:', line, re.I):
            lines.append('[client identity event redacted]'); continue
        if re.match(r'^#\s+\d+\s+\d+\s+"', line) or 'Client "' in line:
            lines.append('[client name event redacted]'); continue
        lines.append(line)
    text = '\n'.join(lines)
    def address(match):
        value = match.group()
        if value == '2.2.4.3': return value
        try: return '[WAN]' if ipaddress.ip_address(value).is_global else value
        except ValueError: return value
    return re.sub(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', address, text)

def module(row, name):
    return next((m for m in row.get('observation', {}).get('modules', [])
                 if m['name'].lower() == name), None)

def last_fields(console, marker):
    lines = [line for line in console.splitlines() if marker in line]
    if not lines: return None
    return dict(re.findall(r'([a-z_]+)=(-?[\d.]+)', lines[-1]))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--session', type=Path, action='append', required=True)
    p.add_argument('--sm-log', type=Path, required=True)
    p.add_argument('--identity-log', type=Path, help='Private console log used only to discover names to redact')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
    identity_text = a.identity_log.read_text(encoding='utf-8', errors='replace') if a.identity_log else ''
    # Include raw session output: names can also occur without an adjacent SteamID,
    # for example FinishClientPutInServer and a status row wrapped across lines.
    for path in a.session:
        identity_text += '\n'.join(json.loads(s).get('console', '')
                                   for s in path.read_text(encoding='utf-8').splitlines())
    names = set(re.findall(r'"([^"<>\r\n]+)<\d+><STEAM_', identity_text))
    names.update(re.findall(r'^#\s+\d+\s+\d+\s+"([^"\r\n]+)"', identity_text, re.M))
    names.update(re.findall(r'FinishClientPutInServer (.+?)\(\d+\):', identity_text))
    sessions = []
    for path in a.session:
        rows = [json.loads(s) for s in path.read_text(encoding='utf-8').splitlines()]
        patched = [r['observation']['fill']['bytes'] for r in rows
                   if r.get('observation', {}).get('fill', {}).get('bytes', '').startswith('e9')]
        unloads = []
        for i, row in enumerate(rows):
            if not row.get('command', '').startswith('sm exts unload '): continue
            previous = rows[i - 1]
            before = module(previous, 'custom_fakelag.ext.dll')
            if not before: continue
            observation = row.get('observation', {})
            unloads.append({'time': row['time'], 'pid': row['pid'], 'command': row['command'],
                'build_sha256': before.get('sha256'),
                'profile_before': last_fields(previous.get('console', ''), '[windows_api] human='),
                'counters_before': last_fields(previous.get('console', ''), '[engine_probe] stage='),
                'module_absent_after': module(row, 'custom_fakelag.ext.dll') is None,
                'lag_after': observation.get('lag'), 'fill_after': observation.get('fill')})
        sessions.append({'source': path.name, 'pid': rows[0]['pid'],
            'launch': rows[0], 'exit': rows[-1] if rows[-1].get('state') == 'stopped' else None,
            'patched_fill_observations': len(patched), 'distinct_patched_fill_bytes': sorted(set(patched)),
            'unloads': unloads})
        exported = []
        for row in rows:
            if 'console' in row: row['console'] = redact(row['console'], names)
            exported.append(json.dumps(row))
        (a.output / path.name).write_text('\n'.join(exported) + '\n', encoding='utf-8')
    (a.output / 'session-summary.json').write_text(json.dumps(sessions, indent=2), encoding='utf-8')
    text = a.sm_log.read_text(encoding='utf-8', errors='replace')
    # Only today's new load-order run; prior acceptance logs are separate artifacts.
    lines = [line for line in text.splitlines() if re.search(r' - (?:1[4-9]|2[0-3]):', line)]
    (a.output / 'sourcemod.log').write_text(redact('\n'.join(lines), names) + '\n', encoding='utf-8')
    events = [line for line in lines if '[windows_api]' in line or '[engine_probe]' in line or
              'Packet adapter accepted:' in line or 'Mapchange' in line]
    (a.output / 'functional-events.log').write_text(redact('\n'.join(events), names) + '\n', encoding='utf-8')
    print(json.dumps([{'pid': s['pid'], 'unloads': len(s['unloads']),
                       'fill_variants': len(s['distinct_patched_fill_bytes'])} for s in sessions]))

if __name__ == '__main__': main()
