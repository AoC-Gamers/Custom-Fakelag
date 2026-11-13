#include "PlayerProfileService.h"

#include "../NET_LagPacket_Detour.h"

bool CFakeLag_IsAlwaysOnDetourMode();
bool CFakeLag_IsModeChanging();

namespace {
struct MutationGuard {
	bool& flag;
	explicit MutationGuard(bool& f) : flag(f) { flag = true; }
	~MutationGuard() { flag = false; }
};
constexpr float kNoLag = 0.0f;

bool SyncLagDetourState(const PlayerLagManager* lagManager)
{
	if (CFakeLag_IsAlwaysOnDetourMode()) {
		return LagDetour_Enable();
	}

	if (lagManager == nullptr) {
		return LagDetour_Disable();
	}

	if (lagManager->GetLagCount() > 0) {
		return LagDetour_Enable();
	}

	return LagDetour_Disable();
}
}

bool PlayerProfileService::TryGetSupportedClient(int client, IGamePlayer** player) const
{
	if (m_ClientRegistry == nullptr) {
		if (player != nullptr) {
			*player = nullptr;
		}
		return false;
	}

	return m_ClientRegistry->GetClientEligibility(client, player) == ClientEligibility::Supported;
}

bool PlayerProfileService::ThrowIfUnsupportedClient(IPluginContext* context, int client) const
{
#ifndef UNIT_TEST
	if (context == nullptr || m_ClientRegistry == nullptr) {
		return false;
	}

	switch (m_ClientRegistry->GetClientEligibility(client)) {
		case ClientEligibility::Supported:
			return true;
		case ClientEligibility::Invalid:
			context->ThrowNativeError("Client index %d is not valid", client);
			return false;
		case ClientEligibility::FakeClient:
			context->ThrowNativeError("Client index %d is a fake client and can't be lagged.", client);
			return false;
	}

	return false;
#else
	(void)context;
	return IsClientSupported(client);
#endif
}

bool PlayerProfileService::IsClientSupported(int client) const
{
	return TryGetSupportedClient(client);
}

void PlayerProfileService::OnClientDisconnecting(int client)
{
	if (m_LagManager == nullptr) {
		return;
	}

	const float oldLag = m_LagManager->GetPlayerLag(client);
	const int oldLoss = m_LagManager->GetPlayerPacketLoss(client);
	m_LagManager->ClearClient(client); // Uses cached connection identity; no address lookup on disconnect.
	SyncLagDetourState(m_LagManager);
	if (oldLag > 0 || oldLoss > 0)
		NotifyPlayerProfileChanged(client, oldLag, oldLoss, 0, 0, CFakeLagChangeReason::Disconnect);
}

bool PlayerProfileService::SetPlayerLatency(int client, float lagTime)
{
	return ApplyPlayerLatencyChange(
		client,
		lagTime,
		lagTime <= 0.0f ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual,
		true);
}

void PlayerProfileService::ClearPlayerLatency(int client)
{
	ApplyPlayerLatencyChange(client, 0.0f, CFakeLagChangeReason::Clear, true);
}

ProfileChangeResult PlayerProfileService::SetPlayerProfile(int client, float lagTime, int packetLossPercent)
{
	return ApplyPlayerProfileChange(
		client,
		lagTime,
		packetLossPercent,
		lagTime <= 0.0f && packetLossPercent <= 0 ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual,
		true);
}

bool PlayerProfileService::SetPlayerPacketLoss(int client, int packetLossPercent)
{
	if (m_LagManager == nullptr) {
		return false;
	}

	const auto changed = ApplyPlayerProfileChange(
		client,
		m_LagManager->GetPlayerLag(client),
		packetLossPercent,
		packetLossPercent <= 0 ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual,
		false);

	return ProfileChangeSucceeded(changed);
}

void PlayerProfileService::ClearPlayerPacketLoss(int client)
{
	if (m_LagManager == nullptr) {
		return;
	}

	ApplyPlayerProfileChange(client, m_LagManager->GetPlayerLag(client), 0, CFakeLagChangeReason::Clear, false);
}

