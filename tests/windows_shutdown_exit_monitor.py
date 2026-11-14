"""Retain an owned live process handle across a collector/dialog interruption.

Read-only supplemental observation; does not replace or rewrite trial evidence.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
from windows_load_order_session import OwnedSteamProcess

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('trial_state', type=Path)
    p.add_argument('output', type=Path)
    a = p.parse_args()
    if a.output.exists(): p.error('Refusing evidence overwrite')
    trial = json.loads(a.trial_state.read_text())
    owned = OwnedSteamProcess(trial['server_pid'], Path(trial['argv'][0]),
        {'started_utc': datetime.fromtimestamp(trial['started'], timezone.utc).isoformat()})
    record = {'server_pid': owned.pid, 'observer': 'supplemental retained Win32 handle',
              'attached_utc': datetime.now(timezone.utc).isoformat(), 'forced_termination': False}
    def save(): a.output.write_text(json.dumps(record, indent=2)+'\n')
    try:
        record['handle_signaled_at_attach'] = owned.k.WaitForSingleObject(owned.handle, 0) == 0
        record['state'] = 'waiting'; save()
        try:
            record['server_exit_code'] = owned.wait(600)
            record['server_exit_hex'] = f"0x{record['server_exit_code']:08x}"
            record['process_handle_signaled'] = owned.k.WaitForSingleObject(owned.handle, 0) == 0
            record['state'] = 'exited'
        except subprocess.TimeoutExpired:
            record['state'] = 'timeout_process_still_alive'
        record['finished_utc'] = datetime.now(timezone.utc).isoformat(); save()
    finally:
        owned.k.CloseHandle.argtypes = [W.HANDLE]
        owned.k.CloseHandle(owned.handle)
