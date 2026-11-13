// Built only with CUSTOM_FAKELAG_ENGINE_HARNESS=1. Never packaged in normal builds.
// Isolated SRCDS driver for real UDP connectionless traffic, not Steam clients.
#ifdef _WIN32
#include <winsock2.h>
#endif
#include "../extension/extension.h"
#include "../extension/NET_LagPacket_Detour.h"
#include "../extension/network/LagSystem.h"
#include <cstdlib>
#include <memory>
#ifndef _WIN32
#include <arpa/inet.h>
#endif
extern IGameConfig* g_pGameConf;
extern CustomFakelag g_Sample;
namespace {
class ProbeResolver : public IClientNetAdrResolver {
public:
    dumb_netadr_t address{};
    bool TryResolveClientNetAdr(int, dumb_netadr_t* result) const override { *result = address; return true; }
};
class ProbeEvents : public IPlayerLagManagerEvents {
public:
    void OnSessionInvalidated(SessionId session) override { LagDetour_ClearSession(session); }
    void OnClientNetAdrResolutionFailed(int) override {}
    void OnPlayerLagChanged(int, const dumb_netadr_t&, float) override {}
};
ProbeResolver resolver;
ProbeEvents events;
std::unique_ptr<PlayerLagManager> manager;
void Snapshot(const char* stage)
{
    size_t pending = 0, bytes = 0, lossStates = 0;
    PacketCounters counters;
    LagDetour_TestSnapshot(pending, bytes, lossStates, counters);
    g_pSM->LogMessage(myself, "[engine_probe] stage=%s enabled=%d pending=%u bytes=%u loss_states=%u dispatched=%llu mean_hold_ms=%.3f loss=%llu restore_failed=%llu lifecycle=%llu invalid=%llu",
        stage, LagDetour_IsEnabled(), unsigned(pending), unsigned(bytes), unsigned(lossStates),
        static_cast<unsigned long long>(counters.dispatched),
        counters.dispatched ? counters.totalHoldSeconds * 1000 / counters.dispatched : 0.0,
        static_cast<unsigned long long>(counters.requestedLoss), static_cast<unsigned long long>(counters.restoreFailed),
        static_cast<unsigned long long>(counters.lifecycle), static_cast<unsigned long long>(counters.invalidPacket));
}
}
CON_COMMAND(cf_probe_profile, "TEST ONLY: port latency_ms loss_percent for loopback UDP traffic")
{
    if (args.ArgC() != 4) return;
    const int port = std::atoi(args.Arg(1)), loss = std::atoi(args.Arg(3));
    const float lag = std::strtof(args.Arg(2), nullptr);
    if (port < 1 || port > 65535 || !ValidLatency(lag) || loss < 0 || loss > 100) return;
    if (!LagDetour_Shutdown()) return;
    resolver.address = {};
    resolver.address.type = NA_IP;
    resolver.address.ip[0] = 127; resolver.address.ip[3] = 1;
    resolver.address.port = htons(static_cast<unsigned short>(port));
    manager.reset(new PlayerLagManager(&resolver, &events));
    double* time = nullptr;
    if (!g_pGameConf->GetAddress("net_time", reinterpret_cast<void**>(&time)) || !LagDetour_Init(manager.get(), time)) return;
    if (!manager->SetPlayerProfile(1, lag, loss) || !LagDetour_Enable()) {
        g_pSM->LogError(myself, "[engine_probe] profile activation failed");
        return;
    }
    Snapshot("profile");
}
CON_COMMAND(cf_probe_clear, "TEST ONLY: invalidate simulated connection generation and disable hook")
{
    if (manager) manager->ClearAll();
    LagDetour_Disable();
    Snapshot("clear");
}
CON_COMMAND(cf_probe_reset, "TEST ONLY: exercise the extension reset entry point")
{
    g_Sample.ResetState();
    Snapshot("reset");
}
CON_COMMAND(cf_probe_status, "TEST ONLY: observe queue and hook counters")
{
    Snapshot("status");
}
