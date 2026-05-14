#pragma once

#include "PlayerLagManager.h"
#include "smsdk_ext.h"

enum class CFakeLagChangeReason {
	Manual = 0,
	Clear,
	Disconnect
};

enum class ClientEligibility {
	Supported = 0,
	Invalid,
	FakeClient
};

class IPlayerLatencyHooks
{
public:
	virtual ~IPlayerLatencyHooks() = default;
	virtual bool OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason) = 0;
	virtual void OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason) = 0;
};

class IClientRegistry
{
public:
	virtual ~IClientRegistry() = default;
	virtual ClientEligibility GetClientEligibility(int client, IGamePlayer** player = nullptr) const = 0;
	virtual int GetMaxClients() const = 0;
};

class PlayerLatencyService
{
private:
	PlayerLagManager* m_LagManager;
	IPlayerLatencyHooks* m_Hooks;
	const IClientRegistry* m_ClientRegistry;

	bool ApplyPlayerLatencyChange(int client, float lagTime, CFakeLagChangeReason reason, bool allowPreForward);
	void NotifyPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason) const;

public:
	PlayerLatencyService(PlayerLagManager* lagManager, IPlayerLatencyHooks* hooks, const IClientRegistry* clientRegistry)
		: m_LagManager(lagManager),
		  m_Hooks(hooks),
		  m_ClientRegistry(clientRegistry) {}

	bool TryGetSupportedClient(int client, IGamePlayer** player = nullptr) const;
	bool ThrowIfUnsupportedClient(IPluginContext* context, int client) const;

	bool IsClientSupported(int client) const;
	void OnClientDisconnecting(int client);

	bool SetPlayerLatency(int client, float lagTime);
	void ClearPlayerLatency(int client);
	void ClearAllPlayerLatencies();

	float GetPlayerLatency(int client) const;
	bool HasPlayerLatency(int client) const;
	int GetLaggedClientCount() const;
};
