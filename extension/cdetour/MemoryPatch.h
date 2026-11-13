#pragma once
#include "MemoryProtection.h"
#include <cstring>

struct patch_t {
    unsigned char patch[20] = {};
    size_t bytes = 0;
};
using MemoryProtectionFn = bool (*)(void*, size_t, int);
#ifdef _WIN32
static constexpr int kPatchProtection = PAGE_EXECUTE_READWRITE;
#else
static constexpr int kPatchProtection = PROT_READ | PROT_WRITE | PROT_EXEC;
#endif

// Protection failure never writes code or changes the saved restoration bytes.
inline bool ApplyPatch(void* address, int offset, const patch_t* patch, patch_t* restore,
                       MemoryProtectionFn protect = TryProtectMemory)
{
    if (!address || offset < 0 || !patch || !patch->bytes || patch->bytes > sizeof(patch->patch)) return false;
    const uintptr_t start = reinterpret_cast<uintptr_t>(address);
    if (size_t(offset) > (std::numeric_limits<uintptr_t>::max)() - start) return false;
    auto* destination = reinterpret_cast<unsigned char*>(start + size_t(offset));
    if (!protect(destination, patch->bytes, kPatchProtection)) return false;
    if (restore) {
        std::memcpy(restore->patch, destination, patch->bytes);
        restore->bytes = patch->bytes;
    }
    std::memcpy(destination, patch->patch, patch->bytes);
#ifdef _WIN32
    FlushInstructionCache(GetCurrentProcess(), destination, patch->bytes);
#endif
    return std::memcmp(destination, patch->patch, patch->bytes) == 0;
}

template <typename Restore>
bool TryDetachHook(bool& attached, Restore restore)
{
    if (!attached) return true;
    if (!restore()) return false;
    attached = false;
    return true;
}
template <typename Restore, typename Release>
bool TryDestroyHook(bool& attached, Restore restore, Release release)
{
    if (!TryDetachHook(attached, restore)) return false;
    release();
    return true;
}
