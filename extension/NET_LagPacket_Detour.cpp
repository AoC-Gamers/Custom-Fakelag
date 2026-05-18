#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include "network/LagPacketPolicy.h"

CDetour* DLagPacket = nullptr;

static const PlayerLagManager* s_LagManager = nullptr;
static LagSystem* s_LagSystem = nullptr;
static LagPacketPolicy* s_LagPacketPolicy = nullptr;

DETOUR_DECL_STATIC2(NET_LagPacket, bool, bool, newdata, _netpacket_t*, packet)
{
	if (packet == nullptr || s_LagPacketPolicy == nullptr) {
		return false;
	}

	const auto result = s_LagPacketPolicy->HandlePacket(newdata, packet);
	return result.ShouldDispatch();
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
	s_LagPacketPolicy = new LagPacketPolicy(s_LagManager, s_LagSystem);
	return true;
}

bool LagDetour_Enable()
{
	if (DLagPacket != nullptr) {
		return true;
	}

	if (s_LagPacketPolicy == nullptr) {
		return false;
	}

	const bool created = CreateNetLagPacketDetour();
	if (created && CFakeLag_IsDebugEnabled()) {
		g_pSM->LogMessage(myself, "[custom_fakelag] NET_LagPacket detour enabled.");
	}

	return created;
}

void LagDetour_Disable()
{
	if (DLagPacket == nullptr) {
		return;
	}

	RemoveNetLagPacketDetour();
	if (CFakeLag_IsDebugEnabled()) {
		g_pSM->LogMessage(myself, "[custom_fakelag] NET_LagPacket detour disabled.");
	}
}

bool LagDetour_IsEnabled()
{
	return DLagPacket != nullptr;
}

void LagDetour_Shutdown()
{
	LagDetour_Disable();
	delete s_LagPacketPolicy;
	s_LagPacketPolicy = nullptr;
	delete s_LagSystem;
	s_LagSystem = nullptr;
	s_LagManager = nullptr;
}

void LagDetour_ClearPacketLossState()
{
	if (s_LagPacketPolicy != nullptr) {
		s_LagPacketPolicy->ClearPacketLossState();
	}
}
