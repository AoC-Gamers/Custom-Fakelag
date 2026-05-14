#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include "PlayerLagManager.h"
#include "LagSystem.h"

CDetour* DLagPacket = nullptr;

static const PlayerLagManager* s_LagManager = nullptr;
static LagSystem* s_LagSystem = nullptr;

float getLagPacketMs(const _netpacket_t& packet)
{
	return s_LagManager->GetPlayerLag(packet.from);
}

DETOUR_DECL_STATIC2(NET_LagPacket, bool, bool, newdata, _netpacket_t*, packet)
{
	if (newdata) {
		const float lagTime = getLagPacketMs(*packet);
		if (lagTime > 0.0) {
			s_LagSystem->LagPacket(packet, lagTime);
		} else {
			return true;
		}
	}

	return s_LagSystem->GetNextPacket(packet->source, packet);
}

bool CreateNetLagPacketDetour()
{
	DLagPacket = DETOUR_CREATE_STATIC(NET_LagPacket, "NET_LagPacket");
	if (DLagPacket == nullptr) {
		g_pSM->LogError(myself, "NET_LagPacket detour could not be initialized.");
		return false;
	}
	DLagPacket->EnableDetour();
	return true;
}

void RemoveNetLagPacketDetour()
{
	if (DLagPacket != nullptr) {
		DLagPacket->Destroy();
		DLagPacket = nullptr;
	}
}

bool LagDetour_Init(const PlayerLagManager* lagManager, const double* pNetTime)
{
	s_LagManager = lagManager;
	s_LagSystem = new LagSystem(pNetTime);
	if (!CreateNetLagPacketDetour()) {
		LagDetour_Shutdown();
		return false;
	}
	return true;
}

void LagDetour_Shutdown()
{
	RemoveNetLagPacketDetour();
	delete s_LagSystem;
	s_LagSystem = nullptr;
	s_LagManager = nullptr;
}
