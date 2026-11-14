#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include "tier1/convar.h"
#include <cstdlib>
#include <cstring>

extern ISmmAPI* g_SMAPI;
extern CustomFakelag g_Sample;
SH_DECL_HOOK0_void(IServerGameDLL, LevelShutdown, SH_NOATTRIB, 0);
namespace {
void LossModeChanged(IConVar*, const char*, float oldValue) { g_Sample.OnLossModeChanged(static_cast<int>(oldValue)); }
void DetourModeChanged(IConVar*, const char*, float oldValue) { g_Sample.OnDetourModeChanged(static_cast<int>(oldValue)); }
void LanPolicyChanged(IConVar* var, const char*, float) {
	if (!std::strcmp(var->GetName(), "sv_lan") || !std::strcmp(var->GetName(), "sm_custom_fakelag_allow_lan"))
		g_Sample.OnLanPolicyChanged();
}
void LanPolicyFrame(bool) { g_Sample.CheckLanPolicy(); }
}

ConVar sm_custom_fakelag_allow_lan("sm_custom_fakelag_allow_lan", "0", FCVAR_NOTIFY,
	"Allow artificial latency/loss with sv_lan 1 for explicit testing. Disabling clears all profiles.", true, 0.0f, true, 1.0f);

ConVar sm_custom_fakelag_loss_mode(
	"sm_custom_fakelag_loss_mode",
	"0",
	FCVAR_NOTIFY,
	"Packet loss simulation mode: 0 = Bernoulli uniform, 1 = Gilbert-Elliott.",
	true,
	0.0f,
	true,
	1.0f);

ConVar sm_custom_fakelag_debug(
	"sm_custom_fakelag_debug",
	"0",
	FCVAR_NOTIFY,
	"Enable production-safe debug logging for Custom Fakelag internals.",
	true,
	0.0f,
	true,
	1.0f);

ConVar sm_custom_fakelag_debug_hold_interval(
	"sm_custom_fakelag_debug_hold_interval",
	"5.0",
	FCVAR_NOTIFY,
	"Minimum seconds between repeated Custom Fakelag hold logs per socket.",
	true,
	0.1f,
	true,
	60.0f);

ConVar sm_custom_fakelag_detour_mode(
	"sm_custom_fakelag_detour_mode",
	"0",
	FCVAR_NOTIFY,
	"NET_LagPacket detour mode: 0 = lazy/on-demand, 1 = always on while extension is loaded.",
	true,
	0.0f,
	true,
	1.0f);

CustomFakelag g_Sample;
extern sp_nativeinfo_t g_CFakeLagNatives[];
IGameConfig* g_pGameConf = nullptr;

namespace {
constexpr float kNoLag = 0.0f;

void CloseGameConfig()
{
	if (g_pGameConf != nullptr) {
		gameconfs->CloseGameConfigFile(g_pGameConf);
		g_pGameConf = nullptr;
	}
}
}

CFakeLagPacketLossMode CFakeLag_GetPacketLossMode() { return g_Sample.GetPacketLossMode(); }

bool CFakeLag_IsDebugEnabled()
{
	return sm_custom_fakelag_debug.GetBool();
}

float CFakeLag_GetDebugHoldInterval()
{
	return sm_custom_fakelag_debug_hold_interval.GetFloat();
}

bool CFakeLag_IsAlwaysOnDetourMode()
{
	return sm_custom_fakelag_detour_mode.GetInt() != 0;
}

bool CFakeLag_IsModeChanging() { return g_Sample.IsModeChanging(); }
bool CFakeLag_IsLanBlocked() { return g_Sample.IsLanBlocked(); }
bool CustomFakelag::IsLanBlocked() const {
	return CFakeLag_LanPolicyBlocks(m_Lan == nullptr || m_Lan->GetBool(), sm_custom_fakelag_allow_lan.GetBool());
}
void CustomFakelag::OnLanPolicyChanged()
{
	if (!m_Loaded) return;
	if (m_ChangingLanPolicy) { m_LanPolicyDirty = true; return; }
	m_LanPolicyDirty = false;
	const bool blocked = IsLanBlocked();
	if (blocked == m_LanBlocked) return;
	m_ChangingLanPolicy = true;
	m_LanBlocked = blocked;
	if (blocked && m_PlayerProfileService && !m_PlayerProfileService->EnforceLanPolicy())
		g_pSM->LogError(myself, "[custom_fakelag] LAN profiles/queues cleared, but hook removal failed; infrastructure retained and packet simulation bypassed.");
	if (m_PlayerProfileApiBridge) m_PlayerProfileApiBridge->OnLanPolicyChanged(blocked);
	g_pSM->LogMessage(myself, "[custom_fakelag] LAN policy blocked=%d; cleared profiles are never restored automatically.", blocked);
	m_ChangingLanPolicy = false;
}
void CustomFakelag::OnSessionInvalidated(SessionId session) { LagDetour_ClearSession(session); }
void CustomFakelag::OnLevelShutdown() { ResetState(); }

