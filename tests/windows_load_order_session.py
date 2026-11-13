"""Own a private SRCDS and record commands plus read-only module/code observations.

Append server commands to the initially empty UTF-8 command file. @wait N waits
at most ten seconds; @snapshot records without sending a command. No remote
process memory is written. Raw evidence can contain client identifiers: redact
it before sharing.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import os
from pathlib import Path
import time
from windows_console import WindowsConsole
from datetime import datetime

class OwnedSteamProcess:
    """Adopt only a new dedicated process matching our saved launch receipt."""
    def __init__(self, pid, expected_path, receipt):
        self.pid = pid
        self.k = C.WinDLL('kernel32', use_last_error=True)
        self.k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
        self.k.OpenProcess.restype = W.HANDLE
        self.k.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
        self.k.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
        self.k.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
        self.handle = self.k.OpenProcess(0x101001, False, pid)
        if not self.handle: raise C.WinError(C.get_last_error())
        self.k.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
        text = C.create_unicode_buffer(32768); size = W.DWORD(len(text))
        if not self.k.QueryFullProcessImageNameW(self.handle, 0, text, C.byref(size)):
            raise C.WinError(C.get_last_error())
        if Path(text.value).resolve() != expected_path.resolve(): raise RuntimeError('Owned executable mismatch')
        times = [W.FILETIME() for _ in range(4)]
        self.k.GetProcessTimes.argtypes = [W.HANDLE] + [C.POINTER(W.FILETIME)] * 4
        if not self.k.GetProcessTimes(self.handle, *(C.byref(t) for t in times)):
            raise C.WinError(C.get_last_error())
        created = ((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime) / 1e7 - 11644473600
        if created < datetime.fromisoformat(receipt['started_utc']).timestamp():
            raise RuntimeError('Refusing a process predating the owned Steam launch')
    def poll(self):
        code = W.DWORD()
        if not self.k.GetExitCodeProcess(self.handle, C.byref(code)): raise C.WinError(C.get_last_error())
        return None if code.value == 259 else code.value
    def wait(self, timeout):
        if self.k.WaitForSingleObject(self.handle, int(timeout * 1000)) != 0:
            import subprocess
            raise subprocess.TimeoutExpired(str(self.pid), timeout)
        return self.poll()
    def terminate(self): self.k.TerminateProcess(self.handle, 1)

def attach_owned(process):
    c = WindowsConsole.__new__(WindowsConsole)
    c.kernel = C.WinDLL('kernel32', use_last_error=True)
    c.kernel.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, W.LPVOID, W.DWORD, W.DWORD, W.HANDLE]
    c.kernel.CreateFileW.restype = W.HANDLE
    from windows_console import InputRecord
    c.kernel.WriteConsoleInputW.argtypes = [W.HANDLE, C.POINTER(InputRecord), W.DWORD, C.POINTER(W.DWORD)]
    c.kernel.CloseHandle.argtypes = [W.HANDLE]
    c.kernel.AttachConsole.argtypes = [W.DWORD]
    c.process = process; c.input = None
    c.kernel.FreeConsole()
    if not c.kernel.AttachConsole(process.pid): raise C.WinError(C.get_last_error())
    return c

class Module(C.Structure):
    _fields_ = [('size', W.DWORD), ('id', W.DWORD), ('pid', W.DWORD),
                ('global_usage', W.DWORD), ('usage', W.DWORD), ('base', C.c_void_p),
                ('bytes', W.DWORD), ('handle', W.HMODULE),
                ('name', W.WCHAR * 256), ('path', W.WCHAR * 260)]

class Region(C.Structure):
    _fields_ = [('base', C.c_void_p), ('allocation', C.c_void_p),
                ('allocation_protect', W.DWORD), ('partition', W.WORD),
                ('bytes', C.c_size_t), ('state', W.DWORD),
                ('protect', W.DWORD), ('kind', W.DWORD)]

def observe(pid):
    k = C.WinDLL('kernel32', use_last_error=True)
    k.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    k.CreateToolhelp32Snapshot.restype = W.HANDLE
    k.Module32FirstW.argtypes = k.Module32NextW.argtypes = [W.HANDLE, C.POINTER(Module)]
    k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    k.OpenProcess.restype = W.HANDLE
    k.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
    k.VirtualQueryEx.argtypes = [W.HANDLE, C.c_void_p, C.POINTER(Region), C.c_size_t]
    k.VirtualQueryEx.restype = C.c_size_t
    k.CloseHandle.argtypes = [W.HANDLE]
    snap = k.CreateToolhelp32Snapshot(0x18, pid)
    modules = []
    entry = Module(); entry.size = C.sizeof(entry)
    try:
        ok = k.Module32FirstW(snap, C.byref(entry))
        while ok:
            modules.append({'name': entry.name, 'path': entry.path,
                            'base': entry.base, 'bytes': entry.bytes})
            ok = k.Module32NextW(snap, C.byref(entry))
    finally:
        k.CloseHandle(snap)
    result = {'modules': modules}
    engine = next((m for m in modules if m['name'].lower() == 'engine.dll'), None)
    process = k.OpenProcess(0x410, False, pid)
    try:
        if engine and process:
            for name, rva in [('fill', 0x133cb0), ('lag', 0x1c9ba0)]:
                address = engine['base'] + rva
                data = (C.c_ubyte * 6)(); read = C.c_size_t()
                if not k.ReadProcessMemory(process, address, data, 6, C.byref(read)) or read.value != 6:
                    raise C.WinError(C.get_last_error())
                site = {'address': address, 'bytes': bytes(data).hex()}
                if data[0] == 0xe9:
                    target = (address + 5 + int.from_bytes(bytes(data)[1:5], 'little')) & 0xffffffff
                    region = Region()
                    queried = k.VirtualQueryEx(process, target, C.byref(region), C.sizeof(region))
                    site.update(target=target, query_bytes=queried, state=region.state,
                                protect=region.protect, region_base=region.base,
                                region_bytes=region.bytes,
                                target_outside_engine=not engine['base'] <= target < engine['base'] + engine['bytes'])
                result[name] = site
            result['net_time_address'] = engine['base'] + 0x6b2b48
        for m in modules:
            if m['name'].lower() == 'engine.dll' or 'custom_fakelag' in m['name'].lower() or 'dhooks' in m['name'].lower():
                m['sha256'] = hashlib.sha256(Path(m['path']).read_bytes()).hexdigest()
    finally:
        if process: k.CloseHandle(process)
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--srcds', type=Path, required=True)
    p.add_argument('--game', type=Path, help='Marked private gamedir; defaults to executable sibling left4dead2')
    p.add_argument('--commands', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ip', required=True)
    p.add_argument('--owned-pid', type=int, help='New process created by our recorded Steam app launch')
    p.add_argument('--launch-receipt', type=Path)
    a = p.parse_args()
    root = a.srcds.resolve().parent
    game = (a.game or root / 'left4dead2').resolve()
    if not (game / '.custom-fakelag-isolated').is_file(): p.error('Private marker required')
    if a.commands.exists() and a.commands.read_text(encoding='utf-8').strip(): p.error('Commands must start empty')
    a.commands.touch()
    # Distinguish the dedicated tool from the desktop game in Steam tracking.
    # The game's auth AppId must remain 550 (222860 rejects real client tickets).
    # Never edit global env, registry or the desktop client's files.
    environment = dict(os.environ, SteamAppId='550', SteamGameId='222860',
                       SteamOverlayGameId='222860', SteamClientLaunch='1')
    game_argument = os.path.relpath(game, root) if game.drive.lower() == root.drive.lower() else str(game)
    if a.owned_pid:
        if not a.launch_receipt: p.error('Owned Steam process requires its launch receipt')
        c = attach_owned(OwnedSteamProcess(a.owned_pid, a.srcds, json.loads(a.launch_receipt.read_text(encoding='utf-8'))))
    else:
        c = WindowsConsole([str(a.srcds.resolve()), '-console', '-condebug', '-insecure',
                            '-ip', a.ip, '-port', '27025', '-game', game_argument, '+map', 'c1m1_hotel'], str(root), env=environment)
    def record(command):
        row = {'pid': c.process.pid, 'time': time.time(), 'command': command,
               'console': c.read_output()}
        try: row['observation'] = observe(c.process.pid)
        except Exception as error: row['observation_error'] = str(error)
        with a.output.open('a', encoding='utf-8') as f: f.write(json.dumps(row) + '\n')
    offset = 0
    try:
        with a.output.open('w', encoding='utf-8') as f:
            f.write(json.dumps({'pid': c.process.pid, 'state': 'started', 'time': time.time(),
                                'launch_mode': 'owned Steam app launch' if a.owned_pid else 'direct',
                                'child_environment': None if a.owned_pid else {k: environment[k] for k in
                                    ('SteamAppId', 'SteamGameId', 'SteamOverlayGameId', 'SteamClientLaunch')},
                                'srcds': str(a.srcds.resolve()), 'game': str(game)}) + '\n')
        while c.process.poll() is None:
            commands = a.commands.read_text(encoding='utf-8')
            pending = commands[offset:]; offset = len(commands)
            for command in pending.splitlines():
                if not command.strip(): continue
                if command.startswith('@wait '): time.sleep(min(10, max(0, float(command.split()[1]))))
                elif command != '@snapshot': c.command(command); time.sleep(.7)
                record(command)
            time.sleep(.1)
    finally:
        with a.output.open('a', encoding='utf-8') as f:
            f.write(json.dumps({'pid': c.process.pid, 'state': 'stopped', 'exit_code': c.process.poll()}) + '\n')
        c.close()

if __name__ == '__main__': main()
