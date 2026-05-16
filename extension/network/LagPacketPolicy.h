#pragma once

#include "LagSystem.h"
#include "../extension.h"
#include "../latency/PlayerLagManager.h"
#include "tier1/convar.h"
#include <amtl/am-hashmap.h>

enum class PacketDispatchState {
	Bypass = 0,
	Dispatch,
	Hold
};

struct PacketDispatchResult {
	PacketDispatchState state;

	bool ShouldDispatch() const { return state == PacketDispatchState::Dispatch; }
};

class LagPacketPolicy
{
private:
	const PlayerLagManager* m_LagManager;
	LagSystem* m_LagSystem;
	mutable ke::HashMap<dumb_netadr_t, bool, NetAdrHashPolicy_s> m_BadStateByAddress;

	LagMilliseconds GetPacketLagMs(const _netpacket_t& packet) const;
	PacketLossPercent GetPacketLossPercent(const _netpacket_t& packet) const;
	bool ShouldBypassLag(LagMilliseconds lagTime) const;
	CFakeLagPacketLossMode GetPacketLossMode() const;
	bool ShouldDropPacketBernoulli(PacketLossPercent packetLossPercent) const;
	bool ShouldDropPacketGilbertElliott(const dumb_netadr_t& netadr, PacketLossPercent packetLossPercent) const;

public:
	LagPacketPolicy(const PlayerLagManager* lagManager, LagSystem* lagSystem)
		: m_LagManager(lagManager), m_LagSystem(lagSystem) {
		m_BadStateByAddress.init(32);
	}

	bool IsReady() const { return m_LagManager != nullptr && m_LagSystem != nullptr; }
	PacketDispatchResult HandlePacket(bool newdata, _netpacket_t* packet) const;
};
