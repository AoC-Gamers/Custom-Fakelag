#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>
#include <custom_fakelag>

public Plugin myinfo =
{
	name = "Per-Player Fakelag",
	author = "ProdigySim, lechuga",
	description = "Admin commands for the Custom Fakelag extension",
	version = "1.1",
	url = "https://github.com/AoC-Gamers/L4D2_Custom_Fakelag"
};

public void OnPluginStart()
{
	LoadTranslations("custom_fakelag_player.phrases");

	RegAdminCmd("sm_fakelag", FakeLagCmd, ADMFLAG_CONFIG, "Set fake lag for a player; use 0 to clear");
	RegAdminCmd("sm_fakelag_clear", ClearLagCmd, ADMFLAG_CONFIG, "Clear fake lag for a player");
	RegAdminCmd("sm_fakelag_clearall", ClearAllLagCmd, ADMFLAG_CONFIG, "Clear all fake lag entries");
	RegAdminCmd("sm_fakelag_list", PrintLagCmd, ADMFLAG_CONFIG, "Print active fake lag entries");
}

stock bool FakelagCommandRequiresClient(int client)
{
	if (client != 0) {
		return true;
	}

	CReplyToCommand(client, "%t %t", "Tag", LANG_SERVER, "FakelagClientOnlyCommand");
	return false;
}

public Action FakeLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client)) {
		return Plugin_Handled;
	}

	if (args < 2) {
		CReplyToCommand(client, "%t %t {green}sm_fakelag <target> <milliseconds|0>{default}", "Tag", "Use");
		return Plugin_Handled;
	}

	char targetStr[256];
	GetCmdArg(1, targetStr, sizeof(targetStr));

	int target = FindTarget(client, targetStr, true);
	if (target < 0) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagTargetNotFound", targetStr);
		return Plugin_Handled;
	}

	if (!IsClientInGame(target)) {
		CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagPlayerNotInGame", target);
		return Plugin_Handled;
	}

	if (IsFakeClient(target)) {
		CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagPlayerIsBot", target);
		return Plugin_Handled;
	}

	int lagAmount = GetCmdArgInt(2);
	if (lagAmount < 0) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagLagNonNegative");
		return Plugin_Handled;
	}

	if (lagAmount == 0) {
		if (!CFakeLag_HasPlayerLatency(target)) {
			CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagPlayerNotLagged", target);
			return Plugin_Handled;
		}

		CFakeLag_ClearPlayerLatency(target);
		CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagClearedOnPlayer", target);
		return Plugin_Handled;
	}

	CFakeLag_SetPlayerLatency(target, float(lagAmount));
	CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagSetOnPlayer", lagAmount, target);
	return Plugin_Handled;
}

public Action ClearLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client)) {
		return Plugin_Handled;
	}

	if (args < 1) {
		CReplyToCommand(client, "%t %t {green}sm_fakelag_clear <target>{default}", "Tag", "Use");
		return Plugin_Handled;
	}

	char targetStr[256];
	GetCmdArg(1, targetStr, sizeof(targetStr));

	int target = FindTarget(client, targetStr, true);
	if (target < 0) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagTargetNotFound", targetStr);
		return Plugin_Handled;
	}

	if (!CFakeLag_IsClientSupported(target)) {
		CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagPlayerUnsupported", target);
		return Plugin_Handled;
	}

	if (!CFakeLag_HasPlayerLatency(target)) {
		CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagPlayerNotLagged", target);
		return Plugin_Handled;
	}

	CFakeLag_ClearPlayerLatency(target);
	CReplyToCommandEx(client, target, "%T %t", "Tag", client, "FakelagClearedOnPlayer", target);
	return Plugin_Handled;
}

public Action ClearAllLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client)) {
		return Plugin_Handled;
	}

	int laggedClients = CFakeLag_GetLaggedClientCount();
	if (laggedClients <= 0) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagNoEntriesToClear");
		return Plugin_Handled;
	}

	CFakeLag_ClearAllPlayerLatencies();
	CReplyToCommand(client, "%t %t", "Tag", client, "FakelagClearedAll", laggedClients);
	return Plugin_Handled;
}

public Action PrintLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client)) {
		return Plugin_Handled;
	}

	int laggedClients = CFakeLag_GetLaggedClientCount();
	if (laggedClients <= 0) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagNoPlayersLagged");
		return Plugin_Handled;
	}

	CReplyToCommand(client, "%t %t", "Tag", client, "FakelagActiveEntries", laggedClients);

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && CFakeLag_HasPlayerLatency(i)) {
			CReplyToCommandEx(client, i, "%T %t", "Tag", client, "FakelagPlayerEntry", i, CFakeLag_GetPlayerLatency(i));
		}
	}

	return Plugin_Handled;
}
