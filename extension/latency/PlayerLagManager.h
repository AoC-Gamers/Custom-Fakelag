#pragma once
#include <cstring>
class IVEngineServer;
#include <map>
#include "../network/LagSystem.h"
#include "../network/net_structures.h"

using ClientIndex = int;
using LagMilliseconds = float;
using PacketLossPercent = int;
using ProfileCount = size_t;

struct NetAdrHashPolicy_s {
	static uint32_t hash(const dumb_netadr_t& value)
	{
		uint32_t hash = 2166136261u;
		for (unsigned char octet : value.ip) {
			hash ^= octet;
			hash *= 16777619u;
		}
		hash ^= value.port;
		hash *= 16777619u;
		hash ^= static_cast<uint32_t>(value.type);
		hash *= 16777619u;
		return hash;
	}

	static bool matches(const dumb_netadr_t& value, const dumb_netadr_t& key)
	{
		return std::memcmp(value.ip, key.ip, sizeof(value.ip)) == 0
			&& value.port == key.port
			&& value.type == key.type;
	}
};

class IClientNetAdrResolver
{
public:
	virtual ~IClientNetAdrResolver() = default;
	virtual bool TryResolveClientNetAdr(ClientIndex client, dumb_netadr_t* netadr) const = 0;
};

class IPlayerLagManagerEvents
{
public:
	virtual ~IPlayerLagManagerEvents() = default;
	virtual void OnClientNetAdrResolutionFailed(ClientIndex client) = 0;
	virtual void OnSessionInvalidated(SessionId session) = 0;
	virtual void OnPlayerLagChanged(ClientIndex client, const dumb_netadr_t& netadr, LagMilliseconds lagTime) = 0;
};

class EngineClientNetAdrResolver final : public IClientNetAdrResolver
{
private:
	IVEngineServer* m_Engine;

public:
	explicit EngineClientNetAdrResolver(IVEngineServer* engine)
		: m_Engine(engine) {}

	bool TryResolveClientNetAdr(ClientIndex client, dumb_netadr_t* netadr) const override;
};

class PlayerLagManager
{
private:
	struct PlayerNetworkProfile {
		dumb_netadr_t address{};
		LagMilliseconds lagTime = 0;
		PacketLossPercent packetLossPercent = 0;
		SessionId session;
	};
	const IClientNetAdrResolver* m_NetAdrResolver;
	IPlayerLagManagerEvents* m_Events;
	std::map<ClientIndex, PlayerNetworkProfile> m_Profiles;
	uint64_t m_Revision = 0;
	uint64_t m_NextSession = 0;
	void Invalidate(SessionId session);

public:
	explicit PlayerLagManager(const IClientNetAdrResolver* netAdrResolver, IPlayerLagManagerEvents* events = nullptr)
		: m_NetAdrResolver(netAdrResolver),
		  m_Events(events) {}

	bool SetPlayerLag(ClientIndex client, LagMilliseconds lagTime);
	void ClearPlayerLag(ClientIndex client);
	bool SetPlayerPacketLoss(ClientIndex client, PacketLossPercent packetLossPercent);
	void ClearPlayerPacketLoss(ClientIndex client);
	void ClearAll();
	void ClearClient(ClientIndex client);
	bool SetPlayerProfile(ClientIndex client, LagMilliseconds lag, PacketLossPercent loss);
	SessionId GetSession(const dumb_netadr_t& address) const;
	uint64_t Revision() const { return m_Revision; }

	bool HasPlayerLag(ClientIndex client) const;
	LagMilliseconds GetPlayerLag(ClientIndex client) const;
	bool HasPlayerPacketLoss(ClientIndex client) const;
	PacketLossPercent GetPlayerPacketLoss(ClientIndex client) const;
	ProfileCount GetLagCount() const { return m_Profiles.size(); }

	LagMilliseconds GetPlayerLag(const dumb_netadr_t& netadr) const;
	PacketLossPercent GetPlayerPacketLoss(const dumb_netadr_t& netadr) const;
};
