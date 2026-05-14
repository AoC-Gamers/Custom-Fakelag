#include <custom_fakelag>
#include <console>

public Plugin myinfo =
{
	name = "Per-Player Fakelag",
	author = "ProdigySim",
	description = "Set a custom fake latency per player",
	version = "1.0",
	url = "https://github.com/AoC-Gamers/L4D2_Custom_Fakelag.git"
};

public OnPluginStart()
{
	RegAdminCmd("sm_fakelag", FakeLagCmd, view_as<int>(Admin_Config), "Set fake lag for a player");
	RegAdminCmd("sm_printlag", PrintLagCmd, view_as<int>(Admin_Config), "Print current fake lag");
}

public Action FakeLagCmd(int client, int args)
{
	if (args < 2) {
		ReplyToCommand(client, "Usage: sm_fakelag <target> <milliseconds>");
		return Plugin_Handled;
	}

	char targetStr[256];
	GetCmdArg(1, targetStr, sizeof(targetStr));

	int target = FindTarget(client, targetStr, true);
	if (target < 0) {
		ReplyToCommand(client, "Unable to find target \"%s\"", targetStr);
		return Plugin_Handled;
	}

	if (!IsClientInGame(target)) {
		ReplyToCommand(client, "Player %N is not in game yet.", target);
		return Plugin_Handled;
	}

	if (IsFakeClient(target)) {
		ReplyToCommand(client, "Player %N is a fake client and can't be lagged.", target);
		return Plugin_Handled;
	}

	int lagAmount = GetCmdArgInt(2);
	CFakeLag_SetPlayerLatency(target, float(lagAmount));
	ShowActivity2(client, "[SM] ", "Set fake lag of %dms on player %N", lagAmount, target);
	return Plugin_Handled;
}

public Action PrintLagCmd(int client, int args)
{
	for(int i = 1; i < MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			ReplyToCommand(client, "%N: %fms", i, CFakeLag_GetPlayerLatency(i));
		}
	}

	return Plugin_Handled;
}

stock int GetCmdArgInt(int argnum)
{
	char str[12];
	GetCmdArg(argnum, str, sizeof(str));

	return StringToInt(str);
}
