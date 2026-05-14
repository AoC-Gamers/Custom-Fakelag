#include "extension.h"
#include "NET_LagPacket_Detour.h"

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

void CustomFakelag::ClearAllPlayerLatencies()
{
	if (m_PlayerLatencyService != nullptr) {
		m_PlayerLatencyService->ClearAllPlayerLatencies();
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

cell_t CFakeLag_ClearAllPlayerLatencies(IPluginContext* pContext, const cell_t* params)
{
	g_Sample.ClearAllPlayerLatencies();
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

sp_nativeinfo_t g_CFakeLagNatives[] =
{
	{"CFakeLag_SetPlayerLatency", CFakeLag_SetPlayerLatency},
	{"CFakeLag_GetPlayerLatency", CFakeLag_GetPlayerLatency},
	{"CFakeLag_HasPlayerLatency", CFakeLag_HasPlayerLatency},
	{"CFakeLag_ClearPlayerLatency", CFakeLag_ClearPlayerLatency},
	{"CFakeLag_ClearAllPlayerLatencies", CFakeLag_ClearAllPlayerLatencies},
	{"CFakeLag_IsClientSupported", CFakeLag_IsClientSupported},
	{"CFakeLag_GetLaggedClientCount", CFakeLag_GetLaggedClientCount},
	{nullptr, nullptr}
};

SMEXT_LINK(&g_Sample);
