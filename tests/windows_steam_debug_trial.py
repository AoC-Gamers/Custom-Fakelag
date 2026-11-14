"""Own one isolated Windows trial; raw evidence stays private until sanitized.

Use --row A/B/C --lan 0/1 --id UNIQUE. Connect the real client when state says
ready_for_client or ready_for_reconnect. The collector retains its child handle
through DLL teardown, including error/modal states. It never patches memory.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import winreg
import zipfile
from windows_console import WindowsConsole
from windows_load_order_session import observe
from windows_shutdown_trial import actual_exit, digest

BASE = '070a71b1b7d64dc8cdc4cc6bcfaaab11cb5c28e4'

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--data', type=Path, required=True)
    p.add_argument('--dll', type=Path, required=True)
    p.add_argument('--row', choices=['A','B','C'], required=True)
    p.add_argument('--lan', type=int, choices=[0,1], required=True)
    p.add_argument('--id', required=True)
    p.add_argument('--preflight', action='store_true')
    p.add_argument('--gate-before-map', action='store_true', help='Pause after activity for an owned debugger attachment')
    a = p.parse_args()
    root = a.root.resolve(); game = root / 'left4dead2'
    assert (game / '.custom-fakelag-isolated').is_file()
    directory = a.data / a.id
    directory.mkdir(parents=True, exist_ok=False)
    statefile = directory / 'state.json'
    commands = directory / 'commands.txt'; commands.touch()
    sm = game / 'addons/sourcemod'
    mm = game / 'addons/metamod.vdf'; off = mm.with_suffix('.vdf.steam-debug-disabled')
    if a.row == 'A' and mm.exists(): mm.rename(off)
    if a.row != 'A' and off.exists(): off.rename(mm)
    assert not list((sm / 'plugins').glob('*.smx')), 'Optional plugins must be disabled'
    assert not list((sm / 'extensions').glob('*.autoload')), 'No optional autoload allowed'
    if a.row == 'C': shutil.copy2(a.dll, sm / 'extensions' / a.dll.name)
    with zipfile.ZipFile(a.data.parent / 'original-cfg-addons.zip') as backup:
        original_cfg = backup.read('cfg/server.cfg')
    cfg, changes = re.subn(rb'(?m)^(sv_lan[ \t]+)[01]([ \t]*\r?$)',
        lambda m: m[1] + str(a.lan).encode('ascii') + m[2], original_cfg)
    assert changes == 1, 'Expected one sv_lan assignment in original private cfg'
    (game / 'cfg/server.cfg').write_bytes(cfg)
    trace = sm / 'logs/steam_lifecycle_debug/trace.log'
    for suffix in ('', '.1'):
        file = Path(str(trace)+suffix)
        if file.exists(): file.rename(directory / ('previous-trace.log'+suffix))
    consolelog = game / 'console.log'
    logoffset = consolelog.stat().st_size if consolelog.exists() else 0
    result = dict(id=a.id, row=a.row, sv_lan=a.lan, base=BASE, started=time.time(),
        collector_source_sha256=digest(__file__), diagnostic_sha256=digest(a.dll),
        runtime_requested=str(a.runtime.resolve()), runtime_sha256=digest(a.runtime),
        events=[], forced_termination=False, debugger=False, preflight=a.preflight)
    result['cfg_sha256'] = hashlib.sha256(cfg).hexdigest()
    result['original_cfg_sha256'] = hashlib.sha256(original_cfg).hexdigest()
    result['cfg_only_sv_lan_changed'] = True
    result['source_revision'] = subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip()
    result['activity_definition'] = 'Authenticated real client remains spawned in gameplay with normal networking for 15 seconds; no scripted movement or packet emulator.'
    result['fixed_hashes'] = {name:digest(path) for name,path in {
        'srcds.exe':root/'srcds.exe','engine.dll':root/'bin/engine.dll',
        'server.dll':game/'bin/server.dll','steam_api.dll':root/'bin/steam_api.dll'}.items()}
    def save(state):
        result['state'] = state
        tmp = statefile.with_suffix('.tmp')
        tmp.write_text(json.dumps(result, indent=2), encoding='utf-8'); tmp.replace(statefile)
    def event(kind, **data):
        item = dict(time=time.time(), kind=kind, **data)
        result['events'].append(item)
        with (directory/'events.jsonl').open('a',encoding='utf-8') as f: f.write(json.dumps(item)+'\n')
    console = None
    kernel = C.WinDLL('kernel32', use_last_error=True)
    kernel.WaitForSingleObject.argtypes = [W.HANDLE,W.DWORD]
    def alive(): return console is not None and kernel.WaitForSingleObject(int(console.process._handle),0)==258
    def rawlog():
        return consolelog.read_bytes()[logoffset:].decode('utf-8','replace') if consolelog.exists() else ''
    def record(command=None):
        if not alive(): raise RuntimeError('Child exited before command '+str(command))
        if command: console.command(command); time.sleep(.25)
        text = console.read_output()
        snap = observe(console.process.pid)
        event('console', command=command, console=text, observation=snap)
        return text
    def humans(text):
        counts = re.findall(r'players\s*:\s*(\d+) humans',text)
        return int(counts[-1]) if counts else None
    def authenticated():
        text=record('status')
        resolved=bool(re.search(r'^#\s*\d+\s+\d+\s+".*?"\s+STEAM_[01]:[01]:\d+',text,re.M))
        return humans(text)==1 and resolved and 'STEAM USERID validated' in rawlog()
    def wait_client(stage, new_auth_count):
        save(stage)
        deadline=time.monotonic()+600
        while alive():
            if rawlog().count('STEAM USERID validated')>=new_auth_count and authenticated():
                event('authenticated_client', phase=stage, humans=1, validated=True)
                return
            if time.monotonic()>deadline: raise TimeoutError('Real client timeout')
            time.sleep(1)
        raise RuntimeError('Child exited while waiting for client')
    def activity(phase):
        start=time.time(); save(phase)
        for _ in range(15):
            if not alive(): raise RuntimeError('Child exited during activity')
            time.sleep(1)
        text=record('status')
        if humans(text)!=1: raise RuntimeError('Real client did not stay for activity')
        event('activity_verified', phase=phase, seconds=time.time()-start, humans=1)
    def wait_map(name):
        deadline=time.monotonic()+60
        while alive():
            text=record('status')
            maps=re.findall(r'map\s*:\s*(\S+)',text)
            if maps and maps[-1]==name: return text
            if time.monotonic()>deadline: raise TimeoutError('Map readiness timeout')
            time.sleep(1)
        raise RuntimeError('Child exited while loading map')
    def verify_lan(phase):
        text=record('sv_lan')
        values=re.findall(r'"sv_lan"\s*=\s*"([01])"',text)
        if not values or int(values[-1])!=a.lan: raise RuntimeError('Actual sv_lan mismatch')
        event('lan_verified',phase=phase,value=int(values[-1]))
    def preflight():
        def trace_bytes(): return trace.read_bytes() if trace.exists() else b''
        default=record('sm_steam_lifecycle_debug')
        if not re.search(r'"sm_steam_lifecycle_debug"\s*=\s*"2"',default): raise RuntimeError('Default is not 2')
        time.sleep(1)
        if b'context=identified_windows_server identified=1' not in trace_bytes(): raise RuntimeError('Server identity not recognized')
        record('sm_steam_lifecycle_debug 0'); before=trace_bytes(); time.sleep(2)
        record('changelevel c1m2_streets'); wait_map('c1m2_streets'); time.sleep(2)
        if trace_bytes()!=before: raise RuntimeError('Mode 0 wrote during frames/map events')
        event('mode_zero_stable',bytes=len(before),sha256=hashlib.sha256(before).hexdigest(),map_event=True)
        record('sm_steam_lifecycle_debug 1'); before=trace_bytes(); time.sleep(12)
        if trace_bytes()!=before: raise RuntimeError('Mode 1 sampled frames')
        record('changelevel c1m1_hotel'); wait_map('c1m1_hotel')
        if len(trace_bytes())<=len(before): raise RuntimeError('Mode 1 did not log map events')
        event('mode_one_verified',no_frame_samples=True, map_events=True)
        record('sm_steam_lifecycle_debug 2'); before=trace_bytes(); time.sleep(12)
        if b'event=sample' not in trace_bytes()[len(before):]: raise RuntimeError('Mode 2 heartbeat absent')
        event('mode_two_verified',heartbeat=True)
        record('sm_steam_lifecycle_debug 0'); before=trace_bytes(); time.sleep(2)
        listing=record('sm exts list')
        ids=re.findall(r'^\[(\d+)\] Steam Lifecycle Debug \(',listing,re.M)
        if not ids: raise RuntimeError('Actual diagnostic extension id not found')
        record('sm exts unload '+str(int(ids[-1])))
        names={m['name'].lower() for m in observe(console.process.pid)['modules']}
        if a.dll.name.lower() in names: raise RuntimeError('DLL still loaded after unload')
        query=record('sm_steam_lifecycle_debug')
        if 'Unknown command "sm_steam_lifecycle_debug"' not in query: raise RuntimeError('ConVar survived unload')
        record('changelevel c1m2_streets'); wait_map('c1m2_streets'); time.sleep(2)
        if trace_bytes()!=before: raise RuntimeError('Unloaded observer wrote trace')
        event('unload_verified',actual_id=int(ids[-1]),module_absent=True,convar_absent=True,trace_stable=True)
        record('sm exts load steam_lifecycle_debug'); query=record('sm_steam_lifecycle_debug')
        if not re.search(r'"sm_steam_lifecycle_debug"\s*=\s*"2"',query): raise RuntimeError('Reload default is not 2')
        event('reload_verified',default=2)
    try:
        env=dict(os.environ,SteamAppId='550',SteamGameId='222860',SteamOverlayGameId='222860',SteamClientLaunch='1')
        result['environment']={k:env[k] for k in ('SteamAppId','SteamGameId','SteamOverlayGameId','SteamClientLaunch')}
        argv=[str(root/'srcds.exe'),'-console','-condebug','-insecure','-ip','192.168.1.87','-port','27025','-game','left4dead2','+map','c1m1_hotel']
        result['argv']=argv
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\Valve\Steam\ActiveProcess',0,winreg.KEY_QUERY_VALUE|winreg.KEY_SET_VALUE) as key:
            original,typ=winreg.QueryValueEx(key,'SteamClientDll'); result['registry_original']=original
            selection=time.time()
            try:
                winreg.SetValueEx(key,'SteamClientDll',0,typ,str(a.runtime.resolve()))
                console=WindowsConsole(argv,str(root),env=env)
                result['server_pid']=console.process.pid; result['collector_pid']=os.getpid();save('booting')
                deadline=time.monotonic()+15
                while alive():
                    runtime=next((m for m in observe(console.process.pid)['modules'] if m['name'].lower()=='steamclient.dll'),None)
                    if runtime: result['runtime_loaded']=runtime; break
                    if time.monotonic()>deadline: raise TimeoutError('Steam module timeout')
                    time.sleep(.1)
                else: raise RuntimeError('Child exited before runtime loaded')
            finally:
                winreg.SetValueEx(key,'SteamClientDll',0,typ,original)
                result['registry_restored']=winreg.QueryValueEx(key,'SteamClientDll')[0]
                result['registry_window_seconds']=time.time()-selection
            assert result['registry_restored']==original
        assert Path(result['runtime_loaded']['path']).resolve()==a.runtime.resolve()
        wait_map('c1m1_hotel'); verify_lan('initial')
        if a.row=='C':
            record('sm exts load steam_lifecycle_debug')
            query = record('sm_steam_lifecycle_debug')
            if not re.search(r'"sm_steam_lifecycle_debug"\s*=\s*"2"',query): raise RuntimeError('Default is not 2')
            result['observer_mode'] = 2
        for command in ('meta list','sm exts list','sm plugins list','status'): record(command)
        snapshot=observe(console.process.pid); result['ready_observation']=snapshot
        names={m['name'].lower() for m in snapshot['modules']}
        effective={'mm':'metamod.2.l4d2.dll' in names,'sm':'sourcemod.2.l4d2.dll' in names,
            'observer':a.dll.name.lower() in names,'cf':'custom_fakelag.ext.dll' in names,'dh':'dhooks.ext.dll' in names}
        expected=dict(mm=a.row!='A',sm=a.row!='A',observer=a.row=='C',cf=False,dh=False)
        result['effective_components']=effective
        assert effective==expected,(effective,expected)
        if a.preflight:
            wait_client('ready_for_client',1)
            preflight();result['quit_requested']=time.time();console.command('quit');save('waiting_for_actual_exit')
        else:
            wait_client('ready_for_client',1);activity('initial_activity')
            if a.gate_before_map:
                save('ready_for_debugger_before_map')
                deadline=time.monotonic()+600
                while alive() and '@map' not in commands.read_text():
                    if time.monotonic()>deadline: raise TimeoutError('Debugger gate timeout')
                    time.sleep(.2)
                event('debugger_gate_released')
            event('changelevel_requested',map='c1m2_streets');record('changelevel c1m2_streets')
            wait_map('c1m2_streets');verify_lan('after_changelevel');activity('map_activity')
            text=record('status')
            # Console snapshots include previous commands in their scrollback.
            # Parse only the latest status response, never count stale rows.
            latest=text.rsplit('hostname:',1)[-1]
            users=re.findall(r'^#\s*(\d+)\s+\d+\s+".*?"\s+STEAM_[01]:[01]:\d+',latest,re.M)
            if len(users)!=1: raise RuntimeError('Exactly one authenticated userid required for kick')
            event('kick_requested',userid=int(users[0]));record('kickid '+users[0]+' private_steam_lifecycle_trial')
            save('after_kick');time.sleep(3)
            if alive():
                text=record('status')
                if humans(text)!=0: raise RuntimeError('Kick did not leave zero humans')
                event('disconnect_verified',humans=0)
                wait_client('ready_for_reconnect',2);activity('reconnected_activity')
                result['quit_requested']=time.time();record('sv_lan');console.command('quit');save('waiting_for_actual_exit')
        deadline=time.monotonic()+90
        while alive():
            if time.monotonic()>deadline:
                event('shutdown_timeout');save('timeout_process_still_alive');break
            time.sleep(.1)
        if alive(): raise TimeoutError('Shutdown has not completed')
    except Exception as error:
        result['collector_error']=str(error);event('collector_error',error=str(error));save('collector_error_alive' if alive() else 'collector_error_exited')
        # Keep our real handle while a modal/teardown remains alive. A supervisor
        # may request quit, but never convert timeout or forced exit into PASS.
        offset=0
        while alive():
            content=commands.read_text();pending=content[offset:];offset=len(content)
            for command in pending.splitlines():
                if command=='@quit': record('quit');result['supervisor_quit_requested']=time.time()
                elif command=='@snapshot': record();save(result['state'])
            time.sleep(.5)
    finally:
        if console and not alive():
            console.process.wait(timeout=1); result.update(actual_exit(console.process));result['finished']=time.time()
            event('actual_process_exit',code=result.get('server_exit_hex'),handle_signaled=result.get('process_handle_signaled'))
            (directory/'console.log').write_text(rawlog(),encoding='utf-8')
            for suffix in ('','.1'):
                file=Path(str(trace)+suffix)
                if file.exists(): shutil.copy2(file,directory/('trace.log'+suffix))
            save('exited')
        if console:
            if console.input: console.kernel.CloseHandle(console.input)
            console.kernel.FreeConsole()
    return 1 if 'collector_error' in result else 0

if __name__=='__main__': raise SystemExit(main())
