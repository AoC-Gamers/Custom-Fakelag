#include "extension.h"
#include "NET_LagPacket_Detour.h"
#include <ctime>
#include <cstdlib>
#include "tier1/convar.h"

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

	m_PlayerLatencyApiBridge = new PlayerLatencyApiBridge();
	if (!m_PlayerLatencyApiBridge->Initialize()) {
		delete m_PlayerLatencyApiBridge;
		m_PlayerLatencyApiBridge = nullptr;
		LagDetour_Shutdown();
		delete m_LagManager;
		m_LagManager = nullptr;
		delete m_NetAdrResolver;
		m_NetAdrResolver = nullptr;
		CloseGameConfig();
		ke::SafeSprintf(error, maxlen, "Could not create Custom Fakelag forwards.");
		return false;
	}

	m_PlayerLatencyService = new PlayerLatencyService(m_LagManager, m_PlayerLatencyApiBridge, this);

	sharesys->AddNatives(myself, g_CFakeLagNatives);
	sharesys->RegisterLibrary(myself, "custom_fakelag");
	playerhelpers->AddClientListener(this);
	return true;
}

void CustomFakelag::SDK_OnAllLoaded()
{
}

void CustomFakelag::SDK_OnUnload() {
	playerhelpers->RemoveClientListener(this);

	if (m_LagManager != nullptr) {
		m_LagManager->ClearAll();
	}
	delete m_PlayerLatencyService;
	m_PlayerLatencyService = nullptr;
	if (m_PlayerLatencyApiBridge != nullptr) {
		m_PlayerLatencyApiBridge->Shutdown();
		delete m_PlayerLatencyApiBridge;
		m_PlayerLatencyApiBridge = nullptr;
	}

	LagDetour_Shutdown();
	delete m_LagManager;
	m_LagManager = nullptr;
	delete m_NetAdrResolver;
	m_NetAdrResolver = nullptr;

	if (g_pGameConf != nullptr) {
		CloseGameConfig();
	}
}

void CustomFakelag::OnClientDisconnecting(int client)
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->OnClientDisconnecting(client);
	}
}

void CustomFakelag::SetPlayerLatency(int client, float lagTime)
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->SetPlayerLatency(client, lagTime);
	}
}

float CustomFakelag::GetPlayerLatency(int client)
{
	if (m_PlayerLatencyService != nullptr) {
		return m_PlayerLatencyService->GetPlayerLatency(client);
	}
	return kNoLag;
}

bool CustomFakelag::HasPlayerLatency(int client) const
{
	return m_PlayerLatencyService != nullptr && m_PlayerLatencyService->HasPlayerLatency(client);
}

void CustomFakelag::ClearPlayerLatency(int client)
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->ClearPlayerLatency(client);
	}
}

void CustomFakelag::SetPlayerPacketLoss(int client, int packetLossPercent)
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->SetPlayerPacketLoss(client, packetLossPercent);
	}
}

int CustomFakelag::GetPlayerPacketLoss(int client) const
{
	if (m_PlayerLatencyService != nullptr) {
		return m_PlayerLatencyService->GetPlayerPacketLoss(client);
	}

	return 0;
}

bool CustomFakelag::HasPlayerPacketLoss(int client) const
{
	return m_PlayerLatencyService != nullptr && m_PlayerLatencyService->HasPlayerPacketLoss(client);
}

void CustomFakelag::ClearPlayerPacketLoss(int client)
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->ClearPlayerPacketLoss(client);
	}
}

void CustomFakelag::SetPacketLossMode(CFakeLagPacketLossMode mode)
{
	sm_custom_fakelag_loss_mode.SetValue(static_cast<int>(mode));
}

CFakeLagPacketLossMode CustomFakelag::GetPacketLossMode() const
{
	const int modeValue = sm_custom_fakelag_loss_mode.GetInt();
	if (modeValue == static_cast<int>(CFakeLagPacketLossMode::GilbertElliott)) {
		return CFakeLagPacketLossMode::GilbertElliott;
	}

	return CFakeLagPacketLossMode::BernoulliUniform;
}

void CustomFakelag::ClearAllPlayerLatencies()
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->ClearAllPlayerLatencies();
	}
}

void CustomFakelag::ClearAllPlayerProfiles()
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->ClearAllPlayerProfiles();
	}
}

bool CustomFakelag::IsClientSupported(int client) const
{
	return m_PlayerLatencyService != nullptr && m_PlayerLatencyService->IsClientSupported(client);
}