void CustomFakelag::OnClientNetAdrResolutionFailed(int client)
{
	if (CFakeLag_IsDebugEnabled()) {
		g_pSM->LogMessage(myself, "[custom_fakelag] Failed to resolve network address for client index %d.", client);
	}
}

void CustomFakelag::OnPlayerLagChanged(int client, const dumb_netadr_t& netadr, float lagTime)
{
	g_pSM->LogMessage(myself,
		"Lagging player index %d with net address %d.%d.%d.%d:%d for %.01fms",
		client,
		netadr.ip[0],
		netadr.ip[1],
		netadr.ip[2],
		netadr.ip[3],
		netadr.port,
		lagTime);
}

ClientEligibility CustomFakelag::GetClientEligibility(int client, IGamePlayer** player) const
{
	IGamePlayer* gamePlayer = playerhelpers->GetGamePlayer(client);
	if (player != nullptr) {
		*player = gamePlayer;
	}

	if (gamePlayer == nullptr || !gamePlayer->IsConnected()) {
		return ClientEligibility::Invalid;
	}

	if (gamePlayer->IsFakeClient()) {
		return ClientEligibility::FakeClient;
	}

	return ClientEligibility::Supported;
}

int CustomFakelag::GetMaxClients() const
{
	return playerhelpers->GetMaxClients();
}

bool CustomFakelag::SDK_OnLoad(char* error, size_t maxlen, bool late)
{
	char conf_error[255];
	if (!gameconfs->LoadGameConfigFile("custom_fakelag.games", &g_pGameConf, &conf_error[0], sizeof(conf_error)))
	{
		if (error)
		{
			ke::SafeSprintf(error, maxlen, "Could not read custom_fakelag.games: %s", &conf_error[0]);
		}
		return false;
	}

	double* pNetTime = nullptr;
	if (!g_pGameConf->GetAddress("net_time", reinterpret_cast<void**>(&pNetTime)) || pNetTime == nullptr) {
		CloseGameConfig();
		ke::SafeSprintf(error, maxlen, "Could not find net_time address in memory");
		return false;
	}

	m_NetAdrResolver = new EngineClientNetAdrResolver(engine);
	m_LagManager = new PlayerLagManager(m_NetAdrResolver, this);

	// Initialize Detour System.
	CDetourManager::Init(g_pSM->GetScriptingEngine(), g_pGameConf);

	if (!LagDetour_Init(m_LagManager, pNetTime)) {
		ReleaseResources();
		ke::SafeSprintf(error, maxlen, "Could not detour Net_LagPacket.");
		return false;
	}

	m_PlayerProfileApiBridge = new PlayerProfileApiBridge();
	if (!m_PlayerProfileApiBridge->Initialize()) {
		ReleaseResources();
		ke::SafeSprintf(error, maxlen, "Could not create Custom Fakelag forwards.");
		return false;
	}

	m_PlayerProfileService = new PlayerProfileService(m_LagManager, m_PlayerProfileApiBridge, this);

#if SOURCE_ENGINE >= SE_ORANGEBOX
	ICvar* cvarIface = nullptr;
	cvarIface = static_cast<ICvar*>(g_SMAPI->VInterfaceMatch(g_SMAPI->GetEngineFactory(), CVAR_INTERFACE_VERSION));
	if (cvarIface == nullptr) {
		if (error != nullptr && maxlen > 0) {
			ke::SafeSprintf(error, maxlen, "Could not find interface: %s", CVAR_INTERFACE_VERSION);
		}
		ReleaseResources();
		return false;
	}
	g_pCVar = cvarIface;
#endif
	m_Lan = g_pCVar->FindVar("sv_lan");
	if (!m_Lan) {
		ReleaseResources();
		ke::SafeSprintf(error, maxlen, "Could not find sv_lan for fakelag LAN policy.");
		return false;
	}
	ConVar_Register(0, this);

	if (CFakeLag_IsDebugEnabled()) {
		g_pSM->LogMessage(
			myself,
			"[custom_fakelag] Loaded. net_time=%p loss_mode=%d debug_hold_interval=%.1f detour_on_load=0",
			pNetTime,
			sm_custom_fakelag_loss_mode.GetInt(),
			CFakeLag_GetDebugHoldInterval());
	}

	if (!CFakeLag_IsLanBlocked() && CFakeLag_IsAlwaysOnDetourMode() && !LagDetour_Enable()) {
		ConVar_Unregister();
		ReleaseResources();
		ke::SafeSprintf(error, maxlen, "Could not enable NET_LagPacket detour in always-on mode.");
		return false;
	}

	sharesys->AddNatives(myself, g_CFakeLagNatives);
	sharesys->RegisterLibrary(myself, "custom_fakelag");
	playerhelpers->AddClientListener(this);
	SH_ADD_HOOK(IServerGameDLL, LevelShutdown, gamedll, SH_MEMBER(this, &CustomFakelag::OnLevelShutdown), false);
	g_pSM->LogMessage(myself, "[custom_fakelag] Packet adapter initialized; unsupported engine identities will reject profile activation.");
	m_Loaded = true;
	g_pCVar->InstallGlobalChangeCallback(LanPolicyChanged);
	g_pSM->AddGameFrameHook(LanPolicyFrame);
	OnLanPolicyChanged();
	sm_custom_fakelag_loss_mode.InstallChangeCallback(LossModeChanged);
	sm_custom_fakelag_detour_mode.InstallChangeCallback(DetourModeChanged);
	return true;
}

