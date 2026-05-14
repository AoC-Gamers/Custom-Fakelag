#pragma once

#include "PlayerLatencyService.h"

class PlayerLatencyApiBridge final : public IPlayerLatencyHooks
{
private:
	IForward* m_OnSetPlayerLatency = nullptr;
	IForward* m_OnPlayerLatencyChanged = nullptr;

public:
	~PlayerLatencyApiBridge() override = default;

	bool Initialize();
	void Shutdown();

	bool OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason) override;
	void OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason) override;
};
