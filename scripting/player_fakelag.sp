#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <colors>
#include <custom_fakelag>
#include <left4dhooks_stocks>

Handle g_FakeLagBalanceVote = null;
StringMap g_PlayerLatencyByAccountId = null;
StringMap g_PlayerDisconnectedByAccountId = null;
ConVar g_CvarDebug = null;
ConVar g_CvarSampleWindow = null;
ConVar g_CvarSampleInterval = null;
bool g_ForgetLatencyOnNextClear[MAXPLAYERS + 1];
Handle g_LatencySamplingTimer = null;
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

stock bool FakelagIsDebugEnabled()
{
	return g_CvarDebug != null && g_CvarDebug.BoolValue;
}

public void OnPluginStart()
{
	g_PlayerLatencyByAccountId = new StringMap();
	g_PlayerDisconnectedByAccountId = new StringMap();
	g_CvarDebug = CreateConVar("sm_fakelag_debug", "0", "Log player_fakelag persistence and restore activity to the SourceMod logs.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_CvarSampleWindow = CreateConVar("sm_fakelag_sample_window", "5", "Number of rolling ping samples used for latency averaging.", FCVAR_NOTIFY, true, 1.0, true, 5.0);
	g_CvarSampleInterval = CreateConVar("sm_fakelag_sample_interval", "1.0", "Seconds between rolling ping samples.", FCVAR_NOTIFY, true, 0.1, true, 5.0);
	g_CvarSampleWindow.AddChangeHook(FakelagOnSamplingSettingsChanged);
	g_CvarSampleInterval.AddChangeHook(FakelagOnSamplingSettingsChanged);
	
	g_FwdOnSetPlayerLatency = new GlobalForward("PlayerFakelag_OnSetPlayerLatency", ET_Hook, Param_Cell, Param_Float, Param_FloatByRef, Param_Cell);
	g_FwdOnPlayerLatencyChanged = new GlobalForward("PlayerFakelag_OnPlayerLatencyChanged", ET_Ignore, Param_Cell, Param_Float, Param_Float, Param_Cell);
	g_FwdOnPluginEnd = new GlobalForward("PlayerFakelag_OnPluginEnd", ET_Ignore);

	LoadTranslations("common.phrases");
	LoadTranslations("player_fakelag.phrases");
	HookEvent("player_team", Event_PlayerTeam);
	FakelagStartLatencySampling();

	RegAdminCmd("sm_fakelag", FakeLagCmd, ADMFLAG_CONFIG, "Set fake lag for a player; use 0 to clear");
	RegAdminCmd("sm_fakelag_balance", BalanceLagCmd, ADMFLAG_CONFIG, "Balance fake lag across survivors and infected using average ping");
	RegAdminCmd("sm_fakelag_balance_preview", PreviewBalanceLagCmd, ADMFLAG_CONFIG, "Preview fake lag balance across survivors and infected using average ping");
	RegAdminCmd("sm_fakelag_clear_all", ClearAllLagCmd, ADMFLAG_CONFIG, "Clear all fake lag entries");
	RegAdminCmd("sm_fakelag_list", PrintLagCmd, ADMFLAG_CONFIG, "Print active fake lag entries");

	RegConsoleCmd("sm_fakelag_clear", ClearLagCmd, "Clear fake lag for yourself or, with admin access, for another player");
	RegConsoleCmd("sm_fakelag_status", StatusLagCmd, "Show your fake lag status or, with admin access, another player's status");
	RegConsoleCmd("sm_fakelag_compare", CompareLagCmd, "Compare your measured latency with another player, or compare two players");
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
	FakelagStopLatencySampling();
	CFakeLag_ClearAllPlayerLatencies();
	delete g_PlayerLatencyByAccountId;
	g_PlayerLatencyByAccountId = null;
	delete g_PlayerDisconnectedByAccountId;
	g_PlayerDisconnectedByAccountId = null;
	g_CvarDebug = null;
	g_CvarSampleWindow = null;
	g_CvarSampleInterval = null;

	delete g_FwdOnSetPlayerLatency;
	g_FwdOnSetPlayerLatency = null;

	delete g_FwdOnPlayerLatencyChanged;
	g_FwdOnPlayerLatencyChanged = null;

	delete g_FwdOnPluginEnd;
	g_FwdOnPluginEnd = null;
}

public void OnClientPostAdminCheck(int client)
{
	FakelagResetClientLatencySamples(client);
	FakelagQueueRestoreClientLatency(client);
}

public void OnClientDisconnect(int client)
{
	FakelagResetClientLatencySamples(client);
	g_ForgetLatencyOnNextClear[client] = false;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetBool("isbot"))
	{
		return;
	}

	if (event.GetBool("disconnect"))
	{
		int disconnectingClient = GetClientOfUserId(event.GetInt("userid"));
		if (disconnectingClient > 0)
		{
			FakelagSetDisconnectedState(disconnectingClient, true);
		}
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || !IsClientInGame(client))
	{
		return;
	}

	L4DTeam oldTeam = view_as<L4DTeam>(event.GetInt("oldteam"));
	L4DTeam newTeam = view_as<L4DTeam>(event.GetInt("team"));

	if (FakelagIsSupportedBalanceTeam(oldTeam) && !FakelagIsSupportedBalanceTeam(newTeam))
	{
		if (CFakeLag_HasPlayerLatency(client))
		{
			CFakeLag_ClearPlayerLatency(client);
		}
		return;
	}

	if (FakelagIsSupportedBalanceTeam(newTeam))
	{
		FakelagQueueRestoreClientLatency(client);
	}
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
	// BuiltinVotes expects the final text here; phrase keys are not localized at render time.
	Format(voteQuestion, sizeof(voteQuestion), "%T", "FakelagBalanceVoteQuestion", LANG_SERVER);

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

	if (!FakelagCanApplyLatencyToClient(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerUnsupported", target);
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

		g_ForgetLatencyOnNextClear[target] = true;
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

	bool canTargetOthers = CheckCommandAccess(client, "sm_fakelag_status_others", ADMFLAG_CONFIG, true);
	int target = client;

	if (args >= 1 && canTargetOthers)
	{
		char targetStr[256];
		FakelagBuildArgRangeString(1, args, targetStr, sizeof(targetStr));

		target = FindTarget(client, targetStr, true);
		if (target < 0)
		{
			return Plugin_Handled;
		}
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

	bool canTargetOthers = CheckCommandAccess(client, "sm_fakelag_clear_others", ADMFLAG_CONFIG, true);
	int target = client;

	if (args >= 1 && canTargetOthers)
	{
		char targetStr[256];
		FakelagBuildArgRangeString(1, args, targetStr, sizeof(targetStr));

		target = FindTarget(client, targetStr, true);
		if (target < 0)
		{
			return Plugin_Handled;
		}
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

	g_ForgetLatencyOnNextClear[target] = true;
	CFakeLag_ClearPlayerLatency(target);
	if (target == client && !canTargetOthers)
	{
		CPrintToChatAll("%t %t", "Tag", "FakelagSelfClearedAnnounce", client);
		return Plugin_Handled;
	}

	CReplyToCommand(client, "%t %t", "Tag", "FakelagClearedOnPlayer", target);
	return Plugin_Handled;
}

public Action CompareLagCmd(int client, int args)
{
	if (!FakelagCommandRequiresClient(client))
	{
		return Plugin_Handled;
	}

	if (args < 1)
	{
		CReplyToCommand(client, "%t %t {green}sm_fakelag_compare <#userid|name> [#userid|name]{default}", "Tag", "Use");
		return Plugin_Handled;
	}

	int firstTarget = client;
	int secondTarget;

	char targetArg[256];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	secondTarget = FakelagFindComparisonTarget(client, targetArg);
	if (secondTarget < 0)
	{
		return Plugin_Handled;
	}

	if (args >= 2)
	{
		char firstTargetArg[256];
		strcopy(firstTargetArg, sizeof(firstTargetArg), targetArg);
		GetCmdArg(2, targetArg, sizeof(targetArg));

		firstTarget = FakelagFindComparisonTarget(client, firstTargetArg);
		if (firstTarget < 0)
		{
			return Plugin_Handled;
		}

		secondTarget = FakelagFindComparisonTarget(client, targetArg);
		if (secondTarget < 0)
		{
			return Plugin_Handled;
		}
	}

	FakelagReplyPlayerComparison(client, firstTarget, secondTarget);
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
	g_PlayerLatencyByAccountId.Clear();
	g_PlayerDisconnectedByAccountId.Clear();
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
#include "player_fakelag/persistence.sp"
#include "player_fakelag/balance.sp"
#include "player_fakelag/vote.sp"
#include "player_fakelag/natives.sp"
