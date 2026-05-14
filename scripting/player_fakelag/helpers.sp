stock void FakelagReplyPlayerStatus(int client, int target)
{
	if (!CFakeLag_IsClientSupported(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPlayerInvalidHumanTarget", target);
		return;
	}

	float averagePingRaw = FakelagGetClientAveragePingRawMs(target);
	float averagePingDisplay = FakelagEstimateNetGraphPingForClientMs(target, averagePingRaw);
	float fakeLag = CFakeLag_GetPlayerLatency(target);
	bool isLagged = CFakeLag_HasPlayerLatency(target);

	if (!isLagged)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagStatusDisabled", target, averagePingDisplay, averagePingRaw);
		return;
	}

	CReplyToCommand(client, "%t %t", "Tag", "FakelagStatusEnabled", target, averagePingDisplay, averagePingRaw, fakeLag);
}

stock bool FakelagIsSupportedBalanceTeam(L4DTeam team)
{
	return team == L4DTeam_Survivor || team == L4DTeam_Infected;
}

stock bool FakelagIsBalanceCandidate(int client, L4DTeam team)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
	{
		return false;
	}

	return L4D_GetClientTeam(client) == team;
}

stock void FakelagBuildArgRangeString(int firstArg, int lastArg, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	char arg[256];
	for (int argIndex = firstArg; argIndex <= lastArg; argIndex++)
	{
		GetCmdArg(argIndex, arg, sizeof(arg));

		if (buffer[0] != '\0')
		{
			StrCat(buffer, maxlen, " ");
		}

		StrCat(buffer, maxlen, arg);
	}
}

stock bool FakelagCommandRequiresClient(int client)
{
	if (client != 0)
	{
		return true;
	}

	CReplyToCommand(client, "%t %t", "Tag", "FakelagClientOnlyCommand");
	return false;
}