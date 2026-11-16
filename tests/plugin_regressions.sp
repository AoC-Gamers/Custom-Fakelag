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
#undef REQUIRE_PLUGIN
#include <player_fakelag>

stock FeatureStatus RealFeatureStatus(FeatureType type, const char[] name) { return GetFeatureStatus(type, name); }
#define GetFeatureStatus MockFeatureStatus
#define CancelBuiltinVote MockCancelVote
#define CreateBuiltinVote MockCreateVote
#define DisplayBuiltinVoteToAllNonSpectators MockDisplayAll
#define SetBuiltinVoteArgument MockVoteArgument
#define SetBuiltinVoteInitiator MockVoteInitiator
#define SetBuiltinVoteResultCallback MockVoteCallback
#define IsNewBuiltinVoteAllowed MockNewVoteAllowed
#define DisplayBuiltinVotePass MockVotePass
#define IsBuiltinVoteInProgress MockVoteInProgress
#define FindTarget MockFindTarget
#define GetCmdArg MockCmdArg
#define CheckCommandAccess MockCommandAccess
#define GetClientName MockName
#define ConsolePanel_RenderToClient TestRender
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
int g_TestSession[4] = {0, 101, 102, 103};
int g_TestClientCount = 2;
float g_TestBasePing[4] = {0.0, 30.0, 80.0, 10.0};
int g_TestForwardClient;
ConsolePanel g_TestLastPanel;
int g_TestRenders;
int g_TestSetCalls;
int g_TestClearCalls;
int g_TestForwardCalls;
int g_TestNameStyle;
int g_TestVotePasses;
char g_TestModeArgument[16];
char g_TestTableCase[64];
int g_TestNoticeTarget[MAXPLAYERS + 1];
char g_TestNoticeText[MAXPLAYERS + 1][1024];
int g_TestTeam[4] = {0, 2, 3, 2};
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

