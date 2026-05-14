#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <custom_fakelag>

ConVar g_CvarEnable;
ConVar g_CvarMaxManualLag;
ConVar g_CvarVerbose;

public Plugin myinfo =
{
	name = "Custom Fakelag Forward",
	author = "lechuga",
	description = "Example hooks for the Custom Fakelag forwards",
	version = "1.0",
	url = "https://github.com/AoC-Gamers/L4D2_Custom_Fakelag"
};

public void OnPluginStart()
{
	g_CvarEnable = CreateConVar(
		"sm_custom_fakelag_forward_demo_enable",
		"1",
		"Enable the Custom Fakelag forward demo plugin.",
		FCVAR_NOTIFY,
		true,
		0.0,
		true,
		1.0);
	g_CvarMaxManualLag = CreateConVar(
		"sm_custom_fakelag_forward_demo_max_manual",
		"100.0",
		"Maximum fakelag in milliseconds allowed for manual changes. Set to 0 to force clears.",
		FCVAR_NOTIFY,
		true,
		0.0);
	g_CvarVerbose = CreateConVar(
		"sm_custom_fakelag_forward_demo_verbose",
		"1",
		"Log fakelag forward activity to the server console.",
		FCVAR_NOTIFY,
		true,
		0.0,
		true,
		1.0);

	AutoExecConfig(true, "custom_fakelag_forward_demo");
}

public Action CFakeLag_OnSetPlayerLatency(int client, float oldLag, float &newLag, CFakeLagChangeReason reason)
{
	if (!g_CvarEnable.BoolValue) {
		return Plugin_Continue;
	}

	if (reason != CFakeLagChange_Manual) {
		return Plugin_Continue;
	}

	float maxManualLag = g_CvarMaxManualLag.FloatValue;
	if (newLag <= maxManualLag) {
		return Plugin_Continue;
	}

	if (g_CvarVerbose.BoolValue) {
		LogMessage(
			"Clamping manual fakelag for %L from %.1fms to %.1fms (old %.1fms)",
			client,
			newLag,
			maxManualLag,
			oldLag);
	}

	newLag = maxManualLag;
	return Plugin_Changed;
}

public void CFakeLag_OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason)
{
	if (!g_CvarEnable.BoolValue || !g_CvarVerbose.BoolValue) {
		return;
	}

	char reasonName[16];
	GetChangeReasonName(reason, reasonName, sizeof(reasonName));

	LogMessage(
		"Fakelag changed for %L: %.1fms -> %.1fms (%s)",
		client,
		oldLag,
		newLag,
		reasonName);
}

static void GetChangeReasonName(CFakeLagChangeReason reason, char[] buffer, int maxlen)
{
	switch (reason) {
		case CFakeLagChange_Manual:
			strcopy(buffer, maxlen, "manual");
		case CFakeLagChange_Clear:
			strcopy(buffer, maxlen, "clear");
		case CFakeLagChange_Disconnect:
			strcopy(buffer, maxlen, "disconnect");
		default:
			strcopy(buffer, maxlen, "unknown");
	}
}