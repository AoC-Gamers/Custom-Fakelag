#include "LagSystem.h"
#include <algorithm>
#include <new>

EnqueueResult LagSystem::LagPacket(const _netpacket_t* packet, Milliseconds lag, SessionId session)
{
    EnginePacketView view;
    if (!packet || !m_NetTime || !std::isfinite(*m_NetTime) || !m_Adapter ||
        !session.value || !ValidLatency(lag.value) || !m_Adapter->Capture(*packet, view) ||
        !ValidSocket(view.source) || view.size < 0 || size_t(view.size) > m_Limits.packetBytes ||
        (view.size && !view.data) || !std::isfinite(view.received.value) ||
        view.reader.bytes < 0 || view.reader.bytes > view.size || view.reader.bits < 0 ||
        static_cast<int64_t>(view.reader.bits) > static_cast<int64_t>(view.reader.bytes) * 8 || view.reader.cursor < 0 ||
        view.reader.cursor > view.reader.bits) {
        ++m_Counters.invalidPacket;
        return EnqueueResult::Invalid;
    }
    size_t count = 0, bytes = 0;
    for (const auto& queue : m_Packets) {
        for (const auto& entry : queue) {
            if (entry.session == session) { ++count; bytes += entry.metadata.size; }
        }
    }
    const size_t payloadSize = size_t(view.size);
    if (m_Count >= m_Limits.globalPackets || count >= m_Limits.sessionPackets ||
        payloadSize > m_Limits.globalBytes || m_Bytes > m_Limits.globalBytes - payloadSize ||
        payloadSize > m_Limits.sessionBytes || bytes > m_Limits.sessionBytes - payloadSize) {
        ++m_Counters.saturation;
        return EnqueueResult::Saturated; // Drop newest; never bypass a configured delay.
    }
    QueuedPacket owned;
    if (payloadSize) {
        owned.payload.reset(new (std::nothrow) unsigned char[payloadSize]);
        if (!owned.payload) { ++m_Counters.saturation; return EnqueueResult::Saturated; }
        std::memcpy(owned.payload.get(), view.data, payloadSize);
    }
    view.data = nullptr; // No borrowed pointers survive capture.
    owned.metadata = view;
    owned.session = session;
    owned.releaseAt = EngineTime(*m_NetTime + lag.value / 1000.0);
    owned.sequence = ++m_Sequence;
    auto& queue = m_Packets[view.source];
    // Clamp within a session to preserve arrival order even when latency decreases.
    for (const auto& entry : queue) {
        if (entry.session == session) owned.releaseAt.value = (std::max)(owned.releaseAt.value, entry.releaseAt.value);
    }
    queue.push_back(std::move(owned));
    std::push_heap(queue.begin(), queue.end(), PacketLater{});
    ++m_Count;
    m_Bytes += payloadSize;
    return EnqueueResult::Queued;
}

bool LagSystem::GetNextPacket(int socket, _netpacket_t* destination, size_t allocationCapacity)
{
    if (!destination || !ValidSocket(socket) || !m_NetTime || !std::isfinite(*m_NetTime)) return false;
    auto& queue = m_Packets[socket];
    // Each failed restoration is discarded once, counted, and cannot block others.
    // Work is bounded by the global packet budget. Counters survive ClearAll.
    while (!queue.empty() && queue.front().releaseAt.value <= *m_NetTime) {
        std::pop_heap(queue.begin(), queue.end(), PacketLater{});
        auto owned = std::move(queue.back());
        queue.pop_back();
        --m_Count;
        m_Bytes -= size_t(owned.metadata.size);
        if (size_t(owned.metadata.size) <= allocationCapacity && m_Adapter &&
            m_Adapter->Restore(owned, *destination, allocationCapacity)) {
            ++m_Counters.dispatched;
            m_Counters.totalHoldSeconds += (std::max)(0.0, *m_NetTime - owned.metadata.received.value);
            return true;
        }
        ++m_Counters.restoreFailed;
    }
    return false;
}

void LagSystem::ClearAll()
{
    m_Counters.lifecycle += m_Count;
    for (auto& queue : m_Packets) {
        std::vector<QueuedPacket> empty;
        queue.swap(empty); // Release metadata storage as well as payload buffers.
    }
    m_Count = m_Bytes = 0;
    m_Sequence = 0;
}
void LagSystem::ClearSession(SessionId session)
{
    for (auto& queue : m_Packets) {
        auto end = std::remove_if(queue.begin(), queue.end(), [&](const QueuedPacket& packet) {
            if (!(packet.session == session)) return false;
            --m_Count;
            m_Bytes -= size_t(packet.metadata.size);
            ++m_Counters.lifecycle;
            return true;
        });
        queue.erase(end, queue.end());
        std::make_heap(queue.begin(), queue.end(), PacketLater{});
    }
}
