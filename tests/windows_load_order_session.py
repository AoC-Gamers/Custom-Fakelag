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
    p.add_argument('--commands', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ip', required=True)
    a = p.parse_args()
    root = a.srcds.resolve().parent
    if not (root / 'left4dead2/.custom-fakelag-isolated').is_file(): p.error('Private marker required')
    if a.commands.exists() and a.commands.read_text(encoding='utf-8').strip(): p.error('Commands must start empty')
    a.commands.touch()
    c = WindowsConsole([str(a.srcds.resolve()), '-console', '-condebug', '-insecure',
                        '-ip', a.ip, '-port', '27025', '-game', 'left4dead2', '+map', 'c1m1_hotel'], str(root))
    def record(command):
        row = {'pid': c.process.pid, 'time': time.time(), 'command': command,
               'console': c.read_output()}
        try: row['observation'] = observe(c.process.pid)
        except Exception as error: row['observation_error'] = str(error)
        with a.output.open('a', encoding='utf-8') as f: f.write(json.dumps(row) + '\n')
    offset = 0
    try:
        with a.output.open('w', encoding='utf-8') as f:
            f.write(json.dumps({'pid': c.process.pid, 'state': 'started', 'time': time.time()}) + '\n')
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
