#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <colors>
#include <custom_fakelag>
#include <left4dhooks_stocks>

Handle g_FakeLagBalanceVote = null;

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
	LoadTranslations("custom_fakelag_player.phrases");

	RegAdminCmd("sm_fakelag", FakeLagCmd, ADMFLAG_CONFIG, "Set fake lag for a player; use 0 to clear");
	RegAdminCmd("sm_fakelag_balance", BalanceLagCmd, ADMFLAG_CONFIG, "Balance fake lag across survivors and infected using average ping");
	RegAdminCmd("sm_fakelag_balance_preview", PreviewBalanceLagCmd, ADMFLAG_CONFIG, "Preview fake lag balance across survivors and infected using average ping");
	RegAdminCmd("sm_fakelag_clear", ClearLagCmd, ADMFLAG_CONFIG, "Clear fake lag for a player");
	RegAdminCmd("sm_fakelag_clearall", ClearAllLagCmd, ADMFLAG_CONFIG, "Clear all fake lag entries");
	RegAdminCmd("sm_fakelag_list", PrintLagCmd, ADMFLAG_CONFIG, "Print active fake lag entries");
	
	RegConsoleCmd("sm_fakelag_balance_vote", BalanceLagVoteCmd, "Start a fake lag balance vote");
}

stock bool FakelagIsSupportedBalanceTeam(L4DTeam team)
{
	return team == L4DTeam_Survivor || team == L4DTeam_Infected;
}

stock bool FakelagIsBalanceCandidate(int client, L4DTeam team)
{
	if (!IsClientInGame(client) || IsFakeClient(client)) {
		return false;
	}

	return L4D_GetClientTeam(client) == team;
}

stock float FakelagGetClientAveragePingMs(int client)
{
	float latency = GetClientAvgLatency(client, NetFlow_Outgoing);
	if (latency < 0.0) {
		return -1.0;
	}

	return latency * 1000.0;
}

stock int FakelagCollectBalanceCandidates(int clients[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], float &highestPing, int &highestClient)
{
	int count = 0;
	highestPing = -1.0;
	highestClient = 0;

	for (int client = 1; client <= MaxClients; client++) {
		L4DTeam team = L4D_GetClientTeam(client);
		if (!FakelagIsSupportedBalanceTeam(team) || !FakelagIsBalanceCandidate(client, team)) {
			continue;
		}

		float averagePing = FakelagGetClientAveragePingMs(client);
		if (averagePing < 0.0) {
			continue;
		}

		clients[count] = client;
		pings[count] = averagePing;
		count++;

		if (averagePing > highestPing) {
			highestPing = averagePing;
			highestClient = client;
		}
	}

	return count;
}

stock void FakelagApplyBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int adjusted = 0;
	int cleared = 0;

	for (int index = 0; index < count; index++) {
		int target = clients[index];
		float ping = pings[index];
		float compensation = targetPing - ping;

		if (compensation <= 0.0) {
			if (CFakeLag_HasPlayerLatency(target)) {
				CFakeLag_ClearPlayerLatency(target);
				cleared++;
			}

			CReplyToCommandEx(admin, target, "%T %t", "Tag", admin, "FakelagBalancePlayerUnchanged", target, ping);
			continue;
		}

		CFakeLag_SetPlayerLatency(target, compensation);
		adjusted++;
		CReplyToCommandEx(admin, target, "%T %t", "Tag", admin, "FakelagBalancePlayerAdjusted", target, ping, compensation);
	}

	CReplyToCommand(admin, "%t %t", "Tag", admin, "FakelagBalanceApplied", count, adjusted, cleared, targetPing);
}

stock void FakelagPreviewBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int adjusted = 0;

	for (int index = 0; index < count; index++) {
		int target = clients[index];
		float ping = pings[index];
		float compensation = targetPing - ping;

		if (compensation <= 0.0) {
			CReplyToCommandEx(admin, target, "%T %t", "Tag", admin, "FakelagBalancePreviewPlayerUnchanged", target, ping);
			continue;
		}

		adjusted++;
		CReplyToCommandEx(admin, target, "%T %t", "Tag", admin, "FakelagBalancePreviewPlayerAdjusted", target, ping, compensation);
	}

	CReplyToCommand(admin, "%t %t", "Tag", admin, "FakelagBalancePreviewApplied", count, adjusted, targetPing);
}