stock bool MockName(int client, char[] out, int len)
{
	if (g_TestNameStyle == 1) strcopy(out, len, "Ána|\n");
	else if (g_TestNameStyle == 2) strcopy(out, len, "VeryLongPlayerNameForColumns");
	else Format(out, len, "Client%d", client);
	return MockInGame(client);
}
stock void TestRender(ConsolePanel panel, int client)
{
	if (client == 0)
	{
		g_TestLastPanel = panel;
		g_TestRenders++;
		char text[256];
		ConsoleTable_BuildHeaderRow(panel, text, sizeof(text));
		PrintToServer("[table_test] HEADER %s %s", g_TestTableCase, text);
		for (int row = 0; row < panel.table.rowCount; row++)
		{
			ConsoleTable_BuildRow(panel, row, text, sizeof(text));
			PrintToServer("[table_test] ROW %s %s", g_TestTableCase, text);
		}
	}
}
stock int MockFindTarget(int admin, const char[] name, bool noBots = false, bool immunity = true) {
#pragma unused admin
#pragma unused name
#pragma unused noBots
#pragma unused immunity
	return 1;
}
stock int MockCmdArg(int number, char[] out, int len) { if (number == 1 && g_TestModeArgument[0] != '\0') strcopy(out, len, g_TestModeArgument); else if (number == 2) IntToString(g_TestLagArgument, out, len); else strcopy(out, len, "test"); return strlen(out); }
stock bool MockCommandAccess(int c, const char[] command, int flags, bool overrideOnly = false) { return c > 0 && command[0] != '\0' && (flags > 0 || overrideOnly); }
stock FeatureStatus MockFeatureStatus(FeatureType type, const char[] name)
{
	if (StrEqual(name, "CancelBuiltinVote") || StrEqual(name, "IsBuiltinVoteInProgress") || StrEqual(name, "CreateBuiltinVote") || StrEqual(name, "DisplayBuiltinVote")) return FeatureStatus_Available;
	return RealFeatureStatus(type, name);
}
stock Handle MockCreateVote(BuiltinVoteActionHandler handler, BuiltinVoteType type, BuiltinVoteAction actions)
{
#pragma unused handler
#pragma unused type
#pragma unused actions
	return new DataPack();
}
stock bool MockDisplayAll(Handle vote, int duration) { return vote != null && duration > 0; }
stock void MockVoteArgument(Handle vote, const char[] argument) {
#pragma unused vote
#pragma unused argument
}
stock void MockVoteInitiator(Handle vote, int initiator) {
#pragma unused vote
#pragma unused initiator
}
stock void MockVoteCallback(Handle vote, BuiltinVoteHandler handler) {
#pragma unused vote
#pragma unused handler
}
stock bool MockNewVoteAllowed() { return true; }
stock void MockVotePass(Handle vote, const char[] text) { if (vote != null && text[0] != '\0') g_TestVotePasses++; }
stock bool MockVoteInProgress() { return g_TestVoteInProgress; }
stock void MockCancelVote()
{
	g_TestVoteCancels++; g_TestVoteInProgress = false;
	int clients[1][2]; int items[1][2];
	FakeLagBalanceVoteResultHandler(g_TestVoteToCancel, 0, 0, clients, 0, items);
	FakeLagBalanceVoteHandler(g_TestVoteToCancel, BuiltinVoteAction_End, 0, 0);
	g_TestVoteToCancel = null;
}
stock int MockUserId(int client) { return client > 0 && client <= g_TestClientCount ? g_TestSession[client] : 0; }
stock int MockClient(int userId) { for (int c = 1; c <= g_TestClientCount; c++) if (g_TestSession[c] == userId && userId > 0) return c; return 0; }
stock bool MockInGame(int client) { return MockUserId(client) > 0; }
stock bool MockFake(int client) { return !MockInGame(client); }
stock int MockAccount(int client, bool validate = true) {
#pragma unused validate
	return client + 1000;
}
stock L4DTeam MockL4DTeam(int client) { return view_as<L4DTeam>(MockTeam(client)); }
stock int MockTeam(int client) { return client > 0 && client <= g_TestClientCount ? g_TestTeam[client] : 0; }
stock float MockPing(int client, NetFlow flow) {
#pragma unused flow
	g_TestReads++;
	return g_TestBasePing[client] / 1000.0 + g_TestProfiles[client].lagMs / 1000.0;
}
stock bool MockInfo(int client, const char[] key, char[] out, int len) { strcopy(out, len, "60"); return client > 0 && key[0] != '\0'; }
stock bool MockBlocked() { return g_TestBlocked; }
stock bool MockHas(int c) { return FakelagProfileIsActive(g_TestProfiles[c]); }
stock bool MockGet(int c, CFakeLagNetworkProfile out) { out = g_TestProfiles[c]; return MockHas(c); }
stock int MockCount() { int n; for (int c = 1; c <= g_TestClientCount; c++) if (MockHas(c)) n++; return n; }
stock CFakeLagPacketLossMode MockMode() { return g_TestMode; }
stock void MockSetMode(CFakeLagPacketLossMode mode) { CFakeLagPacketLossMode old = g_TestMode; MockClearAll(); g_TestMode = mode; CFakeLag_OnPacketLossModeChanged(old, mode); }
stock void TestPrint(int client, const char[] format, any ...)
{
	char text[1024]; VFormat(text, sizeof(text), format, 3);
	strcopy(g_TestLastNotice, sizeof(g_TestLastNotice), text);
	if (client > 0 && client <= MaxClients)
	{
		g_TestNoticeTarget[client]++;
		strcopy(g_TestNoticeText[client], 1024, text);
	}
	g_TestNotices++; PrintToServer("[plugin_test] notice target=%d %s", client, text);
}
stock void TestPrintEx(int client, int author, const char[] format, any ...)
{
	char text[1024]; VFormat(text, sizeof(text), format, 4);
	strcopy(g_TestLastNotice, sizeof(g_TestLastNotice), text);
	if (client > 0 && client <= MaxClients)
	{
		g_TestNoticeTarget[client]++;
		strcopy(g_TestNoticeText[client], 1024, text);
	}
	g_TestNotices++; PrintToServer("[plugin_test] notice target=%d author=%d %s", client, author, text);
}
stock void MockSet(int c, float lag, int loss)
{
	g_TestSetCalls++;
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
	g_TestClearCalls++;
	int userId = MockUserId(c);
	int epoch = g_Runtime.intentEpoch;
	if (g_TestNativeError) ThrowError("plugin_test EXPECTED injected clear failure");
	float lag;
	Action action = CFakeLag_OnSetPlayerLatency(c, g_TestProfiles[c].lagMs, lag, CFakeLagChange_Clear);
	if (action >= Plugin_Handled || userId != MockUserId(c) || epoch != g_Runtime.intentEpoch) return;
	CFakeLagNetworkProfile old; old = g_TestProfiles[c];
	g_TestProfiles[c] = FakelagBuildNetworkProfile(lag, 0);
	if (!FakelagProfilesEqual(old, g_TestProfiles[c])) CFakeLag_OnPlayerProfileChanged(c, old.lagMs, old.packetLossPercent, lag, 0, CFakeLagChange_Clear);
}
stock void MockClearAll()
{
	for (int c = 1; c <= g_TestClientCount; c++)
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
public Action PlayerFakelag_OnSetPlayerLatency(int client, float oldLag, float &lag, CFakeLagChangeReason reason)
{
	g_TestForwardCalls++;
	if (g_TestForwardClient != 0 && client != g_TestForwardClient) return Plugin_Continue;
	if (g_TestReenter == 1) { g_TestSession[client] += 1000; }
	if (g_TestReenter == 2) { g_TestBlocked = true; MockClearAll(); CFakeLag_OnLanPolicyChanged(true); }
	if (g_TestReenter == 3) { FakelagForgetAllIntent(); MockClearAll(); }
	if (g_TestOverride >= 0.0) lag = g_TestOverride;
	return g_TestAction;
}

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int maxlen) { MarkNativeAsOptional("CancelBuiltinVote"); return ProductionAskPluginLoad2(self, late, error, maxlen); }
public void OnPluginStart()
{
	ProductionOnPluginStart();
	RegServerCmd("cf_plugin_test", TestCommand);
	RegServerCmd("cf_plugin_sampling", SamplingCommand);
	RegServerCmd("cf_plugin_tables", TableCommand);
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
	g_TestClientCount = 3; g_TestForwardClient = 0;
	g_TestBasePing[1] = 30.0; g_TestBasePing[2] = 80.0;
	g_TestAction = Plugin_Continue; g_TestOverride = -1.0; g_TestBlocked = false;
	g_TestNativeError = false; g_TestClearError = false; g_TestClearReenter = false; g_TestReenter = 0;
	FakelagForgetAllIntent(); MockClearAll(); FakelagForgetAllIntent();
	for (int c = 1; c <= g_TestClientCount; c++)
	{
		g_TestTeam[c] = c == 2 ? 3 : 2;
		FakelagResetClientLatencySamples(c);
	}
	g_TestClientCount = 2;
	g_TestSetCalls = g_TestClearCalls = g_TestForwardCalls = g_TestRenders = 0;
	g_TestNameStyle = 0;
	g_TestModeArgument[0] = '\0';
	for (int c = 0; c <= MaxClients; c++) { g_TestNoticeTarget[c] = 0; g_TestNoticeText[c][0] = '\0'; }
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

void TableBegin(const char[] name)
{
	ResetCase();
	strcopy(g_TestTableCase, sizeof(g_TestTableCase), name);
	g_TestReads = 0;
	g_TestNotices = 0;
	g_CvarLossBaseCeilingMs.FloatValue = 60.0;
	g_CvarLossBaseSpanMs.FloatValue = 40.0;
	g_CvarLossTargetFloorMs.FloatValue = 35.0;
	g_CvarLossTargetSpanMs.FloatValue = 40.0;
	g_CvarLossAddedFloorMs.FloatValue = 20.0;
	g_CvarLossAddedSpanMs.FloatValue = 35.0;
	g_CvarLossMaxPercent.IntValue = 3;
	g_TestBasePing[2] = 130.0; // Controlled proposal: client1 receives 100 ms / 3%.
}
void TableRun(bool pairs, bool preview = false)
{
	strcopy(g_TestModeArgument, sizeof(g_TestModeArgument), pairs ? "pairs" : "global");
	if (preview) PreviewBalanceLagCmd(0, 1);
	else BalanceLagCmd(0, 1);
}
void TableRow(int row, float lag, int loss, const char[] expected)
{
	bool spanish = GetServerLanguage() == GetLanguageByCode("es");
	char action[32]; strcopy(action, sizeof(action), expected);
	if (spanish)
	{
		if (StrEqual(expected, "adjusted")) strcopy(action, sizeof(action), "ajustado");
		if (StrEqual(expected, "cleared")) strcopy(action, sizeof(action), "limpiado");
		if (StrEqual(expected, "no change confirmed")) strcopy(action, sizeof(action), "sin cambio conf.");
		if (StrEqual(expected, "propose profile")) strcopy(action, sizeof(action), "proponer perfil");
		if (StrEqual(expected, "propose empty")) strcopy(action, sizeof(action), "proponer cero");
	}
	int columns = g_TestLastPanel.table.columnCount;
	Check(row < g_TestLastPanel.table.rowCount && (columns == 6 || columns == 7), g_TestTableCase);
	Check(StrEqual(g_TestLastPanel.table.rows[row].cells[columns - 3].stringValue, action), g_TestTableCase);
	Check(g_TestLastPanel.table.rows[row].cells[columns - 2].type == ConsoleTableCellType_Float
		&& FloatAbs(g_TestLastPanel.table.rows[row].cells[columns - 2].floatValue - lag) < 0.001
		&& g_TestLastPanel.table.rows[row].cells[columns - 1].type == ConsoleTableCellType_Int
		&& g_TestLastPanel.table.rows[row].cells[columns - 1].intValue == loss, g_TestTableCase);
	Check(ConsoleTable_ValidateWidth(g_TestLastPanel), "FL02-R16 actual renderer accepts width");
}
void TableCounts(int adjusted, int cleared, int unchanged, int unavailable)
{
	char expected[128];
	if (GetServerLanguage() == GetLanguageByCode("es")) Format(expected, sizeof(expected), "Confirmados: %d ajustes, %d limpiezas.", adjusted, cleared);
	else Format(expected, sizeof(expected), "Confirmed: %d adjustments, %d clears.", adjusted, cleared);
	Check(StrEqual(g_TestLastPanel.footerLines[2].text, expected), g_TestTableCase);
	if (GetServerLanguage() == GetLanguageByCode("es")) Format(expected, sizeof(expected), "Sin cambio confirmado: %d; no disponibles: %d.", unchanged, unavailable);
	else Format(expected, sizeof(expected), "No change confirmed: %d; unavailable: %d.", unchanged, unavailable);
	Check(StrEqual(g_TestLastPanel.footerLines[3].text, expected), g_TestTableCase);
}
public void InjectedGlobalReport() { TableRun(false); }
public void InjectedPairReport() { TableRun(true); }
public Action TableCommand(int args)
{
	int initial = g_TestChecks;
	TableBegin("FL02-R01 global permitted"); TableRun(false);
	TableRow(0, 100.0, 3, "adjusted"); TableRow(1, 0.0, 0, "no change confirmed"); TableCounts(1, 0, 1, 0);
	Check(g_TestProfiles[1].lagMs > 99.9 && g_TestProfiles[1].packetLossPercent == 3
		&& StrContains(g_TestNoticeText[1], "100.0") >= 0 && StrContains(g_TestNoticeText[1], "3%") >= 0, "FL02-R01 profile notice and cells agree");
	Check(g_TestSetCalls + g_TestClearCalls == 2 && g_TestReads == 2, "FL02-R01 single selection and execution");

	TableBegin("FL02-R02 pairs permitted"); TableRun(true);
	TableRow(0, 100.0, 3, "adjusted"); TableRow(1, 0.0, 0, "no change confirmed"); TableCounts(1, 0, 1, 0);
	char partner[32]; Format(partner, sizeof(partner), "#%d", MockUserId(2));
	Check(StrContains(g_TestLastPanel.table.rows[0].cells[1].stringValue, partner) >= 0
		&& g_TestSetCalls + g_TestClearCalls == 2 && g_TestReads == 2, "FL02-R02 same pair one sampling pass");

	for (int action = view_as<int>(Plugin_Handled); action <= view_as<int>(Plugin_Stop); action++)
	{
		TableBegin("FL02-R03 pair veto");
		MockSet(1, 25.0, 15); g_TestAction = view_as<Action>(action);
		int notices = g_TestNotices; TableRun(true);
		TableRow(0, 25.0, 15, "no change confirmed"); TableCounts(0, 0, 2, 0);
		Check(g_TestNotices == notices && g_TestProfiles[1].packetLossPercent == 15, "FL02-R03 veto has no success notice");
	}

	for (int pairs = 0; pairs <= 1; pairs++)
	{
		TableBegin("FL02-R04 R05 latency modified loss retained");
		g_TestForwardClient = 1; g_TestAction = Plugin_Changed; g_TestOverride = 40.0;
		TableRun(view_as<bool>(pairs));
		TableRow(0, 40.0, 3, "adjusted"); TableCounts(1, 0, 1, 0);
		Check(g_TestProfiles[1].lagMs == 40.0 && g_TestProfiles[1].packetLossPercent == 3
			&& StrContains(g_TestNoticeText[1], "40.0") >= 0 && StrContains(g_TestNoticeText[1], "3%") >= 0, "FL02-R05 loss equals query and notice");
	}

	TableBegin("FL02-R06 identical active profile"); MockSet(1, 100.0, 3); TableRun(false);
	TableRow(0, 100.0, 3, "no change confirmed"); TableCounts(0, 0, 2, 0);
	g_TestAction = Plugin_Stop; TableRun(false);
	TableRow(0, 100.0, 3, "no change confirmed"); TableCounts(0, 0, 2, 0);

	TableBegin("FL02-R07 unpaired veto"); g_TestClientCount = 3; MockSet(3, 25.0, 15); g_TestAction = Plugin_Stop;
	TableRun(true); TableRow(2, 25.0, 15, "no change confirmed"); TableCounts(0, 0, 3, 0);
	Check(StrEqual(g_TestLastPanel.table.rows[2].cells[1].stringValue, "-") && g_TestProfiles[3].lagMs == 25.0, "FL02-R07 unpaired preserved");

	TableBegin("FL02-R08 confirmed paired and unpaired clears"); g_TestClientCount = 3;
	MockSet(2, 25.0, 15); MockSet(3, 25.0, 15);
	TableRun(true); TableRow(1, 0.0, 0, "cleared"); TableRow(2, 0.0, 0, "cleared"); TableCounts(1, 2, 0, 0);
	Check(!MockHas(2) && !MockHas(3), "FL02-R08 clears match queried profiles");

	TableBegin("FL02-R09 modified unpaired clear"); g_TestClientCount = 3;
	MockSet(3, 90.0, 15); g_TestForwardClient = 3; g_TestAction = Plugin_Changed; g_TestOverride = 25.5;
	TableRun(true); TableRow(2, 25.5, 0, "adjusted"); TableCounts(2, 0, 1, 0);
	Check(StrContains(g_TestNoticeText[3], "25.5") >= 0 && g_TestProfiles[3].lagMs == 25.5, "FL02-R09 fractional clear adjustment notice");

	TableBegin("FL02-R09 modified paired clear"); MockSet(2, 90.0, 15);
	g_TestForwardClient = 2; g_TestAction = Plugin_Changed; g_TestOverride = 25.5;
	TableRun(true); TableRow(1, 25.5, 0, "adjusted"); TableCounts(2, 0, 0, 0);
	Check(StrContains(g_TestNoticeText[2], "25.5") >= 0 && g_TestProfiles[2].lagMs == 25.5, "FL02-R09 paired clear remains adjustment");

	TableBegin("FL02-R10 loss-only retained and vetoed"); g_TestClientCount = 3;
	MockSet(3, 0.0, 15); g_TestAction = Plugin_Stop;
	TableRun(true); TableRow(2, 0.0, 15, "no change confirmed"); TableCounts(0, 0, 3, 0);
	g_TestAction = Plugin_Continue; TableRun(true); TableRow(2, 0.0, 0, "cleared"); TableCounts(1, 1, 1, 0);

	TableBegin("FL02-R10 forward yields loss-only profile");
	g_TestForwardClient = 1; g_TestAction = Plugin_Changed; g_TestOverride = 0.0;
	TableRun(true); TableRow(0, 0.0, 3, "adjusted"); TableCounts(1, 0, 1, 0);

	for (int pairs = 0; pairs <= 1; pairs++)
	{
		TableBegin("FL02-R11 preview proposals only"); g_TestClientCount = 3;
		MockSet(1, 25.0, 15); MockSet(3, 0.0, 15);
		int setters = g_TestSetCalls, clears = g_TestClearCalls, forwards = g_TestForwardCalls;
		g_TestAction = Plugin_Stop; TableRun(view_as<bool>(pairs), true);
		TableRow(0, 100.0, 3, "propose profile"); TableRow(1, 0.0, 0, "propose empty");
		TableRow(2, pairs ? 0.0 : 120.0, pairs ? 0 : 3, pairs ? "propose empty" : "propose profile");
		float stored; int loss;
		Check(setters == g_TestSetCalls && clears == g_TestClearCalls && forwards == g_TestForwardCalls
			&& FakelagTryGetStoredProfile(1, stored, loss) && stored == 25.0 && loss == 15 && g_TestProfiles[1].lagMs == 25.0, "FL02-R11 no mutation persistence or forward");
		Check(StrContains(g_TestLastPanel.headerLines[1].text, GetServerLanguage() == GetLanguageByCode("es") ? "PREVIA" : "PREVIEW") >= 0, "FL02-R11 preview label");
	}

	for (int pairs = 0; pairs <= 1; pairs++)
	{
		TableBegin("FL02-R12 replaced session unavailable");
		int oldId = MockUserId(1); g_TestForwardClient = 1; g_TestReenter = 1; TableRun(view_as<bool>(pairs));
		int columns = g_TestLastPanel.table.columnCount;
		Format(partner, sizeof(partner), "#%d", oldId);
		Check(StrContains(g_TestLastPanel.table.rows[0].cells[0].stringValue, partner) >= 0
			&& StrEqual(g_TestLastPanel.table.rows[0].cells[columns - 2].stringValue, "-")
			&& g_TestLastPanel.table.rows[0].cells[columns - 2].type == ConsoleTableCellType_String
			&& g_TestNoticeTarget[1] == 0 && !MockHas(1), "FL02-R12 no identity inheritance or zero-filled success");
		Check(StrEqual(g_TestLastPanel.table.rows[0].cells[columns - 3].stringValue, GetServerLanguage() == GetLanguageByCode("es") ? "no disponible" : "unavailable"), "FL02-R12 unavailable action");
		TableCounts(0, 0, 0, 2);
		Check(g_TestSetCalls + g_TestClearCalls == (pairs ? 2 : 1), "FL02-R12 stop old operation after unavailable observation");
	}

	for (int kind = 2; kind <= 3; kind++)
	{
		for (int pairs = 0; pairs <= 1; pairs++)
		{
			TableBegin("FL02-R13 interrupted policy intent");
			if (pairs) MockSet(2, 25.0, 15);
			g_TestForwardClient = pairs ? 1 : 2; g_TestReenter = kind; TableRun(view_as<bool>(pairs));
			Check(g_TestRenders == 0 && g_TestNoticeTarget[1] == 0 && g_TestNoticeTarget[2] == 0 && !MockHas(1) && !MockHas(2)
				&& g_PlayerLatencyByAccountId.Size == 0, "FL02-R13 no stale table earlier success or persisted intent");
		}
	}

	for (int pairs = 0; pairs <= 1; pairs++)
	{
		TableBegin("FL02-R14 native error"); g_TestNativeError = true;
		Call_StartFunction(null, pairs ? InjectedPairReport : InjectedGlobalReport); int error = Call_Finish();
		Check(error != SP_ERROR_NONE && g_TestRenders == 0 && g_TestNoticeTarget[1] == 0, "FL02-R14 error propagates no planned success panel");
		g_TestNativeError = false;
	}

	TableBegin("FL02-R15 registered silent native");
	float target; int highest, count, adjusted, cleared;
	Check(PlayerFakelag_ApplyBalance(target, highest, count, adjusted, cleared) && adjusted == 1 && cleared == 0
		&& count == 2 && g_TestSetCalls + g_TestClearCalls == 2 && g_TestRenders == 0 && g_TestNotices == 0, "FL02-R15 actual registered native shares pipeline");

	int mutations = g_TestSetCalls + g_TestClearCalls;
	Check(PlayerFakelag_PreviewBalance(target, highest, count) && count == 2 && mutations == g_TestSetCalls + g_TestClearCalls && g_TestRenders == 0, "FL02-R15 registered preview native is read only");
	for (int pairs = 0; pairs <= 1; pairs++)
	{
		TableBegin("FL02-R15 vote result callback");
		Check(PlayerFakelag_StartBalanceVote(0), "FL02-R15 vote starts through registered native");
		g_BalanceVoteMode = pairs;
		int clients[1][2], items[1][2]; items[0][BUILTINVOTEINFO_ITEM_INDEX] = BUILTINVOTES_VOTE_YES;
		Handle vote = g_FakeLagBalanceVote;
		FakeLagBalanceVoteResultHandler(vote, 1, 1, clients, 1, items);
		TableRow(0, 100.0, 3, "adjusted"); TableCounts(1, 0, 1, 0);
		Check(g_TestSetCalls + g_TestClearCalls == 2, "FL02-R15 vote applies once");
		FakeLagBalanceVoteHandler(vote, BuiltinVoteAction_End, 0, 0);
	}

	TableBegin("FL02-R16 names and actual row formatting"); g_TestNameStyle = 1; TableRun(true);
	Check(g_TestLastPanel.table.rows[0].cells[0].stringValue[0] == '#'
		&& StrContains(g_TestLastPanel.footerLines[4].text, "Ána/") >= 0, "FL02-R16 captured sanitized UTF8 legend");
	TableBegin("FL02-R16 long names"); g_TestNameStyle = 2; g_TestSession[1] = 1234567890; TableRun(false);
	Check(strlen(g_TestLastPanel.table.rows[0].cells[0].stringValue) <= 17, "FL02-R16 bounded name includes session id");

	ResetCase();
	PrintToServer("[table_test] COMPLETE checks=%d language=%d", g_TestChecks - initial, GetServerLanguage());
	return Plugin_Handled;
}
