// Opt-in controls for real-client report acceptance on a private test server.
// Not packaged. Remove the consumer and reset profiles after testing.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <custom_fakelag>
#include <player_fakelag>

int g_TargetUserId;
Action g_Action = Plugin_Continue;
float g_Override;

public void OnPluginStart()
{
	RegServerCmd("cf_balance_control", Control, "<userid> <allow|handled|stop|modify> [ms]");
	RegServerCmd("cf_balance_profile", Profile, "<userid> <ms> <loss-percent>");
	RegServerCmd("cf_balance_snapshot", Snapshot, "Query human profiles without modifying them");
}
public void OnMapEnd() { g_TargetUserId = 0; }
public void OnClientDisconnect(int client) { if (GetClientUserId(client) == g_TargetUserId) g_TargetUserId = 0; }

bool ReadNumber(int argument, float &number)
{
	char text[32]; GetCmdArg(argument, text, sizeof(text));
	return StringToFloatEx(text, number) == strlen(text) && text[0] != '\0' && number >= 0.0 && number <= 10000.0;
}
int ReadTarget()
{
	char text[32]; GetCmdArg(1, text, sizeof(text));
	int userId;
	if (StringToIntEx(text, userId) != strlen(text) || userId <= 0) return 0;
	int client = GetClientOfUserId(userId);
	return client > 0 && CFakeLag_IsClientSupported(client) ? client : 0;
}
public Action Control(int args)
{
	int client = ReadTarget();
	char mode[16]; GetCmdArg(2, mode, sizeof(mode));
	if (args < 2 || client <= 0) { PrintToServer("Usage: cf_balance_control <human-userid> <allow|handled|stop|modify> [ms]"); return Plugin_Handled; }
	Action action;
	if (StrEqual(mode, "allow")) action = Plugin_Continue;
	else if (StrEqual(mode, "handled")) action = Plugin_Handled;
	else if (StrEqual(mode, "stop")) action = Plugin_Stop;
	else if (StrEqual(mode, "modify") && args == 3 && ReadNumber(3, g_Override)) action = Plugin_Changed;
	else { PrintToServer("Invalid control mode/value"); return Plugin_Handled; }
	g_TargetUserId = GetClientUserId(client);
	g_Action = action;
	PrintToServer("[balance_acceptance] control userid=%d action=%d override=%.1f", g_TargetUserId, action, g_Override);
	return Plugin_Handled;
}
public Action Profile(int args)
{
	int client = ReadTarget();
	float lag, loss;
	if (args != 3 || client <= 0 || !ReadNumber(2, lag) || !ReadNumber(3, loss) || loss > 100.0 || loss != float(RoundToFloor(loss)))
	{
		PrintToServer("Usage: cf_balance_profile <human-userid> <0..10000-ms> <0..100-integer-loss>");
		return Plugin_Handled;
	}
	CFakeLag_SetPlayerProfile(client, lag, RoundToFloor(loss)); // Native errors propagate.
	Snapshot(0);
	return Plugin_Handled;
}
public Action Snapshot(int args)
{
#pragma unused args
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!CFakeLag_IsClientSupported(client)) continue;
		CFakeLagNetworkProfile profile;
		CFakeLag_GetPlayerProfile(client, profile);
		PrintToServer("[balance_acceptance] userid=%d effective=%.1f/%d", GetClientUserId(client), profile.lagMs, profile.packetLossPercent);
	}
	return Plugin_Handled;
}
public Action PlayerFakelag_OnSetPlayerLatency(int client, float oldLag, float &newLag, CFakeLagChangeReason reason)
{
	if (GetClientUserId(client) != g_TargetUserId) return Plugin_Continue;
	PrintToServer("[balance_acceptance] userid=%d old=%.1f requested=%.1f reason=%d action=%d", g_TargetUserId, oldLag, newLag, reason, g_Action);
	if (g_Action == Plugin_Changed) newLag = g_Override;
	return g_Action;
}