stock bool FakelagCanUseBuiltinVotes()
{
	return GetFeatureStatus(FeatureType_Native, "CreateBuiltinVote") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "DisplayBuiltinVote") == FeatureStatus_Available;
}

stock bool FakelagTryCollectBalance(int client, int targets[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], float &highestPing, int &highestClient, int &count)
{
	count = FakelagCollectBalanceCandidates(targets, pings, highestPing, highestClient);
	if (count <= 0 || highestClient <= 0 || highestPing < 0.0) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceNoPlayers");
		return false;
	}

	return true;
}

stock void FakelagRunBalanceCommand(int client)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int highestClient;
	int count;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count)) {
		return;
	}

	CReplyToCommandEx(client, highestClient, "%T %t", "Tag", client, "FakelagBalanceTarget", highestClient, highestPing);
	FakelagApplyBalance(client, targets, pings, count, highestPing);
}

stock bool FakelagApplyBalanceSilent(float &targetPing, int &highestClient, int &playerCount, int &adjustedCount, int &clearedCount)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];

	playerCount = FakelagCollectBalanceCandidates(targets, pings, targetPing, highestClient);
	adjustedCount = 0;
	clearedCount = 0;

	if (playerCount <= 0 || highestClient <= 0 || targetPing < 0.0) {
		return false;
	}

	for (int index = 0; index < playerCount; index++) {
		int target = targets[index];
		float compensation = targetPing - pings[index];

		if (compensation <= 0.0) {
			if (CFakeLag_HasPlayerLatency(target)) {
				CFakeLag_ClearPlayerLatency(target);
				clearedCount++;
			}
			continue;
		}

		CFakeLag_SetPlayerLatency(target, compensation);
		adjustedCount++;
	}

	return true;
}

stock bool FakelagPreviewBalanceSilent(float &targetPing, int &highestClient, int &playerCount)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];

	playerCount = FakelagCollectBalanceCandidates(targets, pings, targetPing, highestClient);
	return playerCount > 0 && highestClient > 0 && targetPing >= 0.0;
}

stock void FakelagRunBalancePreviewCommand(int client)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int highestClient;
	int count;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count)) {
		return;
	}

	CReplyToCommandEx(client, highestClient, "%T %t", "Tag", client, "FakelagBalancePreviewTarget", highestClient, highestPing);
	FakelagPreviewBalance(client, targets, pings, count, highestPing);
}

stock bool FakelagCanStartBalanceVote(int client)
{
	if (!FakelagCanUseBuiltinVotes()) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceVoteUnavailable");
		return false;
	}

	if (!IsNewBuiltinVoteAllowed() || g_FakeLagBalanceVote != null) {
		int delay = CheckBuiltinVoteDelay();
		if (delay > 0) {
			CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceVoteDelay", delay);
		} else {
			CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceVoteInProgress");
		}
		return false;
	}

	return true;
}

stock void FakelagGetBalanceVoteQuestion(char[] buffer, int maxlen)
{
	Format(buffer, maxlen, "%T", "FakelagBalanceVoteQuestion", LANG_SERVER);
}

stock void FakelagNotifyVoteAudience(const char[] phrase, int initiator = 0)
{
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) < view_as<int>(L4DTeam_Survivor)) {
			continue;
		}

		if (initiator > 0) {
			CReplyToCommandEx(client, initiator, "%T %t", "Tag", client, phrase, initiator);
		} else {
			CReplyToCommand(client, "%t %t", "Tag", client, phrase);
		}
	}
}

public void FakeLagBalanceVoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	if (action == BuiltinVoteAction_End) {
		if (g_FakeLagBalanceVote == vote) {
			g_FakeLagBalanceVote = null;
		}

		delete vote;
	}
}

public void FakeLagBalanceVoteResultHandler(Handle vote, int numVotes, int numClients, const int[][] clientInfo, int numItems, const int[][] itemInfo)
{
	if (numItems < 1 || itemInfo[0][BUILTINVOTEINFO_ITEM_INDEX] != BUILTINVOTES_VOTE_YES) {
		FakelagNotifyVoteAudience("FakelagBalanceVoteFailed");
		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
		return;
	}

	FakelagNotifyVoteAudience("FakelagBalanceVotePassed");
	DisplayBuiltinVotePass(vote);
	FakelagRunBalanceCommand(0);
}

