#include "LagPacketPolicy.h"
#include <cstdlib>

extern ConVar sm_custom_fakelag_loss_mode;

namespace {

const char* GetLossModeName(CFakeLagPacketLossMode mode)
{
	return mode == CFakeLagPacketLossMode::GilbertElliott ? "gilbert-elliott" : "bernoulli";
}

}  // namespace

float LagPacketPolicy::GetPacketLagMs(const _netpacket_t& packet) const
{
	return m_LagManager->GetPlayerLag(packet.from);
}

int LagPacketPolicy::GetPacketLossPercent(const _netpacket_t& packet) const
{
	return m_LagManager->GetPlayerPacketLoss(packet.from);
}

bool LagPacketPolicy::ShouldBypassLag(float lagTime) const
{
	return lagTime <= 0.0f;
}

CFakeLagPacketLossMode LagPacketPolicy::GetPacketLossMode() const
{
	const int modeValue = sm_custom_fakelag_loss_mode.GetInt();
	if (modeValue == static_cast<int>(CFakeLagPacketLossMode::GilbertElliott)) {
		return CFakeLagPacketLossMode::GilbertElliott;
	}

	return CFakeLagPacketLossMode::BernoulliUniform;
}

bool LagPacketPolicy::ShouldDropPacketBernoulli(int packetLossPercent) const
{
	if (packetLossPercent <= 0) {
		return false;
	}

	if (packetLossPercent >= 100) {
		return true;
	}

	const int roll = std::rand() % 100;
	return roll < packetLossPercent;
}

bool LagPacketPolicy::ShouldDropPacketGilbertElliott(const dumb_netadr_t& netadr, int packetLossPercent) const
{
	if (packetLossPercent <= 0) {
		auto existing = m_BadStateByAddress.find(netadr);
		if (existing.found()) {
			m_BadStateByAddress.remove(existing);
		}
		return false;
	}

	static constexpr int kProbabilityBasis = 10000;
	static constexpr int kExitBadProbability = 5000; // average burst length ~= 2 packets.
	int enterBadProbability = (packetLossPercent * kExitBadProbability) / (100 - packetLossPercent);
	if (enterBadProbability < 1) {
		enterBadProbability = 1;
	}

	auto state = m_BadStateByAddress.findForAdd(netadr);
	if (!state.found()) {
		m_BadStateByAddress.add(state, netadr);
		state->value = false;
	}

	const int roll = std::rand() % kProbabilityBasis;
	if (!state->value) {
		if (roll < enterBadProbability) {
			state->value = true;
			return true;
		}

		return false;
	}

	const bool shouldExitBad = roll < kExitBadProbability;
	if (shouldExitBad) {
		state->value = false;
	}

	return true;
}

void LagPacketPolicy::MaybeLogActiveProfileSocket(const _netpacket_t& packet, LagMilliseconds lagTime, PacketLossPercent packetLossPercent) const
{
	if (!CFakeLag_IsDebugEnabled() || packet.source < 0 || packet.source >= kMaxSockets) {
		return;
	}

	if (m_HasLoggedProfiledSocket[packet.source]) {
		return;
	}

	m_HasLoggedProfiledSocket[packet.source] = true;
	g_pSM->LogMessage(
		myself,
		"[custom_fakelag] Active profiled socket=%d addr=%d.%d.%d.%d:%d lag=%.1fms loss=%d%% mode=%s",
		packet.source,
		packet.from.ip[0],
		packet.from.ip[1],
		packet.from.ip[2],
		packet.from.ip[3],
		packet.from.port,
		lagTime,
		packetLossPercent,
		GetLossModeName(GetPacketLossMode()));
}

void LagPacketPolicy::MaybeLogHeldPacket(const _netpacket_t& packet, LagMilliseconds lagTime, PacketLossPercent packetLossPercent, bool dueToPacketLoss) const
{
	if (!CFakeLag_IsDebugEnabled() || packet.source < 0 || packet.source >= kMaxSockets) {
		return;
	}

	const double now = packet.received;
	const float interval = CFakeLag_GetDebugHoldInterval();
	if (now - m_LastHoldLogBySocket[packet.source] < interval) {
		return;
	}

	m_LastHoldLogBySocket[packet.source] = now;
	g_pSM->LogMessage(
		myself,
		"[custom_fakelag] Holding packet socket=%d addr=%d.%d.%d.%d:%d lag=%.1fms loss=%d%% queued=%u reason=%s newdata=1",
		packet.source,
		packet.from.ip[0],
		packet.from.ip[1],
		packet.from.ip[2],
		packet.from.ip[3],
		packet.from.port,
		lagTime,
		packetLossPercent,
		static_cast<unsigned>(m_LagSystem->GetQueueDepth(packet.source)),
		dueToPacketLoss ? "packet_loss" : "lag_queue");
}

PacketDispatchResult LagPacketPolicy::HandlePacket(bool newdata, _netpacket_t* packet) const
{
	if (!IsReady() || packet == nullptr) {
		return { PacketDispatchState::Bypass };
	}

	if (newdata) {
		const float lagTime = GetPacketLagMs(*packet);
		const int packetLossPercent = GetPacketLossPercent(*packet);
		if (lagTime > 0.0f || packetLossPercent > 0) {
			MaybeLogActiveProfileSocket(*packet, lagTime, packetLossPercent);
		}

		const bool shouldDropPacket =
			GetPacketLossMode() == CFakeLagPacketLossMode::GilbertElliott
			? ShouldDropPacketGilbertElliott(packet->from, packetLossPercent)
			: ShouldDropPacketBernoulli(packetLossPercent);
		if (shouldDropPacket) {
			if (m_LagSystem->GetNextPacket(packet->source, packet)) {
				return { PacketDispatchState::Dispatch };
			}

			MaybeLogHeldPacket(*packet, lagTime, packetLossPercent, true);
			return { PacketDispatchState::Hold };
		}

		if (ShouldBypassLag(lagTime)) {
			return { PacketDispatchState::Dispatch };
		}

		if (!m_LagSystem->LagPacket(packet, lagTime)) {
			return { PacketDispatchState::Dispatch };
		}

		if (m_LagSystem->GetNextPacket(packet->source, packet)) {
			return { PacketDispatchState::Dispatch };
		}

		MaybeLogHeldPacket(*packet, lagTime, packetLossPercent, false);
		return { PacketDispatchState::Hold };
	}

	if (m_LagSystem->GetNextPacket(packet->source, packet)) {
		return { PacketDispatchState::Dispatch };
	}

	return { PacketDispatchState::Hold };
}
