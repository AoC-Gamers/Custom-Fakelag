#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <colors>
#include <custom_fakelag>
#include <left4dhooks_stocks>

Handle g_FakeLagBalanceVote = null;
GlobalForward g_FwdOnSetPlayerLatency = null;
GlobalForward g_FwdOnPlayerLatencyChanged = null;
GlobalForward g_FwdOnPluginEnd = null;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	CreateNative("PlayerFakelag_ApplyBalance", Native_ApplyBalance);
	CreateNative("PlayerFakelag_PreviewBalance", Native_PreviewBalance);
	CreateNative("PlayerFakelag_StartBalanceVote", Native_StartBalanceVote);
	CreateNative("PlayerFakelag_IsBalanceVoteInProgress", Native_IsBalanceVoteInProgress);
	RegPluginLibrary("player_fakelag");

	return APLRes_Success;
}

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
	g_FwdOnSetPlayerLatency = new GlobalForward("PlayerFakelag_OnSetPlayerLatency", ET_Hook, Param_Cell, Param_Float, Param_FloatByRef, Param_Cell);
	g_FwdOnPlayerLatencyChanged = new GlobalForward("PlayerFakelag_OnPlayerLatencyChanged", ET_Ignore, Param_Cell, Param_Float, Param_Float, Param_Cell);
	g_FwdOnPluginEnd = new GlobalForward("PlayerFakelag_OnPluginEnd", ET_Ignore);

	LoadTranslations("custom_fakelag_player.phrases");

	RegAdminCmd("sm_fakelag", FakeLagCmd, ADMFLAG_CONFIG, "Set fake lag for a player; use 0 to clear");
	RegAdminCmd("sm_fakelag_status", StatusLagCmd, ADMFLAG_CONFIG, "Show fake lag status for a player");
	RegAdminCmd("sm_fakelag_balance", BalanceLagCmd, ADMFLAG_CONFIG, "Balance fake lag across survivors and infected using average ping");
	RegAdminCmd("sm_fakelag_balance_preview", PreviewBalanceLagCmd, ADMFLAG_CONFIG, "Preview fake lag balance across survivors and infected using average ping");
	RegAdminCmd("sm_fakelag_clear", ClearLagCmd, ADMFLAG_CONFIG, "Clear fake lag for a player");
	RegAdminCmd("sm_fakelag_clear_all", ClearAllLagCmd, ADMFLAG_CONFIG, "Clear all fake lag entries");
	RegAdminCmd("sm_fakelag_list", PrintLagCmd, ADMFLAG_CONFIG, "Print active fake lag entries");

	RegConsoleCmd("sm_fakelag_balance_vote", BalanceLagVoteCmd, "Start a fake lag balance vote");
}

public void OnPluginEnd()
{
	Call_StartForward(g_FwdOnPluginEnd);
	Call_Finish();

	if (g_FakeLagBalanceVote != null
		&& GetFeatureStatus(FeatureType_Native, "CancelBuiltinVote") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "IsBuiltinVoteInProgress") == FeatureStatus_Available
		&& IsBuiltinVoteInProgress())
	{
		CancelBuiltinVote();
	}

	g_FakeLagBalanceVote = null;
	CFakeLag_ClearAllPlayerLatencies();

	delete g_FwdOnSetPlayerLatency;
	g_FwdOnSetPlayerLatency = null;

	delete g_FwdOnPlayerLatencyChanged;
	g_FwdOnPlayerLatencyChanged = null;

	delete g_FwdOnPluginEnd;
	g_FwdOnPluginEnd = null;
}

public Action BalanceLagCmd(int client, int args)
{
	FakelagRunBalanceCommand(client);
	return Plugin_Handled;
}

public Action PreviewBalanceLagCmd(int client, int args)
{
	FakelagRunBalancePreviewCommand(client);
	return Plugin_Handled;
}

public Action BalanceLagVoteCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int highestClient;
	int count;
	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return Plugin_Handled;
	}

	if (!FakelagCanStartBalanceVote(client))
	{
		return Plugin_Handled;
	}

	Handle vote = CreateBuiltinVote(FakeLagBalanceVoteHandler, BuiltinVoteType_Custom_YesNo, BUILTINVOTE_ACTIONS_DEFAULT);
	if (vote == null)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceVoteUnavailable");
		return Plugin_Handled;
	}

	char voteQuestion[128];
	FakelagGetBalanceVoteQuestion(voteQuestion, sizeof(voteQuestion));

	g_FakeLagBalanceVote = vote;
	SetBuiltinVoteArgument(vote, voteQuestion);
	SetBuiltinVoteInitiator(vote, client);
	SetBuiltinVoteResultCallback(vote, FakeLagBalanceVoteResultHandler);

	if (!DisplayBuiltinVoteToAllNonSpectators(vote, 20))
	{
		g_FakeLagBalanceVote = null;
		delete vote;
		CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceVoteInProgress");
		return Plugin_Handled;
	}

	FakeClientCommand(client, "Vote Yes");

	FakelagNotifyVoteAudience("FakelagBalanceVoteAnnounce", client);
	CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceVoteStarted");
	return Plugin_Handled;
}

