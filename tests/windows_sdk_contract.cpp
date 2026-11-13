// Isolated process: maps the exact PE without executing DllMain/imports.
// Tests the actual SDK representation and adapter, NOT a running SRCDS.
#include "../extension/network/L4D2PacketAdapter.h"
#include "../extension/network/WindowsEngineContract.h"
#include <iostream>
#include <array>
#include <cmath>
#include <limits>
namespace {
int failures = 0;
void Check(bool value, const char* name) {
    std::cout << (value ? "PASS " : "FAIL ") << name << '\n';
    if (!value) ++failures;
}
}
int wmain(int argc, wchar_t** argv)
{
    if (argc != 2) return 2;
    HMODULE module = LoadLibraryExW(argv[1], nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!module) return 3;
    auto* base = reinterpret_cast<unsigned char*>(module);
    const void* lag = base + WindowsEngineContract::LagRva;
    auto* time = reinterpret_cast<double*>(base + WindowsEngineContract::TimeRva);
    L4D2PacketAdapter adapter;
    Check(!adapter.Initialize(nullptr, time), "unresolved function refused");
    Check(!adapter.Initialize(base + WindowsEngineContract::LagRva + 1, time), "wrong RVA refused");
    double foreignTime = 12;
    Check(!adapter.Initialize(lag, &foreignTime), "foreign time refused");
    const bool identified = adapter.Initialize(lag, time); Check(identified, adapter.Diagnostic());
    if (!adapter.IsRuntimeValidated()) return 4;
    const double previousTime = *time;
    *time = std::numeric_limits<double>::quiet_NaN();
    Check(!adapter.Initialize(lag, time) && !adapter.IsRuntimeValidated(), "nonfinite engine clock refused");
    *time = previousTime;
    Check(adapter.Initialize(lag, time), "finite clock restores eligibility");
    std::cout << "mapped_base=" << static_cast<void*>(base) << " lag=" << lag << " net_time=" << time
              << " packet_size=" << sizeof(netpacket_t) << " packet_alignment=" << alignof(netpacket_t)
              << " reader_size=" << sizeof(bf_read) << '\n';
    auto** table = reinterpret_cast<netpacket_t**>(base + WindowsEngineContract::TableRva);
    auto* count = reinterpret_cast<int*>(base + WindowsEngineContract::TableRva + 12);
    const int previousCount = *count; *count = 3;
    netpacket_t packets[3];
    auto* previousTable = *table; *table = packets;
    auto* buffer = static_cast<unsigned char*>(VirtualAlloc(nullptr, WindowsEngineContract::BufferBytes,
                                                           MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
    if (!buffer) return 5;
    auto& packet = packets[1];
    packet.source = 1; packet.data = buffer; packet.received = 10;
    packet.size = 4; packet.wiresize = 8; packet.stream = false;
    const unsigned char opaqueStream = 0xa5;
    std::memcpy(&packet.stream, &opaqueStream, 1);
    std::memcpy(buffer, "test", 4);
    std::array<unsigned char, sizeof(bf_read)> reader;
    std::memcpy(reader.data(), &packet.message, reader.size());
    std::memset(&packet.message, 0xa5, sizeof(packet.message));
    EnginePacketView view;
    Check(adapter.Capture(packet, view), "capture ignores unprepared SDK reader");
    Check(adapter.DestinationCapacity(packet, true) == WindowsEngineContract::BufferBytes,
          "new data gets physical capacity");
    packet.size = 0;
    Check(adapter.DestinationCapacity(packet, false) == WindowsEngineContract::BufferBytes,
          "no new data still has full allocation");
    *count = 1;
    Check(!adapter.DestinationCapacity(packet, false), "packet outside constructed vector count rejected");
    *count = 3;
    netpacket_t foreign;
    foreign.source = 1; foreign.data = buffer;
    Check(!adapter.DestinationCapacity(foreign, false), "foreign packet rejected");
    QueuedPacket queued;
    queued.metadata = view; queued.metadata.data = nullptr;
    queued.payload.reset(new unsigned char[4]); std::memcpy(queued.payload.get(), "test", 4);
    *time = 42;
    std::array<unsigned char, sizeof(netpacket_t)> before;
    std::memcpy(before.data(), &packet, before.size());
    Check(!adapter.Restore(queued, packet, 3) && !std::memcmp(before.data(), &packet, before.size()),
          "insufficient capacity is transactional");
    Check(adapter.Restore(queued, packet, WindowsEngineContract::BufferBytes) &&
          packet.data == buffer && packet.received == 42 && packet.size == 4 &&
          packet.pNext == nullptr && !std::memcmp(buffer, "test", 4), "SDK restore preserves buffer and native timestamp");
    std::array<unsigned char, sizeof(bf_read)> poison; poison.fill(0xa5);
    Check(!std::memcmp(&packet.message, poison.data(), poison.size()), "restore never touches stale reader");
    Check(!std::memcmp(&packet.stream, &opaqueStream, 1), "unprepared stream byte is neither interpreted nor overwritten");
    packet.stream = false;
    std::memcpy(&packet.message, reader.data(), reader.size());
    packet.message.StartReading(packet.data, packet.size, 0, -1);
    Check(packet.message.GetBasePointer() == buffer && packet.message.GetNumBitsRead() == 0 &&
          packet.message.ReadUBitLong(8) == static_cast<unsigned char>('t'),
          "SDK caller operation rebuilds reader pointers and cursor");
    DWORD oldProtect;
    VirtualProtect(buffer, WindowsEngineContract::BufferBytes, PAGE_READONLY, &oldProtect);
    Check(!adapter.DestinationCapacity(packet, false), "non-writable allocation rejected");
    VirtualProtect(buffer, WindowsEngineContract::BufferBytes, oldProtect, &oldProtect);
    *table = previousTable;
    *count = previousCount;
    *time = previousTime;
    VirtualFree(buffer, 0, MEM_RELEASE);
    // Alter only this non-executing mapped image, never code in a live server.
    auto* code = base + WindowsEngineContract::LagRva;
    VirtualProtect(code, 1, PAGE_EXECUTE_READWRITE, &oldProtect);
    const unsigned char saved = *code; *code ^= 1;
    Check(!adapter.Initialize(lag, time) && !adapter.IsRuntimeValidated() && *code == (saved ^ 1),
          "modified loaded code refused without writes");
    *code = saved; VirtualProtect(code, 1, oldProtect, &oldProtect);
    Check(adapter.Initialize(lag, time), "identity retry after isolated patch restored");
    FreeLibrary(module);
    return failures ? 1 : 0;
}

