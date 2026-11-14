#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include <mathlib.h>
#include "smsdk_ext.h"
#include "cdetour/detours.h"
#include "latency/PlayerProfileApiBridge.h"
#include "latency/PlayerProfileService.h"

#include "network/NetworkConfig.h"
#include "network/LanPolicy.h"

extern ConVar sm_custom_fakelag_loss_mode;
extern ConVar sm_custom_fakelag_debug;
extern ConVar sm_custom_fakelag_debug_hold_interval;
extern ConVar sm_custom_fakelag_detour_mode;

bool CFakeLag_IsDebugEnabled();
float CFakeLag_GetDebugHoldInterval();
bool CFakeLag_IsAlwaysOnDetourMode();
bool CFakeLag_IsModeChanging();

class CustomFakelag : public SDKExtension,
					  public IConCommandBaseAccessor,
					  public IClientListener,
					  public IPlayerLagManagerEvents,
					  public IClientRegistry
{
private:
	bool m_ChangingMode = false;
	bool m_Loaded = false;
	bool m_ChangingLanPolicy = false;
	bool m_LanPolicyDirty = false;
	bool m_LanBlocked = false;
	ConVar* m_Lan = nullptr;
	EngineClientNetAdrResolver* m_NetAdrResolver = nullptr;
	PlayerLagManager* m_LagManager = nullptr;
	PlayerProfileService* m_PlayerProfileService = nullptr;
	PlayerProfileApiBridge* m_PlayerProfileApiBridge = nullptr;

	void ReleaseResources();
	void OnClientNetAdrResolutionFailed(int client) override;
	void OnSessionInvalidated(SessionId session) override;
	void OnLevelShutdown();
	void OnPlayerLagChanged(int client, const dumb_netadr_t& netadr, float lagTime) override;
	ClientEligibility GetClientEligibility(int client, IGamePlayer** player = nullptr) const override;
	int GetMaxClients() const override;
	bool RegisterConCommandBase(ConCommandBase* pVar) override;

public:
	ProfileChangeResult SetPlayerProfile(int client, float lagTime, int packetLossPercent);
	bool GetPlayerProfile(int client, float& lagTime, int& packetLossPercent) const;
	bool HasPlayerProfile(int client) const;
	ProfileChangeResult ClearPlayerProfile(int client);
	bool IsModeChanging() const { return m_ChangingMode || m_ChangingLanPolicy; }
	bool IsLanBlocked() const;
	void OnLanPolicyChanged();
	void CheckLanPolicy() { if (m_LanPolicyDirty) OnLanPolicyChanged(); }
	void OnLossModeChanged(int oldMode);
	void OnDetourModeChanged(int oldMode);
	void SetPacketLossMode(CFakeLagPacketLossMode mode);
	CFakeLagPacketLossMode GetPacketLossMode() const;
	bool ClearAllPlayerProfiles();
	bool ResetState();
	bool IsClientSupported(int client) const;
	bool ThrowIfUnsupportedClient(IPluginContext* context, int client) const;
	int GetProfiledClientCount() const;

public:
	bool SDK_OnLoad(char* error, size_t maxlen, bool late) override;
	void SDK_OnUnload() override;
	void SDK_OnAllLoaded() override;
	void OnClientDisconnecting(int client) override;
	void OnClientConnected(int client) override;
public:
#if defined SMEXT_CONF_METAMOD
	//virtual bool SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool late);
	//virtual bool SDK_OnMetamodUnload(char *error, size_t maxlen);
	//virtual bool SDK_OnMetamodPauseChange(bool paused, char *error, size_t maxlen);
#endif
};

#endif // _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
