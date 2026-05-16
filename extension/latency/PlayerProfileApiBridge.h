#pragma once

#include "PlayerProfileService.h"

enum class CFakeLagPacketLossMode : int;

class PlayerProfileApiBridge final : public IPlayerProfileHooks
{
private:
	IForward* m_OnSetPlayerLatency = nullptr;
	IForward* m_OnPlayerProfileChanged = nullptr;
	IForward* m_OnPacketLossModeChanged = nullptr;

public:
	~PlayerProfileApiBridge() override = default;

	bool Initialize();
	void Shutdown();

	bool OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason) override;
	void OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason) override;
	void OnPacketLossModeChanged(CFakeLagPacketLossMode oldMode, CFakeLagPacketLossMode newMode) const;
};
