"""Read the hash-specific server context implicated by the historical AV.

Only an owned receipt-matching process is accepted. No process memory is written.
The structure identity is a hypothesis; offsets follow the actual disassembly.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from windows_load_order_session import OwnedSteamProcess, observe

SERVER_HASH = 'a93ec916a8f26fbea85688c321d2ba8dd346d435fab09a0b926dd950c2e1ea12'

def snapshot(receipt):
    owned = OwnedSteamProcess(receipt['server_pid'], Path(receipt['argv'][0]),
        {'started_utc': datetime.fromtimestamp(receipt['started'], timezone.utc).isoformat()})
    read_handle = None
    try:
        if owned.poll() is not None: raise RuntimeError('Owned process has exited')
        modules = observe(owned.pid)['modules']
        server = next(m for m in modules if m['name'].lower() == 'server.dll')
        digest = hashlib.sha256(Path(server['path']).read_bytes()).hexdigest()
        if digest != SERVER_HASH: raise RuntimeError('Unrecognized server.dll; offsets refused')
        k = owned.k
        read_handle = k.OpenProcess(0x410, False, owned.pid)
        if not read_handle: raise C.WinError(C.get_last_error())
        read_errors = []
        k.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
        def read(address, size):
            data = (C.c_ubyte * size)(); done = C.c_size_t()
            if not k.ReadProcessMemory(read_handle, address, data, size, C.byref(done)) or done.value != size:
                read_errors.append({'address': address, 'size': size, 'winerror': C.get_last_error()})
                return None
            return bytes(data)
        def pointer(address):
            data = read(address, 4)
            return int.from_bytes(data, 'little') if data is not None else None
        def location(address):
            if address is None: return None
            module = next((m for m in modules if m['base'] <= address < m['base'] + m['bytes']), None)
            return {'module': module['name'], 'rva': hex(address-module['base'])} if module else {'module': None}
        address = server['base'] + 0x7f77dc
        fields = []
        for offset in (0, 4, 8):
            object_address = pointer(address + offset)
            vtable = pointer(object_address) if object_address else None
            slot = pointer(vtable + (0x28 if offset == 4 else 0x24)) if vtable else None
            fields.append({'offset': offset, 'object': object_address, 'vtable': vtable,
                           'vtable_location': location(vtable), 'candidate_slot': slot,
                           'candidate_slot_location': location(slot)})
        return {'captured_utc': datetime.now(timezone.utc).isoformat(), 'server_pid': owned.pid,
                'server_sha256': digest, 'server_base': server['base'], 'context_rva': '0x7f77dc',
                'context_address': address, 'fields': fields,
                'read_errors': read_errors,
                'meaning': 'read-only candidate cached-interface context; identity not proven by this snapshot'}
    finally:
        owned.k.CloseHandle.argtypes = [W.HANDLE]
        if read_handle: owned.k.CloseHandle(read_handle)
        owned.k.CloseHandle(owned.handle)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('trial_state', type=Path); p.add_argument('output', type=Path)
    a = p.parse_args()
    if a.output.exists(): p.error('Refusing evidence overwrite')
    a.output.write_text(json.dumps(snapshot(json.loads(a.trial_state.read_text())), indent=2)+'\n', encoding='utf-8')
