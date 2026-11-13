"""Regression: real child exit codes and timeout are not collector success."""
import ctypes as C
from ctypes import wintypes as W
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys
from windows_load_order_session import OwnedSteamProcess

kernel = C.WinDLL('kernel32', use_last_error=True)
kernel.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
for expected in (0, 23, 0xc0000005, 0xc0000409):
    receipt = {'started_utc': datetime.now(timezone.utc).isoformat()}
    child = subprocess.Popen([sys.executable, '-c',
        f'import ctypes,time;time.sleep(.3);ctypes.windll.kernel32.ExitProcess({expected})'],
        creationflags=subprocess.CREATE_NO_WINDOW)
    owned = OwnedSteamProcess(child.pid, Path(sys.executable), receipt)
    assert child.poll() is None
    assert owned.poll() is None
    actual = child.wait(timeout=5)
    code = W.DWORD()
    assert kernel.GetExitCodeProcess(int(child._handle), C.byref(code))
    assert kernel.WaitForSingleObject(int(child._handle), 0) == 0
    assert actual == code.value == owned.poll() == expected
    print(f'PASS real child/Popen/Win32/adopted handle agree: 0x{expected:08x}')
child = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(10)'],
                         creationflags=subprocess.CREATE_NO_WINDOW)
try:
    try: child.wait(timeout=.1)
    except subprocess.TimeoutExpired: pass
    else: raise AssertionError('Timeout was reported as completion')
    assert child.poll() is None
    assert kernel.WaitForSingleObject(int(child._handle), 0) == 258
    print('PASS timeout leaves child alive and unsignaled; not a clean exit')
finally:
    child.terminate()  # Only this synthetic Python fixture, never a server.
    child.wait(timeout=5)
