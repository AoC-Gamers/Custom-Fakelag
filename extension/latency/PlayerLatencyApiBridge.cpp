#include "PlayerLatencyApiBridge.h"

namespace {
constexpr int kLatencyForwardParamCount = 4;
constexpr int kProfileForwardParamCount = 6;
}

bool PlayerLatencyApiBridge::Initialize()
{
	m_OnSetPlayerLatency = forwards->CreateForward(
		"CFakeLag_OnSetPlayerLatency",
		ET_Hook,
		kLatencyForwardParamCount,
		nullptr,
		Param_Cell,
		Param_Float,
		Param_FloatByRef,
		Param_Cell);
	m_OnPlayerProfileChanged = forwards->CreateForward(
		"CFakeLag_OnPlayerProfileChanged",
		ET_Ignore,
		kProfileForwardParamCount,
		nullptr,
		Param_Cell,
		Param_Float,
		Param_Cell,
		Param_Float,
		Param_Cell,
		Param_Cell);

	if (m_OnSetPlayerLatency == nullptr || m_OnPlayerProfileChanged == nullptr) {
		Shutdown();
		return false;
	}

	return true;
}

void PlayerLatencyApiBridge::Shutdown()
{
	if (m_OnSetPlayerLatency != nullptr) {
		forwards->ReleaseForward(m_OnSetPlayerLatency);
		m_OnSetPlayerLatency = nullptr;
	}

	if (m_OnPlayerProfileChanged != nullptr) {
		forwards->ReleaseForward(m_OnPlayerProfileChanged);
		m_OnPlayerProfileChanged = nullptr;
	}
}

bool PlayerLatencyApiBridge::OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason)
{
	if (requestedLag == nullptr) {
		return false;
	}

	if (m_OnSetPlayerLatency == nullptr || m_OnSetPlayerLatency->GetFunctionCount() == 0) {
		return true;
	}

	cell_t result = 0;
	m_OnSetPlayerLatency->PushCell(client);
	m_OnSetPlayerLatency->PushFloat(oldLag);
	m_OnSetPlayerLatency->PushFloatByRef(requestedLag);
	m_OnSetPlayerLatency->PushCell(static_cast<cell_t>(reason));
	m_OnSetPlayerLatency->Execute(&result);
	return result < Pl_Handled;
}

void PlayerLatencyApiBridge::OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason)
{
	if (m_OnPlayerProfileChanged == nullptr || m_OnPlayerProfileChanged->GetFunctionCount() == 0) {
		return;
	}

	m_OnPlayerProfileChanged->PushCell(client);
	m_OnPlayerProfileChanged->PushFloat(oldLag);
	m_OnPlayerProfileChanged->PushCell(oldPacketLossPercent);
	m_OnPlayerProfileChanged->PushFloat(newLag);
	m_OnPlayerProfileChanged->PushCell(newPacketLossPercent);
	m_OnPlayerProfileChanged->PushCell(static_cast<cell_t>(reason));
	m_OnPlayerProfileChanged->Execute();
}