bool PlayerProfileService::ClearAllPlayerProfiles()
{
	if (!m_LagManager) return false;
	if (m_Clearing) return true;
	MutationGuard clearing(m_Clearing);
	struct Previous { int client; float lag; int loss; };
	std::vector<Previous> previous;
	if (m_ClientRegistry) {
		for (int client = 1; client <= m_ClientRegistry->GetMaxClients(); ++client) {
			float lag = m_LagManager->GetPlayerLag(client);
			int loss = m_LagManager->GetPlayerPacketLoss(client);
			if (lag > 0 || loss > 0) previous.push_back({client, lag, loss});
		}
	}
	m_LagManager->ClearAll(); // Includes profiles whose players are no longer queryable.
	LagDetour_ClearAll();
	const bool synchronized = SyncLagDetourState(m_LagManager);
	for (const auto& old : previous)
		NotifyPlayerProfileChanged(old.client, old.lag, old.loss, 0, 0, CFakeLagChangeReason::Clear);
	return synchronized;
}

void PlayerProfileService::ClearAllPlayerLatencies()
{
	ClearAllPlayerProfiles();
}

float PlayerProfileService::GetPlayerLatency(int client) const
{
	if (m_LagManager == nullptr) {
		return kNoLag;
	}

	return m_LagManager->GetPlayerLag(client);
}

bool PlayerProfileService::HasPlayerLatency(int client) const
{
	return m_LagManager != nullptr && m_LagManager->HasPlayerLag(client);
}

PacketLossPercent PlayerProfileService::GetPlayerPacketLoss(ClientIndex client) const
{
	if (m_LagManager == nullptr) {
		return 0;
	}

	return m_LagManager->GetPlayerPacketLoss(client);
}

bool PlayerProfileService::HasPlayerPacketLoss(ClientIndex client) const
{
	return m_LagManager != nullptr && m_LagManager->HasPlayerPacketLoss(client);
}

ProfileCount PlayerProfileService::GetLaggedClientCount() const
{
	if (m_LagManager == nullptr) {
		return 0;
	}

	return m_LagManager->GetLagCount();
}

bool PlayerProfileService::ApplyPlayerLatencyChange(ClientIndex client, LagMilliseconds lagTime, CFakeLagChangeReason reason, bool allowPreForward)
{
	if (!m_LagManager) return false;
	return ProfileChangeSucceeded(ApplyPlayerProfileChange(client, lagTime, m_LagManager->GetPlayerPacketLoss(client), reason, allowPreForward));
}

ProfileChangeResult PlayerProfileService::ApplyPlayerProfileChange(ClientIndex client, LagMilliseconds lagTime, PacketLossPercent packetLossPercent, CFakeLagChangeReason reason, bool allowPreForward)
{
	if (!m_LagManager || m_ApplyingChange || m_Clearing || CFakeLag_IsModeChanging() || !IsClientSupported(client) ||
		!ValidLatency(lagTime) || packetLossPercent < 0 || packetLossPercent > 100) return ProfileChangeResult::Error;
	MutationGuard applying(m_ApplyingChange);
	const auto revision = m_LagManager->Revision();
	const float oldLag = m_LagManager->GetPlayerLag(client);
	const int oldLoss = m_LagManager->GetPlayerPacketLoss(client);
	float requestedLag = lagTime;
	if (allowPreForward && m_Hooks) {
		const auto forward = m_Hooks->OnSetPlayerLatency(client, oldLag, &requestedLag, reason);
		if (forward == LatencyForwardResult::Vetoed) return ProfileChangeResult::Vetoed;
		if (forward == LatencyForwardResult::Error) return ProfileChangeResult::Error;
	}
	// A forward may disconnect, reset, or attempt a nested mutation.
	if (!ValidLatency(requestedLag) || !IsClientSupported(client) || revision != m_LagManager->Revision()) return ProfileChangeResult::Error;
	if (oldLag == requestedLag && oldLoss == packetLossPercent) return ProfileChangeResult::Unchanged;
	const bool wasEnabled = LagDetour_IsEnabled();
	if ((requestedLag > 0 || packetLossPercent > 0) && !LagDetour_Enable()) return ProfileChangeResult::Error;
	if (!m_LagManager->SetPlayerProfile(client, requestedLag, packetLossPercent)) {
		if (!wasEnabled) SyncLagDetourState(m_LagManager);
		return ProfileChangeResult::Error;
	}
	if (!SyncLagDetourState(m_LagManager)) return ProfileChangeResult::Error;
	NotifyPlayerProfileChanged(client, oldLag, oldLoss, requestedLag, packetLossPercent, reason);
	return ProfileChangeResult::Applied;
}

void PlayerProfileService::NotifyPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason) const
{
	if (m_Hooks == nullptr) {
		return;
	}

	m_Hooks->OnPlayerProfileChanged(client, oldLag, oldPacketLossPercent, newLag, newPacketLossPercent, reason);
}
