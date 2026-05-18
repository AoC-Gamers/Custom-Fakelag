#ifndef _INCLUDE_CUSTOM_FAKELAG_LAGPACKET_DETOUR_H_
#define _INCLUDE_CUSTOM_FAKELAG_LAGPACKET_DETOUR_H_

#include "latency/PlayerLagManager.h"

// lagManager: A Lag Manager instance to look up player lag times
// pNetTime: Pointer to the engine "net_time" variable
bool LagDetour_Init(const PlayerLagManager* lagManager, const double* pNetTime);
bool LagDetour_Enable();
void LagDetour_Disable();
bool LagDetour_IsEnabled();
void LagDetour_Shutdown();
void LagDetour_ClearPacketLossState();

#endif // _INCLUDE_CUSTOM_FAKELAG_LAGPACKET_DETOUR_H_
