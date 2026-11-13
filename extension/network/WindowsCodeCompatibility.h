#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

// Compatibility exception for the independently observed Left4DHooks 1.175
// entry detour in this exact engine. Disk identity and every other executable
// byte remain checked by WindowsEngineContract. This does not identify the
// author of arbitrary injected code or make guarantees about hostile plugins.
namespace WindowsEngineCode {
constexpr uint32_t FillServerInfoRva = 0x133cb0;
constexpr size_t EntryDetourBytes = 5;
constexpr unsigned char FillServerInfoEntry[EntryDetourBytes] = {0x55, 0x8b, 0xec, 0x53, 0x56};

template <typename ExecutableTarget>
bool MatchesExecutableRange(const unsigned char* loaded, const unsigned char* expected,
                            size_t imageBytes, uint64_t imageBase, size_t rangeRva,
                            size_t rangeBytes, ExecutableTarget executableTarget)
{
    if (!loaded || !expected || !rangeBytes || rangeRva > imageBytes ||
        rangeBytes > imageBytes - rangeRva || imageBase > UINT32_MAX ||
        imageBytes > (uint64_t(1) << 32) - imageBase) return false;
    if (!std::memcmp(loaded + rangeRva, expected + rangeRva, rangeBytes)) return true;
    const size_t slot = FillServerInfoRva;
    // The five bytes must lie wholly within this executable range. A change
    // in any other section or across a section boundary is never masked.
    if (slot < rangeRva || slot > imageBytes || EntryDetourBytes > imageBytes - slot ||
        slot - rangeRva > rangeBytes || EntryDetourBytes > rangeBytes - (slot - rangeRva)) return false;
    if (std::memcmp(expected + slot, FillServerInfoEntry, EntryDetourBytes) || loaded[slot] != 0xe9 ||
        std::memcmp(loaded + rangeRva, expected + rangeRva, slot - rangeRva) ||
        std::memcmp(loaded + slot + EntryDetourBytes, expected + slot + EntryDetourBytes,
                    rangeBytes - (slot - rangeRva) - EntryDetourBytes)) return false;
    uint32_t displacement = 0;
    std::memcpy(&displacement, loaded + slot + 1, sizeof(displacement));
    // rel32 adds to EIP modulo 2^32 on the supported i386 engine.
    const uint32_t target = static_cast<uint32_t>(imageBase + slot + EntryDetourBytes) + displacement;
    if (!target) return false;
    // DHooks' callback is external to engine.dll. Reject loops and jumps into
    // the engine, including jumps into packet functions or the entry itself.
    if (target >= imageBase && target - imageBase < imageBytes) return false;
    return executableTarget(static_cast<uint32_t>(target));
}
} // namespace WindowsEngineCode
