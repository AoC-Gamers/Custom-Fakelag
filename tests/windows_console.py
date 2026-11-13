"""Native Windows console input for an owned, hidden test process.

No Docker, shell interpolation, RCON, or attachment to an existing server.
"""
import ctypes
from ctypes import wintypes as w
import os
from pathlib import Path
import subprocess
import time


class KeyEvent(ctypes.Structure):
    _fields_ = [('down', w.BOOL), ('repeat', w.WORD), ('virtual', w.WORD),
                ('scan', w.WORD), ('char', w.WCHAR), ('control', w.DWORD)]


class EventUnion(ctypes.Union):
    _fields_ = [('key', KeyEvent), ('padding', ctypes.c_byte * 16)]


class InputRecord(ctypes.Structure):
    _fields_ = [('kind', w.WORD), ('event', EventUnion)]


class WindowsConsole:
    def __init__(self, argv, cwd):
        if os.name != 'nt':
            raise RuntimeError('Windows console transport requires native Windows')
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.kernel.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID,
                                           w.DWORD, w.DWORD, w.HANDLE]
        self.kernel.CreateFileW.restype = w.HANDLE
        self.kernel.WriteConsoleInputW.argtypes = [w.HANDLE, ctypes.POINTER(InputRecord),
                                                  w.DWORD, ctypes.POINTER(w.DWORD)]
        self.kernel.CloseHandle.argtypes = [w.HANDLE]
        self.kernel.AttachConsole.argtypes = [w.DWORD]
        info = subprocess.STARTUPINFO()
        info.dwFlags = subprocess.STARTF_USESHOWWINDOW
        info.wShowWindow = 0
        self.process = subprocess.Popen(argv, cwd=cwd, startupinfo=info,
                                        creationflags=subprocess.CREATE_NEW_CONSOLE | subprocess.CREATE_BREAKAWAY_FROM_JOB)
        self.input = None
        try:
            self.kernel.FreeConsole()  # Detach only this driver process.
            for _ in range(100):
                if self.process.poll() is not None:
                    raise RuntimeError(f'Test process exited: {self.process.returncode}')
                if self.kernel.AttachConsole(self.process.pid):
                    break
                time.sleep(.05)
            else:
                raise ctypes.WinError(ctypes.get_last_error())
            self.input = self.kernel.CreateFileW('CONIN$', 0xC0000000, 3, None, 3, 0, None)
            if self.input == ctypes.c_void_p(-1).value:
                self.input = None
                raise ctypes.WinError(ctypes.get_last_error())
        except BaseException:
            self.close()
            raise

    def command(self, text):
        if '\n' in text or '\r' in text or self.process.poll() is not None:
            raise RuntimeError('Invalid command or test process already exited')
        # SRCDS recreates its console during bootstrap. Refresh the attachment
        # and input handle instead of retaining the launcher's stale buffer.
        self.kernel.FreeConsole()
        if not self.kernel.AttachConsole(self.process.pid):
            raise ctypes.WinError(ctypes.get_last_error())
        if self.input:
            self.kernel.CloseHandle(self.input)
        self.input = self.kernel.CreateFileW('CONIN$', 0xC0000000, 3, None, 3, 0, None)
        if self.input == ctypes.c_void_p(-1).value:
            self.input = None
            raise ctypes.WinError(ctypes.get_last_error())
        # A recreated SRCDS console can enable QuickEdit and pause the server.
        # Disable selection and hide only this owned console window.
        mode = w.DWORD()
        self.kernel.GetConsoleMode.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
        self.kernel.SetConsoleMode.argtypes = [w.HANDLE, w.DWORD]
        if self.kernel.GetConsoleMode(self.input, ctypes.byref(mode)):
            self.kernel.SetConsoleMode(self.input, (mode.value | 0x80) & ~0x40)
        self.kernel.GetConsoleWindow.restype = w.HWND
        window = self.kernel.GetConsoleWindow()
        user = ctypes.WinDLL('user32', use_last_error=True)
        user.PostMessageW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
        user.ShowWindow.argtypes = [w.HWND, ctypes.c_int]
        user.ShowWindow(window, 0)
        records = []
        for character in text + '\r':
            for down in (True, False):
                record = InputRecord()
                record.kind = 1  # KEY_EVENT
                record.event.key = KeyEvent(down, 1, 13 if character == '\r' else 0,
                                            0, character, 0)
                records.append(record)
        array = (InputRecord * len(records))(*records)
        written = w.DWORD()
        if not self.kernel.WriteConsoleInputW(self.input, array, len(records), ctypes.byref(written)):
            raise ctypes.WinError(ctypes.get_last_error())
        if written.value != len(records):
            raise RuntimeError('Partial console input write')

    def read_output(self):
        class Coord(ctypes.Structure):
            _fields_ = [('x', ctypes.c_short), ('y', ctypes.c_short)]
        class Rect(ctypes.Structure):
            _fields_ = [('l', ctypes.c_short), ('t', ctypes.c_short), ('r', ctypes.c_short), ('b', ctypes.c_short)]
        class Info(ctypes.Structure):
            _fields_ = [('size', Coord), ('cursor', Coord), ('attr', w.WORD), ('window', Rect), ('max', Coord)]
        self.kernel.FreeConsole()
        if not self.kernel.AttachConsole(self.process.pid):
            return 'Console unavailable'
        handle = self.kernel.CreateFileW('CONOUT$', 0x80000000, 3, None, 3, 0, None)
        try:
            info = Info()
            self.kernel.GetConsoleScreenBufferInfo.argtypes = [w.HANDLE, ctypes.POINTER(Info)]
            if not self.kernel.GetConsoleScreenBufferInfo(handle, ctypes.byref(info)):
                return 'Console info unavailable'
            start = max(0, info.cursor.y - 100)
            length = min(20000, (info.size.y-start)*info.size.x)
            buffer = ctypes.create_unicode_buffer(length)
            read = w.DWORD()
            self.kernel.ReadConsoleOutputCharacterW.argtypes = [w.HANDLE, w.LPWSTR, w.DWORD, w.DWORD, ctypes.POINTER(w.DWORD)]
            self.kernel.ReadConsoleOutputCharacterW(handle, buffer, length, start << 16, ctypes.byref(read))
            text = buffer[:read.value].replace(chr(0), ' ')
            return '\n'.join(text[i:i+info.size.x].rstrip() for i in range(0,len(text),info.size.x))
        finally:
            self.kernel.CloseHandle(handle)

    def close(self):
        if self.process.poll() is None:
            try:
                if self.input:
                    self.command('quit')
                    self.process.wait(timeout=5)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                pass
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=10)
        if self.input:
            self.kernel.CloseHandle(self.input)
            self.input = None
        self.kernel.FreeConsole()


if __name__ == '__main__':
    # Verify real console input delivery independently of unavailable SRCDS.
    import sys
    import tempfile
    with tempfile.TemporaryDirectory(prefix='cf-console-') as directory:
        result = Path(directory) / 'received.txt'
        code = 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text(input(),encoding="utf-8")'
        console = WindowsConsole([sys.executable, '-c', code, str(result)], directory)
        try:
            console.command('cf_probe_status')
            console.process.wait(timeout=10)
            assert result.read_text(encoding='utf-8') == 'cf_probe_status'
            print('PASS native hidden Windows console input; no SRCDS claim', flush=True)
        finally:
            console.close()
