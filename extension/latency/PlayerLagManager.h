#pragma once
#include <cstring>
#include <mathlib.h>
#include <eiface.h>
#include <inetchannel.h>
#include <amtl/am-hashmap.h>
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
		LagMilliseconds lagTime = 0.0f;
		PacketLossPercent packetLossPercent = 0;
	};

	const IClientNetAdrResolver* m_NetAdrResolver;
	IPlayerLagManagerEvents* m_Events;
	ke::HashMap<dumb_netadr_t, PlayerNetworkProfile, NetAdrHashPolicy_s> m_NetworkProfiles;

	bool TryGetClientNetAdr(ClientIndex client, dumb_netadr_t* netadr) const;
	void RemoveLagEntry(const dumb_netadr_t& netadr);

public:
	explicit PlayerLagManager(const IClientNetAdrResolver* netAdrResolver, IPlayerLagManagerEvents* events = nullptr)
		: m_NetAdrResolver(netAdrResolver),
		  m_Events(events) {
		m_NetworkProfiles.init(32);
	}

	void SetPlayerLag(ClientIndex client, LagMilliseconds lagTime);
	void ClearPlayerLag(ClientIndex client);
	void SetPlayerPacketLoss(ClientIndex client, PacketLossPercent packetLossPercent);
	void ClearPlayerPacketLoss(ClientIndex client);
	void ClearAll();

	bool HasPlayerLag(ClientIndex client) const;
	LagMilliseconds GetPlayerLag(ClientIndex client) const;
	bool HasPlayerPacketLoss(ClientIndex client) const;
	PacketLossPercent GetPlayerPacketLoss(ClientIndex client) const;
	ProfileCount GetLagCount() const { return m_NetworkProfiles.elements(); }

	LagMilliseconds GetPlayerLag(const dumb_netadr_t& netadr) const;
	PacketLossPercent GetPlayerPacketLoss(const dumb_netadr_t& netadr) const;
};
