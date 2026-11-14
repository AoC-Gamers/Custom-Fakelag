#pragma once

#include "PlayerLagManager.h"
#ifndef UNIT_TEST
#include "smsdk_ext.h"
#else
class IGamePlayer;
class IPluginContext;
#endif

enum class ProfileChangeResult { Applied, Unchanged, Vetoed, Error, LanBlocked };
inline bool ProfileChangeSucceeded(ProfileChangeResult result) {
    return result == ProfileChangeResult::Applied || result == ProfileChangeResult::Unchanged;
}
enum class LatencyForwardResult { Continue, Vetoed, Error };
inline LatencyForwardResult ClassifyLatencyForwardResult(int executeError, int action) {
    if (executeError != 0 || action < 0 || action == 2 || action > 4) return LatencyForwardResult::Error;
    return action >= 3 ? LatencyForwardResult::Vetoed : LatencyForwardResult::Continue;
}

enum class CFakeLagChangeReason {
	Manual = 0,
	Clear,
	Disconnect,
	LanPolicy
};

enum class ClientEligibility {
	Supported = 0,
	Invalid,
	FakeClient
};

class IPlayerProfileHooks
{
public:
	virtual ~IPlayerProfileHooks() = default;
	virtual LatencyForwardResult OnSetPlayerLatency(ClientIndex client, LagMilliseconds oldLag, LagMilliseconds* requestedLag, CFakeLagChangeReason reason) = 0;
	virtual void OnPlayerProfileChanged(ClientIndex client, LagMilliseconds oldLag, PacketLossPercent oldPacketLossPercent, LagMilliseconds newLag, PacketLossPercent newPacketLossPercent, CFakeLagChangeReason reason) = 0;
};

class IClientRegistry
{
public:
	virtual ~IClientRegistry() = default;
	virtual ClientEligibility GetClientEligibility(ClientIndex client, IGamePlayer** player = nullptr) const = 0;
	virtual ClientIndex GetMaxClients() const = 0;
};

class PlayerProfileService
{
private:
	PlayerLagManager* m_LagManager;
	IPlayerProfileHooks* m_Hooks;
	const IClientRegistry* m_ClientRegistry;
	bool m_ApplyingChange = false;
	bool m_Clearing = false;

	bool ApplyPlayerLatencyChange(ClientIndex client, LagMilliseconds lagTime, CFakeLagChangeReason reason, bool allowPreForward);
	ProfileChangeResult ApplyPlayerProfileChange(ClientIndex client, LagMilliseconds lagTime, PacketLossPercent packetLossPercent, CFakeLagChangeReason reason, bool allowPreForward);
	void NotifyPlayerProfileChanged(ClientIndex client, LagMilliseconds oldLag, PacketLossPercent oldPacketLossPercent, LagMilliseconds newLag, PacketLossPercent newPacketLossPercent, CFakeLagChangeReason reason) const;

public:
	PlayerProfileService(PlayerLagManager* lagManager, IPlayerProfileHooks* hooks, const IClientRegistry* clientRegistry)
		: m_LagManager(lagManager),
		  m_Hooks(hooks),
		  m_ClientRegistry(clientRegistry) {}

	bool TryGetSupportedClient(ClientIndex client, IGamePlayer** player = nullptr) const;
	bool ThrowIfUnsupportedClient(IPluginContext* context, ClientIndex client) const;

	bool IsClientSupported(ClientIndex client) const;
	void OnClientDisconnecting(ClientIndex client);

	bool SetPlayerLatency(ClientIndex client, LagMilliseconds lagTime);
	void ClearPlayerLatency(ClientIndex client);
	ProfileChangeResult SetPlayerProfile(ClientIndex client, LagMilliseconds lagTime, PacketLossPercent packetLossPercent);
	bool SetPlayerPacketLoss(ClientIndex client, PacketLossPercent packetLossPercent);
	void ClearPlayerPacketLoss(ClientIndex client);
	bool ClearAllPlayerProfiles(CFakeLagChangeReason reason = CFakeLagChangeReason::Clear);
	bool EnforceLanPolicy();
	void ClearAllPlayerLatencies();

	LagMilliseconds GetPlayerLatency(ClientIndex client) const;
	bool HasPlayerLatency(ClientIndex client) const;
	PacketLossPercent GetPlayerPacketLoss(ClientIndex client) const;
	bool HasPlayerPacketLoss(ClientIndex client) const;
	ProfileCount GetLaggedClientCount() const;
};
