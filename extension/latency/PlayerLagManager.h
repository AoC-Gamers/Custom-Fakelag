#pragma once
#include <cstring>
#include <mathlib.h>
#include <eiface.h>
#include <inetchannel.h>
#include <amtl/am-hashmap.h>
#include "../network/net_structures.h"

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
	virtual bool TryResolveClientNetAdr(int client, dumb_netadr_t* netadr) const = 0;
};

class IPlayerLagManagerEvents
{
public:
	virtual ~IPlayerLagManagerEvents() = default;
	virtual void OnClientNetAdrResolutionFailed(int client) = 0;
	virtual void OnPlayerLagChanged(int client, const dumb_netadr_t& netadr, float lagTime) = 0;
};

class EngineClientNetAdrResolver final : public IClientNetAdrResolver
{
private:
	IVEngineServer* m_Engine;

public:
	explicit EngineClientNetAdrResolver(IVEngineServer* engine)
		: m_Engine(engine) {}

	bool TryResolveClientNetAdr(int client, dumb_netadr_t* netadr) const override;
};

class PlayerLagManager
{
private:
	const IClientNetAdrResolver* m_NetAdrResolver;
	IPlayerLagManagerEvents* m_Events;
	ke::HashMap<dumb_netadr_t, float, NetAdrHashPolicy_s> m_LagTimes;

	bool TryGetClientNetAdr(int client, dumb_netadr_t* netadr) const;
	void RemoveLagEntry(const dumb_netadr_t& netadr);

public:
	explicit PlayerLagManager(const IClientNetAdrResolver* netAdrResolver, IPlayerLagManagerEvents* events = nullptr)
		: m_NetAdrResolver(netAdrResolver),
		  m_Events(events) {
		m_LagTimes.init(32);
	}

	void SetPlayerLag(int client, float lagTime);
	void ClearPlayerLag(int client);
	void ClearAll();

	bool HasPlayerLag(int client) const;
	float GetPlayerLag(int client) const;
	size_t GetLagCount() const { return m_LagTimes.elements(); }

	float GetPlayerLag(const dumb_netadr_t& netadr) const;
};
