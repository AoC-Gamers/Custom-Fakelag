stock void FakelagReplyPlayerStatus(int client, int target)
{
	if (!CFakeLag_IsClientSupported(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "PlayerInvalidHumanTarget", target);
		return;
	}

	float averagePingRaw	 = FakelagGetClientAveragePingRawMs(target);
	float averagePingDisplay = FakelagEstimateNetGraphPingForClientMs(target, averagePingRaw);
	float fakeLag			 = CFakeLag_GetPlayerLatency(target);
	bool  isLagged			 = CFakeLag_HasPlayerLatency(target);

	if (!isLagged)
	{
		CReplyToCommand(client, "%t %t", "Tag", "StatusDisabled", target, averagePingDisplay, averagePingRaw);
		return;
	}

	CReplyToCommand(client, "%t %t", "Tag", "StatusEnabled", target, averagePingDisplay, averagePingRaw, fakeLag);
}

stock void FakelagReplyPlayerComparison(int client, int firstTarget, int secondTarget)
{
	if (!IsHumanInGame(firstTarget))
	{
		CReplyToCommand(client, "%t %t", "Tag", "PlayerInvalidHumanTarget", firstTarget);
		return;
	}

	if (!IsHumanInGame(secondTarget))
	{
		CReplyToCommand(client, "%t %t", "Tag", "PlayerInvalidHumanTarget", secondTarget);
		return;
	}

	float firstRaw	= FakelagGetClientAveragePingRawMs(firstTarget);
	float secondRaw = FakelagGetClientAveragePingRawMs(secondTarget);
	if (firstRaw < 0.0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "PlayerNoPingData", firstTarget);
		return;
	}

	if (secondRaw < 0.0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "PlayerNoPingData", secondTarget);
		return;
	}

	float firstDisplay	= FakelagEstimateNetGraphPingForClientMs(firstTarget, firstRaw);
	float secondDisplay = FakelagEstimateNetGraphPingForClientMs(secondTarget, secondRaw);
	float difference	= FloatAbs(firstRaw - secondRaw);

	CReplyToCommand(client, "%t %t", "Tag", "CompareResult", firstTarget, firstDisplay, secondTarget, secondDisplay, difference);

	if (difference <= 0.0)
	{
		return;
	}

	int higherTarget = firstRaw >= secondRaw ? firstTarget : secondTarget;
	CReplyToCommand(client, "%t %t", "Tag", "CompareHigher", higherTarget, difference);
}

stock int FakelagFindComparisonTarget(int client, const char[] pattern)
{
	int	 targets[MAXPLAYERS];
	char targetName[MAX_TARGET_LENGTH];
	bool targetNameIsMl;
	int	 targetCount = ProcessTargetString(
		 pattern,
		 client,
		 targets,
		 sizeof(targets),
		 COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY,
		 targetName,
		 sizeof(targetName),
		 targetNameIsMl);

	if (targetCount != 1)
	{
		ReplyToTargetError(client, targetCount);
		return -1;
	}

	return targets[0];
}

stock bool FakelagIsSupportedBalanceTeam(L4DTeam team)
{
	return team == L4DTeam_Survivor || team == L4DTeam_Infected;
}

stock bool IsHumanInGame(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

stock bool FakelagIsBalanceAudienceClient(int client)
{
	if (!IsHumanInGame(client))
	{
		return false;
	}

	return L4D_GetClientTeam(client) >= L4DTeam_Survivor;
}

stock bool FakelagCanApplyLatencyToClient(int client)
{
	if (!IsHumanInGame(client) || !CFakeLag_IsClientSupported(client))
	{
		return false;
	}

	return FakelagIsSupportedBalanceTeam(L4D_GetClientTeam(client));
}

stock bool FakelagIsBalanceCandidate(int client, L4DTeam team)
{
	if (!IsHumanInGame(client))
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

	CReplyToCommand(client, "%t %t", "Tag", "ClientOnlyCommand");
	return false;
}
