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
	virtual bool OnSetPlayerLatency(ClientIndex client, LagMilliseconds oldLag, LagMilliseconds* requestedLag, CFakeLagChangeReason reason) = 0;
	virtual void OnPlayerProfileChanged(ClientIndex client, LagMilliseconds oldLag, PacketLossPercent oldPacketLossPercent, LagMilliseconds newLag, PacketLossPercent newPacketLossPercent, CFakeLagChangeReason reason) = 0;
};

class IClientRegistry
{
public:
	virtual ~IClientRegistry() = default;
	virtual ClientEligibility GetClientEligibility(ClientIndex client, IGamePlayer** player = nullptr) const = 0;
	virtual ClientIndex GetMaxClients() const = 0;
};

class PlayerLatencyService
{
private:
	PlayerLagManager* m_LagManager;
	IPlayerLatencyHooks* m_Hooks;
	const IClientRegistry* m_ClientRegistry;

	bool ApplyPlayerLatencyChange(ClientIndex client, LagMilliseconds lagTime, CFakeLagChangeReason reason, bool allowPreForward);
	void NotifyPlayerProfileChanged(ClientIndex client, LagMilliseconds oldLag, PacketLossPercent oldPacketLossPercent, LagMilliseconds newLag, PacketLossPercent newPacketLossPercent, CFakeLagChangeReason reason) const;

public:
	PlayerLatencyService(PlayerLagManager* lagManager, IPlayerLatencyHooks* hooks, const IClientRegistry* clientRegistry)
		: m_LagManager(lagManager),
		  m_Hooks(hooks),
		  m_ClientRegistry(clientRegistry) {}

	bool TryGetSupportedClient(ClientIndex client, IGamePlayer** player = nullptr) const;
	bool ThrowIfUnsupportedClient(IPluginContext* context, ClientIndex client) const;

	bool IsClientSupported(ClientIndex client) const;
	void OnClientDisconnecting(ClientIndex client);

	bool SetPlayerLatency(ClientIndex client, LagMilliseconds lagTime);
	void ClearPlayerLatency(ClientIndex client);
	bool SetPlayerPacketLoss(ClientIndex client, PacketLossPercent packetLossPercent);
	void ClearPlayerPacketLoss(ClientIndex client);
	void ClearAllPlayerProfiles();
	void ClearAllPlayerLatencies();

	LagMilliseconds GetPlayerLatency(ClientIndex client) const;
	bool HasPlayerLatency(ClientIndex client) const;
	PacketLossPercent GetPlayerPacketLoss(ClientIndex client) const;
	bool HasPlayerPacketLoss(ClientIndex client) const;
	ProfileCount GetLaggedClientCount() const;
};