void CustomFakelag::SDK_OnAllLoaded()
{
}

bool CustomFakelag::RegisterConCommandBase(ConCommandBase* pVar)
{
	return META_REGCVAR(pVar);
}

void CustomFakelag::SDK_OnUnload() {
	m_Loaded = false;
	g_pCVar->RemoveGlobalChangeCallback(LanPolicyChanged);
	g_pSM->RemoveGameFrameHook(LanPolicyFrame);
	SH_REMOVE_HOOK(IServerGameDLL, LevelShutdown, gamedll, SH_MEMBER(this, &CustomFakelag::OnLevelShutdown), false);
	playerhelpers->RemoveClientListener(this);

	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->ClearAllPlayerProfiles();
	} else if (m_LagManager != nullptr) {
		m_LagManager->ClearAll();
	}
	ConVar_Unregister();
	ReleaseResources();
}

void CustomFakelag::ReleaseResources()
{
	if (!LagDetour_Shutdown()) {
		// SourceMod's unload callback is void: returning cannot veto dlclose.
		// Stop before code containing a live callback can be unmapped.
		g_pSM->LogError(myself, "[custom_fakelag] Fatal: cannot unload while NET_LagPacket remains patched. No hook infrastructure was freed.");
		std::abort();
	}
	delete m_PlayerProfileService;
	m_PlayerProfileService = nullptr;
	if (m_PlayerProfileApiBridge != nullptr) {
		m_PlayerProfileApiBridge->Shutdown();
		delete m_PlayerProfileApiBridge;
		m_PlayerProfileApiBridge = nullptr;
	}

	delete m_LagManager;
	m_LagManager = nullptr;
	delete m_NetAdrResolver;
	m_NetAdrResolver = nullptr;

	if (g_pGameConf != nullptr) {
		CloseGameConfig();
	}
}

void CustomFakelag::OnClientConnected(int client)
{
	if (m_PlayerProfileService) m_PlayerProfileService->OnClientDisconnecting(client);
}

void CustomFakelag::OnClientDisconnecting(int client)
{
	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->OnClientDisconnecting(client);
	}
}

ProfileChangeResult CustomFakelag::SetPlayerProfile(int client, float lagTime, int packetLossPercent)
{
	if (m_PlayerProfileService != nullptr) {
		return m_PlayerProfileService->SetPlayerProfile(client, lagTime, packetLossPercent);
	}
	return ProfileChangeResult::Error;
}

bool CustomFakelag::GetPlayerProfile(int client, float& lagTime, int& packetLossPercent) const
{
	if (m_PlayerProfileService == nullptr) {
		lagTime = kNoLag;
		packetLossPercent = 0;
		return false;
	}

	lagTime = m_PlayerProfileService->GetPlayerLatency(client);
	packetLossPercent = m_PlayerProfileService->GetPlayerPacketLoss(client);
	return lagTime > kNoLag || packetLossPercent > 0;
}