public Action FakeLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	if (args < 2)
	{
		CReplyToCommand(client, "%t %t {green}sm_fakelag <#userid|name> <milliseconds|0>{default}", "Tag", "Use");
		return Plugin_Handled;
	}

	char targetStr[256];
	FakelagBuildArgRangeString(1, args - 1, targetStr, sizeof(targetStr));

	int target = FindTarget(client, targetStr, true);
	if (target < 0)
	{
		return Plugin_Handled;
	}

	if (!IsClientInGame(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerNotInGame", target);
		return Plugin_Handled;
	}

	if (IsFakeClient(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerIsBot", target);
		return Plugin_Handled;
	}

	char lagArg[32];
	GetCmdArg(args, lagArg, sizeof(lagArg));
	int lagAmount = StringToInt(lagArg);
	if (lagAmount < 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagLagNonNegative");
		return Plugin_Handled;
	}

	if (lagAmount == 0)
	{
		if (!CFakeLag_HasPlayerLatency(target))
		{
			CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerNotLagged", target);
			return Plugin_Handled;
		}

		CFakeLag_ClearPlayerLatency(target);
		CReplyToCommand(client, "%t %t", "Tag", "FakelagClearedOnPlayer", target);
		return Plugin_Handled;
	}

	CFakeLag_SetPlayerLatency(target, float(lagAmount));
	CReplyToCommand(client, "%t %t", "Tag", "FakelagSetOnPlayer", lagAmount, target);
	return Plugin_Handled;
}

public Action StatusLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	if (args < 1)
	{
		CReplyToCommand(client, "%t %t {green}sm_fakelag_status <#userid|name>{default}", "Tag", "Use");
		return Plugin_Handled;
	}

	char targetStr[256];
	FakelagBuildArgRangeString(1, args, targetStr, sizeof(targetStr));

	int target = FindTarget(client, targetStr, true);
	if (target < 0)
	{
		return Plugin_Handled;
	}

	FakelagReplyPlayerStatus(client, target);
	return Plugin_Handled;
}

public Action ClearLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	if (args < 1)
	{
		CReplyToCommand(client, "%t %t {green}sm_fakelag_clear <#userid|name>{default}", "Tag", "Use");
		return Plugin_Handled;
	}

	char targetStr[256];
	FakelagBuildArgRangeString(1, args, targetStr, sizeof(targetStr));

	int target = FindTarget(client, targetStr, true);
	if (target < 0)
	{
		return Plugin_Handled;
	}

	if (!CFakeLag_IsClientSupported(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerUnsupported", target);
		return Plugin_Handled;
	}

	if (!CFakeLag_HasPlayerLatency(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerNotLagged", target);
		return Plugin_Handled;
	}

	CFakeLag_ClearPlayerLatency(target);
	CReplyToCommand(client, "%t %t", "Tag", "FakelagClearedOnPlayer", target);
	return Plugin_Handled;
}

public Action ClearAllLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	int laggedClients = CFakeLag_GetLaggedClientCount();
	if (laggedClients <= 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagNoEntriesToClear");
		return Plugin_Handled;
	}

	CFakeLag_ClearAllPlayerLatencies();
	CReplyToCommand(client, "%t %t", "Tag", "FakelagClearedAll", laggedClients);
	return Plugin_Handled;
}

public Action PrintLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	int laggedClients = CFakeLag_GetLaggedClientCount();
	if (laggedClients <= 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagNoPlayersLagged");
		return Plugin_Handled;
	}

	CReplyToCommand(client, "%t %t", "Tag", "FakelagActiveEntries", laggedClients);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && CFakeLag_HasPlayerLatency(i))
		{
			CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerEntry", i, CFakeLag_GetPlayerLatency(i));
		}
	}

	return Plugin_Handled;
}

#include "player_fakelag/latency.sp"
#include "player_fakelag/helpers.sp"
#include "player_fakelag/balance.sp"
#include "player_fakelag/vote.sp"
#include "player_fakelag/natives.sp"
