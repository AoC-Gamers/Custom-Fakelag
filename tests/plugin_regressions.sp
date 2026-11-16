// Isolated SourceMod regression host: executes the production plugin sources.
// Client identity/transport and CFakeLag natives are mocked; timers, forwards,
// RequestFrame, StringMaps, translations and exception boundaries are real SM.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#undef REQUIRE_EXTENSIONS
#undef AUTOLOAD_EXTENSIONS
#include <builtinvotes>
#include <colors>
#include <console_table>
#include <left4dhooks_stocks>
#undef REQUIRE_EXTENSIONS
#undef AUTOLOAD_EXTENSIONS
#include <custom_fakelag>

stock FeatureStatus RealFeatureStatus(FeatureType type, const char[] name) { return GetFeatureStatus(type, name); }
#define GetFeatureStatus MockFeatureStatus
#define CancelBuiltinVote MockCancelVote
#define IsBuiltinVoteInProgress MockVoteInProgress
#define FindTarget MockFindTarget
#define GetCmdArg MockCmdArg
#define CheckCommandAccess MockCommandAccess
#define GetClientUserId MockUserId
#define GetClientOfUserId MockClient
#define IsClientInGame MockInGame
#define IsClientAuthorized MockInGame
#define IsFakeClient MockFake
#define GetSteamAccountID MockAccount
#define GetClientTeam MockTeam
#define L4D_GetClientTeam MockL4DTeam
#define GetClientAvgLatency MockPing
#define GetClientInfo MockInfo
#define CPrintToChat TestPrint
#define CReplyToCommand TestPrint
#define CPrintToChatEx TestPrintEx
#define CFakeLag_IsLanBlocked MockBlocked
#define CFakeLag_IsClientSupported MockInGame
#define CFakeLag_GetPlayerProfile MockGet
#define CFakeLag_HasPlayerProfile MockHas
#define CFakeLag_GetProfiledClientCount MockCount
#define CFakeLag_SetPlayerProfile MockSet
#define CFakeLag_ClearPlayerProfile MockClear
#define CFakeLag_ClearAllPlayerProfiles MockClearAll
#define CFakeLag_ResetState MockClearAll
#define CFakeLag_GetPacketLossMode MockMode
#define CFakeLag_SetPacketLossMode MockSetMode
#define AskPluginLoad2 ProductionAskPluginLoad2
#define OnPluginStart ProductionOnPluginStart
#define OnMapStart ProductionOnMapStart
#define OnMapEnd ProductionOnMapEnd
#define OnPluginEnd ProductionOnPluginEnd
#define OnConfigsExecuted ProductionOnConfigsExecuted
#include "../scripting/player_fakelag.sp"
#undef AskPluginLoad2
#undef OnPluginStart
#undef OnMapStart
#undef OnMapEnd
#undef OnPluginEnd
#undef OnConfigsExecuted

CFakeLagNetworkProfile g_TestProfiles[MAXPLAYERS + 1];
int g_TestSession[3] = {0, 101, 102};
int g_TestTeam[3] = {0, 2, 3};
bool g_TestBlocked;
Action g_TestAction;
float g_TestOverride = -1.0;
bool g_TestNativeError;
bool g_TestClearError;
bool g_TestClearReenter;
int g_TestReenter;
int g_TestReads;
int g_TestNotices;
int g_TestChecks;
int g_TestLagArgument = 100;
char g_TestLastNotice[1024];
bool g_TestVoteInProgress;
int g_TestVoteCancels;
Handle g_TestVoteToCancel;
CFakeLagPacketLossMode g_TestMode = CFakeLagPacketLoss_GilbertElliott;

