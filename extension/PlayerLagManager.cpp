#include "PlayerLagManager.h"
#include "extension.h"

bool PlayerLagManager::TryGetClientNetAdr(int client, dumb_netadr_t* netadr) const
{
	if (netadr == nullptr) {
		return false;
	}

	INetChannel* pNetChan = static_cast<INetChannel*>(m_pEngine->GetPlayerNetInfo(client));
	if (pNetChan == nullptr) {
		return false;
	}

	const auto& remoteAddress = pNetChan->GetRemoteAddress();
	static_assert(sizeof(*netadr) <= sizeof(remoteAddress), "dumb_netadr_t must fit within netadr_t.");
	std::memcpy(netadr, &remoteAddress, sizeof(*netadr));
	return true;
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
		g_pSM->LogError(myself, "Failed to resolve network address for client index %d.", client);
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
	g_pSM->LogMessage(myself,
		"Lagging player index %d with net address %d.%d.%d.%d:%d for %.01fms",
		client,
		netadr.ip[0],
		netadr.ip[1],
		netadr.ip[2],
		netadr.ip[3],
		netadr.port,
		lagTime);
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
