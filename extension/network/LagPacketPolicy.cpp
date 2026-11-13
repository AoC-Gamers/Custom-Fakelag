#include "LagPacketPolicy.h"
#ifndef UNIT_TEST
#include "../extension.h"
#endif
#include "LossModel.h"

#ifndef UNIT_TEST
namespace {

const char* GetLossModeName(CFakeLagPacketLossMode mode)
{
	return mode == CFakeLagPacketLossMode::GilbertElliott ? "gilbert-elliott" : "bernoulli";
}

}  // namespace
#endif

float LagPacketPolicy::GetPacketLagMs(const _netpacket_t& packet) const
{
	return m_LagManager->GetPlayerLag(AddressKey(packet.from));
}

int LagPacketPolicy::GetPacketLossPercent(const _netpacket_t& packet) const
{
	return m_LagManager->GetPlayerPacketLoss(AddressKey(packet.from));
}

bool LagPacketPolicy::ShouldBypassLag(float lagTime) const
{
	return lagTime <= 0.0f;
}

CFakeLagPacketLossMode LagPacketPolicy::GetPacketLossMode() const
{
	return CFakeLag_GetPacketLossMode();
}

bool LagPacketPolicy::ShouldDropPacketBernoulli(int packetLossPercent) const
{
	if (packetLossPercent <= 0) {
		return false;
	}

	if (packetLossPercent >= 100) {
		return true;
	}

	return std::generate_canonical<double, 53>(m_Random) < packetLossPercent / 100.0;
}

bool LagPacketPolicy::ShouldDropPacketGilbertElliott(SessionId session, int packetLossPercent) const
{
	if (!session.value) return false;
	if (packetLossPercent <= 0) { m_BadStateBySession.erase(session.value); return false; }
	return GilbertElliottDrop(m_BadStateBySession[session.value], packetLossPercent,
		std::generate_canonical<double, 53>(m_Random));
}

void LagPacketPolicy::MaybeLogActiveProfileSocket(const _netpacket_t& packet, LagMilliseconds lagTime, PacketLossPercent packetLossPercent) const
{
#ifndef UNIT_TEST
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
#else
	(void)packet; (void)lagTime; (void)packetLossPercent;
#endif
}

void LagPacketPolicy::MaybeLogHeldPacket(const _netpacket_t& packet, LagMilliseconds lagTime, PacketLossPercent packetLossPercent, bool dueToPacketLoss) const
{
#ifndef UNIT_TEST
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
#else
	(void)packet; (void)lagTime; (void)packetLossPercent; (void)dueToPacketLoss;
#endif
}

PacketDispatchResult LagPacketPolicy::HandlePacket(bool newdata, _netpacket_t* packet) const
{
	if (!IsReady() || packet == nullptr || m_Adapter == nullptr) {
		return { PacketDispatchState::Bypass };
	}

	if (m_LagManager->GetLagCount() == 0 && m_LagSystem->GetPendingCount() == 0)
		return { PacketDispatchState::Bypass };
	const size_t capacity = m_Adapter->DestinationCapacity(*packet, newdata);
	if (capacity == 0) return { PacketDispatchState::Bypass };
	if (newdata) {
		const float lagTime = GetPacketLagMs(*packet);
		const int packetLossPercent = GetPacketLossPercent(*packet);
		if (lagTime > 0.0f || packetLossPercent > 0) {
			MaybeLogActiveProfileSocket(*packet, lagTime, packetLossPercent);
		}

		const bool shouldDropPacket =
			GetPacketLossMode() == CFakeLagPacketLossMode::GilbertElliott
			? ShouldDropPacketGilbertElliott(m_LagManager->GetSession(AddressKey(packet->from)), packetLossPercent)
			: ShouldDropPacketBernoulli(packetLossPercent);
		if (shouldDropPacket) {
			m_LagSystem->CountRequestedLoss();
			if (m_LagSystem->GetNextPacket(packet->source, packet, capacity)) {
				return { PacketDispatchState::Dispatch };
			}

			MaybeLogHeldPacket(*packet, lagTime, packetLossPercent, true);
			return { PacketDispatchState::Hold };
		}

		if (ShouldBypassLag(lagTime)) {
			return { PacketDispatchState::Dispatch };
		}

		m_LagSystem->LagPacket(packet, Milliseconds(lagTime),
			m_LagManager->GetSession(AddressKey(packet->from)));
		// Invalid capture and budget saturation drop newest, never fail open.

		if (m_LagSystem->GetNextPacket(packet->source, packet, capacity)) {
			return { PacketDispatchState::Dispatch };
		}

		MaybeLogHeldPacket(*packet, lagTime, packetLossPercent, false);
		return { PacketDispatchState::Hold };
	}

	if (m_LagSystem->GetNextPacket(packet->source, packet, capacity)) {
		return { PacketDispatchState::Dispatch };
	}

	return { PacketDispatchState::Hold };
}
