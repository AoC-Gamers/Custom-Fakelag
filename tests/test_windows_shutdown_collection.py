"""Regression: real child exit codes and timeout are not collector success."""
import ctypes as C
from ctypes import wintypes as W
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys
import time
from windows_load_order_session import OwnedSteamProcess
from windows_shutdown_trial import actual_exit

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
    retained = actual_exit(child)
    assert retained['server_exit_code'] == retained['win32_exit_code'] == expected
    assert retained['process_handle_signaled'] and retained['exit_codes_agree']
    print(f'PASS real child/Popen/Win32/adopted handle agree: 0x{expected:08x}')
child = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(10)'],
                         creationflags=subprocess.CREATE_NO_WINDOW)
try:
    try: child.wait(timeout=.1)
    except subprocess.TimeoutExpired: pass
    else: raise AssertionError('Timeout was reported as completion')
    assert child.poll() is None
    assert actual_exit(child) is None
    assert kernel.WaitForSingleObject(int(child._handle), 0) == 258
    print('PASS timeout leaves child alive and unsignaled; not a clean exit')
finally:
    child.terminate()  # Only this synthetic Python fixture, never a server.
    child.wait(timeout=5)

if len(sys.argv) == 3:
    receipt = {'started_utc': datetime.now(timezone.utc).isoformat()}
    child = subprocess.Popen([sys.argv[1], sys.argv[2]], creationflags=subprocess.CREATE_NO_WINDOW)
    owned = OwnedSteamProcess(child.pid, Path(sys.argv[1]), receipt)
    saw_detach = False
    while child.poll() is None:
        status = W.DWORD()
        assert kernel.GetExitCodeProcess(int(child._handle), C.byref(status))
        if status.value == 23 and kernel.WaitForSingleObject(int(child._handle), 0) == 258:
            assert owned.poll() is None
            saw_detach = True
        time.sleep(.01)
    assert saw_detach, 'Fixture did not expose the status-before-completion window'
    assert child.returncode == owned.poll() == 23
    print('PASS ExitProcess status during DLL detach is not actual completion')
