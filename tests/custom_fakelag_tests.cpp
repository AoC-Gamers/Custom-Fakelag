#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>

#include <amtl/am-priority-queue.h>

#include "../extension/network/LagSystem.h"
#include "../extension/network/net_structures.h"

namespace {

int g_failures = 0;

void Expect(bool condition, const char* message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        ++g_failures;
    }
}

_netpacket_t MakePacket(double received, int size, unsigned char fill)
{
    _netpacket_t packet{};
    packet.source = 0;
    packet.received = received;
    packet.size = size;
    packet.wiresize = size;
    packet.message.m_nDataBytes = size;
    packet.message.m_nDataBits = size * 8;

    if (size > 0) {
        packet.data = new unsigned char[size];
        std::memset(packet.data, fill, size);
        packet.message.m_pData = packet.data;
    }

    return packet;
}

_netpacket_t MakeEmptyPacket()
{
    return MakePacket(0.0, 0, 0);
}

_netpacket_t MakeLivePacket(int capacity)
{
    _netpacket_t packet{};
    packet.source = 0;
    packet.size = capacity;
    packet.wiresize = capacity;
    packet.message.m_nDataBytes = capacity;
    packet.message.m_nDataBits = capacity * 8;

    if (capacity > 0) {
        packet.data = new unsigned char[capacity];
        std::memset(packet.data, 0, capacity);
        packet.message.m_pData = packet.data;
    }

    return packet;
}

void TestPriorityQueueOrdersOldestPacketFirst()
{
    ke::PriorityQueue<_netpacket_t, PacketEarlier> queue;
    queue.add(MakePacket(10.0, 1, 0x10));
    queue.add(MakePacket(5.0, 1, 0x05));
    queue.add(MakePacket(7.5, 1, 0x07));

    Expect(!queue.empty(), "priority queue should not be empty");
    Expect(queue.peek().received == 5.0, "priority queue should prioritize the earliest received packet");

    _netpacket_t first = queue.pop();
    _netpacket_t second = queue.pop();
    _netpacket_t third = queue.pop();

    Expect(first.received == 5.0, "first popped packet should be the earliest one");
    Expect(second.received == 7.5, "second popped packet should be the middle one");
    Expect(third.received == 10.0, "third popped packet should be the latest one");
}

void TestCopyToLivePacketPreservesLiveBuffer()
{
    _netpacket_t queued = MakePacket(3.0, 4, 0x4A);
    _netpacket_t live = MakeEmptyPacket();

    unsigned char liveBuffer[4] = {};
    live.data = liveBuffer;
    live.size = 4;
    live.message.m_nDataBytes = 4;
    live.message.m_pData = liveBuffer;

    const bool copied = queued.CopyToLivePacket(&live);

    Expect(copied, "copy to live packet should succeed when capacity is sufficient");
    Expect(live.data == liveBuffer, "copy to live packet should preserve the engine-owned live buffer");
    Expect(live.message.m_pData == liveBuffer, "message buffer pointer should point to the live buffer");
    Expect(std::memcmp(live.data, queued.data, 4) == 0, "payload bytes should be copied into the live buffer");

    live.data = nullptr;
    live.message.m_pData = nullptr;
}

void TestCopyToLivePacketRejectsSmallBuffer()
{
    _netpacket_t queued = MakePacket(2.0, 8, 0x8B);
    _netpacket_t live = MakeEmptyPacket();

    unsigned char liveBuffer[4] = {};
    std::memset(liveBuffer, 0xCD, sizeof(liveBuffer));
    live.data = liveBuffer;
    live.size = 4;
    live.message.m_nDataBytes = 4;
    live.message.m_pData = liveBuffer;

    const bool copied = queued.CopyToLivePacket(&live);

    Expect(!copied, "copy to live packet should fail when the live buffer is too small");
    Expect(std::memcmp(liveBuffer, "\xCD\xCD\xCD\xCD", 4) == 0, "failed copy should not mutate the live buffer");

    live.data = nullptr;
    live.message.m_pData = nullptr;
}

