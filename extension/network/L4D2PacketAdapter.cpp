#include "L4D2PacketAdapter.h"
#include <cmath>
#include "WindowsEngineContract.h"

#if defined(__linux__) && !defined(UNIT_TEST)
#include <dlfcn.h>
#include <link.h>
#endif

bool L4D2PacketCodec::Capture(const _netpacket_t& packet, EnginePacketView& view, bool opaqueStream)
{
    if (!packet.data || packet.size < 0 || size_t(packet.size) > ReceiveBufferBytes ||
        packet.source < 0 || packet.source > 2 || !std::isfinite(packet.received)) return false;
    view.from = AddressKey(packet.from);
    view.source = packet.source;
    view.received = EngineTime(packet.received);
    view.data = packet.data;
    view.size = packet.size;
    view.wiresize = packet.wiresize;
    // Windows datagram/loopback paths leave this byte unprepared. It remains
    // opaque in the live table entry; do not evaluate a potentially invalid bool.
    view.stream = opaqueStream ? false : packet.stream;
    view.reader = {packet.size, packet.size * 8, 0}; // Future reader, constructed by the caller.
    return true;
}

bool L4D2PacketCodec::Restore(const QueuedPacket& packet, _netpacket_t& destination,
                             size_t capacity, EngineTime deliveredAt, bool opaqueStream)
{
    const auto& source = packet.metadata;
    if (source.size < 0 || size_t(source.size) > capacity || capacity > ReceiveBufferBytes ||
        source.source != destination.source || !destination.data ||
        (source.size && !packet.payload) || !std::isfinite(deliveredAt.value)) return false;
    if (source.size) std::memcpy(destination.data, packet.payload.get(), size_t(source.size));
    destination.from.type = source.from.type;
    std::memcpy(destination.from.ip, source.from.ip, sizeof(source.from.ip));
    destination.from.port = source.from.port;
    destination.received = deliveredAt.value; // Verified native NET_LagPacket semantics.
    destination.size = source.size;
    destination.wiresize = source.wiresize;
    if (!opaqueStream) destination.stream = source.stream;
#ifndef UNIT_TEST
    destination.pNext = nullptr;
#endif
    // Do not access/copy the stale reader. The verified caller invokes
    // CBitRead::StartReading(data, size, 0, -1) before dispatch on BOTH paths.
    return true;
}

bool L4D2PacketAdapter::Initialize(const void* lagFunction, const double* netTime)
{
    m_Validated = false;
    m_PacketTable = nullptr;
    m_NetTime = nullptr;
    m_Diagnostic = "Engine architecture or identity is unsupported";
#if defined(__linux__) && !defined(UNIT_TEST) && UINTPTR_MAX == UINT32_MAX
    static_assert(sizeof(netadr_t) == 12 && alignof(netadr_t) == 4, "identified Linux netadr ABI");
    static_assert(sizeof(bf_read) == 36 && alignof(bf_read) == 4, "identified Linux reader ABI");
    static_assert(sizeof(netpacket_t) == 80 && alignof(netpacket_t) == 4, "identified Linux packet ABI");
    Dl_info module{};
    if (!lagFunction || !netTime || !dladdr(lagFunction, &module) || !module.dli_fbase) return false;
    const auto* base = static_cast<const unsigned char*>(module.dli_fbase);
    const auto* header = reinterpret_cast<const Elf32_Ehdr*>(base);
    if (std::memcmp(header->e_ident, ELFMAG, SELFMAG) || header->e_ident[EI_CLASS] != ELFCLASS32 ||
        header->e_machine != EM_386 || header->e_phentsize != sizeof(Elf32_Phdr) || header->e_phnum > 128) return false;
    const auto* program = reinterpret_cast<const Elf32_Phdr*>(base + header->e_phoff);
    // engine_srv.so: PatchVersion 2.2.4.3, build-id from the local server volume.
    static constexpr unsigned char buildId[] = {
        0xb1,0x52,0x43,0x91,0x70,0xaf,0x08,0x1a,0x0d,0x31,
        0xfc,0x35,0x73,0x64,0xa4,0xcd,0x4c,0xaa,0x56,0xac
    };
    bool identified = false;
    for (unsigned i = 0; i < header->e_phnum; ++i) {
        if (program[i].p_type != PT_NOTE) continue;
        const auto* cursor = base + program[i].p_vaddr;
        const auto* end = cursor + program[i].p_memsz;
        while (size_t(end - cursor) >= sizeof(Elf32_Nhdr)) {
            const auto* note = reinterpret_cast<const Elf32_Nhdr*>(cursor);
            cursor += sizeof(*note);
            const size_t nameBytes = (size_t(note->n_namesz) + 3) & ~size_t(3);
            const size_t dataBytes = (size_t(note->n_descsz) + 3) & ~size_t(3);
            if (nameBytes > size_t(end - cursor) || dataBytes > size_t(end - cursor) - nameBytes) break;
            if (note->n_type == NT_GNU_BUILD_ID && note->n_namesz == 4 &&
                !std::memcmp(cursor, "GNU", 4) && note->n_descsz == sizeof(buildId) &&
                !std::memcmp(cursor + nameBytes, buildId, sizeof(buildId))) identified = true;
            cursor += nameBytes + dataBytes;
        }
    }
    if (!identified || lagFunction != base + 0x1b36b0 ||
        reinterpret_cast<const void*>(netTime) != base + 0x39c140) return false;
    // Check SDK field placement using a real object, without offsetof on its
    // non-standard-layout reader type or fabricated packing directives.
    netpacket_t packet;
    const uintptr_t object = reinterpret_cast<uintptr_t>(&packet);
    if (reinterpret_cast<uintptr_t>(&packet.source) - object != 12 ||
        reinterpret_cast<uintptr_t>(&packet.received) - object != 16 ||
        reinterpret_cast<uintptr_t>(&packet.data) - object != 24 ||
        reinterpret_cast<uintptr_t>(&packet.message) - object != 28 ||
        reinterpret_cast<uintptr_t>(&packet.size) - object != 64 ||
        reinterpret_cast<uintptr_t>(&packet.wiresize) - object != 68 ||
        reinterpret_cast<uintptr_t>(&packet.stream) - object != 72 ||
        reinterpret_cast<uintptr_t>(&packet.pNext) - object != 76) return false;
    m_PacketTable = reinterpret_cast<_netpacket_t**>(const_cast<unsigned char*>(base + 0x39c4d0));
    m_NetTime = netTime;
    m_Validated = true;
    m_Diagnostic = "Identified Linux x86 engine";
    return true;
#elif defined(_WIN32) && !defined(UNIT_TEST) && UINTPTR_MAX == UINT32_MAX
    static_assert(sizeof(netadr_t) == 12 && alignof(netadr_t) == 4, "identified Windows netadr ABI");
    static_assert(sizeof(bf_read) == 36 && alignof(bf_read) == 4, "identified Windows reader ABI");
    static_assert(sizeof(netpacket_t) == 80 && alignof(netpacket_t) == 8, "identified Windows MSVC packet ABI");
    static_assert(L4D2PacketCodec::ReceiveBufferBytes == WindowsEngineContract::BufferBytes,
                  "independently verified Windows receive capacity");
    unsigned char* base = nullptr;
    if (!WindowsEngineContract::Identify(lagFunction, netTime, base, m_Diagnostic)) return false;
    if (!std::isfinite(*netTime)) {
        m_Diagnostic = "Windows net_time is not a finite double";
        return false;
    }
    netpacket_t packet;
    const uintptr_t object = reinterpret_cast<uintptr_t>(&packet);
    if (reinterpret_cast<uintptr_t>(&packet.source) - object != 12 ||
        reinterpret_cast<uintptr_t>(&packet.received) - object != 16 ||
        reinterpret_cast<uintptr_t>(&packet.data) - object != 24 ||
        reinterpret_cast<uintptr_t>(&packet.message) - object != 28 ||
        reinterpret_cast<uintptr_t>(&packet.size) - object != 64 ||
        reinterpret_cast<uintptr_t>(&packet.wiresize) - object != 68 ||
        reinterpret_cast<uintptr_t>(&packet.stream) - object != 72 ||
        reinterpret_cast<uintptr_t>(&packet.pNext) - object != 76) {
        m_Diagnostic = "Windows SDK packet fields differ from the disassembled ABI";
        return false;
    }
    m_PacketTable = reinterpret_cast<_netpacket_t**>(base + WindowsEngineContract::TableRva);
    m_NetTime = netTime;
    m_Validated = true;
    return true;
#else
    (void)lagFunction; (void)netTime;
    return false; // Windows/x64 require independently identified engine modules.
#endif
}

