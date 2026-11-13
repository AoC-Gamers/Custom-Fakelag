#pragma once

#include "LagSystem.h"
#include "NetworkConfig.h"
#include "../latency/PlayerLagManager.h"
#include <unordered_map>
#include <random>

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
	mutable std::unordered_map<uint64_t, bool> m_BadStateBySession;
	const EnginePacketAdapter* m_Adapter;
	mutable std::mt19937 m_Random{0xCF123u};
	mutable double m_LastHoldLogBySocket[kMaxSockets] = {};
	mutable bool m_HasLoggedProfiledSocket[kMaxSockets] = {};

	LagMilliseconds GetPacketLagMs(const _netpacket_t& packet) const;
	PacketLossPercent GetPacketLossPercent(const _netpacket_t& packet) const;
	bool ShouldBypassLag(LagMilliseconds lagTime) const;
	CFakeLagPacketLossMode GetPacketLossMode() const;
	bool ShouldDropPacketBernoulli(PacketLossPercent packetLossPercent) const;
	bool ShouldDropPacketGilbertElliott(SessionId session, PacketLossPercent packetLossPercent) const;
	void MaybeLogActiveProfileSocket(const _netpacket_t& packet, LagMilliseconds lagTime, PacketLossPercent packetLossPercent) const;
	void MaybeLogHeldPacket(const _netpacket_t& packet, LagMilliseconds lagTime, PacketLossPercent packetLossPercent, bool dueToPacketLoss) const;

public:
	LagPacketPolicy(const PlayerLagManager* lagManager, LagSystem* lagSystem, const EnginePacketAdapter* adapter)
		: m_LagManager(lagManager), m_LagSystem(lagSystem), m_Adapter(adapter) {}

	bool IsReady() const { return m_LagManager != nullptr && m_LagSystem != nullptr; }
	void ClearPacketLossState() { m_BadStateBySession.clear();
		for (int i = 0; i < kMaxSockets; ++i) { m_LastHoldLogBySocket[i] = 0; m_HasLoggedProfiledSocket[i] = false; } }
	size_t GetLossStateCount() const { return m_BadStateBySession.size(); }
	void ClearSession(SessionId session) { m_BadStateBySession.erase(session.value); }
	PacketDispatchResult HandlePacket(bool newdata, _netpacket_t* packet) const;
};
