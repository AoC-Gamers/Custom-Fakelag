#!/usr/bin/env python3
"""Run production SourcePawn sources in an already isolated SRCDS container.
Requires tests/integration/plugin_regressions.sp compiled and installed in a marked private
GAME directory, never the production player_fakelag plugin. No install/network.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--game', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; supply a new evidence path")
    game = args.game.resolve(strict=True)
    if not (game / '.custom-fakelag-isolated').is_file():
        parser.error('Expected a marked private gamedir')
    # Check container identity and isolation before issuing mutations.
    info = json.loads(subprocess.check_output(['docker', 'inspect', args.container]))[0]
    if info['HostConfig']['NetworkMode'] != 'none':
        parser.error('The regression container must use --network none')
    if any(m.get('Type') == 'volume' and m.get('RW') for m in info['Mounts']):
        parser.error('Existing volumes must be mounted read-only')
    log = game / 'console.log'
    def read():
        return log.read_text(errors='replace') if log.exists() else ''
    def wait(pattern, offset, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = read()[offset:]
            if match := re.search(pattern, text):
                return match
            time.sleep(.1)
        raise RuntimeError('Timeout: ' + pattern + '\n' + read()[offset:][-2500:])
    def command(text, pattern, timeout=30):
        offset = len(read())
        subprocess.run(['docker', 'exec', args.container, 'sh', '-c',
                        'printf "%s\\n" "$1" > /proc/1/fd/0', 'sh', text], check=True)
        return wait(pattern, offset, timeout)

    wait(r'\[plugin_test\] map-start timer=1 count=0', 0)
    command('sm config ServerLang en', r'Config option.*ServerLang.*set to.*en')
    start = len(read())
    error_offsets = {p: len(p.read_text(errors='replace'))
                     for p in (game / 'addons/sourcemod/logs').glob('errors_*.log')}
    match = command('cf_plugin_test', r'\[plugin_test\] COMPLETE checks=(\d+)')
    checks = int(match[1])
    table_checks = {}
    for language in ('en', 'es'):
        command('sm config ServerLang ' + language, r'Config option.*ServerLang.*set to.*' + language)
        result = command('cf_plugin_tables', r'\[table_test\] COMPLETE checks=(\d+) language=\d+')
        table_checks[language] = int(result[1])
    command('sm config ServerLang en', r'Config option.*ServerLang.*set to.*en')
    command('cf_plugin_sampling', r'\[plugin_test\] SAMPLING COMPLETE reads=\d+')
    for map_name in ('c1m2_streets', 'c1m1_hotel'):
        command('changelevel ' + map_name, r'\[plugin_test\] map-end timer=0', timeout=45)
        # Map-start might already be in the buffer after the map-end response.
        wait(r'\[plugin_test\] map-start timer=1 count=0', read().rfind('[plugin_test] map-end'), timeout=45)
        command('cf_plugin_sampling', r'\[plugin_test\] SAMPLING COMPLETE reads=\d+')
    for _ in range(2):
        command('sm plugins unload plugin_regressions', r'\[SM\] Plugin Per-Player Fakelag unloaded successfully')
        command('sm plugins load plugin_regressions', r'\[plugin_test\] map-start timer=1 count=0')
        command('cf_plugin_sampling', r'\[plugin_test\] SAMPLING COMPLETE reads=\d+')
    # Fail on unexpected SourcePawn exceptions, even if an earlier assertion passed.
    exceptions = []
    for p in (game / 'addons/sourcemod/logs').glob('errors_*.log'):
        text = p.read_text(errors='replace')[error_offsets.get(p, 0):]
        exceptions += re.findall(r'Exception reported: (.*)', text)
    expected = ('plugin_test EXPECTED injected ', 'Clear-all failed (SourcePawn error ')
    unexpected = [e for e in exceptions if not e.startswith(expected)]
    if unexpected:
        raise RuntimeError('Unexpected SourcePawn exceptions: ' + repr(unexpected))
    lines = [line for line in read()[start:].splitlines() if line.startswith(('[plugin_test]', '[table_test]'))]
    evidence = {
        'kind': 'Real SourceMod VM/timers/forwards/RequestFrame; mock clients and CFakeLag native transport',
        'source_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'harness_sha256': hashlib.sha256(Path('.build/plugin-regressions/plugin_regressions.smx').read_bytes()).hexdigest(),
        'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True)),
        'checks_in_suite': checks,
        'table_checks': table_checks,
        'sampling_runs': sum('SAMPLING COMPLETE' in line for line in lines),
        'map_changes': 2, 'reloads': 2,
        'expected_exceptions': exceptions, 'unexpected_exceptions': unexpected,
        'trace': lines,
        'pending': 'Steam human sessions, real packet effects/LAN integration, Windows and actual BuiltinVotes extension',
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + '\n')
    print(f'PASS checks={checks} tables={table_checks} sampling=5 maps=2 reloads=2 (isolated consumer tests)')


if __name__ == '__main__':
    main()