void TestLagSystemDelaysPacketUntilNetTime()
{
    double netTime = 1.0;
    LagSystem lagSystem(&netTime);

    _netpacket_t queued = MakePacket(1.0, 4, 0x11);
    queued.source = 2;

    const bool delayed = lagSystem.LagPacket(&queued, 50.0f);
    Expect(delayed, "lag system should accept a valid packet for delaying");
    Expect(lagSystem.GetQueueDepth(2) == 1, "lag system should track queue depth after enqueuing");

    _netpacket_t live = MakeLivePacket(4);
    live.source = 2;

    Expect(!lagSystem.GetNextPacket(2, &live), "packet should not be released before target net_time");

    netTime = 1.049;
    Expect(!lagSystem.GetNextPacket(2, &live), "packet should remain queued just before scheduled time");

    netTime = 1.050;
    Expect(lagSystem.GetNextPacket(2, &live), "packet should be released once net_time reaches scheduled time");
    Expect(lagSystem.GetQueueDepth(2) == 0, "queue depth should return to zero after release");
    Expect(std::memcmp(live.data, queued.data, 4) == 0, "released packet payload should match queued payload");
}

void TestLagSystemReleasesPacketsInChronologicalOrder()
{
    double netTime = 10.0;
    LagSystem lagSystem(&netTime);

    _netpacket_t first = MakePacket(10.0, 2, 0x21);
    _netpacket_t second = MakePacket(10.0, 2, 0x42);
    first.source = 3;
    second.source = 3;

    Expect(lagSystem.LagPacket(&first, 40.0f), "first packet should enqueue");
    Expect(lagSystem.LagPacket(&second, 10.0f), "second packet should enqueue");
    Expect(lagSystem.GetQueueDepth(3) == 2, "two packets should be queued on the same socket");

    _netpacket_t live = MakeLivePacket(2);
    live.source = 3;

    netTime = 10.010;
    Expect(lagSystem.GetNextPacket(3, &live), "earliest scheduled packet should release first");
    Expect(live.data[0] == 0x42, "packet with the earliest release time should be dispatched first");

    netTime = 10.040;
    Expect(lagSystem.GetNextPacket(3, &live), "later scheduled packet should release second");
    Expect(live.data[0] == 0x21, "packet with the later release time should be dispatched second");
    Expect(lagSystem.GetQueueDepth(3) == 0, "socket queue should be empty after both releases");
}

void TestLagSystemAvoidsHeadOfLineBlockingOnSameSocket()
{
    double netTime = 20.0;
    LagSystem lagSystem(&netTime);

    _netpacket_t later = MakePacket(20.0, 3, 0x61);
    _netpacket_t earlier = MakePacket(20.0, 3, 0x17);
    later.source = 1;
    earlier.source = 1;

    // Enqueue the later-release packet first to ensure queue ordering is based on
    // release time, not insertion order.
    Expect(lagSystem.LagPacket(&later, 80.0f), "later packet should enqueue");
    Expect(lagSystem.LagPacket(&earlier, 10.0f), "earlier packet should enqueue");

    _netpacket_t live = MakeLivePacket(3);
    live.source = 1;

    netTime = 20.010;
    Expect(lagSystem.GetNextPacket(1, &live), "earlier packet should not be blocked by a later packet ahead of it");
    Expect(live.data[0] == 0x17, "earliest ready packet should be dispatched first on the same socket");

    netTime = 20.079;
    Expect(!lagSystem.GetNextPacket(1, &live), "later packet should remain queued until its scheduled time");

    netTime = 20.080;
    Expect(lagSystem.GetNextPacket(1, &live), "later packet should release once its scheduled time arrives");
    Expect(live.data[0] == 0x61, "later packet should be dispatched second");
}

}  // namespace

int main()
{
    TestPriorityQueueOrdersOldestPacketFirst();
    TestCopyToLivePacketPreservesLiveBuffer();
    TestCopyToLivePacketRejectsSmallBuffer();
    TestLagSystemDelaysPacketUntilNetTime();
    TestLagSystemReleasesPacketsInChronologicalOrder();
    TestLagSystemAvoidsHeadOfLineBlockingOnSameSocket();

    if (g_failures != 0) {
        std::cerr << g_failures << " test(s) failed.\n";
        return 1;
    }

    std::cout << "All tests passed.\n";
    return 0;
}
