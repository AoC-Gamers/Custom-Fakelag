stock int FakelagCollectBalanceCandidates(int clients[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], float &highestPing, int &highestClient)
{
	int count = 0;
	highestPing = -1.0;
	highestClient = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client))
		{
			continue;
		}

		L4DTeam team = L4D_GetClientTeam(client);
		if (!FakelagIsSupportedBalanceTeam(team))
		{
			continue;
		}

		float averagePing = FakelagGetClientAveragePingRawMs(client);
		if (averagePing < 0.0)
		{
			continue;
		}

		clients[count] = client;
		pings[count] = averagePing;
		count++;

		if (averagePing > highestPing)
		{
			highestPing = averagePing;
			highestClient = client;
		}
	}

	return count;
}

stock void FakelagPrintPreviewToConsole(int client, const char[] message, any ...)
{
	char formatted[512];
	SetGlobalTransTarget(client);
	VFormat(formatted, sizeof(formatted), message, 3);

	if (client == 0)
	{
		PrintToServer("%s", formatted);
		return;
	}

	PrintToConsole(client, "%s", formatted);
}

stock void FakelagReplyBalanceTarget(int admin, int highestClient, float displayHighestPing, float highestPing)
{
	if (admin != 0)
	{
		CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalanceTarget", highestClient, displayHighestPing, highestPing);
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || L4D_GetClientTeam(client) < L4DTeam_Survivor)
		{
			continue;
		}

		CPrintToChat(client, "%t %t", "Tag", "FakelagBalanceTarget", highestClient, displayHighestPing, highestPing);
	}
}

stock void FakelagReplyBalanceApplied(int admin, int count, int adjusted, int cleared, float displayTargetPing, float targetPing)
{
	if (admin != 0)
	{
		CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalanceApplied", count, adjusted, cleared, displayTargetPing, targetPing);
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || L4D_GetClientTeam(client) < L4DTeam_Survivor)
		{
			continue;
		}

		CPrintToChat(client, "%t %t", "Tag", "FakelagBalanceApplied", count, adjusted, cleared, displayTargetPing, targetPing);
	}
}

stock void FakelagApplyBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing, float displayTargetPing)
{
	int adjusted = 0;
	int cleared = 0;

	for (int index = 0; index < count; index++)
	{
		int target = clients[index];
		float rawPing = pings[index];
		float compensation = targetPing - rawPing;
		float displayPing = FakelagEstimateNetGraphPingForClientMs(target, rawPing);
		float displayTargetPingForClient = FakelagEstimateNetGraphPingForClientMs(target, targetPing);

		if (compensation <= 0.0)
		{
			if (CFakeLag_HasPlayerLatency(target))
			{
				CFakeLag_ClearPlayerLatency(target);
				cleared++;
			}

			if (admin != 0)
			{
				CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalancePlayerUnchanged", target, displayPing, rawPing, displayTargetPingForClient, targetPing);
			}
			else {
				CPrintToChat(target, "%t %t", "Tag", "FakelagBalancePlayerUnchanged", target, displayPing, rawPing, displayTargetPingForClient, targetPing);
			}
			continue;
		}

		CFakeLag_SetPlayerLatency(target, compensation);
		adjusted++;
		if (admin != 0)
		{
			CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalancePlayerAdjusted", target, displayPing, rawPing, compensation, displayTargetPingForClient, targetPing);
		}
		else {
			CPrintToChat(target, "%t %t", "Tag", "FakelagBalancePlayerAdjusted", target, displayPing, rawPing, compensation, displayTargetPingForClient, targetPing);
		}
	}

	FakelagReplyBalanceApplied(admin, count, adjusted, cleared, displayTargetPing, targetPing);
}

stock void FakelagPreviewBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing, float displayTargetPing)
{
	int adjusted = 0;

	for (int index = 0; index < count; index++)
	{
		int target = clients[index];
		float rawPing = pings[index];
		float compensation = targetPing - rawPing;
		float displayPing = FakelagEstimateNetGraphPingForClientMs(target, rawPing);
		float displayTargetPingForClient = FakelagEstimateNetGraphPingForClientMs(target, targetPing);

		if (compensation <= 0.0)
		{
			FakelagPrintPreviewToConsole(admin, "%t %t", "TagConsole", "FakelagBalancePreviewPlayerUnchangedConsole", target, displayPing, rawPing, displayTargetPingForClient, targetPing);
			continue;
		}

		adjusted++;
		FakelagPrintPreviewToConsole(admin, "%t %t", "TagConsole", "FakelagBalancePreviewPlayerAdjustedConsole", target, displayPing, rawPing, compensation, displayTargetPingForClient, targetPing);
	}

	FakelagPrintPreviewToConsole(admin, "%t %t", "TagConsole", "FakelagBalancePreviewAppliedConsole", count, adjusted, displayTargetPing, targetPing);
}

stock bool FakelagApplyBalanceSilent(float &targetPing, int &highestClient, int &playerCount, int &adjustedCount, int &clearedCount)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];

	playerCount = FakelagCollectBalanceCandidates(targets, pings, targetPing, highestClient);
	adjustedCount = 0;
	clearedCount = 0;

	if (playerCount <= 0 || highestClient <= 0 || targetPing < 0.0)
	{
		return false;
	}

	for (int index = 0; index < playerCount; index++)
	{
		int target = targets[index];
		float compensation = targetPing - pings[index];

		if (compensation <= 0.0)
		{
			if (CFakeLag_HasPlayerLatency(target))
			{
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

stock void FakelagRunBalanceCommand(int client)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int highestClient;
	int count;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return;
	}

	float displayHighestPing = FakelagGetClientAveragePingMs(highestClient);
	FakelagReplyBalanceTarget(client, highestClient, displayHighestPing, highestPing);
	FakelagApplyBalance(client, targets, pings, count, highestPing, displayHighestPing);
}

stock void FakelagRunBalancePreviewCommand(int client)
{
	int targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int highestClient;
	int count;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return;
	}

	float displayHighestPing = FakelagGetClientAveragePingMs(highestClient);
	FakelagPrintPreviewToConsole(client, "%t %t", "TagConsole", "FakelagBalancePreviewTargetConsole", highestClient, displayHighestPing, highestPing);
	FakelagPreviewBalance(client, targets, pings, count, highestPing, displayHighestPing);

	if (client != 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagPreviewSentToConsole");
	}
}