stock int MockFindTarget(int admin, const char[] name, bool noBots = false, bool immunity = true) {
#pragma unused admin
#pragma unused name
#pragma unused noBots
#pragma unused immunity
	return 1;
}
stock int MockCmdArg(int number, char[] out, int len) { if (number == 2) IntToString(g_TestLagArgument, out, len); else strcopy(out, len, "test"); return strlen(out); }
stock bool MockCommandAccess(int c, const char[] command, int flags, bool overrideOnly = false) { return c > 0 && command[0] != '\0' && (flags > 0 || overrideOnly); }
stock FeatureStatus MockFeatureStatus(FeatureType type, const char[] name)
{
	if (StrEqual(name, "CancelBuiltinVote") || StrEqual(name, "IsBuiltinVoteInProgress")) return FeatureStatus_Available;
	return RealFeatureStatus(type, name);
}
stock bool MockVoteInProgress() { return g_TestVoteInProgress; }
stock void MockCancelVote()
{
	g_TestVoteCancels++; g_TestVoteInProgress = false;
	int clients[1][2]; int items[1][2];
	FakeLagBalanceVoteResultHandler(g_TestVoteToCancel, 0, 0, clients, 0, items);
	FakeLagBalanceVoteHandler(g_TestVoteToCancel, BuiltinVoteAction_End, 0, 0);
	g_TestVoteToCancel = null;
}
stock int MockUserId(int client) { return client > 0 && client < 3 ? g_TestSession[client] : 0; }
stock int MockClient(int userId) { for (int c = 1; c < 3; c++) if (g_TestSession[c] == userId && userId > 0) return c; return 0; }
stock bool MockInGame(int client) { return MockUserId(client) > 0; }
stock bool MockFake(int client) { return !MockInGame(client); }
stock int MockAccount(int client, bool validate = true) {
#pragma unused validate
	return client + 1000;
}
stock L4DTeam MockL4DTeam(int client) { return view_as<L4DTeam>(MockTeam(client)); }
stock int MockTeam(int client) { return client > 0 && client < 3 ? g_TestTeam[client] : 0; }
stock float MockPing(int client, NetFlow flow) {
#pragma unused flow
	g_TestReads++;
	return (client == 1 ? 0.030 : 0.080) + g_TestProfiles[client].lagMs / 1000.0;
}
stock bool MockInfo(int client, const char[] key, char[] out, int len) { strcopy(out, len, "60"); return client > 0 && key[0] != '\0'; }
stock bool MockBlocked() { return g_TestBlocked; }
stock bool MockHas(int c) { return FakelagProfileIsActive(g_TestProfiles[c]); }
stock bool MockGet(int c, CFakeLagNetworkProfile out) { out = g_TestProfiles[c]; return MockHas(c); }
stock int MockCount() { int n; for (int c = 1; c < 3; c++) if (MockHas(c)) n++; return n; }
stock CFakeLagPacketLossMode MockMode() { return g_TestMode; }
stock void MockSetMode(CFakeLagPacketLossMode mode) { CFakeLagPacketLossMode old = g_TestMode; MockClearAll(); g_TestMode = mode; CFakeLag_OnPacketLossModeChanged(old, mode); }
stock void TestPrint(int client, const char[] format, any ...)
{
	char text[1024]; VFormat(text, sizeof(text), format, 3);
	strcopy(g_TestLastNotice, sizeof(g_TestLastNotice), text);
	g_TestNotices++; PrintToServer("[plugin_test] notice target=%d %s", client, text);
}
stock void TestPrintEx(int client, int author, const char[] format, any ...)
{
	char text[1024]; VFormat(text, sizeof(text), format, 4);
	strcopy(g_TestLastNotice, sizeof(g_TestLastNotice), text);
	g_TestNotices++; PrintToServer("[plugin_test] notice target=%d author=%d %s", client, author, text);
}
stock void MockSet(int c, float lag, int loss)
{
	if (g_TestNativeError) ThrowError("plugin_test EXPECTED injected set failure");
	int userId = MockUserId(c);
	int epoch = g_Runtime.intentEpoch;
	Action action = CFakeLag_OnSetPlayerLatency(c, g_TestProfiles[c].lagMs, lag, CFakeLagChange_Manual);
	if (action >= Plugin_Handled || userId != MockUserId(c) || epoch != g_Runtime.intentEpoch || g_TestBlocked) return;
	CFakeLagNetworkProfile old; old = g_TestProfiles[c];
	g_TestProfiles[c] = FakelagBuildNetworkProfile(lag, loss);
	if (!FakelagProfilesEqual(old, g_TestProfiles[c])) CFakeLag_OnPlayerProfileChanged(c, old.lagMs, old.packetLossPercent, lag, loss, CFakeLagChange_Manual);
}
stock void MockClear(int c)
{
	if (g_TestNativeError) ThrowError("plugin_test EXPECTED injected clear failure");
	float lag;
	Action action = CFakeLag_OnSetPlayerLatency(c, g_TestProfiles[c].lagMs, lag, CFakeLagChange_Clear);
	if (action >= Plugin_Handled) return;
	CFakeLagNetworkProfile old; old = g_TestProfiles[c];
	g_TestProfiles[c] = FakelagBuildNetworkProfile(lag, 0);
	if (!FakelagProfilesEqual(old, g_TestProfiles[c])) CFakeLag_OnPlayerProfileChanged(c, old.lagMs, old.packetLossPercent, lag, 0, CFakeLagChange_Clear);
}
stock void MockClearAll()
{
	for (int c = 1; c < 3; c++)
	{
		CFakeLagNetworkProfile old; old = g_TestProfiles[c];
		g_TestProfiles[c] = FakelagBuildNetworkProfile(0.0, 0);
		if (FakelagProfileIsActive(old)) CFakeLag_OnPlayerProfileChanged(c, old.lagMs, old.packetLossPercent, 0.0, 0, CFakeLagChange_Clear);
	}
	if (g_TestClearReenter)
	{
		FakelagStoreProfileForClient(1, 90.0, 1);
		FakelagQueueRestoreClientLatency(1);
	}
	if (g_TestClearError) ThrowError("plugin_test EXPECTED injected detour synchronization failure");
}
public Action PlayerFakelag_OnSetPlayerLatency(int client, float oldLag, float &lag, int reason)
{
	if (g_TestReenter == 1) { g_TestSession[client] += 1000; }
	if (g_TestReenter == 2) { g_TestBlocked = true; CFakeLag_OnLanPolicyChanged(true); }
	if (g_TestReenter == 3) { FakelagForgetAllIntent(); }
	if (g_TestOverride >= 0.0) lag = g_TestOverride;
	return g_TestAction;
}

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int maxlen) { MarkNativeAsOptional("CancelBuiltinVote"); return ProductionAskPluginLoad2(self, late, error, maxlen); }
public void OnPluginStart()
{
	ProductionOnPluginStart();
	RegServerCmd("cf_plugin_test", TestCommand);
	RegServerCmd("cf_plugin_sampling", SamplingCommand);
	PrintToServer("[plugin_test] loaded late=%d", g_Runtime.lateLoad);
}
public void OnMapStart() { ProductionOnMapStart(); PrintToServer("[plugin_test] map-start timer=%d count=%d", g_LatencySamplingTimer != null, g_ClientLatencySampleCount[1]); }
public void OnMapEnd() { ProductionOnMapEnd(); PrintToServer("[plugin_test] map-end timer=%d", g_LatencySamplingTimer != null); }
public void OnPluginEnd() { g_TestNativeError = false; g_TestClearError = false; ProductionOnPluginEnd(); }
public void OnConfigsExecuted() { ProductionOnConfigsExecuted(); }

