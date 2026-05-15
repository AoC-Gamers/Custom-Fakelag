stock int FakelagCollectBalanceCandidates(int clients[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], float &highestPing, int &highestClient)
{
	int count = 0;
	highestPing = -1.0;
	highestClient = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanInGame(client))
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

stock void FakelagApplyBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int adjusted = 0;
	int cleared = 0;

	for (int index = 0; index < count; index++)
	{
		int target = clients[index];
		float rawPing = pings[index];
		float compensation = targetPing - rawPing;
		float displayPing = FakelagEstimateNetGraphPingForClientMs(target, rawPing);

		if (compensation <= 0.0)
		{
			if (CFakeLag_HasPlayerLatency(target))
			{
				g_ForgetLatencyOnNextClear[target] = true;
				CFakeLag_ClearPlayerLatency(target);
				cleared++;
			}

			if (admin != 0)
			{
				CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalancePlayerUnchanged", target, displayPing, rawPing);
				continue;
			}

			CPrintToChat(target, "%t %t", "Tag", "FakelagBalancePlayerUnchanged", target, displayPing, rawPing);
			continue;
		}

		CFakeLag_SetPlayerLatency(target, compensation);
		adjusted++;
		if (admin != 0)
		{
			CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalancePlayerAdjusted", target, displayPing, rawPing, compensation);
			continue;
		}

		CPrintToChat(target, "%t %t", "Tag", "FakelagBalancePlayerAdjusted", target, displayPing, rawPing, compensation);
	}

	if (admin != 0)
	{
		CReplyToCommand(admin, "%t %t", "Tag", "FakelagBalanceApplied", count, adjusted, cleared);
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!FakelagIsBalanceAudienceClient(client))
		{
			continue;
		}

		CPrintToChat(client, "%t %t", "Tag", "FakelagBalanceApplied", count, adjusted, cleared);
	}
}

stock void FakelagPreviewBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int adjusted = 0;
	char formatted[512];

	for (int index = 0; index < count; index++)
	{
		int target = clients[index];
		float rawPing = pings[index];
		float compensation = targetPing - rawPing;
		float displayPing = FakelagEstimateNetGraphPingForClientMs(target, rawPing);

		if (compensation <= 0.0)
		{
			SetGlobalTransTarget(admin);
			Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "FakelagBalancePreviewPlayerUnchangedConsole", target, displayPing, rawPing);
			if (admin == 0)
			{
				PrintToServer("%s", formatted);
				continue;
			}

			PrintToConsole(admin, "%s", formatted);
			continue;
		}

		adjusted++;
		SetGlobalTransTarget(admin);
		Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "FakelagBalancePreviewPlayerAdjustedConsole", target, displayPing, rawPing, compensation);
		if (admin == 0)
		{
			PrintToServer("%s", formatted);
			continue;
		}

		PrintToConsole(admin, "%s", formatted);
	}

	SetGlobalTransTarget(admin);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "FakelagBalancePreviewAppliedConsole", count, adjusted);
	if (admin == 0)
	{
		PrintToServer("%s", formatted);
		return;
	}

	PrintToConsole(admin, "%s", formatted);
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
				g_ForgetLatencyOnNextClear[target] = true;
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
	if (client != 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceTarget", highestClient, displayHighestPing, highestPing);
	}
	else {
		for (int audience = 1; audience <= MaxClients; audience++)
		{
			if (!FakelagIsBalanceAudienceClient(audience))
			{
				continue;
			}

			CPrintToChat(audience, "%t %t", "Tag", "FakelagBalanceTarget", highestClient, displayHighestPing, highestPing);
		}
	}

	FakelagApplyBalance(client, targets, pings, count, highestPing);
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
	char formatted[512];
	SetGlobalTransTarget(client);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "FakelagBalancePreviewTargetConsole", highestClient, displayHighestPing, highestPing);
	if (client == 0)
	{
		PrintToServer("%s", formatted);
	}
	else {
		PrintToConsole(client, "%s", formatted);
	}
	FakelagPreviewBalance(client, targets, pings, count, highestPing);

	if (client == 0)
	{
		return;
	}

	CReplyToCommand(client, "%t %t", "Tag", "FakelagPreviewSentToConsole");
}