bool CustomFakelag::HasPlayerProfile(int client) const
{
	if (m_PlayerProfileService == nullptr) {
		return false;
	}

	return m_PlayerProfileService->HasPlayerLatency(client)
		|| m_PlayerProfileService->HasPlayerPacketLoss(client);
}

ProfileChangeResult CustomFakelag::ClearPlayerProfile(int client)
{
	if (m_PlayerProfileService != nullptr) {
		return m_PlayerProfileService->SetPlayerProfile(client, kNoLag, 0);
	}
	return ProfileChangeResult::Error;
}

void CustomFakelag::SetPacketLossMode(CFakeLagPacketLossMode mode)
{
	sm_custom_fakelag_loss_mode.SetValue(static_cast<int>(mode));
}

void CustomFakelag::OnLossModeChanged(int oldMode)
{
	if (!m_Loaded || m_ChangingMode) return;
	m_ChangingMode = true;
	if (!ResetState()) {
		g_pSM->LogError(myself, "[custom_fakelag] Loss mode change aborted: detour synchronization failed.");
		sm_custom_fakelag_loss_mode.SetValue(oldMode);
		m_ChangingMode = false;
		return;
	}
	if (m_PlayerProfileApiBridge)
		m_PlayerProfileApiBridge->OnPacketLossModeChanged(static_cast<CFakeLagPacketLossMode>(oldMode), GetPacketLossMode());
	m_ChangingMode = false;
}
void CustomFakelag::OnDetourModeChanged(int oldMode)
{
	if (!m_Loaded || m_ChangingMode) return;
	m_ChangingMode = true;
	if (!ResetState()) {
		g_pSM->LogError(myself, "[custom_fakelag] Detour mode change failed; previous mode restored and hook infrastructure retained.");
		sm_custom_fakelag_detour_mode.SetValue(oldMode);
	}
	m_ChangingMode = false;
}

CFakeLagPacketLossMode CustomFakelag::GetPacketLossMode() const
{
	const int modeValue = sm_custom_fakelag_loss_mode.GetInt();
	if (modeValue == static_cast<int>(CFakeLagPacketLossMode::GilbertElliott)) {
		return CFakeLagPacketLossMode::GilbertElliott;
	}

	return CFakeLagPacketLossMode::BernoulliUniform;
}

bool CustomFakelag::ClearAllPlayerProfiles()
{
	return m_PlayerProfileService && m_PlayerProfileService->ClearAllPlayerProfiles();
}

bool CustomFakelag::ResetState()
{
	const bool synchronized = ClearAllPlayerProfiles();
	LagDetour_ClearAll();
	return synchronized;
}

bool CustomFakelag::IsClientSupported(int client) const
{
	return m_PlayerProfileService != nullptr && m_PlayerProfileService->IsClientSupported(client);
}

bool CustomFakelag::ThrowIfUnsupportedClient(IPluginContext* context, int client) const
{
	return m_PlayerProfileService != nullptr && m_PlayerProfileService->ThrowIfUnsupportedClient(context, client);
}

int CustomFakelag::GetProfiledClientCount() const
{
	if (m_PlayerProfileService != nullptr) {
		return m_PlayerProfileService->GetLaggedClientCount();
	}

	return 0;
}

cell_t CFakeLag_SetPlayerProfile(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	float lagTime = sp_ctof(params[2]);
	int packetLossPercent = params[3];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	if (!ValidLatency(lagTime)) {
		return pContext->ThrowNativeError("Lag time must be finite and between 0 and 10000 milliseconds.");
	}

	if (packetLossPercent < 0 || packetLossPercent > 100) {
		return pContext->ThrowNativeError("Packet loss percent must be between 0 and 100.");
	}

	const auto result = g_Sample.SetPlayerProfile(client, lagTime, packetLossPercent);
	if (result == ProfileChangeResult::LanBlocked)
		return pContext->ThrowNativeError("Fakelag is blocked by sv_lan 1. Use sm_custom_fakelag_allow_lan 1 only for explicit tests.");
	if (result == ProfileChangeResult::Vetoed) return 0;
	if (result == ProfileChangeResult::Error)
		return pContext->ThrowNativeError("Profile was not applied: invalid latency, forward execution error, unresolved address, reentrant mutation or detour operation failed.");
	return 1;
}