bool L4D2PacketAdapter::IsEnginePacket(const _netpacket_t& packet) const
{
#if defined(_WIN32) && !defined(UNIT_TEST)
    // The identified NET_GetPacket writes only its three table entries and
    // retains the full-size NET_ProcessSocket buffer across all receive paths.
    // Neither packet.size nor reader fields establish allocation capacity.
    if (!m_Validated || !m_PacketTable ||
        !WindowsEngineContract::Region(m_PacketTable, 16) || !*m_PacketTable ||
        !WindowsEngineContract::Region(&packet, sizeof(packet), true) ||
        packet.source < 0 || packet.source > 2 ||
        reinterpret_cast<uintptr_t>(&packet) != reinterpret_cast<uintptr_t>(*m_PacketTable) + size_t(packet.source) * sizeof(packet) ||
        reinterpret_cast<uintptr_t>(packet.data) % alignof(uint32_t) != 0) return false;
    int count = 0;
    std::memcpy(&count, reinterpret_cast<const unsigned char*>(m_PacketTable) + 12, sizeof(count));
    if (count < 1 || count > 3 || packet.source >= count) return false;
    return WindowsEngineContract::Region(packet.data, WindowsEngineContract::BufferBytes, true);
#else
    return m_Validated && m_PacketTable && *m_PacketTable && packet.source >= 0 && packet.source <= 2 &&
        &packet == *m_PacketTable + packet.source && packet.data &&
        reinterpret_cast<uintptr_t>(packet.data) % alignof(uint32_t) == 0;
#endif
}
bool L4D2PacketAdapter::Capture(const _netpacket_t& packet, EnginePacketView& view) const
{
    return IsEnginePacket(packet) && L4D2PacketCodec::Capture(packet, view,
#if defined(_WIN32) && !defined(UNIT_TEST)
        true
#else
        false
#endif
    );
}
size_t L4D2PacketAdapter::DestinationCapacity(const _netpacket_t& packet, bool) const
{
    return IsEnginePacket(packet) ? L4D2PacketCodec::ReceiveBufferBytes : 0;
}
bool L4D2PacketAdapter::Restore(const QueuedPacket& packet, _netpacket_t& destination, size_t capacity) const
{
    return IsEnginePacket(destination) && capacity == L4D2PacketCodec::ReceiveBufferBytes && m_NetTime &&
        L4D2PacketCodec::Restore(packet, destination, capacity, EngineTime(*m_NetTime),
#if defined(_WIN32) && !defined(UNIT_TEST)
            true
#else
            false
#endif
        );
}
