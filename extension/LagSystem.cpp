#include <cstddef>
#include <cstring>
#include "LagSystem.h"

void LagSystem::LagPacket(_netpacket_t* pPacket, float lagTime)
{
	auto newPacket = _netpacket_t(*pPacket);

	// Delay the packet by shifting its visible receive time forward.
	newPacket.received += (lagTime / 1000.0f);

	m_LagPackets[newPacket.source].add(newPacket);
}

bool LagSystem::GetNextPacket(int socket, _netpacket_t* destPacket)
{
	auto packetQueue = &m_LagPackets[socket];
	if (packetQueue->empty()) {
		return false;
	}

	if (packetQueue->peek().received > GetNetTime()) {
		return false;
	}

	const _netpacket_t topPacket = packetQueue->pop();

	destPacket->from = topPacket.from;
	destPacket->pNext = nullptr;
	destPacket->received = topPacket.received;
	destPacket->size = topPacket.size;
	destPacket->wiresize = topPacket.wiresize;
	destPacket->stream = topPacket.stream;
	std::memcpy(destPacket->data, topPacket.data, topPacket.size);
	return true;
}
