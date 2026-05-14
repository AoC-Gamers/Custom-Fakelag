#include "PlayerLatencyService.h"

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
	if (oldLag <= kNoLag) {
		return;
	}

	m_LagManager->ClearPlayerLag(client);
	NotifyPlayerLatencyChanged(client, oldLag, kNoLag, CFakeLagChangeReason::Disconnect);
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

void PlayerLatencyService::ClearAllPlayerLatencies()
{
	if (m_LagManager == nullptr || m_ClientRegistry == nullptr) {
		return;
	}

	for (int client = 1; client <= m_ClientRegistry->GetMaxClients(); client++) {
		if (!TryGetSupportedClient(client)) {
			continue;
		}

		const float oldLag = m_LagManager->GetPlayerLag(client);
		if (oldLag <= kNoLag) {
			continue;
		}

		ApplyPlayerLatencyChange(client, kNoLag, CFakeLagChangeReason::Clear, false);
	}
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

int PlayerLatencyService::GetLaggedClientCount() const
{
	if (m_LagManager == nullptr) {
		return 0;
	}

	return static_cast<int>(m_LagManager->GetLagCount());
}

bool PlayerLatencyService::ApplyPlayerLatencyChange(int client, float lagTime, CFakeLagChangeReason reason, bool allowPreForward)
{
	if (m_LagManager == nullptr) {
		return false;
	}

	float oldLag = m_LagManager->GetPlayerLag(client);
	float requestedLag = lagTime;

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

	m_LagManager->SetPlayerLag(client, requestedLag);
	NotifyPlayerLatencyChanged(client, oldLag, requestedLag, reason);
	return true;
}

void PlayerLatencyService::NotifyPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason) const
{
	if (m_Hooks == nullptr) {
		return;
	}

	m_Hooks->OnPlayerLatencyChanged(client, oldLag, newLag, reason);
}
