#pragma once

#include "PlayerLatencyService.h"

class PlayerLatencyApiBridge final : public IPlayerLatencyHooks
{
private:
	IForward* m_OnSetPlayerLatency = nullptr;
	IForward* m_OnPlayerProfileChanged = nullptr;

public:
	~PlayerLatencyApiBridge() override = default;

	bool Initialize();
	void Shutdown();

	bool OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason) override;
	void OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason) override;
};
