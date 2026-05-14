#pragma once
#include <cstring>
#include <mathlib.h>
#include <eiface.h>
#include <inetchannel.h>
#include <amtl/am-hashmap.h>
#include "net_structures.h"

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

class PlayerLagManager
{
private:
	IVEngineServer* m_pEngine;
	ke::HashMap<dumb_netadr_t, float, NetAdrHashPolicy_s> m_LagTimes;

	bool TryGetClientNetAdr(int client, dumb_netadr_t* netadr) const;
	void RemoveLagEntry(const dumb_netadr_t& netadr);

public:
	explicit PlayerLagManager(IVEngineServer* engine) : m_pEngine(engine) {
		m_LagTimes.init(32);
	}

	void SetPlayerLag(int client, float lagTime);
	void ClearPlayerLag(int client);
	void ClearAll();

	float GetPlayerLag(int client) const;

	float GetPlayerLag(const dumb_netadr_t& netadr) const;
};