bool CustomFakelag::ThrowIfUnsupportedClient(IPluginContext* context, int client) const
{
	return m_PlayerLatencyService != nullptr && m_PlayerLatencyService->ThrowIfUnsupportedClient(context, client);
}

int CustomFakelag::GetLaggedClientCount() const
{
	if (m_PlayerLatencyService != nullptr) {
		return m_PlayerLatencyService->GetLaggedClientCount();
	}

	return 0;
}

int CustomFakelag::GetProfiledClientCount() const
{
	return GetLaggedClientCount();
}

cell_t CFakeLag_SetPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	float lagTime = sp_ctof(params[2]);
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	if (lagTime < kNoLag) {
		return pContext->ThrowNativeError("Lag time must be greater than or equal to 0.");
	}

	g_Sample.SetPlayerLatency(client, lagTime);
	return 1;
}

cell_t CFakeLag_GetPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	return sp_ftoc(g_Sample.GetPlayerLatency(client));
}

cell_t CFakeLag_HasPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	return g_Sample.HasPlayerLatency(client) ? 1 : 0;
}

cell_t CFakeLag_ClearPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	g_Sample.ClearPlayerLatency(client);
	return 1;
}

cell_t CFakeLag_SetPlayerPacketLoss(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	int packetLossPercent = params[2];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	if (packetLossPercent < 0 || packetLossPercent > 100) {
		return pContext->ThrowNativeError("Packet loss percent must be between 0 and 100.");
	}

	g_Sample.SetPlayerPacketLoss(client, packetLossPercent);
	return 1;
}

cell_t CFakeLag_GetPlayerPacketLoss(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	return g_Sample.GetPlayerPacketLoss(client);
}

cell_t CFakeLag_HasPlayerPacketLoss(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	return g_Sample.HasPlayerPacketLoss(client) ? 1 : 0;
}

cell_t CFakeLag_ClearPlayerPacketLoss(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (!g_Sample.ThrowIfUnsupportedClient(pContext, client)) {
		return 0;
	}

	g_Sample.ClearPlayerPacketLoss(client);
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

cell_t CFakeLag_ClearAllPlayerLatencies(IPluginContext* pContext, const cell_t* params)
{
	g_Sample.ClearAllPlayerLatencies();
	return 1;
}

cell_t CFakeLag_ClearAllPlayerProfiles(IPluginContext* pContext, const cell_t* params)
{
	g_Sample.ClearAllPlayerProfiles();
	return 1;
}

cell_t CFakeLag_IsClientSupported(IPluginContext* pContext, const cell_t* params)
{
	return g_Sample.IsClientSupported(params[1]) ? 1 : 0;
}

cell_t CFakeLag_GetLaggedClientCount(IPluginContext* pContext, const cell_t* params)
{
	return g_Sample.GetLaggedClientCount();
}

cell_t CFakeLag_GetProfiledClientCount(IPluginContext* pContext, const cell_t* params)
{
	return g_Sample.GetProfiledClientCount();
}

sp_nativeinfo_t g_CFakeLagNatives[] =
{
	{"CFakeLag_SetPlayerLatency", CFakeLag_SetPlayerLatency},
	{"CFakeLag_GetPlayerLatency", CFakeLag_GetPlayerLatency},
	{"CFakeLag_HasPlayerLatency", CFakeLag_HasPlayerLatency},
	{"CFakeLag_ClearPlayerLatency", CFakeLag_ClearPlayerLatency},
	{"CFakeLag_SetPlayerPacketLoss", CFakeLag_SetPlayerPacketLoss},
	{"CFakeLag_GetPlayerPacketLoss", CFakeLag_GetPlayerPacketLoss},
	{"CFakeLag_HasPlayerPacketLoss", CFakeLag_HasPlayerPacketLoss},
	{"CFakeLag_ClearPlayerPacketLoss", CFakeLag_ClearPlayerPacketLoss},
	{"CFakeLag_SetPacketLossMode", CFakeLag_SetPacketLossMode},
	{"CFakeLag_GetPacketLossMode", CFakeLag_GetPacketLossMode},
	{"CFakeLag_ClearAllPlayerProfiles", CFakeLag_ClearAllPlayerProfiles},
	{"CFakeLag_ClearAllPlayerLatencies", CFakeLag_ClearAllPlayerLatencies},
	{"CFakeLag_IsClientSupported", CFakeLag_IsClientSupported},
	{"CFakeLag_GetProfiledClientCount", CFakeLag_GetProfiledClientCount},
	{"CFakeLag_GetLaggedClientCount", CFakeLag_GetLaggedClientCount},
	{nullptr, nullptr}
};

SMEXT_LINK(&g_Sample);
