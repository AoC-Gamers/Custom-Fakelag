#include <cstdlib>
#include <cstring>
#include <iostream>
#include <random>
#include <cmath>
#include <limits>
#include <functional>
#include "../extension/cdetour/MemoryProtection.h"
#include "../extension/network/LagSystem.h"
#include "../extension/network/LossModel.h"
#include "../extension/network/LagPacketPolicy.h"
#include "../extension/latency/PlayerProfileService.h"

// Injectable boundaries: these tests never patch engine memory.
bool enabled = false, activationWorks = true, alwaysOn = false, changingMode = false;
int activations = 0;
CFakeLagPacketLossMode lossMode = CFakeLagPacketLossMode::GilbertElliott;
CFakeLagPacketLossMode CFakeLag_GetPacketLossMode() { return lossMode; }
LagSystem* activeQueue = nullptr;
bool LagDetour_Enable() { ++activations; if (!activationWorks) return false; return enabled = true; }
void LagDetour_ClearAll() { if (activeQueue) activeQueue->ClearAll(); }
void LagDetour_Disable() { enabled = false; LagDetour_ClearAll(); }
bool LagDetour_IsEnabled() { return enabled; }
void LagDetour_ClearPacketLossState() {}
bool CFakeLag_IsAlwaysOnDetourMode() { return alwaysOn; }
bool CFakeLag_IsModeChanging() { return changingMode; }

int failures = 0;
void Expect(bool ok, const char* what) { if (!ok) { std::cerr << "FAIL: " << what << '\n'; ++failures; } }

