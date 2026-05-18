#include <cstddef>
#ifndef UNIT_TEST
#include "../extension.h"
#endif
#include "LagSystem.h"

bool LagSystem::HasReadyPacket(int socket) const
{
	if (!IsValidSocket(socket)) {
		return false;
	}

	const auto& packetQueue = m_LagPackets[socket];
	if (packetQueue.empty()) {
		return false;
	}

	return packetQueue.peek().received <= GetNetTime();
}

bool LagSystem::LagPacket(_netpacket_t* pPacket, float lagTime)
{
	if (pPacket == nullptr) {
		return false;
	}

	if (!IsValidSocket(pPacket->source)) {
		return false;
	}

	auto newPacket = _netpacket_t(*pPacket);

	// Delay the packet by shifting its visible receive time forward.
	newPacket.received += (lagTime / kMillisecondsToSeconds);

	m_LagPackets[newPacket.source].add(newPacket);
	++m_QueueDepths[newPacket.source];
	return true;
}

bool LagSystem::GetNextPacket(int socket, _netpacket_t* destPacket)
{
	if (destPacket == nullptr) {
		return false;
	}

	if (!IsValidSocket(socket)) {
		return false;
	}

	if (!HasReadyPacket(socket)) {
		return false;
	}

	auto packetQueue = &m_LagPackets[socket];
	const _netpacket_t topPacket = packetQueue->pop();
	if (m_QueueDepths[socket] > 0) {
		--m_QueueDepths[socket];
	}

	if (!topPacket.CopyToLivePacket(destPacket)) {
#ifndef UNIT_TEST
		if (CFakeLag_IsDebugEnabled()) {
			g_pSM->LogError(
				myself,
				"[custom_fakelag] Failed to restore queued packet for socket %d: queued_size=%d live_capacity=%d live_data=%p",
				socket,
				topPacket.size,
				destPacket->message.m_nDataBytes > 0 ? destPacket->message.m_nDataBytes : destPacket->size,
				destPacket->data);
		}
#endif
		return false;
	}

	return true;
}
