#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include <mathlib.h>
#include "smsdk_ext.h"
#include "cdetour/detours.h"
#include "PlayerLagManager.h"

class CustomFakelag : public SDKExtension
{
private:
	PlayerLagManager* m_LagManager = nullptr;

public:
	void SetPlayerLatency(int client, float lagTime);
	float GetPlayerLatency(int client);

public:
	virtual bool SDK_OnLoad(char *error, size_t maxlen, bool late);
	virtual void SDK_OnUnload();
	virtual void SDK_OnAllLoaded();
public:
#if defined SMEXT_CONF_METAMOD
	//virtual bool SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool late);
	//virtual bool SDK_OnMetamodUnload(char *error, size_t maxlen);
	//virtual bool SDK_OnMetamodPauseChange(bool paused, char *error, size_t maxlen);
#endif
};

#endif // _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
