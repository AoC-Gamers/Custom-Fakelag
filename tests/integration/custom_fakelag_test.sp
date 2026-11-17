#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <custom_fakelag>

ConVar g_CvarEnable;
ConVar g_CvarMaxManualLag;
ConVar g_CvarVerbose;

public Plugin myinfo =
{
	name = "Custom Fakelag Test",
	author = "lechuga",
	description = "Forward and native smoke tests for custom_fakelag",
	version = "2.0.0",
	url = "https://github.com/AoC-Gamers/L4D2_Custom_Fakelag"
};

public void OnPluginStart()
{
	g_CvarEnable = CreateConVar("sm_custom_fakelag_test_enable", "1", "Enable the Custom Fakelag test plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarMaxManualLag = CreateConVar("sm_custom_fakelag_test_max_manual", "100.0", "Maximum fakelag in milliseconds allowed for manual changes. Set to 0 to force clears.", FCVAR_NOTIFY, true, 0.0);
	g_CvarVerbose = CreateConVar("sm_custom_fakelag_test_verbose", "1", "Log Custom Fakelag test activity to the server console.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegAdminCmd("sm_cft_setprofile", Command_SetProfile, ADMFLAG_ROOT, "sm_cft_setprofile <target> <lag_ms> <packet_loss_percent>");
	RegAdminCmd("sm_cft_getprofile", Command_GetProfile, ADMFLAG_ROOT, "sm_cft_getprofile <target>");
	RegAdminCmd("sm_cft_clearprofile", Command_ClearProfile, ADMFLAG_ROOT, "sm_cft_clearprofile <target>");
	RegAdminCmd("sm_cft_countprofiles", Command_CountProfiles, ADMFLAG_ROOT, "Print the number of active profiles.");
	RegAdminCmd("sm_cft_setlossmode", Command_SetLossMode, ADMFLAG_ROOT, "sm_cft_setlossmode <bernoulli|gilbert|0|1>");
	RegAdminCmd("sm_cft_getlossmode", Command_GetLossMode, ADMFLAG_ROOT, "Print the current packet loss mode.");

	AutoExecConfig(true, "custom_fakelag_test");
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
		LogMessage("Clamping manual fakelag for %L from %.1fms to %.1fms (old %.1fms)", client, newLag, maxManualLag, oldLag);
	}

	newLag = maxManualLag;
	return Plugin_Changed;
}

public void CFakeLag_OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason)
{
	if (!g_CvarEnable.BoolValue || !g_CvarVerbose.BoolValue) {
		return;
	}

	char reasonName[16];
	GetChangeReasonName(reason, reasonName, sizeof(reasonName));
	LogMessage("Fakelag profile changed for %L: %.1fms/%d%% -> %.1fms/%d%% (%s)", client, oldLag, oldPacketLossPercent, newLag, newPacketLossPercent, reasonName);
}

public void CFakeLag_OnPacketLossModeChanged(CFakeLagPacketLossMode oldMode, CFakeLagPacketLossMode newMode)
{
	if (!g_CvarEnable.BoolValue || !g_CvarVerbose.BoolValue) {
		return;
	}

	LogMessage(
		"Packet loss mode changed: %s -> %s",
		oldMode == CFakeLagPacketLoss_GilbertElliott ? "gilbert-elliott" : "bernoulli",
		newMode == CFakeLagPacketLoss_GilbertElliott ? "gilbert-elliott" : "bernoulli");
}

