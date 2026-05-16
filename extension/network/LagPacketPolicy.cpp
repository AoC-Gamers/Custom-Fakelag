#include "LagPacketPolicy.h"
#include <cstdlib>

extern ConVar sm_custom_fakelag_loss_mode;

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

PacketDispatchResult LagPacketPolicy::HandlePacket(bool newdata, _netpacket_t* packet) const
{
	if (!IsReady() || packet == nullptr) {
		return { PacketDispatchState::Bypass };
	}

	if (newdata) {
		const float lagTime = GetPacketLagMs(*packet);
		const int packetLossPercent = GetPacketLossPercent(*packet);
		const bool shouldDropPacket =
			GetPacketLossMode() == CFakeLagPacketLossMode::GilbertElliott
			? ShouldDropPacketGilbertElliott(packet->from, packetLossPercent)
			: ShouldDropPacketBernoulli(packetLossPercent);
		if (shouldDropPacket) {
			if (m_LagSystem->GetNextPacket(packet->source, packet)) {
				return { PacketDispatchState::Dispatch };
			}

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

		return { PacketDispatchState::Hold };
	}

	if (m_LagSystem->GetNextPacket(packet->source, packet)) {
		return { PacketDispatchState::Dispatch };
	}

	return { PacketDispatchState::Hold };
}
