#pragma once
#include <cstdint>
#include <cstddef>
#include <limits>

namespace SteamTrace {
struct InterfaceState {
    uint32_t object = 0, vtable = 0, method = 0;
    bool objectRead = false, vtableRead = false, methodRead = false;
    bool vtableInSteam = false, methodInSteam = false, methodExecutable = false;
};
struct Snapshot {
    bool identified = false;
    InterfaceState fields[2];
};

// Read callbacks copy bytes and return failure; no sampled pointer is called.
// Unknown identities never reach the reader. Windows RVAs are not Linux offsets.
template <typename Read, typename InSteam, typename Executable>
Snapshot Capture(bool identified, uint32_t context, Read read, InSteam inSteam, Executable executable)
{
    Snapshot result;
    if (!identified || context > (std::numeric_limits<uint32_t>::max)() - 12) return result;
    result.identified = true;
    for (size_t i = 0; i < 2; ++i) {
        auto& field = result.fields[i];
        field.objectRead = read(context + 4 + static_cast<uint32_t>(i * 4), field.object);
        if (!field.objectRead || !field.object) continue;
        field.vtableRead = read(field.object, field.vtable);
        if (!field.vtableRead || !field.vtable) continue;
        field.vtableInSteam = inSteam(field.vtable);
        const uint32_t slot = i == 0 ? 0x28 : 0x24;
        if (field.vtable > (std::numeric_limits<uint32_t>::max)() - slot) continue;
        field.methodRead = read(field.vtable + slot, field.method);
        if (!field.methodRead || !field.method) continue;
        field.methodInSteam = inSteam(field.method);
        field.methodExecutable = executable(field.method);
    }
    return result;
}

inline bool Same(const Snapshot& a, const Snapshot& b)
{
    if (a.identified != b.identified) return false;
    for (size_t i = 0; i < 2; ++i) {
        const auto& x = a.fields[i]; const auto& y = b.fields[i];
        if (x.object != y.object || x.vtable != y.vtable || x.method != y.method ||
            x.objectRead != y.objectRead || x.vtableRead != y.vtableRead || x.methodRead != y.methodRead ||
            x.vtableInSteam != y.vtableInSteam || x.methodInSteam != y.methodInSteam ||
            x.methodExecutable != y.methodExecutable) return false;
    }
    return true;
}
} // namespace SteamTrace
