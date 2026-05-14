#include "LagPacketPolicy.h"

float LagPacketPolicy::GetPacketLagMs(const _netpacket_t& packet) const
{
	return m_LagManager->GetPlayerLag(packet.from);
}

bool LagPacketPolicy::ShouldBypassLag(float lagTime) const
{
	return lagTime <= 0.0f;
}

PacketDispatchResult LagPacketPolicy::HandlePacket(bool newdata, _netpacket_t* packet) const
{
	if (!IsReady() || packet == nullptr) {
		return { PacketDispatchState::Bypass };
	}

	if (newdata) {
		const float lagTime = GetPacketLagMs(*packet);
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
