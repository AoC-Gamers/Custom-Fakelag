#include "PlayerProfileApiBridge.h"

namespace {
constexpr int kLatencyForwardParamCount = 4;
constexpr int kProfileForwardParamCount = 6;
constexpr int kPacketLossModeForwardParamCount = 2;
}

bool PlayerProfileApiBridge::Initialize()
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
	m_OnPacketLossModeChanged = forwards->CreateForward(
		"CFakeLag_OnPacketLossModeChanged",
		ET_Ignore,
		kPacketLossModeForwardParamCount,
		nullptr,
		Param_Cell,
		Param_Cell);

	if (m_OnSetPlayerLatency == nullptr || m_OnPlayerProfileChanged == nullptr || m_OnPacketLossModeChanged == nullptr) {
		Shutdown();
		return false;
	}

	return true;
}

void PlayerProfileApiBridge::Shutdown()
{
	if (m_OnSetPlayerLatency != nullptr) {
		forwards->ReleaseForward(m_OnSetPlayerLatency);
		m_OnSetPlayerLatency = nullptr;
	}

	if (m_OnPlayerProfileChanged != nullptr) {
		forwards->ReleaseForward(m_OnPlayerProfileChanged);
		m_OnPlayerProfileChanged = nullptr;
	}

	if (m_OnPacketLossModeChanged != nullptr) {
		forwards->ReleaseForward(m_OnPacketLossModeChanged);
		m_OnPacketLossModeChanged = nullptr;
	}
}

bool PlayerProfileApiBridge::OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason)
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

void PlayerProfileApiBridge::OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason)
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

void PlayerProfileApiBridge::OnPacketLossModeChanged(CFakeLagPacketLossMode oldMode, CFakeLagPacketLossMode newMode) const
{
	if (m_OnPacketLossModeChanged == nullptr || m_OnPacketLossModeChanged->GetFunctionCount() == 0) {
		return;
	}

	m_OnPacketLossModeChanged->PushCell(static_cast<cell_t>(oldMode));
	m_OnPacketLossModeChanged->PushCell(static_cast<cell_t>(newMode));
	m_OnPacketLossModeChanged->Execute();
}
