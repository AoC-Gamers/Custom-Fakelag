#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include "network/LagPacketPolicy.h"

CDetour* DLagPacket = nullptr;

static EnginePacketAdapter s_EngineAdapter; // No runtime ABI has been certified.
static const PlayerLagManager* s_LagManager = nullptr;
static LagSystem* s_LagSystem = nullptr;
static LagPacketPolicy* s_LagPacketPolicy = nullptr;

DETOUR_DECL_STATIC2(NET_LagPacket, bool, bool, newdata, _netpacket_t*, packet)
{
	if (packet == nullptr || s_LagPacketPolicy == nullptr) {
		return DETOUR_STATIC_CALL(NET_LagPacket)(newdata, packet);
	}

	const auto result = s_LagPacketPolicy->HandlePacket(newdata, packet);
	return result.state == PacketDispatchState::Bypass
		? DETOUR_STATIC_CALL(NET_LagPacket)(newdata, packet) : result.ShouldDispatch();
}

bool CreateNetLagPacketDetour()
{
	DLagPacket = DETOUR_CREATE_STATIC(NET_LagPacket, "NET_LagPacket");
	if (DLagPacket == nullptr) {
		g_pSM->LogError(myself, "NET_LagPacket detour could not be initialized.");
		return false;
	}
	if (!DLagPacket->EnableDetour()) {
		g_pSM->LogError(myself, "NET_LagPacket detour activation failed: memory protection could not be changed.");
		DLagPacket->Destroy();
		DLagPacket = nullptr;
		return false;
	}
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
	if (!lagManager || !pNetTime) return false;
	s_LagManager = lagManager;
	s_LagSystem = new LagSystem(pNetTime, &s_EngineAdapter);
	s_LagPacketPolicy = new LagPacketPolicy(s_LagManager, s_LagSystem, &s_EngineAdapter);
	return true;
}

bool LagDetour_Enable()
{
	if (!s_EngineAdapter.IsRuntimeValidated()) {
		g_pSM->LogError(myself, "[custom_fakelag] Activation refused: engine ABI, reader reconstruction and destination capacity are unverified. See docs/SDK_RUNTIME_REFERENCES.md.");
		return false;
	}
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
	LagDetour_ClearAll();
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

void LagDetour_ClearAll()
{
    if (s_LagSystem) s_LagSystem->ClearAll();
    LagDetour_ClearPacketLossState();
}
void LagDetour_ClearSession(SessionId session)
{
    if (s_LagSystem) s_LagSystem->ClearSession(session);
    if (s_LagPacketPolicy) s_LagPacketPolicy->ClearSession(session);
}
