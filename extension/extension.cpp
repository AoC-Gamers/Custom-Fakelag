#include "extension.h"
#include "NET_LagPacket_Detour.h"

CustomFakelag g_Sample;
extern sp_nativeinfo_t g_CFakeLagNatives[];
IGameConfig* g_pGameConf = nullptr;

static IGamePlayer* GetLagTarget(int client)
{
	auto player = playerhelpers->GetGamePlayer(client);
	if (player == nullptr || !player->IsConnected()) {
		return nullptr;
	}

	if (player->IsFakeClient()) {
		return nullptr;
	}

	return player;
}

static IGamePlayer* GetLagTargetOrError(IPluginContext* pContext, int client)
{
	auto player = GetLagTarget(client);
	if (player == nullptr) {
		auto gamePlayer = playerhelpers->GetGamePlayer(client);
		if (gamePlayer == nullptr || !gamePlayer->IsConnected()) {
		pContext->ThrowNativeError("Client index %d is not valid", client);
		return nullptr;
	}

		pContext->ThrowNativeError("Client index %d is a fake client and can't be lagged.", client);
		return nullptr;
	}

	return player;
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
		gameconfs->CloseGameConfigFile(g_pGameConf);
		g_pGameConf = nullptr;
		ke::SafeSprintf(error, maxlen, "Could not find net_time address in memory");
		return false;
	}

	m_LagManager = new PlayerLagManager(engine);

	// Initialize Detour System.
	CDetourManager::Init(g_pSM->GetScriptingEngine(), g_pGameConf);

	if (!LagDetour_Init(m_LagManager, pNetTime)) {
		delete m_LagManager;
		m_LagManager = nullptr;
		gameconfs->CloseGameConfigFile(g_pGameConf);
		g_pGameConf = nullptr;
		ke::SafeSprintf(error, maxlen, "Could not detour Net_LagPacket.");
		return false;
	}

	m_OnSetPlayerLatency = forwards->CreateForward(
		"CFakeLag_OnSetPlayerLatency",
		ET_Hook,
		4,
		nullptr,
		Param_Cell,
		Param_Float,
		Param_FloatByRef,
		Param_Cell);
	m_OnPlayerLatencyChanged = forwards->CreateForward(
		"CFakeLag_OnPlayerLatencyChanged",
		ET_Ignore,
		4,
		nullptr,
		Param_Cell,
		Param_Float,
		Param_Float,
		Param_Cell);

	if (m_OnSetPlayerLatency == nullptr || m_OnPlayerLatencyChanged == nullptr) {
		if (m_OnSetPlayerLatency != nullptr) {
			forwards->ReleaseForward(m_OnSetPlayerLatency);
			m_OnSetPlayerLatency = nullptr;
		}
		if (m_OnPlayerLatencyChanged != nullptr) {
			forwards->ReleaseForward(m_OnPlayerLatencyChanged);
			m_OnPlayerLatencyChanged = nullptr;
		}
		LagDetour_Shutdown();
		delete m_LagManager;
		m_LagManager = nullptr;
		gameconfs->CloseGameConfigFile(g_pGameConf);
		g_pGameConf = nullptr;
		ke::SafeSprintf(error, maxlen, "Could not create Custom Fakelag forwards.");
		return false;
	}

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
	if (m_OnSetPlayerLatency != nullptr) {
		forwards->ReleaseForward(m_OnSetPlayerLatency);
		m_OnSetPlayerLatency = nullptr;
	}
	if (m_OnPlayerLatencyChanged != nullptr) {
		forwards->ReleaseForward(m_OnPlayerLatencyChanged);
		m_OnPlayerLatencyChanged = nullptr;
	}

	LagDetour_Shutdown();
	delete m_LagManager;
	m_LagManager = nullptr;

	if (g_pGameConf != nullptr) {
		gameconfs->CloseGameConfigFile(g_pGameConf);
		g_pGameConf = nullptr;
	}
}

