#include "PlayerProfileApiBridge.h"
#include <vector>

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

	m_OnLanPolicyChanged = forwards->CreateForward("CFakeLag_OnLanPolicyChanged", ET_Ignore, 1, nullptr, Param_Cell);
	if (m_OnSetPlayerLatency == nullptr || m_OnPlayerProfileChanged == nullptr || m_OnPacketLossModeChanged == nullptr || m_OnLanPolicyChanged == nullptr) {
		Shutdown();
		return false;
	}

	return true;
}

void PlayerProfileApiBridge::Shutdown()
{
	if (m_OnLanPolicyChanged) {
		forwards->ReleaseForward(m_OnLanPolicyChanged);
		m_OnLanPolicyChanged = nullptr;
	}
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

void PlayerProfileApiBridge::OnLanPolicyChanged(bool blocked) const
{
	if (!m_OnLanPolicyChanged) return;
	m_OnLanPolicyChanged->PushCell(blocked ? 1 : 0);
	m_OnLanPolicyChanged->Execute(nullptr);
}

LatencyForwardResult PlayerProfileApiBridge::OnSetPlayerLatency(int client, float oldLag, float* requestedLag, CFakeLagChangeReason reason)
{
	if (requestedLag == nullptr) {
		return LatencyForwardResult::Error;
	}

	if (m_OnSetPlayerLatency == nullptr || m_OnSetPlayerLatency->GetFunctionCount() == 0) {
		return LatencyForwardResult::Continue;
	}

    // SourceMod CForward::Execute reports SP_ERROR_NONE even if a listener
    // throws. Call the named listeners individually so failures abort the
    // transaction. Snapshot stable handles/serials, never borrowed functions:
    // callbacks may unload/reload other plugins while this list is executing.
    struct Listener { Handle_t handle; unsigned int serial; };
    std::vector<Listener> listeners;
    IPluginIterator* iterator = plsys->GetPluginIterator();
    for (; iterator->MorePlugins(); iterator->NextPlugin()) {
        IPlugin* plugin = iterator->GetPlugin();
        if (plugin->GetStatus() == Plugin_Running &&
            plugin->GetRuntime()->GetFunctionByName("CFakeLag_OnSetPlayerLatency"))
            listeners.push_back({plugin->GetMyHandle(), plugin->GetSerial()});
    }
    iterator->Release();
    float candidate = *requestedLag;
    cell_t highest = 0;
    for (const auto& listener : listeners) {
        HandleError handleError;
        IPlugin* plugin = plsys->PluginFromHandle(listener.handle, &handleError);
        if (!plugin || plugin->GetSerial() != listener.serial || plugin->GetStatus() != Plugin_Running) continue;
        IPluginFunction* function = plugin->GetRuntime()->GetFunctionByName("CFakeLag_OnSetPlayerLatency");
        if (!function) continue;
        int error = function->PushCell(client);
        if (!error) error = function->PushFloat(oldLag);
        if (!error) error = function->PushFloatByRef(&candidate);
        if (!error) error = function->PushCell(static_cast<cell_t>(reason));
        if (error) { function->Cancel(); return LatencyForwardResult::Error; }
        cell_t action = 0;
        error = function->Execute(&action);
        if (ClassifyLatencyForwardResult(error, action) == LatencyForwardResult::Error)
            return LatencyForwardResult::Error;
        if (action > highest) highest = action;
        if (highest == 4) break; // Plugin_Stop: ET_Hook short-circuit semantics.
    }
    const auto result = ClassifyLatencyForwardResult(0, highest);
    if (result == LatencyForwardResult::Continue) *requestedLag = candidate;
    return result;
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
