#!/usr/bin/env python3
"""Drive the opt-in harness in an ALREADY isolated Linux SRCDS container.
No downloads, installations, host ports, production volumes or Steam clients.
This tests connectionless UDP input; it does not assert successful game login.
"""
import argparse
import atexit
import json
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
transport = parser.add_mutually_exclusive_group(required=True)
transport.add_argument('--container')
transport.add_argument('--srcds', type=Path, help='Native Windows srcds.exe (owned test process)')
parser.add_argument('--game', type=Path, help='Private gamedir with .custom-fakelag-isolated marker')
parser.add_argument('--log', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--source-port', type=int, default=28025)
parser.add_argument('--server-port', type=int, default=27025)
parser.add_argument('--extension-id', type=int, default=2)
parser.add_argument('--change-map', action='store_true')
args = parser.parse_args()
results = []
console = None
launch_log_offset = len(args.log.read_text(errors='replace')) if args.log.exists() else 0
if args.srcds:
    from windows_console import WindowsConsole
    if not args.game or not (args.game / '.custom-fakelag-isolated').is_file():
        parser.error('Native tests require an explicitly marked private gamedir')
    if not args.log.resolve().is_relative_to(args.game.resolve()):
        parser.error('Native test log must be inside the private gamedir')
    executable = args.srcds.resolve(strict=True)
    console = WindowsConsole([str(executable), '-console', '-insecure', '-ip', '127.0.0.1',
                              '-port', str(args.server_port), '-game', str(args.game.resolve()),
                              '+map', 'c1m1_hotel'], str(executable.parent))
    atexit.register(console.close)

def command(text):
    if console:
        console.command(text)
        return
    subprocess.run(['docker', 'exec', args.container, 'sh', '-c',
                    'printf "%s\\n" "$1" > /proc/1/fd/0', 'sh', text], check=True)

def wait_for(pattern, offset, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        text = args.log.read_text(errors='replace')[offset:] if args.log.exists() else ''
        match = re.search(pattern, text)
        if match:
            return match
        time.sleep(.1)
    raise RuntimeError('Timed out: ' + pattern)

def snapshot(stage='status', cmd='cf_probe_status'):
    offset = len(args.log.read_text(errors='replace')) if args.log.exists() else 0
    command(cmd)
    match = wait_for(r'\[engine_probe\] stage=' + stage + r' (.*)', offset)
    fields = dict(re.findall(r'(\w+)=([0-9.]+)', match[1]))
    return {name: float(value) if '.' in value else int(value) for name, value in fields.items()}

def profile(lag, loss):
    return snapshot('profile', f'cf_probe_profile {args.source_port} {lag} {loss}')

def send(count):
    if console:
        import socket
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1', args.source_port))
            for _ in range(count):
                sock.sendto(b'\xff' * 4 + b'getchallenge steam\n', ('127.0.0.1', args.server_port))
                time.sleep(.03)
        return
    # Real socket data traverses NET_ReceiveDatagram and the real detour.
    code = '''import socket,time,sys
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.bind(("127.0.0.1",int(sys.argv[1])))
for _ in range(int(sys.argv[3])):
 s.sendto(b"\\xff"*4+b"getchallenge steam\\n",("127.0.0.1",int(sys.argv[2])))
 time.sleep(.03)
'''
    subprocess.run(['docker', 'exec', args.container, 'python3', '-c', code,
                    str(args.source_port), str(args.server_port), str(count)], check=True)

def check(name, state, **expected):
    if any(state.get(key) != value for key, value in expected.items()):
        raise AssertionError((name, state, expected))
    results.append({'test': name, 'state': state})
    print(json.dumps(results[-1]), flush=True)

if console:
    wait_for('Packet adapter initialized', launch_log_offset, timeout=60)
command("sm_custom_fakelag_loss_mode 0")
snapshot()
profile(120, 0)
send(6)
time.sleep(.4)
state = snapshot()
check('latency-120ms', state, enabled=1, dispatched=6, loss=0, pending=0, bytes=0, restore_failed=0, invalid=0)
if not 120 <= state['mean_hold_ms'] < 300:
    raise AssertionError(('measured hold time', state))

profile(0, 100)
send(6)
check('bernoulli-loss-100', snapshot(), enabled=1, dispatched=0, loss=6, pending=0, bytes=0)
command('sm_custom_fakelag_loss_mode 1')
check('direct-convar-reset', snapshot(), enabled=0, pending=0, bytes=0, loss_states=0)
profile(0, 100)
send(6)
check('ge-loss-100', snapshot(), enabled=1, dispatched=0, loss=6, pending=0, bytes=0, loss_states=1)

profile(5000, 0)
send(4)
check('pending-before-reset', snapshot(), pending=4)
check('reset-pending', snapshot('reset', 'cf_probe_reset'), enabled=0, pending=0, bytes=0, lifecycle=4)

profile(5000, 0)
send(3)
check('pending-before-session-clear', snapshot(), pending=3)
check('session-clear', snapshot('clear', 'cf_probe_clear'), enabled=0, pending=0, bytes=0, lifecycle=3)
profile(120, 0)
send(3)
time.sleep(.4)
check('same-address-new-profile', snapshot(), dispatched=3, pending=0, restore_failed=0, invalid=0)

profile(5000, 0)
send(2)
check('pending-before-always-on', snapshot(), pending=2)
command('sm_custom_fakelag_detour_mode 1')
check('always-on-reset', snapshot(), enabled=1, pending=0, bytes=0, loss_states=0, lifecycle=2)
command('sm_custom_fakelag_detour_mode 0')
check('lazy-reset', snapshot(), enabled=0, pending=0, bytes=0)

if args.change_map:
    profile(5000, 0)
    send(2)
    check('pending-before-map-change', snapshot(), pending=2)
    offset = len(args.log.read_text(errors='replace'))
    command('changelevel c1m2_streets')
    wait_for('Mapchange to c1m2_streets', offset, timeout=90)
    check('map-change', snapshot(), enabled=0, pending=0, bytes=0, lifecycle=2)

profile(5000, 0)
send(2)
check('pending-before-unload', snapshot(), pending=2)
command(f'sm exts unload {args.extension_id}')
time.sleep(.5)
# Reload must restore a clean object and allow a new real patch to be installed.
offset = len(args.log.read_text(errors='replace'))
command('sm exts load custom_fakelag')
wait_for('Packet adapter initialized', offset)
check('reload-clean', snapshot(), enabled=0, pending=0, bytes=0, dispatched=0)
profile(120, 0)
send(3)
time.sleep(.4)
check('dispatch-after-unload-reload', snapshot(), dispatched=3, pending=0, restore_failed=0, invalid=0)
snapshot('clear', 'cf_probe_clear')
args.output.write_text(json.dumps({'kind': 'SRCDS real connectionless UDP; synthetic profile identity', 'results': results}, indent=2) + '\n')