void CustomFakelag::OnClientDisconnecting(int client)
{
	if (m_LagManager == nullptr) {
		return;
	}

	const float oldLag = m_LagManager->GetPlayerLag(client);
	if (oldLag <= 0.0f) {
		return;
	}

	m_LagManager->ClearPlayerLag(client);
	NotifyPlayerLatencyChanged(client, oldLag, 0.0f, CFakeLagChangeReason::Disconnect);
}

void CustomFakelag::SetPlayerLatency(int client, float lagTime)
{
	ApplyPlayerLatencyChange(
		client,
		lagTime,
		lagTime <= 0.0f ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual);
}

float CustomFakelag::GetPlayerLatency(int client)
{
	if (m_LagManager) {
		return m_LagManager->GetPlayerLag(client);
	}
	return 0.0f;
}

bool CustomFakelag::HasPlayerLatency(int client) const
{
	return m_LagManager != nullptr && m_LagManager->HasPlayerLag(client);
}

void CustomFakelag::ClearPlayerLatency(int client)
{
	ApplyPlayerLatencyChange(client, 0.0f, CFakeLagChangeReason::Clear);
}

void CustomFakelag::ClearAllPlayerLatencies()
{
	if (m_LagManager != nullptr) {
		m_LagManager->ClearAll();
	}
}

bool CustomFakelag::IsClientSupported(int client) const
{
	return GetLagTarget(client) != nullptr;
}

int CustomFakelag::GetLaggedClientCount() const
{
	if (m_LagManager == nullptr) {
		return 0;
	}

	return static_cast<int>(m_LagManager->GetLagCount());
}

bool CustomFakelag::ApplyPlayerLatencyChange(int client, float lagTime, CFakeLagChangeReason reason, bool allowPreForward)
{
	if (m_LagManager == nullptr) {
		return false;
	}

	float oldLag = m_LagManager->GetPlayerLag(client);
	float requestedLag = lagTime;

	if (allowPreForward && m_OnSetPlayerLatency != nullptr && m_OnSetPlayerLatency->GetFunctionCount() > 0) {
		cell_t result = 0;
		m_OnSetPlayerLatency->PushCell(client);
		m_OnSetPlayerLatency->PushFloat(oldLag);
		m_OnSetPlayerLatency->PushFloatByRef(&requestedLag);
		m_OnSetPlayerLatency->PushCell(static_cast<cell_t>(reason));
		m_OnSetPlayerLatency->Execute(&result);

		if (result >= Pl_Handled) {
			return false;
		}
	}

	if (requestedLag < 0.0f) {
		requestedLag = 0.0f;
	}

	if (oldLag == requestedLag) {
		return true;
	}

	m_LagManager->SetPlayerLag(client, requestedLag);
	NotifyPlayerLatencyChanged(client, oldLag, requestedLag, reason);
	return true;
}

void CustomFakelag::NotifyPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason)
{
	if (m_OnPlayerLatencyChanged == nullptr || m_OnPlayerLatencyChanged->GetFunctionCount() == 0) {
		return;
	}

	m_OnPlayerLatencyChanged->PushCell(client);
	m_OnPlayerLatencyChanged->PushFloat(oldLag);
	m_OnPlayerLatencyChanged->PushFloat(newLag);
	m_OnPlayerLatencyChanged->PushCell(static_cast<cell_t>(reason));
	m_OnPlayerLatencyChanged->Execute();
}

cell_t CFakeLag_SetPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	float lagTime = sp_ctof(params[2]);
	if (GetLagTargetOrError(pContext, client) == nullptr) {
		return 0;
	}

	if (lagTime < 0.0f) {
		return pContext->ThrowNativeError("Lag time must be greater than or equal to 0.");
	}

	g_Sample.SetPlayerLatency(client, lagTime);
	return 1;
}

cell_t CFakeLag_GetPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (GetLagTargetOrError(pContext, client) == nullptr) {
		return 0;
	}

	return sp_ftoc(g_Sample.GetPlayerLatency(client));
}

cell_t CFakeLag_HasPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (GetLagTargetOrError(pContext, client) == nullptr) {
		return 0;
	}

	return g_Sample.HasPlayerLatency(client) ? 1 : 0;
}

cell_t CFakeLag_ClearPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	if (GetLagTargetOrError(pContext, client) == nullptr) {
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
