#include "PlayerLatencyService.h"
#include "../NET_LagPacket_Detour.h"

namespace {
constexpr float kNoLag = 0.0f;
}

bool PlayerLatencyService::TryGetSupportedClient(int client, IGamePlayer** player) const
{
	if (m_ClientRegistry == nullptr) {
		if (player != nullptr) {
			*player = nullptr;
		}
		return false;
	}

	return m_ClientRegistry->GetClientEligibility(client, player) == ClientEligibility::Supported;
}

bool PlayerLatencyService::ThrowIfUnsupportedClient(IPluginContext* context, int client) const
{
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
}

bool PlayerLatencyService::IsClientSupported(int client) const
{
	return TryGetSupportedClient(client);
}

void PlayerLatencyService::OnClientDisconnecting(int client)
{
	if (m_LagManager == nullptr) {
		return;
	}

	const float oldLag = m_LagManager->GetPlayerLag(client);
	const int oldPacketLossPercent = m_LagManager->GetPlayerPacketLoss(client);
	if (oldLag <= kNoLag && oldPacketLossPercent <= 0) {
		return;
	}

	m_LagManager->ClearPlayerLag(client);
	m_LagManager->ClearPlayerPacketLoss(client);
	LagDetour_ClearPacketLossState();
	NotifyPlayerProfileChanged(client, oldLag, oldPacketLossPercent, kNoLag, 0, CFakeLagChangeReason::Disconnect);
}

bool PlayerLatencyService::SetPlayerLatency(int client, float lagTime)
{
	return ApplyPlayerLatencyChange(
		client,
		lagTime,
		lagTime <= 0.0f ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual,
		true);
}

void PlayerLatencyService::ClearPlayerLatency(int client)
{
	ApplyPlayerLatencyChange(client, 0.0f, CFakeLagChangeReason::Clear, true);
}

bool PlayerLatencyService::SetPlayerProfile(int client, float lagTime, int packetLossPercent)
{
	return ApplyPlayerProfileChange(
		client,
		lagTime,
		packetLossPercent,
		lagTime <= 0.0f && packetLossPercent <= 0 ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual,
		true);
}

bool PlayerLatencyService::SetPlayerPacketLoss(int client, int packetLossPercent)
{
	if (m_LagManager == nullptr) {
		return false;
	}

	const bool changed = ApplyPlayerProfileChange(
		client,
		m_LagManager->GetPlayerLag(client),
		packetLossPercent,
		packetLossPercent <= 0 ? CFakeLagChangeReason::Clear : CFakeLagChangeReason::Manual,
		false);

	if (changed && packetLossPercent <= 0) {
		LagDetour_ClearPacketLossState();
	}

	return changed;
}

void PlayerLatencyService::ClearPlayerPacketLoss(int client)
{
	if (m_LagManager == nullptr) {
		return;
	}

	ApplyPlayerProfileChange(client, m_LagManager->GetPlayerLag(client), 0, CFakeLagChangeReason::Clear, false);
	LagDetour_ClearPacketLossState();
}

void PlayerLatencyService::ClearAllPlayerProfiles()
{
	if (m_LagManager == nullptr || m_ClientRegistry == nullptr) {
		return;
	}

	for (int client = 1; client <= m_ClientRegistry->GetMaxClients(); client++) {
		if (!TryGetSupportedClient(client)) {
			continue;
		}

		const float oldLag = m_LagManager->GetPlayerLag(client);
		const int oldPacketLossPercent = m_LagManager->GetPlayerPacketLoss(client);
		if (oldLag <= kNoLag && oldPacketLossPercent <= 0) {
			continue;
		}

		m_LagManager->ClearPlayerLag(client);
		m_LagManager->ClearPlayerPacketLoss(client);
		NotifyPlayerProfileChanged(client, oldLag, oldPacketLossPercent, kNoLag, 0, CFakeLagChangeReason::Clear);
	}

	LagDetour_ClearPacketLossState();
}

void PlayerLatencyService::ClearAllPlayerLatencies()
{
	ClearAllPlayerProfiles();
}

float PlayerLatencyService::GetPlayerLatency(int client) const
{
	if (m_LagManager == nullptr) {
		return kNoLag;
	}

	return m_LagManager->GetPlayerLag(client);
}

bool PlayerLatencyService::HasPlayerLatency(int client) const
{
	return m_LagManager != nullptr && m_LagManager->HasPlayerLag(client);
}

PacketLossPercent PlayerLatencyService::GetPlayerPacketLoss(ClientIndex client) const
{
	if (m_LagManager == nullptr) {
		return 0;
	}

	return m_LagManager->GetPlayerPacketLoss(client);
}

bool PlayerLatencyService::HasPlayerPacketLoss(ClientIndex client) const
{
	return m_LagManager != nullptr && m_LagManager->HasPlayerPacketLoss(client);
}

ProfileCount PlayerLatencyService::GetLaggedClientCount() const
{
	if (m_LagManager == nullptr) {
		return 0;
	}

	return m_LagManager->GetLagCount();
}

bool PlayerLatencyService::ApplyPlayerLatencyChange(ClientIndex client, LagMilliseconds lagTime, CFakeLagChangeReason reason, bool allowPreForward)
{
	if (m_LagManager == nullptr) {
		return false;
	}

	LagMilliseconds oldLag = m_LagManager->GetPlayerLag(client);
	LagMilliseconds requestedLag = lagTime;

	if (allowPreForward && m_Hooks != nullptr) {
		if (!m_Hooks->OnSetPlayerLatency(client, oldLag, &requestedLag, reason)) {
			return false;
		}
	}

	if (requestedLag < kNoLag) {
		requestedLag = kNoLag;
	}

	if (oldLag == requestedLag) {
		return true;
	}

	const int oldPacketLossPercent = m_LagManager->GetPlayerPacketLoss(client);
	m_LagManager->SetPlayerLag(client, requestedLag);
	NotifyPlayerProfileChanged(client, oldLag, oldPacketLossPercent, requestedLag, oldPacketLossPercent, reason);
	return true;
}

bool PlayerLatencyService::ApplyPlayerProfileChange(ClientIndex client, LagMilliseconds lagTime, PacketLossPercent packetLossPercent, CFakeLagChangeReason reason, bool allowPreForward)
{
	if (m_LagManager == nullptr) {
		return false;
	}

	LagMilliseconds oldLag = m_LagManager->GetPlayerLag(client);
	PacketLossPercent oldPacketLossPercent = m_LagManager->GetPlayerPacketLoss(client);
	LagMilliseconds requestedLag = lagTime;

	if (allowPreForward && m_Hooks != nullptr) {
		if (!m_Hooks->OnSetPlayerLatency(client, oldLag, &requestedLag, reason)) {
			return false;
		}
	}

	if (requestedLag < kNoLag) {
		requestedLag = kNoLag;
	}

	if (packetLossPercent < 0) {
		packetLossPercent = 0;
	}

	if (oldLag == requestedLag && oldPacketLossPercent == packetLossPercent) {
		return true;
	}

	m_LagManager->SetPlayerLag(client, requestedLag);
	m_LagManager->SetPlayerPacketLoss(client, packetLossPercent);
	NotifyPlayerProfileChanged(client, oldLag, oldPacketLossPercent, requestedLag, packetLossPercent, reason);
	return true;
}

void PlayerLatencyService::NotifyPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason) const
{
	if (m_Hooks == nullptr) {
		return;
	}

	m_Hooks->OnPlayerProfileChanged(client, oldLag, oldPacketLossPercent, newLag, newPacketLossPercent, reason);
}
