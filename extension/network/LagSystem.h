#pragma once
#include "net_structures.h"
#include <vector>
#include <cstddef>
#include <cmath>

static constexpr int kMaxSockets = 6;
static constexpr float kMaxLatencyMs = 10000.0f;
inline bool ValidLatency(float lag) { return std::isfinite(lag) && lag >= 0 && lag <= kMaxLatencyMs; }

struct QueueLimits {
    size_t sessionPackets = 256;
    size_t sessionBytes = 2 * 1024 * 1024;
    size_t globalPackets = 4096;
    size_t globalBytes = 32 * 1024 * 1024;
    size_t packetBytes = 65536;
};
struct PacketCounters {
    uint64_t requestedLoss = 0;
    uint64_t saturation = 0;
    uint64_t restoreFailed = 0;
    uint64_t lifecycle = 0;
    uint64_t invalidPacket = 0;
};
enum class EnqueueResult { Queued, Saturated, Invalid };
struct PacketLater {
    bool operator()(const QueuedPacket& a, const QueuedPacket& b) const {
        return a.releaseAt.value > b.releaseAt.value ||
            (a.releaseAt.value == b.releaseAt.value && a.sequence > b.sequence);
    }
};
class LagSystem {
    std::vector<QueuedPacket> m_Packets[kMaxSockets];
    const double* m_NetTime;
    const EnginePacketAdapter* m_Adapter;
    QueueLimits m_Limits;
    size_t m_Bytes = 0;
    size_t m_Count = 0;
    uint64_t m_Sequence = 0;
    PacketCounters m_Counters;
    bool ValidSocket(int socket) const { return socket >= 0 && socket < kMaxSockets; }
public:
    LagSystem(const double* time, const EnginePacketAdapter* adapter, QueueLimits limits = {})
        : m_NetTime(time), m_Adapter(adapter), m_Limits(limits) {}
    EnqueueResult LagPacket(const _netpacket_t* packet, Milliseconds lag, SessionId session);
    bool GetNextPacket(int socket, _netpacket_t* destination, size_t allocationCapacity);
    void ClearAll();
    void ClearSession(SessionId session);
    size_t GetQueueDepth(int socket) const { return ValidSocket(socket) ? m_Packets[socket].size() : 0; }
    size_t GetPendingCount() const { return m_Count; }
    size_t GetRetainedBytes() const { return m_Bytes; }
    const PacketCounters& Counters() const { return m_Counters; }
    void CountRequestedLoss() { ++m_Counters.requestedLoss; }
};
