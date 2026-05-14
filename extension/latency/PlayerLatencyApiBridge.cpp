#include "PlayerLatencyApiBridge.h"

namespace {
constexpr int kLatencyForwardParamCount = 4;
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
	m_OnPlayerLatencyChanged = forwards->CreateForward(
		"CFakeLag_OnPlayerLatencyChanged",
		ET_Ignore,
		kLatencyForwardParamCount,
		nullptr,
		Param_Cell,
		Param_Float,
		Param_Float,
		Param_Cell);

	if (m_OnSetPlayerLatency == nullptr || m_OnPlayerLatencyChanged == nullptr) {
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

	if (m_OnPlayerLatencyChanged != nullptr) {
		forwards->ReleaseForward(m_OnPlayerLatencyChanged);
		m_OnPlayerLatencyChanged = nullptr;
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

void PlayerLatencyApiBridge::OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason)
{
	if (m_OnPlayerLatencyChanged == nullptr || m_OnPlayerLatencyChanged->GetFunctionCount() == 0) {
		return;
	}

	m_OnPlayerLatencyChanged->PushCell(client);
	m_OnPlayerLatencyChanged->PushFloat(oldLag);
	m_OnPlayerLatencyChanged->PushFloat(newLag);
	m_OnPlayerLatencyChanged->PushCell(static_cast<cell_t>(reason));
	m_OnPlayerLatencyChanged->Execute();
}
