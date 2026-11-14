// Synthetic fixture only: exposes an exit status before process completion.
#include <windows.h>
#ifdef EXIT_DETACH_EXE
int wmain(int argc, wchar_t** argv) {
    if (argc != 2 || !LoadLibraryW(argv[1])) return 91;
    Sleep(300);
    ExitProcess(23);
}
#else
BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_DETACH) Sleep(1000);
    return TRUE;
}
#endif
