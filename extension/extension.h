#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include <mathlib.h>
#include "smsdk_ext.h"
#include "cdetour/detours.h"
#include "PlayerLagManager.h"

enum class CFakeLagChangeReason {
	Manual = 0,
	Clear,
	Disconnect
};

class CustomFakelag : public SDKExtension, public IClientListener
{
private:
	PlayerLagManager* m_LagManager = nullptr;
	IForward* m_OnSetPlayerLatency = nullptr;
	IForward* m_OnPlayerLatencyChanged = nullptr;

	bool ApplyPlayerLatencyChange(int client, float lagTime, CFakeLagChangeReason reason, bool allowPreForward = true);
	void NotifyPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason);

public:
	void SetPlayerLatency(int client, float lagTime);
	float GetPlayerLatency(int client);
	bool HasPlayerLatency(int client) const;
	void ClearPlayerLatency(int client);
	void ClearAllPlayerLatencies();
	bool IsClientSupported(int client) const;
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
