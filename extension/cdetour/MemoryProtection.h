#pragma once
#include <cstddef>
#include <cstdint>
#include <limits>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

inline bool TryProtectMemory(void* address, size_t length, int protection)
{
    if (!address || !length) return false;
    const uintptr_t start = reinterpret_cast<uintptr_t>(address);
    if (length > (std::numeric_limits<uintptr_t>::max)() - start) return false;
#ifdef _WIN32
    DWORD oldProtection;
    return VirtualProtect(address, length, protection, &oldProtection) != 0;
#else
    const long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) return false;
    const uintptr_t aligned = start - start % static_cast<uintptr_t>(pageSize);
    return mprotect(reinterpret_cast<void*>(aligned), start - aligned + length, protection) == 0;
#endif
}
