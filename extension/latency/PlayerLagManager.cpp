#include "PlayerLagManager.h"
bool EngineClientNetAdrResolver::TryResolveClientNetAdr(int client, dumb_netadr_t* netadr) const
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

bool PlayerLagManager::TryGetClientNetAdr(int client, dumb_netadr_t* netadr) const
{
	if (netadr == nullptr || m_NetAdrResolver == nullptr) {
		return false;
	}

	return m_NetAdrResolver->TryResolveClientNetAdr(client, netadr);
}

void PlayerLagManager::RemoveLagEntry(const dumb_netadr_t& netadr)
{
	auto existing = m_LagTimes.find(netadr);
	if (existing.found()) {
		m_LagTimes.remove(existing);
	}
}

void PlayerLagManager::SetPlayerLag(int client, float lagTime)
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		if (m_Events != nullptr) {
			m_Events->OnClientNetAdrResolutionFailed(client);
		}
		return;
	}

	if (lagTime <= 0.0f) {
		RemoveLagEntry(netadr);
		return;
	}

	auto i = m_LagTimes.findForAdd(netadr);
	if (!i.found()) {
		m_LagTimes.add(i, netadr);
	}
	i->value = lagTime;

	if (m_Events != nullptr) {
		m_Events->OnPlayerLagChanged(client, netadr, lagTime);
	}
}

void PlayerLagManager::ClearPlayerLag(int client)
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		return;
	}

	RemoveLagEntry(netadr);
}

void PlayerLagManager::ClearAll()
{
	m_LagTimes.clear();
}

bool PlayerLagManager::HasPlayerLag(int client) const
{
	return GetPlayerLag(client) > 0.0f;
}

float PlayerLagManager::GetPlayerLag(int client) const
{
	dumb_netadr_t netadr;
	if (!TryGetClientNetAdr(client, &netadr)) {
		return 0.0f;
	}

	return GetPlayerLag(netadr);
}

float PlayerLagManager::GetPlayerLag(const dumb_netadr_t& netadr) const
{
	auto found = m_LagTimes.find(netadr);
	if (!found.found()) {
		return 0.0f;
	}
	return found->value;
}
