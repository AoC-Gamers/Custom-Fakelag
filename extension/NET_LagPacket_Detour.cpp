#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include "network/LagPacketPolicy.h"
#include "network/L4D2PacketAdapter.h"
#ifdef _WIN32
#include <windows.h>
#endif

extern IGameConfig* g_pGameConf;
CDetour* DLagPacket = nullptr;

static L4D2PacketAdapter s_EngineAdapter;
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

bool RemoveNetLagPacketDetour()
{
	if (DLagPacket != nullptr) {
		if (!DLagPacket->Destroy()) {
			g_pSM->LogError(myself, "[custom_fakelag] Detour removal failed; hook and trampoline remain owned and active.");
			return false;
		}
		DLagPacket = nullptr;
	}
	return true;
}

bool LagDetour_Init(const PlayerLagManager* lagManager, const double* pNetTime)
{
	if (!lagManager || !pNetTime) return false;
	s_LagManager = lagManager;
	void* lagFunction = nullptr;
	if (!g_pGameConf->GetMemSig("NET_LagPacket", &lagFunction) || !lagFunction) return false;
	if (!s_EngineAdapter.Initialize(lagFunction, pNetTime))
		g_pSM->LogError(myself, "[custom_fakelag] Packet adapter refused: %s", s_EngineAdapter.Diagnostic());
	else {
		g_pSM->LogMessage(myself, "[custom_fakelag] Packet adapter accepted: NET_LagPacket=%p net_time=%p (%s)",
			lagFunction, static_cast<const void*>(pNetTime), s_EngineAdapter.Diagnostic());
#ifdef _WIN32
		HMODULE owner = nullptr;
		char path[32768];
		if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
			reinterpret_cast<LPCSTR>(lagFunction), &owner) && GetModuleFileNameA(owner, path, sizeof(path)))
			g_pSM->LogMessage(myself, "[custom_fakelag] Accepted engine module: %s base=%p", path, static_cast<void*>(owner));
#endif
	}
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

bool LagDetour_Disable()
{
	const bool wasEnabled = DLagPacket != nullptr;
	if (!RemoveNetLagPacketDetour()) return false;
	LagDetour_ClearAll();

	if (wasEnabled && CFakeLag_IsDebugEnabled()) {
		g_pSM->LogMessage(myself, "[custom_fakelag] NET_LagPacket detour disabled.");
	}
	return true;
}

bool LagDetour_IsEnabled()
{
	return DLagPacket != nullptr;
}

bool LagDetour_Shutdown()
{
	if (!LagDetour_Disable()) return false;
	delete s_LagPacketPolicy;
	s_LagPacketPolicy = nullptr;
	delete s_LagSystem;
	s_LagSystem = nullptr;
	s_LagManager = nullptr;
	return true;
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

#ifdef CUSTOM_FAKELAG_ENGINE_HARNESS
void LagDetour_TestSnapshot(size_t& pending, size_t& bytes, size_t& lossStates, PacketCounters& counters)
{
    if (!s_LagSystem) return;
    lossStates = s_LagPacketPolicy ? s_LagPacketPolicy->GetLossStateCount() : 0;
    pending = s_LagSystem->GetPendingCount();
    bytes = s_LagSystem->GetRetainedBytes();
    counters = s_LagSystem->Counters();
}
#endif
