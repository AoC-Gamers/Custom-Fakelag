#include "extension.h"
#include "NET_LagPacket_Detour.h"

CustomFakelag g_Sample;
extern sp_nativeinfo_t g_CFakeLagNatives[];
IGameConfig* g_pGameConf = nullptr;

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
		ke::SafeSprintf(error, maxlen, "Could not find net_time address in memory");
		return false;
	}

	m_LagManager = new PlayerLagManager(engine);

	// Initialize Detour System.
	CDetourManager::Init(g_pSM->GetScriptingEngine(), g_pGameConf);

	if (!LagDetour_Init(m_LagManager, pNetTime)) {
		ke::SafeSprintf(error, maxlen, "Could not detour Net_LagPacket.");
		return false;
	}

	sharesys->AddNatives(myself, g_CFakeLagNatives);
	sharesys->RegisterLibrary(myself, "custom_fakelag");
	return true;
}

void CustomFakelag::SDK_OnAllLoaded()
{
}

void CustomFakelag::SDK_OnUnload() {
	LagDetour_Shutdown();
	delete m_LagManager;
	m_LagManager = nullptr;
}

void CustomFakelag::SetPlayerLatency(int client, float lagTime)
{
	if (m_LagManager) {
		m_LagManager->SetPlayerLag(client, lagTime);
	}
}

float CustomFakelag::GetPlayerLatency(int client)
{
	if (m_LagManager) {
		return m_LagManager->GetPlayerLag(client);
	}
	return 0.0f;
}

cell_t CFakeLag_SetPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	float lagTime = sp_ctof(params[2]);
	auto player = playerhelpers->GetGamePlayer(client);
	if (player == nullptr) {
		return pContext->ThrowNativeError("Client index %d is not valid", client);
	}

	if (player->IsFakeClient()) {
		return pContext->ThrowNativeError("Client index %d is a fake client and can't be lagged.", client);
	}
	g_Sample.SetPlayerLatency(client, lagTime);
	return 1;
}

cell_t CFakeLag_GetPlayerLatency(IPluginContext* pContext, const cell_t* params)
{
	int client = params[1];
	auto player = playerhelpers->GetGamePlayer(client);
	if (player == nullptr) {
		return pContext->ThrowNativeError("Client index %d is not valid", client);
	}

	if (player->IsFakeClient()) {
		return pContext->ThrowNativeError("Client index %d is a fake client and can't be lagged.", client);
	}
	return sp_ftoc(g_Sample.GetPlayerLatency(client));
}

sp_nativeinfo_t g_CFakeLagNatives[] =
{
	{"CFakeLag_SetPlayerLatency", CFakeLag_SetPlayerLatency},
	{"CFakeLag_GetPlayerLatency", CFakeLag_GetPlayerLatency},
	{nullptr, nullptr}
};

SMEXT_LINK(&g_Sample);
