#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include <mathlib.h>
#include "smsdk_ext.h"
#include "cdetour/detours.h"
#include "latency/PlayerLatencyApiBridge.h"
#include "latency/PlayerLatencyService.h"

enum class CFakeLagPacketLossMode {
	BernoulliUniform = 0,
	GilbertElliott = 1
};

class CustomFakelag : public SDKExtension,
					  public IClientListener,
					  public IPlayerLagManagerEvents,
					  public IClientRegistry
{
private:
	EngineClientNetAdrResolver* m_NetAdrResolver = nullptr;
	PlayerLagManager* m_LagManager = nullptr;
	PlayerLatencyService* m_PlayerLatencyService = nullptr;
	PlayerLatencyApiBridge* m_PlayerLatencyApiBridge = nullptr;

	void OnClientNetAdrResolutionFailed(int client) override;
	void OnPlayerLagChanged(int client, const dumb_netadr_t& netadr, float lagTime) override;
	ClientEligibility GetClientEligibility(int client, IGamePlayer** player = nullptr) const override;
	int GetMaxClients() const override;

public:
	void SetPlayerLatency(int client, float lagTime);
	float GetPlayerLatency(int client);
	bool HasPlayerLatency(int client) const;
	void ClearPlayerLatency(int client);
	void SetPlayerPacketLoss(int client, int packetLossPercent);
	int GetPlayerPacketLoss(int client) const;
	bool HasPlayerPacketLoss(int client) const;
	void ClearPlayerPacketLoss(int client);
	void SetPacketLossMode(CFakeLagPacketLossMode mode);
	CFakeLagPacketLossMode GetPacketLossMode() const;
	void ClearAllPlayerProfiles();
	void ClearAllPlayerLatencies();
	bool IsClientSupported(int client) const;
	bool ThrowIfUnsupportedClient(IPluginContext* context, int client) const;
	int GetProfiledClientCount() const;
	int GetLaggedClientCount() const;

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