stock bool FakelagCommandRequiresClient(int client)
{
	if (client != 0) {
		return true;
	}

	CReplyToCommand(client, "%t %t", "Tag", LANG_SERVER, "FakelagClientOnlyCommand");
	return false;
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
	if (!FakelagCommandRequiresClient(client)) {
		return Plugin_Handled;
	}

	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int highestClient;
	int count;
	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count)) {
		return Plugin_Handled;
	}

	if (!FakelagCanStartBalanceVote(client)) {
		return Plugin_Handled;
	}

	Handle vote = CreateBuiltinVote(FakeLagBalanceVoteHandler, BuiltinVoteType_Custom_YesNo, BUILTINVOTE_ACTIONS_DEFAULT);
	if (vote == null) {
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceVoteUnavailable");
		return Plugin_Handled;
	}

	char voteQuestion[128];
	FakelagGetBalanceVoteQuestion(voteQuestion, sizeof(voteQuestion));

	g_FakeLagBalanceVote = vote;
	SetBuiltinVoteArgument(vote, voteQuestion);
	SetBuiltinVoteInitiator(vote, client);
	SetBuiltinVoteResultCallback(vote, FakeLagBalanceVoteResultHandler);

	if (!DisplayBuiltinVoteToAllNonSpectators(vote, 20)) {
		g_FakeLagBalanceVote = null;
		delete vote;
		CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceVoteInProgress");
		return Plugin_Handled;
	}

	FakelagNotifyVoteAudience("FakelagBalanceVoteAnnounce", client);
	CReplyToCommand(client, "%t %t", "Tag", client, "FakelagBalanceVoteStarted");
	return Plugin_Handled;
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

public int Native_ApplyBalance(Handle plugin, int numParams)
{
	float targetPing;
	int highestClient;
	int playerCount;
	int adjustedCount;
	int clearedCount;

	bool result = FakelagApplyBalanceSilent(targetPing, highestClient, playerCount, adjustedCount, clearedCount);
	SetNativeCellRef(1, view_as<int>(targetPing));
	SetNativeCellRef(2, highestClient);
	SetNativeCellRef(3, playerCount);
	SetNativeCellRef(4, adjustedCount);
	SetNativeCellRef(5, clearedCount);
	return result;
}

public int Native_PreviewBalance(Handle plugin, int numParams)
{
	float targetPing;
	int highestClient;
	int playerCount;

	bool result = FakelagPreviewBalanceSilent(targetPing, highestClient, playerCount);
	SetNativeCellRef(1, view_as<int>(targetPing));
	SetNativeCellRef(2, highestClient);
	SetNativeCellRef(3, playerCount);
	return result;
}

public int Native_StartBalanceVote(Handle plugin, int numParams)
{
	int initiator = numParams >= 1 ? GetNativeCell(1) : 0;

	if (initiator != 0 && (!IsClientInGame(initiator) || IsFakeClient(initiator))) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not a valid human initiator", initiator);
	}

	if (!FakelagCanStartBalanceVote(initiator)) {
		return false;
	}

	float highestPing;
	int highestClient;
	int playerCount;
	if (!FakelagPreviewBalanceSilent(highestPing, highestClient, playerCount)) {
		return false;
	}

	Handle vote = CreateBuiltinVote(FakeLagBalanceVoteHandler, BuiltinVoteType_Custom_YesNo, BUILTINVOTE_ACTIONS_DEFAULT);
	if (vote == null) {
		return false;
	}

	char voteQuestion[128];
	FakelagGetBalanceVoteQuestion(voteQuestion, sizeof(voteQuestion));

	g_FakeLagBalanceVote = vote;
	SetBuiltinVoteArgument(vote, voteQuestion);
	SetBuiltinVoteInitiator(vote, initiator == 0 ? BUILTINVOTES_SERVER_INDEX : initiator);
	SetBuiltinVoteResultCallback(vote, FakeLagBalanceVoteResultHandler);

	if (!DisplayBuiltinVoteToAllNonSpectators(vote, 20)) {
		g_FakeLagBalanceVote = null;
		delete vote;
		return false;
	}

	if (initiator > 0) {
		FakelagNotifyVoteAudience("FakelagBalanceVoteAnnounce", initiator);
	} else {
		FakelagNotifyVoteAudience("FakelagBalanceVoteStartedServer");
	}

	return true;
}

public int Native_IsBalanceVoteInProgress(Handle plugin, int numParams)
{
	return g_FakeLagBalanceVote != null;
}
