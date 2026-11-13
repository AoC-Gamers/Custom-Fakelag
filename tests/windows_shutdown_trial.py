"""Private native SRCDS shutdown experiment. Does not modify product code.

Start a new process for one matrix row. Append @run to the empty command file
after connecting a real client (connected/detached scenarios). The idle scenario
runs automatically. All raw output is private and must be redacted for delivery.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import winreg
from windows_console import WindowsConsole
from windows_load_order_session import observe

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def configure(game, row):
    if not (game / '.custom-fakelag-isolated').is_file(): raise RuntimeError('Private marker missing')
    mm = game / 'addons/metamod.vdf'
    off = game / 'addons/metamod.vdf.shutdown-disabled'
    if row == 'A' and mm.exists(): mm.rename(off)
    if row != 'A' and off.exists(): off.rename(mm)
    sm = game / 'addons/sourcemod'
    for p in (sm / 'plugins').glob('*.smx'):
        target = sm / 'plugins/disabled' / p.name
        if target.exists(): raise RuntimeError('Refusing to overwrite plugin backup')
        p.rename(target)
    for name in ('custom_fakelag', 'dhooks'):
        p = sm / 'extensions' / (name + '.autoload')
        if p.exists(): p.unlink()
    if row in 'CDEFG': (sm / 'extensions/dhooks.autoload').touch()
    if row in 'EG': (sm / 'extensions/custom_fakelag.autoload').touch()
    # Load Left4DHooks explicitly after map readiness in D/F/G. In the initial
    # empty-server startup pilot its library was registered before its map-time
    # detours became active; that pilot is not an active-hook control.

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--row', choices=list('ABCDEFG'), required=True)
    p.add_argument('--scenario', choices=['connected', 'detached', 'idle'], required=True)
    p.add_argument('--repeat', type=int, required=True)
    p.add_argument('--commands', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--duration', type=float, default=15)
    p.add_argument('--ip', default='192.168.1.87')
    a = p.parse_args(); root = a.root.resolve(); game = root / 'left4dead2'
    if a.commands.exists() and a.commands.read_text(encoding='utf-8').strip(): p.error('Commands must be empty')
    a.commands.touch(); configure(game, a.row)
    log = game / 'console.log'; log_offset = len(log.read_bytes()) if log.exists() else 0
    result = {'row': a.row, 'scenario': a.scenario, 'repeat': a.repeat,
              'duration_requested': a.duration, 'started': time.time(),
              'production_source': '9c7debcf334ef534d715449b828e0c6d5fa67853',
              'base': '65031fb83da9b1ce9487237c3a19e83735c02686',
              'runtime_requested': str(a.runtime.resolve()), 'runtime_sha256': digest(a.runtime),
              'collector_source_sha256': digest(Path(__file__)),
              'events': [], 'who_terminated': None, 'forced_termination': False}
    state_path = a.output.with_suffix('.state.json')
    def save(state):
        result['state'] = state
        temporary = state_path.with_suffix('.tmp')
        temporary.write_text(json.dumps(result, indent=2), encoding='utf-8')
        temporary.replace(state_path)
    def event(kind, **data):
        row = {'time': time.time(), 'kind': kind, **data}
        result['events'].append(row)
        with a.output.open('a', encoding='utf-8') as f: f.write(json.dumps(row) + '\n')
    a.output.write_text('', encoding='utf-8')
    environment = dict(os.environ, SteamAppId='550', SteamGameId='222860',
                       SteamOverlayGameId='222860', SteamClientLaunch='1')
    result['environment'] = {k: environment[k] for k in ('SteamAppId','SteamGameId','SteamOverlayGameId','SteamClientLaunch')}
    argv = [str(root / 'srcds.exe'), '-console', '-condebug', '-insecure', '-ip', a.ip,
            '-port', '27025', '-game', 'left4dead2', '+map', 'c1m1_hotel']
    result['argv'] = argv
    console = None
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam\ActiveProcess', 0,
                             winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE)
        with key:
            original, value_type = winreg.QueryValueEx(key, 'SteamClientDll')
            result['registry_original'] = original
            selection_started = time.time()
            try:
                winreg.SetValueEx(key, 'SteamClientDll', 0, value_type, str(a.runtime.resolve()))
                console = WindowsConsole(argv, str(root), env=environment)
                result['server_pid'] = console.process.pid
                result['collector_pid'] = os.getpid()
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    modules = observe(console.process.pid)['modules']
                    runtime = next((m for m in modules if m['name'].lower() == 'steamclient.dll'), None)
                    if runtime:
                        result['runtime_loaded'] = runtime
                        break
                    if console.process.poll() is not None: raise RuntimeError('Server exited before runtime selection')
                    time.sleep(.05)
                else: raise RuntimeError('Runtime module not observed')
            finally:
                winreg.SetValueEx(key, 'SteamClientDll', 0, value_type, original)
                result['registry_restored'] = winreg.QueryValueEx(key, 'SteamClientDll')[0]
                result['registry_window_seconds'] = time.time() - selection_started
            if result['registry_restored'] != original: raise RuntimeError('Registry restoration failed')
        if Path(result['runtime_loaded']['path']).resolve() != a.runtime.resolve():
            raise RuntimeError('Wrong Steam runtime loaded')
        save('booting')
        def record(command):
            if command: console.command(command); time.sleep(.2)
            text = console.read_output()
            try: snapshot = observe(console.process.pid)
            except Exception as error: snapshot = {'error': str(error)}
            event('console', command=command, console=text, observation=snapshot)
            return text
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if console.process.poll() is not None: raise RuntimeError('Server exited during bootstrap')
            text = record('status')
            if re.search(r'map\s*:\s*c1m1_hotel', text): break
            time.sleep(.8)
        else: raise RuntimeError('Map readiness timeout')
        if a.row in 'DFG': record('sm plugins load disabled/windows_shutdown_fill_consumer')
        if a.row in 'DF': record('sm plugins load disabled/left4dhooks')
        if a.row in 'DF':
            deadline = time.monotonic() + 10
            while not observe(console.process.pid)['fill']['bytes'].startswith('e9'):
                if time.monotonic() > deadline: raise RuntimeError('Left4DHooks Fill detour activation timeout')
                time.sleep(.3)
        if a.row == 'F': record('sm exts load custom_fakelag')
        if a.row == 'G': record('sm plugins load disabled/left4dhooks')
        if a.row == 'G': time.sleep(2)
        for command in ('meta list', 'sm exts list', 'sm plugins list', 'status'): record(command)
        result['ready_observation'] = observe(console.process.pid)
        names = {m['name'].lower() for m in result['ready_observation']['modules']}
        effective = {'metamod': 'metamod.2.l4d2.dll' in names,
                     'sourcemod': 'sourcemod.2.l4d2.dll' in names,
                     'dhooks': 'dhooks.ext.dll' in names,
                     'custom_fakelag': 'custom_fakelag.ext.dll' in names,
                     'fill_detour': result['ready_observation']['fill']['bytes'].startswith('e9')}
        expected = {'metamod': a.row != 'A', 'sourcemod': a.row != 'A',
                    'dhooks': a.row in 'CDEFG', 'custom_fakelag': a.row in 'EFG',
                    'fill_detour': a.row in 'DFG'}
        result['effective_components'] = effective
        result['expected_components'] = expected
        if effective != expected: raise RuntimeError(f'Effective matrix row mismatch: {effective} != {expected}')
        event('ready', pid=console.process.pid)
        save('ready_for_client' if a.scenario != 'idle' else 'idle_ready')
        offset = 0; should_run = a.scenario == 'idle'
        while console.process.poll() is None:
            commands = a.commands.read_text(encoding='utf-8'); pending = commands[offset:]; offset = len(commands)
            for command in pending.splitlines():
                if command == '@run': should_run = True
                elif command == '@snapshot': record(None); save(result['state'])
                elif command.strip(): record(command); save(result['state'])
            if should_run:
                should_run = False
                text = record('status')
                matches = re.findall(r'players\s*:\s*(\d+) humans', text)
                humans = int(matches[-1]) if matches else None
                result['humans_at_activity_start'] = humans
                if a.scenario != 'idle' and humans != 1:
                    event('run_refused', reason='Exactly one human is required', humans=humans)
                    save('ready_for_client'); continue
                if a.scenario == 'idle' and humans != 0: raise RuntimeError('Idle scenario has a client')
                private_log = log.read_bytes()[log_offset:].decode('utf-8', errors='replace')
                result['resolved_human_steam_identity'] = bool(re.search(r'STEAM_[01]:[01]:\d+', text + private_log))
                result['auth_validation_event'] = 'STEAM USERID validated' in private_log
                if a.scenario != 'idle' and not (result['resolved_human_steam_identity'] and result['auth_validation_event']):
                    raise RuntimeError('Real Steam client authentication not confirmed')
                result['activity_started'] = time.time(); save('activity')
                time.sleep(a.duration)
                text = record('status')
                matches = re.findall(r'players\s*:\s*(\d+) humans', text)
                result['humans_before_disconnect_or_quit'] = int(matches[-1]) if matches else None
                if a.scenario != 'idle' and result['humans_before_disconnect_or_quit'] != 1:
                    raise RuntimeError('Human did not remain connected for the full activity interval')
                if a.scenario == 'detached':
                    users = re.findall(r'^#\s*(\d+)\s+\d+\s+".*?"\s+STEAM_[01]:[01]:\d+', text, re.M)
                    if not users: raise RuntimeError('Could not identify real human userid for disconnect')
                    record('kickid ' + users[-1] + ' private_shutdown_trial')
                    time.sleep(2)
                    text = record('status')
                    matches = re.findall(r'players\s*:\s*(\d+) humans', text)
                    result['humans_after_disconnect'] = int(matches[-1]) if matches else None
                    if result['humans_after_disconnect'] != 0: raise RuntimeError('Disconnect not confirmed')
                result['before_quit_observation'] = observe(console.process.pid)
                result['quit_requested'] = time.time(); result['who_terminated'] = 'server quit command'
                console.command('quit'); save('waiting_for_actual_exit')
                try: result['server_exit_code'] = console.process.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    result['shutdown_timeout'] = True; save('timeout_process_still_alive'); continue
                result['server_exit_seconds'] = time.time() - result['quit_requested']
                break
            time.sleep(.1)
        result['server_exit_code'] = console.process.wait(timeout=1)
        result['server_exit_hex'] = f"0x{result['server_exit_code'] & 0xffffffff:08x}"
        kernel = C.WinDLL('kernel32', use_last_error=True)
        kernel.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
        kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
        exit_code = W.DWORD()
        if not kernel.GetExitCodeProcess(int(console.process._handle), C.byref(exit_code)): raise C.WinError(C.get_last_error())
        result['win32_exit_code'] = exit_code.value
        result['process_handle_signaled'] = kernel.WaitForSingleObject(int(console.process._handle), 0) == 0
        result['exit_codes_agree'] = exit_code.value == (result['server_exit_code'] & 0xffffffff)
        result['finished'] = time.time()
        event('actual_process_exit', code=result['server_exit_code'], win32_code=exit_code.value,
              handle_signaled=result['process_handle_signaled'])
        (a.output.with_suffix('.console.log')).write_bytes(log.read_bytes()[log_offset:])
        save('exited')
        return 0
    except Exception as error:
        result['collector_error'] = str(error)
        result['server_still_alive'] = console is not None and console.process.poll() is None
        event('collector_error', error=str(error)); save('collector_error')
        # Never silently turn a collector error into a successful server exit,
        # and never force-kill a live server to make a failed trial look clean.
        return 1
    finally:
        if console:
            if console.input: console.kernel.CloseHandle(console.input)
            console.kernel.FreeConsole()

if __name__ == '__main__': raise SystemExit(main())
