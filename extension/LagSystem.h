#ifndef _CUSTOM_FAKELAG_LAG_SYSTEM_H_
#define _CUSTOM_FAKELAG_LAG_SYSTEM_H_

#include <amtl/am-priority-queue.h>
#include "net_structures.h"

static constexpr int kMaxSockets = 6;

struct PacketEarlier {
	constexpr bool operator ()(const _netpacket_t& left, const _netpacket_t& right) const {
		return left.received < right.received;
	}
};

class LagSystem {
private:
	ke::PriorityQueue<_netpacket_t, PacketEarlier> m_LagPackets[kMaxSockets];
	const double* m_pNetTime;

	double GetNetTime() const { return *m_pNetTime; }

public:
	explicit LagSystem(const double* pNetTime) : m_pNetTime(pNetTime) {
		assert(pNetTime != nullptr);
	}

	void LagPacket(_netpacket_t* pPacket, float lagTime);
	bool GetNextPacket(int socket, _netpacket_t* destPacket);
};

#endif // _CUSTOM_FAKELAG_LAG_SYSTEM_H_