void Check(bool condition, const char[] label)
{
	if (!condition) SetFailState("plugin_test FAIL %s", label);
	g_TestChecks++; PrintToServer("[plugin_test] PASS %s", label);
}
void ResetCase()
{
	g_TestAction = Plugin_Continue; g_TestOverride = -1.0; g_TestBlocked = false;
	g_TestNativeError = false; g_TestClearError = false; g_TestClearReenter = false; g_TestReenter = 0;
	FakelagForgetAllIntent(); MockClearAll(); FakelagForgetAllIntent();
	for (int c = 1; c < 3; c++) { g_TestTeam[c] = c + 1; FakelagResetClientLatencySamples(c); }
}
public void InjectedSet() { CFakeLagNetworkProfile p; FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(100.0, 1), p); }
public void InjectedClear() { FakelagClearNetworkProfile(1, true); }
public void InjectedClearAll() { ClearAllLagCmd(1, 0); }
public Action TestCommand(int args)
{
	g_TestChecks = 0;
	ResetCase();
	CFakeLagNetworkProfile effective;
	g_TestAction = Plugin_Changed; g_TestOverride = 40.0;
	FakeLagCmd(1, 2);
	Check(StrContains(g_TestLastNotice, "40") >= 0 && StrContains(g_TestLastNotice, "100") < 0, "T09 command actual notice");
	g_TestAction = Plugin_Stop; g_TestLagArgument = 0;
	FakeLagCmd(1, 2);
	Check(StrContains(g_TestLastNotice, "confirmed") >= 0 && MockHas(1), "T08 command veto no clear success");
	g_TestAction = Plugin_Changed; g_TestOverride = 25.5;
	FakeLagCmd(1, 2);
	Check(StrContains(g_TestLastNotice, "25.5") >= 0 && MockHas(1), "T09 modified clear reports effective fractional profile");
	g_TestLagArgument = 100; ResetCase();
	Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(100.0, 1), effective) == FakelagProfile_Changed && effective.lagMs == 100.0, "T07 permitted");
	for (int a = view_as<int>(Plugin_Handled); a <= view_as<int>(Plugin_Stop); a++)
	{
		g_TestAction = view_as<Action>(a);
		Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(80.0, 2), effective) == FakelagProfile_Unchanged && g_TestProfiles[1].lagMs == 100.0, "T08 veto normal");
		Check(!FakelagClearNetworkProfile(1, true) && MockHas(1), "T08 veto clear");
	}
	g_TestAction = Plugin_Changed; g_TestOverride = 40.0;
	Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(100.0, 1), effective) == FakelagProfile_Changed && effective.lagMs == 40.0, "T09 modified actual");
	float stored; int loss;
	Check(FakelagTryGetStoredProfile(1, stored, loss) && stored == 40.0, "T09 persisted actual");
	g_TestOverride = -1.0; g_TestAction = Plugin_Continue;
	Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(40.0, 1), effective) == FakelagProfile_Unchanged, "T10 already satisfied");
	g_TestAction = Plugin_Stop;
	Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(40.0, 1), effective) == FakelagProfile_Unchanged, "T10 same with veto indistinguishable");
	Check(!FakelagClearNetworkProfile(1, true), "T11 veto forget");
	g_TestAction = Plugin_Continue; MockClear(1);
	Check(FakelagTryGetStoredProfile(1, stored, loss) && stored == 40.0, "T11 later implicit clear preserves intent");
	FakelagSetDisconnectedState(1, true); g_TestAction = Plugin_Stop;
	int notices = g_TestNotices; FakelagRestoreClientLatencyIfEligible(1);
	Check(FakelagHasDisconnectedState(1) && !MockHas(1) && notices == g_TestNotices, "T12 veto restore marker retained");
	g_TestAction = Plugin_Continue; FakelagRestoreClientLatencyIfEligible(1);
	Check(!FakelagHasDisconnectedState(1) && MockHas(1) && g_TestNotices == notices + 1, "T12 later restore confirmed");
	for (int kind = 1; kind <= 3; kind++)
	{
		ResetCase(); g_TestReenter = kind;
		Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(100.0, 1), effective) == FakelagProfile_Unavailable, "T13 reentrant identity policy clear");
	}
	ResetCase();
	float targetPing; int highest, players, adjusted, cleared;
	g_TestAction = Plugin_Stop;
	Check(FakelagApplyBalanceSilent(targetPing, highest, players, adjusted, cleared) && adjusted == 0 && cleared == 0, "T14 global veto counters");
	int pairs; Check(FakelagApplyPairBalanceSilent(players, pairs, adjusted, cleared) && adjusted == 0 && cleared == 0, "T14 pair veto counters");
	g_TestAction = Plugin_Continue;
	Check(FakelagApplyBalanceSilent(targetPing, highest, players, adjusted, cleared) && adjusted == 1, "T14 global actual counters");
	Check(FakelagApplyBalanceSilent(targetPing, highest, players, adjusted, cleared) && adjusted == 0, "T14 unchanged counters");
	ResetCase(); MockSet(2, 100.0, 1);
	g_TestAction = Plugin_Changed; g_TestOverride = 25.5;
	adjusted = 0; cleared = 0;
	Check(FakelagClearPlayerLatencyExplicit(2, adjusted, cleared) && adjusted == 1 && cleared == 0 && g_TestProfiles[2].lagMs == 25.5, "T14 modified clear counts actual adjustment");
	ResetCase(); g_TestNativeError = true;
	Call_StartFunction(null, InjectedSet); int error = Call_Finish();
	Check(error != SP_ERROR_NONE && !MockHas(1), "T15 set error propagates");
	Call_StartFunction(null, InjectedClear); error = Call_Finish();
	Check(error != SP_ERROR_NONE, "T15 clear error propagates");
	g_TestNativeError = false; FakelagStoreProfileForClient(1, 0.0, 15);
	g_TestTeam[1] = 1; FakelagRestoreClientLatencyIfEligible(1);
	Check(!MockHas(1), "T16 spectator deferred");
	g_TestTeam[1] = 2; FakelagRestoreClientLatencyIfEligible(1);
	Check(MockHas(1) && g_TestProfiles[1].lagMs == 0.0 && g_TestProfiles[1].packetLossPercent == 15, "T16 loss-only team restore");
	FakelagSetDisconnectedState(1, true); MockClear(1); FakelagRestoreClientLatencyIfEligible(1);
	Check(MockHas(1) && !FakelagHasDisconnectedState(1), "T17 loss-only reconnect intent");
	FakelagSnapshotProfilesForModeChange(); MockSetMode(CFakeLagPacketLoss_BernoulliUniform); FakelagQueueModeChangeRestore();
	RequestFrame(TestAfterMode);
	return Plugin_Handled;
}
public void TestAfterMode(any data)
{
	Check(MockHas(1) && g_TestProfiles[1].packetLossPercent == 15, "T18 loss-only mode restore");
	MockSetMode(CFakeLagPacketLoss_GilbertElliott);
	RequestFrame(TestAfterExternalMode);
}
public void TestAfterExternalMode(any data)
{
	Check(!MockHas(1), "T19 external mode stays reset");
	Check(!FakelagProfileIsActive(FakelagBuildNetworkProfile(0.0, 0)) && FakelagProfileIsActive(FakelagBuildNetworkProfile(0.0, 15)) && FakelagProfileIsActive(FakelagBuildNetworkProfile(20.0, 0)), "T20 active predicate");
	ResetCase(); FakelagStoreProfileForClient(1, 0.0, 15); FakelagSetDisconnectedState(1, true);
	FakelagQueueRestoreClientLatency(1); ClearAllLagCmd(1, 0);
	Check(g_PlayerLatencyByAccountId.Size == 0 && g_PlayerPacketLossByAccountId.Size == 0 && g_PlayerDisconnectedByAccountId.Size == 0, "T21 disconnected-only clear");
	// An old callback must not apply even a NEW saved intent with the same userid.
	FakelagStoreProfileForClient(1, 60.0, 2); RequestFrame(TestAfterDeferredClear);
}
public void TestAfterDeferredClear(any data)
{
	Check(!MockHas(1), "T23 stale restore epoch");
	ResetCase(); CFakeLagNetworkProfile p; FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(20.0, 2), p);
	FakelagStoreProfileForClient(2, 0.0, 15); FakelagSetDisconnectedState(2, true);
	FakelagSnapshotProfilesForModeChange(); FakelagQueueModeChangeRestore();
	g_TestClearReenter = true; ClearAllLagCmd(1, 0);
	Check(MockCount() == 0 && g_PlayerLatencyByAccountId.Size == 0, "T22 T27 active disconnected reentrant clear");
	g_TestClearReenter = false; FakelagStoreProfileForClient(1, 60.0, 2);
	RequestFrame(TestAfterSnapshotClear);
}
public void TestAfterSnapshotClear(any data)
{
	Check(!MockHas(1) && !g_ModeChangeRestorePending, "T24 stale mode snapshot");
	// A vote owned elsewhere must remain untouched.
	g_TestVoteInProgress = true;
	int cancellations = g_TestVoteCancels;
	ClearAllLagCmd(1, 0);
	Check(g_TestVoteCancels == cancellations && g_TestVoteInProgress, "T25 foreign vote preserved");
	g_TestVoteToCancel = new DataPack(); g_FakeLagBalanceVote = g_TestVoteToCancel;
	ClearAllLagCmd(1, 0);
	Check(g_TestVoteCancels == cancellations + 1 && g_FakeLagBalanceVote == null && !g_TestVoteInProgress && !MockHas(1), "T25 own vote invalidated before callbacks");
	ClearAllLagCmd(1, 0); ClearAllLagCmd(1, 0);
	Check(g_PlayerLatencyByAccountId.Size == 0 && !g_Runtime.clearingIntent, "T26 empty idempotent");
	CFakeLagNetworkProfile p;
	Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(25.0, 3), p) == FakelagProfile_Changed, "T28 new explicit permitted");
	FakelagSetDisconnectedState(1, true); g_TestClearError = true;
	int notices = g_TestNotices; Call_StartFunction(null, InjectedClearAll); int error = Call_Finish();
	Check(error != SP_ERROR_NONE && g_PlayerLatencyByAccountId.Size == 0 && !g_Runtime.clearingIntent && notices == g_TestNotices, "T29 sync failure discards intent releases guard no success");
	g_TestClearError = false;
	Check(FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(25.0, 3), p) == FakelagProfile_Changed, "T29 recovery explicit after failure");
	g_TestBlocked = true; MockClearAll(); CFakeLag_OnLanPolicyChanged(true);
	Check(!MockHas(1) && g_PlayerLatencyByAccountId.Size == 0 && FakelagApplyNetworkProfile(1, FakelagBuildNetworkProfile(10.0, 1), p) == FakelagProfile_Unavailable, "L01 L02 blocked policy consumer");
	g_TestBlocked = false; CFakeLag_OnLanPolicyChanged(false); FakelagRestoreClientLatencyIfEligible(1);
	Check(!MockHas(1), "L05 unblock no old restoration");
	PrintToServer("[plugin_test] COMPLETE checks=%d", g_TestChecks);
}
public Action SamplingCommand(int args)
{
	Handle previous = g_LatencySamplingTimer;
	ProductionOnMapStart();
	Check(previous == g_LatencySamplingTimer, "T01 idempotent map start");
	g_CvarSampleInterval.FloatValue = g_CvarSampleInterval.FloatValue == 0.1 ? 0.11 : 0.1;
	g_CvarSampleWindow.IntValue = g_CvarSampleWindow.IntValue == 3 ? 4 : 3;
	Check(g_ClientLatencySampleCount[1] == 0, "T04 settings reset samples");
	FakelagResetClientLatencySamples(1); g_TestReads = 0;
	CreateTimer(0.35, CheckSampling);
	return Plugin_Handled;
}
public Action CheckSampling(Handle timer)
{
	Check(g_LatencySamplingTimer != null && g_ClientLatencySampleCount[1] >= 2 && g_ClientLatencySampleCount[1] <= 4 && g_TestReads >= 4 && g_TestReads <= 8, "T01 T02 T03 T04 one sampler active");
	OnClientDisconnect(1);
	Check(g_ClientLatencySampleCount[1] == 0, "T06 session window reset");
	PrintToServer("[plugin_test] SAMPLING COMPLETE reads=%d", g_TestReads);
	return Plugin_Stop;
}
