#pragma once
#include "net_structures.h"

// Both independently identified engines supply full-size receive buffers and
// start the reader AFTER NET_LagPacket. Reader fields are not capture sources.
// Windows additionally preserves its unprepared stream byte without reading it.
class L4D2PacketCodec {
public:
    static constexpr size_t ReceiveBufferBytes = 0x37ab0;
    static bool Capture(const _netpacket_t& packet, EnginePacketView& view, bool opaqueStream = false);
    static bool Restore(const QueuedPacket& packet, _netpacket_t& destination,
                        size_t capacity, EngineTime deliveredAt, bool opaqueStream = false);
};

class L4D2PacketAdapter final : public EnginePacketAdapter {
    bool m_Validated = false;
    _netpacket_t** m_PacketTable = nullptr;
    const double* m_NetTime = nullptr;
    const char* m_Diagnostic = "Engine architecture or identity is unsupported";
    bool IsEnginePacket(const _netpacket_t& packet) const;
public:
    bool Initialize(const void* lagFunction, const double* netTime);
    const char* Diagnostic() const { return m_Diagnostic; }
    bool IsRuntimeValidated() const override { return m_Validated; }
    bool Capture(const _netpacket_t& packet, EnginePacketView& view) const override;
    size_t DestinationCapacity(const _netpacket_t& packet, bool newdata) const override;
    bool Restore(const QueuedPacket& packet, _netpacket_t& destination, size_t capacity) const override;
};
