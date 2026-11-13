#include "PlayerLagManager.h"
#ifndef UNIT_TEST
#include <eiface.h>
#include <inetchannel.h>
bool EngineClientNetAdrResolver::TryResolveClientNetAdr(ClientIndex client, dumb_netadr_t* netadr) const
{
	if (netadr == nullptr || m_Engine == nullptr) {
		return false;
	}

	INetChannel* pNetChan = static_cast<INetChannel*>(m_Engine->GetPlayerNetInfo(client));
	if (pNetChan == nullptr) {
		return false;
	}

	const auto& remoteAddress = pNetChan->GetRemoteAddress();
	static_assert(sizeof(*netadr) <= sizeof(remoteAddress), "dumb_netadr_t must fit within netadr_t.");
	*netadr = AddressKey(remoteAddress);
	return true;
}


#endif

void PlayerLagManager::Invalidate(SessionId session)
{
    if (m_Events) m_Events->OnSessionInvalidated(session);
}
bool PlayerLagManager::SetPlayerProfile(ClientIndex client, LagMilliseconds lag, PacketLossPercent loss)
{
    if (!ValidLatency(lag) || loss < 0 || loss > 100 || client <= 0) return false;
    if (lag == 0 && loss == 0) { ClearClient(client); return true; }
    dumb_netadr_t address{};
    if (!m_NetAdrResolver || !m_NetAdrResolver->TryResolveClientNetAdr(client, &address)) {
        if (m_Events) m_Events->OnClientNetAdrResolutionFailed(client);
        return false;
    }
    // One address cannot belong to two active connection generations.
    for (const auto& entry : m_Profiles) {
        if (entry.first != client && NetAdrHashPolicy_s::matches(entry.second.address, address)) return false;
    }
    auto found = m_Profiles.find(client);
    if (found != m_Profiles.end()) Invalidate(found->second.session);
    PlayerNetworkProfile profile;
    profile.address = address;
    profile.lagTime = lag;
    profile.packetLossPercent = loss;
    profile.session = SessionId(++m_NextSession);
    m_Profiles[client] = profile;
    ++m_Revision;
    if (m_Events) m_Events->OnPlayerLagChanged(client, address, lag);
    return true;
}
bool PlayerLagManager::SetPlayerLag(ClientIndex client, LagMilliseconds lag)
{
    return SetPlayerProfile(client, lag, GetPlayerPacketLoss(client));
}
bool PlayerLagManager::SetPlayerPacketLoss(ClientIndex client, PacketLossPercent loss)
{
    return SetPlayerProfile(client, GetPlayerLag(client), loss);
}
void PlayerLagManager::ClearPlayerLag(ClientIndex client) { SetPlayerLag(client, 0); }
void PlayerLagManager::ClearPlayerPacketLoss(ClientIndex client) { SetPlayerPacketLoss(client, 0); }
void PlayerLagManager::ClearClient(ClientIndex client)
{
    auto found = m_Profiles.find(client);
    if (found != m_Profiles.end()) {
        const auto session = found->second.session;
        m_Profiles.erase(found);
        Invalidate(session);
    }
    ++m_Revision; // Also invalidates an in-flight pre-forward after a disconnect.
}
void PlayerLagManager::ClearAll()
{
    for (const auto& entry : m_Profiles) Invalidate(entry.second.session);
    m_Profiles.clear();
    ++m_Revision;
}
bool PlayerLagManager::HasPlayerLag(ClientIndex client) const { return GetPlayerLag(client) > 0; }
bool PlayerLagManager::HasPlayerPacketLoss(ClientIndex client) const { return GetPlayerPacketLoss(client) > 0; }
LagMilliseconds PlayerLagManager::GetPlayerLag(ClientIndex client) const
{
    const auto found = m_Profiles.find(client);
    return found == m_Profiles.end() ? 0 : found->second.lagTime;
}
PacketLossPercent PlayerLagManager::GetPlayerPacketLoss(ClientIndex client) const
{
    const auto found = m_Profiles.find(client);
    return found == m_Profiles.end() ? 0 : found->second.packetLossPercent;
}
LagMilliseconds PlayerLagManager::GetPlayerLag(const dumb_netadr_t& address) const
{
    for (const auto& entry : m_Profiles) {
        if (NetAdrHashPolicy_s::matches(entry.second.address, address)) return entry.second.lagTime;
    }
    return 0;
}
PacketLossPercent PlayerLagManager::GetPlayerPacketLoss(const dumb_netadr_t& address) const
{
    for (const auto& entry : m_Profiles) {
        if (NetAdrHashPolicy_s::matches(entry.second.address, address)) return entry.second.packetLossPercent;
    }
    return 0;
}
SessionId PlayerLagManager::GetSession(const dumb_netadr_t& address) const
{
    for (const auto& entry : m_Profiles) {
        if (NetAdrHashPolicy_s::matches(entry.second.address, address)) return entry.second.session;
    }
    return SessionId{};
}
