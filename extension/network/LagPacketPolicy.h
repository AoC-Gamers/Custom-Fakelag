#pragma once

#include "LagSystem.h"
#include "../latency/PlayerLagManager.h"

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

	float GetPacketLagMs(const _netpacket_t& packet) const;
	bool ShouldBypassLag(float lagTime) const;

public:
	LagPacketPolicy(const PlayerLagManager* lagManager, LagSystem* lagSystem)
		: m_LagManager(lagManager), m_LagSystem(lagSystem) {}

	bool IsReady() const { return m_LagManager != nullptr && m_LagSystem != nullptr; }
	PacketDispatchResult HandlePacket(bool newdata, _netpacket_t* packet) const;
};