// Synthetic adapter tests the capacity/transaction contract, NOT a game reader.
class SyntheticAdapter : public EnginePacketAdapter {
public:
    mutable bool failRestore = false;
    size_t DestinationCapacity(const _netpacket_t&, bool) const override { return 32; }
    bool Capture(const _netpacket_t& p, EnginePacketView& v) const override {
        v.from = p.from; v.source = p.source; v.received = EngineTime(p.received);
        v.size = p.size; v.data = p.data; v.wiresize = p.wiresize; v.stream = p.stream;
        v.reader = {p.readerBytes, p.readerBits, p.readerCursor};
        return true;
    }
    bool Restore(const QueuedPacket& p, _netpacket_t& dest, size_t capacity) const override {
        if (failRestore || size_t(p.metadata.size) > capacity || (p.metadata.size && !dest.data)) return false;
        // All validation precedes mutation. No pointers from capture are reused.
        if (p.metadata.size) std::memcpy(dest.data, p.payload.get(), p.metadata.size);
        dest.from = p.metadata.from; dest.source = p.metadata.source; dest.received = p.metadata.received.value;
        dest.size = p.metadata.size; dest.wiresize = p.metadata.wiresize; dest.stream = p.metadata.stream;
        dest.readerBytes = p.metadata.reader.bytes; dest.readerBits = p.metadata.reader.bits;
        dest.readerCursor = p.metadata.reader.cursor; dest.readerPointer = dest.data;
        return true;
    }
};
struct PacketFixture {
    unsigned char bytes[32] = {};
    _netpacket_t packet;
    PacketFixture(int size = 4, unsigned char fill = 1) {
        std::memset(bytes, fill, sizeof(bytes));
        packet.data = bytes; packet.size = size; packet.wiresize = size;
        packet.readerBytes = size; packet.readerBits = size * 8; packet.readerPointer = bytes;
        packet.from.type = NA_IP; packet.from.ip[0] = 127; packet.from.port = 123;
        packet.received = 7.0; packet.readerCursor = 3;
    }
};
void TestQueueOwnershipAndOrdering()
{
    SyntheticAdapter adapter;
    double now = 10;
    LagSystem queue(&now, &adapter);
    PacketFixture a(4, 0x11), b(4, 0x22), c(4, 0x33), live;
    auto add = [&](PacketFixture& p, float lag, uint64_t session) {
        return queue.LagPacket(&p.packet, Milliseconds(lag), SessionId(session)) == EnqueueResult::Queued;
    };
    Expect(add(a, 80, 1) && add(b, 10, 1) && add(c, 10, 2), "enqueue across sessions");
    a.bytes[0] = 0xAA; // Owned payload must survive borrowed data mutation/destruction.
    now = 10.01;
    Expect(queue.GetNextPacket(0, &live.packet, sizeof(live.bytes)) && live.bytes[0] == 0x33, "another session avoids head of line blocking");
    Expect(!queue.GetNextPacket(0, &live.packet, sizeof(live.bytes)), "lower latency cannot overtake same session");
    now = 10.08;
    Expect(queue.GetNextPacket(0, &live.packet, sizeof(live.bytes)) && live.bytes[0] == 0x11, "capture makes one independent payload copy");
    Expect(live.packet.received == 7.0 && live.packet.readerCursor == 3 && live.packet.readerPointer == live.bytes, "receive time preserved and scalar reader restored to destination");
    Expect(queue.GetNextPacket(0, &live.packet, sizeof(live.bytes)) && live.bytes[0] == 0x22, "ties preserve session order");
    Expect(queue.GetPendingCount() == 0 && queue.GetRetainedBytes() == 0, "drain balances accounting");
    QueuedPacket owned;
    owned.payload.reset(new unsigned char[4]);
    auto* pointer = owned.payload.get();
    QueuedPacket moved(std::move(owned));
    QueuedPacket target; target.payload.reset(new unsigned char[8]); target = std::move(moved);
    Expect(target.payload.get() == pointer && !moved.payload && !owned.payload, "move construction and assignment transfer without copying");
    auto* sameOwner = &target;
    target = std::move(*sameOwner);
    Expect(target.payload.get() == pointer, "self move assignment retains valid ownership");
    // Copy/assignment of owner are rejected by static_assert in net_structures.h.
}
void TestRestoreFailureAndLimits()
{
    SyntheticAdapter adapter;
    double now = 1;
    QueueLimits limits; limits.sessionPackets = 2; limits.globalPackets = 3;
    limits.sessionBytes = 12; limits.globalBytes = 16;
    LagSystem queue(&now, &adapter, limits);
    PacketFixture large(8), small(4), live;
    Expect(queue.LagPacket(&large.packet, Milliseconds(10), SessionId(1)) == EnqueueResult::Queued, "first budgeted packet");
    Expect(queue.LagPacket(&large.packet, Milliseconds(10), SessionId(1)) == EnqueueResult::Saturated, "session byte budget");
    Expect(queue.LagPacket(&small.packet, Milliseconds(10), SessionId(1)) == EnqueueResult::Queued, "session exact byte limit");
    Expect(queue.LagPacket(&small.packet, Milliseconds(10), SessionId(1)) == EnqueueResult::Saturated, "session packet limit");
    Expect(queue.LagPacket(&small.packet, Milliseconds(10), SessionId(2)) == EnqueueResult::Queued, "global exact limit");
    Expect(queue.LagPacket(&small.packet, Milliseconds(10), SessionId(3)) == EnqueueResult::Saturated, "global packet/byte budget");
    now = 2;
    Expect(queue.GetNextPacket(0, &live.packet, 4), "insufficient destination drops large head and delivers next");
    Expect(queue.Counters().restoreFailed == 1 && queue.GetRetainedBytes() == 4, "failed restoration accounted exactly once");
    adapter.failRestore = true;
    auto before = live.bytes[0];
    Expect(!queue.GetNextPacket(0, &live.packet, 32) && live.bytes[0] == before, "adapter failure is transactional");
    Expect(queue.GetPendingCount() == 0 && queue.Counters().restoreFailed == 2 && queue.Counters().saturation == 3, "no retry loop or residual ownership");
    queue.CountRequestedLoss();
    Expect(queue.Counters().requestedLoss == 1, "requested loss separate from internal failures");
    for (float lag : {-1.f, 10001.f, std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
        Expect(queue.LagPacket(&small.packet, Milliseconds(lag), SessionId(2)) == EnqueueResult::Invalid, "invalid latency rejected");
    small.packet.readerBits = 999;
    Expect(queue.LagPacket(&small.packet, Milliseconds(1), SessionId(2)) == EnqueueResult::Invalid, "invalid reader scalar bounds");
    small.packet.readerBits = 32; small.packet.source = -1;
    Expect(queue.LagPacket(&small.packet, Milliseconds(1), SessionId(2)) == EnqueueResult::Invalid, "invalid socket");
    EnginePacketAdapter unsupported;
    LagSystem unavailable(&now, &unsupported);
    Expect(!unsupported.IsRuntimeValidated() && unsupported.DestinationCapacity(live.packet, false) == 0, "unknown ABI fails closed with no capacity assumption");
    Expect(unavailable.LagPacket(&large.packet, Milliseconds(1), SessionId(1)) == EnqueueResult::Invalid, "unknown adapter refuses capture");
}
class Resolver : public IClientNetAdrResolver {
public:
    bool works = true;
    bool TryResolveClientNetAdr(ClientIndex client, dumb_netadr_t* address) const override {
        if (!works) return false;
        *address = {}; address->type = NA_IP; address->ip[0] = 127; address->port = static_cast<unsigned short>(client);
        return true;
    }
};
class Events : public IPlayerLagManagerEvents {
public:
    int errors = 0;
    void OnSessionInvalidated(SessionId session) override { if (activeQueue) activeQueue->ClearSession(session); }
    void OnClientNetAdrResolutionFailed(int) override { ++errors; }
    void OnPlayerLagChanged(int, const dumb_netadr_t&, float) override {}
};
class Registry : public IClientRegistry {
public:
    bool connected = true;
    ClientEligibility GetClientEligibility(int client, IGamePlayer** = nullptr) const override {
        return connected && client >= 1 && client <= 2 ? ClientEligibility::Supported : ClientEligibility::Invalid;
    }
    int GetMaxClients() const override { return 2; }
};
class Hooks : public IPlayerProfileHooks {
public:
    std::function<void(float*)> pre;
    std::function<void()> post;
    int notifications = 0;
    bool OnSetPlayerLatency(int, float, float* lag, CFakeLagChangeReason) override { if (pre) pre(lag); return true; }
    void OnPlayerProfileChanged(int, float, int, float, int, CFakeLagChangeReason) override { ++notifications; if (post) post(); }
};
void TestProfilesResetReconnectAndFailures()
{
    SyntheticAdapter adapter;
    double now = 1;
    LagSystem queue(&now, &adapter); activeQueue = &queue;
    Resolver resolver; Events events; Registry registry; Hooks hooks;
    PlayerLagManager manager(&resolver, &events);
    PlayerProfileService service(&manager, &hooks, &registry);
    activationWorks = true; enabled = alwaysOn = false;
    Expect(service.SetPlayerProfile(1, 100, 20) && enabled, "lazy enables on first profile");
    dumb_netadr_t address{}; resolver.TryResolveClientNetAdr(1, &address);
    auto first = manager.GetSession(address);
    PacketFixture packet;
    Expect(queue.LagPacket(&packet.packet, Milliseconds(100), first) == EnqueueResult::Queued, "queue first connection");
    resolver.works = false; registry.connected = false;
    service.OnClientDisconnecting(1);
    Expect(queue.GetPendingCount() == 0 && queue.GetRetainedBytes() == 0 && manager.GetLagCount() == 0 && !enabled, "disconnect clears by cached session without resolver");
    resolver.works = true; registry.connected = true;
    Expect(service.SetPlayerProfile(1, 100, 0) && !(manager.GetSession(address) == first), "reconnect gets a fresh generation");
    queue.LagPacket(&packet.packet, Milliseconds(100), manager.GetSession(address));
    Expect(service.SetPlayerProfile(1, 50, 0) && queue.GetPendingCount() == 0, "profile edit discards old queue");
    queue.LagPacket(&packet.packet, Milliseconds(100), manager.GetSession(address));
    alwaysOn = true; service.ClearAllPlayerProfiles(); service.ClearAllPlayerProfiles();
    Expect(manager.GetLagCount() == 0 && queue.GetPendingCount() == 0 && queue.GetRetainedBytes() == 0 && enabled, "always-on total reset is idempotent");
    alwaysOn = false; service.ClearAllPlayerProfiles();
    Expect(!enabled, "lazy reset disables; reactivation leaves queue empty");
    activationWorks = false;
    auto notifications = hooks.notifications;
    Expect(!service.SetPlayerProfile(1, 100, 0) && manager.GetLagCount() == 0 && hooks.notifications == notifications, "activation failure cannot commit or notify");
    activationWorks = true; resolver.works = false;
    Expect(!service.SetPlayerProfile(1, 100, 20) && manager.GetLagCount() == 0 && !enabled && events.errors == 1, "resolution failure rolls back new detour");
    resolver.works = true;
    for (float lag : {-1.f, 10001.f, std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
        Expect(!service.SetPlayerProfile(1, lag, 0), "invalid input rejected before forward");
    Expect(!service.SetPlayerProfile(1, 1, 101), "loss range validated internally");
    hooks.pre = [](float* lag) { *lag = std::numeric_limits<float>::quiet_NaN(); };
    Expect(!service.SetPlayerProfile(1, 100, 0), "invalid forward result rejected");
    hooks.pre = [&](float*) { Expect(!service.SetPlayerProfile(1, 20, 0), "nested profile write rejected"); service.ClearAllPlayerProfiles(); };
    Expect(!service.SetPlayerProfile(1, 100, 0) && manager.GetLagCount() == 0, "reset during pre-forward invalidates transaction");
    hooks.pre = [&](float*) { service.OnClientDisconnecting(1); };
    Expect(!service.SetPlayerProfile(1, 100, 0), "disconnect during forward invalidates transaction");
    hooks.pre = {};
    changingMode = true;
    Expect(!service.SetPlayerProfile(1, 100, 0), "mode transition cannot repopulate state from forwards");
    changingMode = false;
    Expect(service.SetPlayerProfile(1, 100, 0), "profile restored after failures");
    auto oldSession = manager.GetSession(address);
    queue.LagPacket(&packet.packet, Milliseconds(100), oldSession);
    hooks.post = [&] { Expect(!service.SetPlayerProfile(2, 100, 0), "reset notification cannot recreate profiles"); };
    registry.connected = false;
    service.ClearAllPlayerProfiles();
    Expect(queue.Counters().lifecycle >= 3 && manager.GetLagCount() == 0, "total reset includes unsupported clients and lifecycle counters");
    hooks.post = {}; activeQueue = nullptr;
}
void TestPolicyPreservesUnprofiledAndClearsLoss()
{
    SyntheticAdapter adapter;
    double now = 1;
    LagSystem queue(&now, &adapter);
    Resolver resolver; PlayerLagManager manager(&resolver);
    LagPacketPolicy policy(&manager, &queue, &adapter);
    PacketFixture packet;
    Expect(policy.HandlePacket(true, &packet.packet).state == PacketDispatchState::Bypass &&
           policy.HandlePacket(false, &packet.packet).state == PacketDispatchState::Bypass,
           "no profiles preserves original engine path for newdata true and false");
    manager.SetPlayerProfile(1, 0, 100);
    resolver.TryResolveClientNetAdr(1, &packet.packet.from);
    Expect(policy.HandlePacket(true, &packet.packet).state == PacketDispatchState::Hold, "100 percent GE holds without division");
    Expect(queue.Counters().requestedLoss == 1 && policy.GetLossStateCount() == 1, "policy counts requested loss");
    policy.ClearSession(manager.GetSession(packet.packet.from));
    Expect(policy.GetLossStateCount() == 0, "individual loss state cleanup");
    policy.HandlePacket(true, &packet.packet);
    policy.ClearPacketLossState(); policy.ClearPacketLossState();
    queue.ClearAll(); manager.ClearAll();
    Expect(policy.GetLossStateCount() == 0 && queue.GetRetainedBytes() == 0 && manager.GetLagCount() == 0,
           "total reset leaves zero profiles queues bytes loss state");
    lossMode = CFakeLagPacketLossMode::BernoulliUniform;
    manager.SetPlayerProfile(1, 0, 100);
    Expect(policy.HandlePacket(true, &packet.packet).state == PacketDispatchState::Hold, "Bernoulli 100 percent");
    manager.SetPlayerProfile(1, 0, 0);
    Expect(policy.HandlePacket(true, &packet.packet).state == PacketDispatchState::Bypass, "Bernoulli zero preserves engine");
    lossMode = CFakeLagPacketLossMode::GilbertElliott;
}
void TestMemoryProtectionFailures()
{
    Expect(!TryProtectMemory(nullptr, 5, 0), "null patch address rejected");
    Expect(!TryProtectMemory(reinterpret_cast<void*>(1), 0, 0), "zero patch length rejected");
    Expect(!TryProtectMemory(reinterpret_cast<void*>(1), 5, 0), "unmapped page protection failure propagated");
#ifndef _WIN32
    const size_t page = static_cast<size_t>(sysconf(_SC_PAGESIZE));
    void* memory = mmap(nullptr, page * 2, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    Expect(memory != MAP_FAILED, "allocate protection harness");
    if (memory != MAP_FAILED) {
        auto* boundary = static_cast<unsigned char*>(memory) + page - 2;
        Expect(TryProtectMemory(boundary, 5, PROT_READ | PROT_WRITE), "patch span unprotects both pages");
        std::memset(boundary, 42, 5);
        munmap(memory, page * 2);
    }
#endif
}
void TestLossModel()
{
    for (int percent : {0, 1, 10, 20, 50, 80, 99, 100}) {
        std::mt19937 rng(0xCF123u + percent);
        bool bad = false;
        const int n = 2000000;
        int drops = 0, runs = 0;
        for (int i = 0; i < n; ++i) {
            bool previous = bad;
            bool drop = GilbertElliottDrop(bad, percent, std::generate_canonical<double, 53>(rng));
            drops += drop; runs += drop && !previous;
        }
        double p = percent / 100.0;
        double tolerance = 8 * std::sqrt(3 * p * (1-p) / n) + 20.0/n;
        Expect(std::abs(double(drops)/n-p) <= tolerance, "loss within correlated eight-sigma bound");
        double burst = runs ? double(drops)/runs : 0;
        if (percent > 0 && percent < 100) {
            double mean = 2/(1-p);
            double bound = 8 * std::sqrt(mean*(mean-1)/runs) + mean/runs;
            Expect(std::abs(burst-mean) <= bound, "burst within geometric eight-sigma bound");
        }
        std::cout << "loss=" << percent << " effective=" << double(drops)*100/n << " burst=" << burst << " runs=" << runs << '\n';
    }
    LossPercentage percent;
    Expect(!LossPercentage::TryFrom(-1, percent) && !LossPercentage::TryFrom(101, percent), "validated percentage rejects invalid input");
    bool bad = false;
    Expect(GilbertElliottDrop(bad, 20, 0), "entry drops");
    Expect(!GilbertElliottDrop(bad, 20, 0), "exit delivers");
    Expect(!GilbertElliottDrop(bad, 0, 0) && !bad, "zero clears loss state");
}
int main()
{
    TestQueueOwnershipAndOrdering(); TestRestoreFailureAndLimits(); TestProfilesResetReconnectAndFailures(); TestPolicyPreservesUnprofiledAndClearsLoss(); TestMemoryProtectionFailures(); TestLossModel();
    if (failures) { std::cerr << failures << " failures\n"; return 1; }
    std::cout << "All tests passed (synthetic transport, no engine ABI claim).\n";
}
