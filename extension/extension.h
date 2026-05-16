#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include <mathlib.h>
#include "smsdk_ext.h"
#include "cdetour/detours.h"
#include "latency/PlayerProfileApiBridge.h"
#include "latency/PlayerProfileService.h"

enum class CFakeLagPacketLossMode : int {
	BernoulliUniform = 0,
	GilbertElliott = 1
};

class CustomFakelag : public SDKExtension,
					  public IConCommandBaseAccessor,
					  public IClientListener,
					  public IPlayerLagManagerEvents,
					  public IClientRegistry
{
private:
	EngineClientNetAdrResolver* m_NetAdrResolver = nullptr;
	PlayerLagManager* m_LagManager = nullptr;
	PlayerProfileService* m_PlayerProfileService = nullptr;
	PlayerProfileApiBridge* m_PlayerProfileApiBridge = nullptr;

	void OnClientNetAdrResolutionFailed(int client) override;
	void OnPlayerLagChanged(int client, const dumb_netadr_t& netadr, float lagTime) override;
	ClientEligibility GetClientEligibility(int client, IGamePlayer** player = nullptr) const override;
	int GetMaxClients() const override;
	bool RegisterConCommandBase(ConCommandBase* pVar) override;

public:
	void SetPlayerProfile(int client, float lagTime, int packetLossPercent);
	bool GetPlayerProfile(int client, float& lagTime, int& packetLossPercent) const;
	bool HasPlayerProfile(int client) const;
	void ClearPlayerProfile(int client);
	void SetPacketLossMode(CFakeLagPacketLossMode mode);
	CFakeLagPacketLossMode GetPacketLossMode() const;
	void ClearAllPlayerProfiles();
	void ResetState();
	bool IsClientSupported(int client) const;
	bool ThrowIfUnsupportedClient(IPluginContext* context, int client) const;
	int GetProfiledClientCount() const;

public:
	bool SDK_OnLoad(char* error, size_t maxlen, bool late) override;
	void SDK_OnUnload() override;
	void SDK_OnAllLoaded() override;
	void OnClientDisconnecting(int client) override;
public:
#if defined SMEXT_CONF_METAMOD
	//virtual bool SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool late);
	//virtual bool SDK_OnMetamodUnload(char *error, size_t maxlen);
	//virtual bool SDK_OnMetamodPauseChange(bool paused, char *error, size_t maxlen);
#endif
};

#endif // _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
