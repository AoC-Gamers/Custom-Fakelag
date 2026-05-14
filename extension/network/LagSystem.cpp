#include <cstddef>
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
	topPacket.CopyToLivePacket(destPacket);
	return true;
}