static Action Command_SetProfile(int client, int args)
{
	if (args < 3) {
		ReplyToCommand(client, "[CFT] Usage: sm_cft_setprofile <target> <lag_ms> <packet_loss_percent>");
		return Plugin_Handled;
	}

	char targetArg[64];
	char lagArg[32];
	char lossArg[16];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	GetCmdArg(2, lagArg, sizeof(lagArg));
	GetCmdArg(3, lossArg, sizeof(lossArg));

	float lagMs = StringToFloat(lagArg);
	int packetLossPercent = StringToInt(lossArg);

	int targets[MAXPLAYERS];
	char targetName[MAX_TARGET_LENGTH];
	bool tnIsMl;
	int count = ProcessTargetString(targetArg, client, targets, sizeof(targets), COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_BOTS, targetName, sizeof(targetName), tnIsMl);
	if (count <= 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for (int i = 0; i < count; i++) {
		CFakeLag_SetPlayerProfile(targets[i], lagMs, packetLossPercent);
	}

	ReplyToCommand(client, "[CFT] Applied profile %.1fms/%d%% to %s.", lagMs, packetLossPercent, targetName);
	return Plugin_Handled;
}

static Action Command_GetProfile(int client, int args)
{
	if (args < 1) {
		ReplyToCommand(client, "[CFT] Usage: sm_cft_getprofile <target>");
		return Plugin_Handled;
	}

	int target = GetSingleTargetFromCmd(client, 1);
	if (target <= 0) {
		return Plugin_Handled;
	}

	CFakeLagNetworkProfile profile;
	bool hasProfile = CFakeLag_GetPlayerProfile(target, profile);
	ReplyToCommand(client, "[CFT] %N profile: active=%d lag=%.1fms loss=%d%%", target, hasProfile, profile.lagMs, profile.packetLossPercent);
	return Plugin_Handled;
}

static Action Command_ClearProfile(int client, int args)
{
	if (args < 1) {
		ReplyToCommand(client, "[CFT] Usage: sm_cft_clearprofile <target>");
		return Plugin_Handled;
	}

	char targetArg[64];
	GetCmdArg(1, targetArg, sizeof(targetArg));

	int targets[MAXPLAYERS];
	char targetName[MAX_TARGET_LENGTH];
	bool tnIsMl;
	int count = ProcessTargetString(targetArg, client, targets, sizeof(targets), COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_BOTS, targetName, sizeof(targetName), tnIsMl);
	if (count <= 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for (int i = 0; i < count; i++) {
		CFakeLag_ClearPlayerProfile(targets[i]);
	}

	ReplyToCommand(client, "[CFT] Cleared profile for %s.", targetName);
	return Plugin_Handled;
}

static Action Command_CountProfiles(int client, int args)
{
	ReplyToCommand(client, "[CFT] Active profiles: %d", CFakeLag_GetProfiledClientCount());
	return Plugin_Handled;
}

static Action Command_SetLossMode(int client, int args)
{
	if (args < 1) {
		ReplyToCommand(client, "[CFT] Usage: sm_cft_setlossmode <bernoulli|gilbert|0|1>");
		return Plugin_Handled;
	}

	char modeArg[32];
	GetCmdArg(1, modeArg, sizeof(modeArg));

	CFakeLagPacketLossMode mode;
	if (StrEqual(modeArg, "1", false) || StrEqual(modeArg, "gilbert", false) || StrEqual(modeArg, "gilbert-elliott", false)) {
		mode = CFakeLagPacketLoss_GilbertElliott;
	} else {
		mode = CFakeLagPacketLoss_BernoulliUniform;
	}

	CFakeLag_SetPacketLossMode(mode);
	ReplyToCommand(client, "[CFT] Packet loss mode set to %s.", mode == CFakeLagPacketLoss_GilbertElliott ? "gilbert-elliott" : "bernoulli");
	return Plugin_Handled;
}

static Action Command_GetLossMode(int client, int args)
{
	CFakeLagPacketLossMode mode = CFakeLag_GetPacketLossMode();
	ReplyToCommand(client, "[CFT] Current packet loss mode: %s", mode == CFakeLagPacketLoss_GilbertElliott ? "gilbert-elliott" : "bernoulli");
	return Plugin_Handled;
}

static int GetSingleTargetFromCmd(int client, int arg)
{
	char targetArg[64];
	GetCmdArg(arg, targetArg, sizeof(targetArg));

	int target = FindTarget(client, targetArg, true, false);
	if (target <= 0) {
		return -1;
	}

	return target;
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
