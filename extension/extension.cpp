#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include <ctime>
#include <cstdlib>
#include "tier1/convar.h"

extern ISmmAPI* g_SMAPI;

ConVar sm_custom_fakelag_loss_mode(
	"sm_custom_fakelag_loss_mode",
	"0",
	FCVAR_NOTIFY,
	"Packet loss simulation mode: 0 = Bernoulli uniform, 1 = Gilbert-Elliott.",
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

void CustomFakelag::OnClientNetAdrResolutionFailed(int client)
{
	g_pSM->LogError(myself, "Failed to resolve network address for client index %d.", client);
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
	std::srand(static_cast<unsigned int>(std::time(nullptr)));

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
	if (!g_pGameConf->GetAddress("net_time", reinterpret_cast<void**>(&pNetTime))) {
		CloseGameConfig();
		ke::SafeSprintf(error, maxlen, "Could not find net_time address in memory");
		return false;
	}

	m_NetAdrResolver = new EngineClientNetAdrResolver(engine);
	m_LagManager = new PlayerLagManager(m_NetAdrResolver, this);

	// Initialize Detour System.
	CDetourManager::Init(g_pSM->GetScriptingEngine(), g_pGameConf);

	if (!LagDetour_Init(m_LagManager, pNetTime)) {
		delete m_LagManager;
		m_LagManager = nullptr;
		delete m_NetAdrResolver;
		m_NetAdrResolver = nullptr;
		CloseGameConfig();
		ke::SafeSprintf(error, maxlen, "Could not detour Net_LagPacket.");
		return false;
	}

	m_PlayerProfileApiBridge = new PlayerProfileApiBridge();
	if (!m_PlayerProfileApiBridge->Initialize()) {
		delete m_PlayerProfileApiBridge;
		m_PlayerProfileApiBridge = nullptr;
		LagDetour_Shutdown();
		delete m_LagManager;
		m_LagManager = nullptr;
		delete m_NetAdrResolver;
		m_NetAdrResolver = nullptr;
		CloseGameConfig();
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
		return false;
	}
	g_pCVar = cvarIface;
#endif
	ConVar_Register(0, this);

	sharesys->AddNatives(myself, g_CFakeLagNatives);
	sharesys->RegisterLibrary(myself, "custom_fakelag");
	playerhelpers->AddClientListener(this);
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
	playerhelpers->RemoveClientListener(this);

	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->ClearAllPlayerProfiles();
	} else if (m_LagManager != nullptr) {
		m_LagManager->ClearAll();
	}
	delete m_PlayerProfileService;
	m_PlayerProfileService = nullptr;
	if (m_PlayerProfileApiBridge != nullptr) {
		m_PlayerProfileApiBridge->Shutdown();
		delete m_PlayerProfileApiBridge;
		m_PlayerProfileApiBridge = nullptr;
	}

	LagDetour_Shutdown();
	delete m_LagManager;
	m_LagManager = nullptr;
	delete m_NetAdrResolver;
	m_NetAdrResolver = nullptr;

	ConVar_Unregister();

	if (g_pGameConf != nullptr) {
		CloseGameConfig();
	}
}

void CustomFakelag::OnClientDisconnecting(int client)
{
	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->OnClientDisconnecting(client);
	}
}

void CustomFakelag::SetPlayerProfile(int client, float lagTime, int packetLossPercent)
{
	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->SetPlayerProfile(client, lagTime, packetLossPercent);
	}
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

void CustomFakelag::ClearPlayerProfile(int client)
{
	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->SetPlayerProfile(client, kNoLag, 0);
	}
}

void CustomFakelag::SetPacketLossMode(CFakeLagPacketLossMode mode)
{
	const CFakeLagPacketLossMode oldMode = GetPacketLossMode();
	if (oldMode != mode) {
		ResetState();
	}

	sm_custom_fakelag_loss_mode.SetValue(static_cast<int>(mode));

	if (oldMode != mode && m_PlayerProfileApiBridge != nullptr) {
		m_PlayerProfileApiBridge->OnPacketLossModeChanged(oldMode, mode);
	}
}

CFakeLagPacketLossMode CustomFakelag::GetPacketLossMode() const
{
	const int modeValue = sm_custom_fakelag_loss_mode.GetInt();
	if (modeValue == static_cast<int>(CFakeLagPacketLossMode::GilbertElliott)) {
		return CFakeLagPacketLossMode::GilbertElliott;
	}

	return CFakeLagPacketLossMode::BernoulliUniform;
}

void CustomFakelag::ClearAllPlayerProfiles()
{
	if (m_PlayerProfileService != nullptr) {
		m_PlayerProfileService->ClearAllPlayerProfiles();
	}
}

void CustomFakelag::ResetState()
{
	ClearAllPlayerProfiles();
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

	if (lagTime < kNoLag) {
		return pContext->ThrowNativeError("Lag time must be greater than or equal to 0.");
	}

	if (packetLossPercent < 0 || packetLossPercent > 100) {
		return pContext->ThrowNativeError("Packet loss percent must be between 0 and 100.");
	}

	g_Sample.SetPlayerProfile(client, lagTime, packetLossPercent);
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

	g_Sample.ClearPlayerProfile(client);
	return 1;
}

cell_t CFakeLag_SetPacketLossMode(IPluginContext* pContext, const cell_t* params)
{
	const int modeValue = params[1];
	if (modeValue < static_cast<int>(CFakeLagPacketLossMode::BernoulliUniform)
		|| modeValue > static_cast<int>(CFakeLagPacketLossMode::GilbertElliott)) {
		return pContext->ThrowNativeError("Packet loss mode must be 0 (BernoulliUniform) or 1 (GilbertElliott).");
	}

	g_Sample.SetPacketLossMode(static_cast<CFakeLagPacketLossMode>(modeValue));
	return 1;
}

cell_t CFakeLag_GetPacketLossMode(IPluginContext* pContext, const cell_t* params)
{
	return static_cast<cell_t>(g_Sample.GetPacketLossMode());
}

cell_t CFakeLag_ClearAllPlayerProfiles(IPluginContext* pContext, const cell_t* params)
{
	g_Sample.ClearAllPlayerProfiles();
	return 1;
}

cell_t CFakeLag_ResetState(IPluginContext* pContext, const cell_t* params)
{
	g_Sample.ResetState();
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
