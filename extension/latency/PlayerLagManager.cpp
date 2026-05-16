#include "PlayerLagManager.h"
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
	std::memcpy(netadr, &remoteAddress, sizeof(*netadr));
	return true;
}

bool PlayerLagManager::TryGetClientNetAdr(ClientIndex client, dumb_netadr_t* netadr) const
{
	if (netadr == nullptr || m_NetAdrResolver == nullptr) {
		return false;
	}

	return m_NetAdrResolver->TryResolveClientNetAdr(client, netadr);
}

void PlayerLagManager::RemoveLagEntry(const dumb_netadr_t& netadr)
{
	auto existing = m_NetworkProfiles.find(netadr);
	if (existing.found()) {
		m_NetworkProfiles.remove(existing);
	}
}

void PlayerLagManager::SetPlayerLag(ClientIndex client, LagMilliseconds lagTime)
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		if (m_Events != nullptr) {
			m_Events->OnClientNetAdrResolutionFailed(client);
		}
		return;
	}

	if (lagTime <= 0.0f) {
		auto existing = m_NetworkProfiles.find(netadr);
		if (!existing.found()) {
			return;
		}

		existing->value.lagTime = 0.0f;
		if (existing->value.packetLossPercent <= 0) {
			m_NetworkProfiles.remove(existing);
		}
		return;
	}

	auto i = m_NetworkProfiles.findForAdd(netadr);
	if (!i.found()) {
		m_NetworkProfiles.add(i, netadr);
	}
	i->value.lagTime = lagTime;

	if (m_Events != nullptr) {
		m_Events->OnPlayerLagChanged(client, netadr, lagTime);
	}
}

void PlayerLagManager::ClearPlayerLag(ClientIndex client)
{
	SetPlayerLag(client, 0.0f);
}

void PlayerLagManager::SetPlayerPacketLoss(ClientIndex client, PacketLossPercent packetLossPercent)
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		if (m_Events != nullptr) {
			m_Events->OnClientNetAdrResolutionFailed(client);
		}
		return;
	}

	if (packetLossPercent <= 0) {
		auto existing = m_NetworkProfiles.find(netadr);
		if (!existing.found()) {
			return;
		}

		existing->value.packetLossPercent = 0;
		if (existing->value.lagTime <= 0.0f) {
			m_NetworkProfiles.remove(existing);
		}
		return;
	}

	auto i = m_NetworkProfiles.findForAdd(netadr);
	if (!i.found()) {
		m_NetworkProfiles.add(i, netadr);
	}

	i->value.packetLossPercent = packetLossPercent;
}

void PlayerLagManager::ClearPlayerPacketLoss(ClientIndex client)
{
	SetPlayerPacketLoss(client, 0);
}

void PlayerLagManager::ClearAll()
{
	m_NetworkProfiles.clear();
}

bool PlayerLagManager::HasPlayerLag(ClientIndex client) const
{
	return GetPlayerLag(client) > 0.0f;
}

LagMilliseconds PlayerLagManager::GetPlayerLag(ClientIndex client) const
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		return 0.0f;
	}

	return GetPlayerLag(netadr);
}

LagMilliseconds PlayerLagManager::GetPlayerLag(const dumb_netadr_t& netadr) const
{
	auto found = m_NetworkProfiles.find(netadr);
	if (!found.found()) {
		return 0.0f;
	}
	return found->value.lagTime;
}

bool PlayerLagManager::HasPlayerPacketLoss(ClientIndex client) const
{
	return GetPlayerPacketLoss(client) > 0;
}

PacketLossPercent PlayerLagManager::GetPlayerPacketLoss(ClientIndex client) const
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		return 0;
	}

	return GetPlayerPacketLoss(netadr);
}

PacketLossPercent PlayerLagManager::GetPlayerPacketLoss(const dumb_netadr_t& netadr) const
{
	auto found = m_NetworkProfiles.find(netadr);
	if (!found.found()) {
		return 0;
	}

	return found->value.packetLossPercent;
}