cell_t CFakeLag_GetPlayerProfile(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	cell_t* profileAddr = nullptr;
	if (pContext->LocalToPhysAddr(params[2], &profileAddr) != SP_ERROR_NONE) {
		return pContext->ThrowNativeError("Invalid profile buffer.");
	}

	float lagTime = kNoLag;
	int packetLossPercent = 0;
	const bool hasProfile = g_Sample.GetPlayerProfile(client, lagTime, packetLossPercent);
	profileAddr[0] = sp_ftoc(lagTime);
	profileAddr[1] = packetLossPercent;
	return hasProfile ? 1 : 0;
}

cell_t CFakeLag_HasPlayerProfile(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	return g_Sample.HasPlayerProfile(client) ? 1 : 0;
}

cell_t CFakeLag_ClearPlayerProfile(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	const auto result = g_Sample.ClearPlayerProfile(client);
	if (result == ProfileChangeResult::Error) return pContext->ThrowNativeError("Profile could not be cleared.");
	return ProfileChangeSucceeded(result) ? 1 : 0;
}

cell_t CFakeLag_SetPacketLossMode(IPluginContext* pContext, const cell_t* params)
{
	const int modeValue = params[1];
	if (modeValue < static_cast<int>(CFakeLagPacketLossMode::BernoulliUniform)
		|| modeValue > static_cast<int>(CFakeLagPacketLossMode::GilbertElliott)) {
		return pContext->ThrowNativeError("Packet loss mode must be 0 (BernoulliUniform) or 1 (GilbertElliott).");
	}

	g_Sample.SetPacketLossMode(static_cast<CFakeLagPacketLossMode>(modeValue));
	if (g_Sample.GetPacketLossMode() != static_cast<CFakeLagPacketLossMode>(modeValue))
		return pContext->ThrowNativeError("Packet loss mode change failed while synchronizing the detour.");
	return 1;
}

cell_t CFakeLag_GetPacketLossMode(IPluginContext* pContext, const cell_t* params)
{
	return static_cast<cell_t>(g_Sample.GetPacketLossMode());
}

cell_t CFakeLag_ClearAllPlayerProfiles(IPluginContext* pContext, const cell_t* params)
{
	if (!g_Sample.ClearAllPlayerProfiles())
		return pContext->ThrowNativeError("Profiles were cleared, but detour synchronization failed; hook infrastructure was retained.");
	return 1;
}

cell_t CFakeLag_ResetState(IPluginContext* pContext, const cell_t* params)
{
	if (!g_Sample.ResetState())
		return pContext->ThrowNativeError("State was cleared, but detour synchronization failed; hook infrastructure was retained.");
	return 1;
}

cell_t CFakeLag_IsClientSupported(IPluginContext* pContext, const cell_t* params)
{
	return g_Sample.IsClientSupported(params[1]) ? 1 : 0;
}

cell_t CFakeLag_GetProfiledClientCount(IPluginContext* pContext, const cell_t* params)
{
	return g_Sample.GetProfiledClientCount();
}

sp_nativeinfo_t g_CFakeLagNatives[] =
{
	{"CFakeLag_IsLanBlocked", [](IPluginContext*, const cell_t*) -> cell_t { return CFakeLag_IsLanBlocked() ? 1 : 0; }},
	{"CFakeLag_SetPlayerProfile", CFakeLag_SetPlayerProfile},
	{"CFakeLag_GetPlayerProfile", CFakeLag_GetPlayerProfile},
	{"CFakeLag_HasPlayerProfile", CFakeLag_HasPlayerProfile},
	{"CFakeLag_ClearPlayerProfile", CFakeLag_ClearPlayerProfile},
	{"CFakeLag_SetPacketLossMode", CFakeLag_SetPacketLossMode},
	{"CFakeLag_GetPacketLossMode", CFakeLag_GetPacketLossMode},
	{"CFakeLag_ClearAllPlayerProfiles", CFakeLag_ClearAllPlayerProfiles},
	{"CFakeLag_ResetState", CFakeLag_ResetState},
	{"CFakeLag_IsClientSupported", CFakeLag_IsClientSupported},
	{"CFakeLag_GetProfiledClientCount", CFakeLag_GetProfiledClientCount},
	{nullptr, nullptr}
};

SMEXT_LINK(&g_Sample);
