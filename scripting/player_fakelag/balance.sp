const int  FAKELAG_CONSOLE_TABLE_INNER_WIDTH = 108;
const int  FAKELAG_GLOBAL_NAME_WIDTH		 = 18;
const int  FAKELAG_PAIR_NAME_WIDTH			 = 14;

stock void FakelagPrintConsoleMessage(int client, const char[] message)
{
	if (client == 0)
	{
		PrintToServer("%s", message);
		return;
	}

	PrintToConsole(client, "%s", message);
}

stock void FakelagPrintConsoleTableBorder(int client)
{
	char border[FAKELAG_CONSOLE_TABLE_INNER_WIDTH + 5];
	int	 index		= 0;

	border[index++] = '|';
	for (int i = 0; i < FAKELAG_CONSOLE_TABLE_INNER_WIDTH + 2; i++)
	{
		border[index++] = '-';
	}
	border[index++] = '|';
	border[index]	= '\0';

	FakelagPrintConsoleMessage(client, border);
}

stock void FakelagPrintConsoleTableLine(int client, const char[] content)
{
	char output[FAKELAG_CONSOLE_TABLE_INNER_WIDTH + 5];
	int	 index		  = 0;

	output[index++]	  = '|';
	output[index++]	  = ' ';

	int contentLength = strlen(content);
	int copyLength	  = contentLength;
	if (copyLength > FAKELAG_CONSOLE_TABLE_INNER_WIDTH)
	{
		copyLength = FAKELAG_CONSOLE_TABLE_INNER_WIDTH;
	}

	for (int i = 0; i < copyLength; i++)
	{
		output[index++] = content[i];
	}

	while (index < FAKELAG_CONSOLE_TABLE_INNER_WIDTH + 2)
	{
		output[index++] = ' ';
	}

	output[index++] = '|';
	output[index]	= '\0';

	FakelagPrintConsoleMessage(client, output);
}

stock void FakelagPrintConsoleTableStart(int client, const char[] title)
{
	FakelagPrintConsoleTableBorder(client);
	FakelagPrintConsoleTableLine(client, title);
	FakelagPrintConsoleTableBorder(client);
}

stock void FakelagPrintConsoleTableColumns(int client, const char[] columns)
{
	FakelagPrintConsoleTableLine(client, columns);
	FakelagPrintConsoleTableBorder(client);
}

stock void FakelagPrintConsoleTableFinish(int client, const char[] summary)
{
	char legend[256];
	SetGlobalTransTarget(client);
	Format(legend, sizeof(legend), "%t", "BalanceTableLegend");

	FakelagPrintConsoleTableBorder(client);
	FakelagPrintConsoleTableLine(client, summary);
	FakelagPrintConsoleTableLine(client, legend);
	FakelagPrintConsoleTableBorder(client);
}

stock void FakelagPrintConsoleTableStartToAudience(const char[] title, int excludedClient = 0)
{
	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (audience == excludedClient)
		{
			continue;
		}

		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		FakelagPrintConsoleTableStart(audience, title);
	}
}

stock void FakelagPrintConsoleTableColumnsToAudience(const char[] columns, int excludedClient = 0)
{
	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (audience == excludedClient)
		{
			continue;
		}

		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		FakelagPrintConsoleTableColumns(audience, columns);
	}
}

stock void FakelagPrintConsoleTableLineToAudience(const char[] line, int excludedClient = 0)
{
	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (audience == excludedClient)
		{
			continue;
		}

		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		FakelagPrintConsoleTableLine(audience, line);
	}
}

stock void FakelagPrintConsoleTableFinishToAudience(const char[] summary, int excludedClient = 0)
{
	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (audience == excludedClient)
		{
			continue;
		}

		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		FakelagPrintConsoleTableFinish(audience, summary);
	}
}

stock void FakelagNotifyGlobalBalanceTarget(int target, float compensation)
{
	if (!IsHumanInGame(target) || compensation <= 0.0)
	{
		return;
	}

	CPrintToChat(target, "%t %t", "Tag", "BalanceTargetAdjusted", compensation);
	CPrintToChat(target, "%t %t", "Tag", "DetailsSentToTargetConsole");
}

stock void FakelagNotifyPairBalanceTarget(int target, int partner, float compensation)
{
	if (!IsHumanInGame(target) || !IsHumanInGame(partner) || compensation <= 0.0)
	{
		return;
	}

	CPrintToChat(target, "%t %t", "Tag", "PairBalanceTargetAdjusted", partner, compensation);
	CPrintToChat(target, "%t %t", "Tag", "DetailsSentToTargetConsole");
}

stock void FakelagGetConsoleClientName(int client, char[] buffer, int maxlen, int maxWidth)
{
	char original[64];
	GetClientName(client, original, sizeof(original));
	ReplaceString(original, sizeof(original), "|", "/");
	ReplaceString(original, sizeof(original), "\n", " ");
	ReplaceString(original, sizeof(original), "\r", " ");

	int length = strlen(original);
	if (length <= maxWidth)
	{
		strcopy(buffer, maxlen, original);
		return;
	}

	if (maxWidth <= 3)
	{
		strcopy(buffer, maxlen, original);
		buffer[maxWidth] = '\0';
		return;
	}

	int prefixLength = (maxWidth - 3) / 2;
	int suffixLength = maxWidth - 3 - prefixLength;
	int index		 = 0;

	for (int i = 0; i < prefixLength && index < maxlen - 1; i++)
	{
		buffer[index++] = original[i];
	}

	if (index < maxlen - 1)
	{
		buffer[index++] = '.';
	}
	if (index < maxlen - 1)
	{
		buffer[index++] = '.';
	}
	if (index < maxlen - 1)
	{
		buffer[index++] = '.';
	}

	int suffixStart = length - suffixLength;
	for (int i = suffixStart; i < length && index < maxlen - 1; i++)
	{
		buffer[index++] = original[i];
	}

	buffer[index] = '\0';
}

stock void FakelagFormatGlobalBalanceRow(int client, int target, float displayPing, float rawPing, float compensation, bool cleared, char[] buffer, int maxlen)
{
	char name[64];
	char result[32];
	FakelagGetConsoleClientName(target, name, sizeof(name), FAKELAG_GLOBAL_NAME_WIDTH);

	SetGlobalTransTarget(client);
	if (compensation > 0.0)
	{
		Format(result, sizeof(result), "%t", "BalanceTableActionAdjust", compensation);
	}
	else if (cleared)
	{
		Format(result, sizeof(result), "%t", "BalanceTableActionClear");
	}
	else
	{
		Format(result, sizeof(result), "%t", "BalanceTableActionSame");
	}

	Format(buffer, maxlen, "%-18s | %7.1f | %7.1f | %-24s", name, displayPing, rawPing, result);
}

stock void FakelagFormatPairBalanceRow(int client, int survivor, float survivorDisplay, float survivorRaw, int infected, float infectedDisplay, float infectedRaw, float compensation, int adjustedClient, bool unchanged, char[] buffer, int maxlen)
{
	char survivorName[64];
	char infectedName[64];
	char result[40];
	FakelagGetConsoleClientName(survivor, survivorName, sizeof(survivorName), FAKELAG_PAIR_NAME_WIDTH);
	FakelagGetConsoleClientName(infected, infectedName, sizeof(infectedName), FAKELAG_PAIR_NAME_WIDTH);

	SetGlobalTransTarget(client);
	if (unchanged)
	{
		Format(result, sizeof(result), "%t", "BalanceTableActionSame");
	}
	else
	{
		char adjustedName[64];
		FakelagGetConsoleClientName(adjustedClient, adjustedName, sizeof(adjustedName), 12);
		Format(result, sizeof(result), "%t", "PairBalanceTableActionAdjust", adjustedName, compensation);
	}

	Format(buffer, maxlen, "%-14s | %7.1f | %7.1f | %-14s | %7.1f | %7.1f | %-20s", survivorName, survivorDisplay, survivorRaw, infectedName, infectedDisplay, infectedRaw, result);
}

stock void FakelagFormatUnpairedBalanceRow(int client, int target, float displayPing, float rawPing, bool survivorSide, char[] buffer, int maxlen)
{
	char name[64];
	char result[32];
	FakelagGetConsoleClientName(target, name, sizeof(name), FAKELAG_PAIR_NAME_WIDTH);

	SetGlobalTransTarget(client);
	Format(result, sizeof(result), "%t", "BalanceTableActionClear");

	if (survivorSide)
	{
		Format(buffer, maxlen, "%-14s | %7.1f | %7.1f | %-14s | %7s | %7s | %-20s", name, displayPing, rawPing, "-", "-", "-", result);
		return;
	}

	Format(buffer, maxlen, "%-14s | %7s | %7s | %-14s | %7.1f | %7.1f | %-20s", "-", "-", "-", name, displayPing, rawPing, result);
}

stock int FakelagCollectBalanceCandidates(int clients[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], float &highestPing, int &highestClient)
{
	int count	  = 0;
	highestPing	  = -1.0;
	highestClient = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanInGame(client))
		{
			continue;
		}

		if (!IsClientInGame(client))
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
		pings[count]   = averagePing;
		count++;

		if (averagePing > highestPing)
		{
			highestPing	  = averagePing;
			highestClient = client;
		}
	}

	return count;
}

stock int FakelagCollectTeamBalanceCandidates(L4DTeam team, int clients[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1])
{
	int count = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!FakelagIsBalanceCandidate(client, team))
		{
			continue;
		}

		float averagePing = FakelagGetClientAveragePingRawMs(client);
		if (averagePing < 0.0)
		{
			continue;
		}

		clients[count] = client;
		pings[count]   = averagePing;
		count++;
	}

	return count;
}

stock void FakelagSortBalanceCandidatesDescending(int clients[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], int count)
{
	for (int left = 0; left < count - 1; left++)
	{
		for (int right = left + 1; right < count; right++)
		{
			if (pings[left] >= pings[right])
			{
				continue;
			}

			float ping	   = pings[left];
			pings[left]	   = pings[right];
			pings[right]   = ping;

			int client	   = clients[left];
			clients[left]  = clients[right];
			clients[right] = client;
		}
	}
}

stock bool FakelagClearPlayerLatencyExplicit(int client)
{
	if (!CFakeLag_HasPlayerLatency(client))
	{
		return false;
	}

	g_ForgetLatencyOnNextClear[client] = true;
	FakelagClearNetworkProfile(client);
	return true;
}

stock bool FakelagPreparePairBalance(int survivorClients[MAXPLAYERS + 1], float survivorPings[MAXPLAYERS + 1], int &survivorCount, int infectedClients[MAXPLAYERS + 1], float infectedPings[MAXPLAYERS + 1], int &infectedCount, int &pairCount)
{
	survivorCount = FakelagCollectTeamBalanceCandidates(L4DTeam_Survivor, survivorClients, survivorPings);
	infectedCount = FakelagCollectTeamBalanceCandidates(L4DTeam_Infected, infectedClients, infectedPings);
	pairCount	  = survivorCount < infectedCount ? survivorCount : infectedCount;

	if (pairCount <= 0)
	{
		return false;
	}

	FakelagSortBalanceCandidatesDescending(survivorClients, survivorPings, survivorCount);
	FakelagSortBalanceCandidatesDescending(infectedClients, infectedPings, infectedCount);
	return true;
}

stock bool FakelagApplyPairBalanceSilent(int &playerCount, int &pairCount, int &adjustedCount, int &clearedCount)
{
	int	  survivorClients[MAXPLAYERS + 1];
	float survivorPings[MAXPLAYERS + 1];
	int	  infectedClients[MAXPLAYERS + 1];
	float infectedPings[MAXPLAYERS + 1];

	int	  survivorCount;
	int	  infectedCount;
	if (!FakelagPreparePairBalance(survivorClients, survivorPings, survivorCount, infectedClients, infectedPings, infectedCount, pairCount))
	{
		playerCount	  = 0;
		adjustedCount = 0;
		clearedCount  = 0;
		return false;
	}

	playerCount	  = survivorCount + infectedCount;
	adjustedCount = 0;
	clearedCount  = 0;

	for (int index = 0; index < pairCount; index++)
	{
		int	  survivor	   = survivorClients[index];
		int	  infected	   = infectedClients[index];
		float survivorPing = survivorPings[index];
		float infectedPing = infectedPings[index];

		if (survivorPing > infectedPing)
		{
			if (FakelagClearPlayerLatencyExplicit(survivor))
			{
				clearedCount++;
			}

			float compensation = survivorPing - infectedPing;
			FakelagApplyNetworkProfile(infected, FakelagBuildNetworkProfile(compensation, FakelagResolvePacketLossPercent(infectedPing, compensation, survivorPing)));
			FakelagNotifyPairBalanceTarget(infected, survivor, compensation);
			adjustedCount++;
			continue;
		}

		if (infectedPing > survivorPing)
		{
			if (FakelagClearPlayerLatencyExplicit(infected))
			{
				clearedCount++;
			}

			float compensation = infectedPing - survivorPing;
			FakelagApplyNetworkProfile(survivor, FakelagBuildNetworkProfile(compensation, FakelagResolvePacketLossPercent(survivorPing, compensation, infectedPing)));
			FakelagNotifyPairBalanceTarget(survivor, infected, compensation);
			adjustedCount++;
			continue;
		}

		if (FakelagClearPlayerLatencyExplicit(survivor))
		{
			clearedCount++;
		}

		if (FakelagClearPlayerLatencyExplicit(infected))
		{
			clearedCount++;
		}
	}

	for (int index = pairCount; index < survivorCount; index++)
	{
		if (FakelagClearPlayerLatencyExplicit(survivorClients[index]))
		{
			clearedCount++;
		}
	}

	for (int index = pairCount; index < infectedCount; index++)
	{
		if (FakelagClearPlayerLatencyExplicit(infectedClients[index]))
		{
			clearedCount++;
		}
	}

	return true;
}

stock void FakelagApplyBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int	 adjusted = 0;
	int	 cleared  = 0;
	char formatted[512];
	char row[256];

	for (int index = 0; index < count; index++)
	{
		int	  target		= clients[index];
		float rawPing		= pings[index];
		float compensation	= targetPing - rawPing;
		float displayPing	= FakelagEstimateNetGraphPingForClientMs(target, rawPing);
		bool  clearedClient = false;

		if (compensation <= 0.0)
		{
			if (CFakeLag_HasPlayerLatency(target))
			{
				g_ForgetLatencyOnNextClear[target] = true;
				FakelagClearNetworkProfile(target);
				cleared++;
				clearedClient = true;
			}

			FakelagFormatGlobalBalanceRow(admin, target, displayPing, rawPing, compensation, clearedClient, row, sizeof(row));
			FakelagPrintConsoleTableLine(admin, row);
			FakelagPrintConsoleTableLineToAudience(row, admin);
			continue;
		}

		FakelagApplyNetworkProfile(target, FakelagBuildNetworkProfile(compensation, FakelagResolvePacketLossPercent(rawPing, compensation, targetPing)));
		adjusted++;
		FakelagNotifyGlobalBalanceTarget(target, compensation);
		FakelagFormatGlobalBalanceRow(admin, target, displayPing, rawPing, compensation, false, row, sizeof(row));
		FakelagPrintConsoleTableLine(admin, row);
		FakelagPrintConsoleTableLineToAudience(row, admin);
	}

	SetGlobalTransTarget(admin);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalanceConsoleApplied", count, adjusted, cleared);
	FakelagPrintConsoleTableFinish(admin, formatted);
	FakelagPrintConsoleTableFinishToAudience(formatted, admin);
}

stock void FakelagPreviewBalance(int admin, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int	 adjusted = 0;
	char formatted[512];
	char row[256];

	for (int index = 0; index < count; index++)
	{
		int	  target	   = clients[index];
		float rawPing	   = pings[index];
		float compensation = targetPing - rawPing;
		float displayPing  = FakelagEstimateNetGraphPingForClientMs(target, rawPing);

		if (compensation <= 0.0)
		{
			FakelagFormatGlobalBalanceRow(admin, target, displayPing, rawPing, compensation, CFakeLag_HasPlayerLatency(target), row, sizeof(row));
			FakelagPrintConsoleTableLine(admin, row);
			continue;
		}

		adjusted++;
		FakelagFormatGlobalBalanceRow(admin, target, displayPing, rawPing, compensation, false, row, sizeof(row));
		FakelagPrintConsoleTableLine(admin, row);
	}

	SetGlobalTransTarget(admin);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalancePreviewAppliedConsole", count, adjusted);
	FakelagPrintConsoleTableFinish(admin, formatted);
}

stock bool FakelagApplyBalanceSilent(float &targetPing, int &highestClient, int &playerCount, int &adjustedCount, int &clearedCount)
{
	int	  targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];

	playerCount	  = FakelagCollectBalanceCandidates(targets, pings, targetPing, highestClient);
	adjustedCount = 0;
	clearedCount  = 0;

	if (playerCount <= 0 || highestClient <= 0 || targetPing < 0.0)
	{
		return false;
	}

	for (int index = 0; index < playerCount; index++)
	{
		int	  target	   = targets[index];
		float compensation = targetPing - pings[index];

		if (compensation <= 0.0)
		{
			if (CFakeLag_HasPlayerLatency(target))
			{
				g_ForgetLatencyOnNextClear[target] = true;
				FakelagClearNetworkProfile(target);
				clearedCount++;
			}
			continue;
		}

		FakelagApplyNetworkProfile(target, FakelagBuildNetworkProfile(compensation, FakelagResolvePacketLossPercent(pings[index], compensation, targetPing)));
		adjustedCount++;
	}

	return true;
}

stock bool FakelagPreviewBalanceSilent(float &targetPing, int &highestClient, int &playerCount)
{
	int	  targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];

	playerCount = FakelagCollectBalanceCandidates(targets, pings, targetPing, highestClient);
	return playerCount > 0 && highestClient > 0 && targetPing >= 0.0;
}

stock void FakelagRunBalanceCommand(int client)
{
	int	  targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int	  highestClient;
	int	  count;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return;
	}

	float displayHighestPing = FakelagGetClientAveragePingMs(highestClient);
	if (client != 0)
	{
		char formatted[512];
		char columns[256];
		SetGlobalTransTarget(client);
		Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalanceConsoleTitle", highestClient, displayHighestPing, highestPing);
		FakelagPrintConsoleTableStart(client, formatted);
		Format(columns, sizeof(columns), "%t", "BalanceTableColumns");
		FakelagPrintConsoleTableColumns(client, columns);
		FakelagPrintConsoleTableStartToAudience(formatted, client);
		FakelagPrintConsoleTableColumnsToAudience(columns, client);

		for (int audience = 1; audience <= MaxClients; audience++)
		{
			if (!FakelagIsBalanceAudienceClient(audience))
			{
				continue;
			}

			CPrintToChat(audience, "%t %t", "Tag", "BalanceStarted");
		}
	}
	else {
		char formatted[512];
		char columns[256];
		SetGlobalTransTarget(client);
		Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalanceConsoleTitle", highestClient, displayHighestPing, highestPing);
		FakelagPrintConsoleTableStart(client, formatted);
		Format(columns, sizeof(columns), "%t", "BalanceTableColumns");
		FakelagPrintConsoleTableColumns(client, columns);
		FakelagPrintConsoleTableStartToAudience(formatted);
		FakelagPrintConsoleTableColumnsToAudience(columns);

		for (int audience = 1; audience <= MaxClients; audience++)
		{
			if (!FakelagIsBalanceAudienceClient(audience))
			{
				continue;
			}

			CPrintToChat(audience, "%t %t", "Tag", "BalanceStarted");
		}
	}

	FakelagApplyBalance(client, targets, pings, count, highestPing);

	if (client != 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "BalanceStarted");
		CReplyToCommand(client, "%t %t", "Tag", "DetailsSentToConsole");
	}
}

stock void FakelagRunBalancePreviewCommand(int client)
{
	int	  targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int	  highestClient;
	int	  count;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return;
	}

	float displayHighestPing = FakelagGetClientAveragePingMs(highestClient);
	char  formatted[512];
	char  columns[256];
	SetGlobalTransTarget(client);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalanceConsoleTitle", highestClient, displayHighestPing, highestPing);
	FakelagPrintConsoleTableStart(client, formatted);
	Format(columns, sizeof(columns), "%t", "BalanceTableColumns");
	FakelagPrintConsoleTableColumns(client, columns);
	FakelagPreviewBalance(client, targets, pings, count, highestPing);

	if (client == 0)
	{
		return;
	}

	CReplyToCommand(client, "%t %t", "Tag", "PreviewSentToConsole");
}

stock void FakelagRunPairBalanceCommand(int client)
{
	int	  survivorClients[MAXPLAYERS + 1];
	float survivorPings[MAXPLAYERS + 1];
	int	  infectedClients[MAXPLAYERS + 1];
	float infectedPings[MAXPLAYERS + 1];
	int	  survivorCount;
	int	  infectedCount;
	int	  pairCount;

	if (!FakelagPreparePairBalance(survivorClients, survivorPings, survivorCount, infectedClients, infectedPings, infectedCount, pairCount))
	{
		CReplyToCommand(client, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}

	char formatted[512];
	char columns[256];
	char row[256];
	SetGlobalTransTarget(client);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "PairBalanceConsoleTitle", pairCount);
	FakelagPrintConsoleTableStart(client, formatted);
	Format(columns, sizeof(columns), "%t", "PairBalanceTableColumns");
	FakelagPrintConsoleTableColumns(client, columns);
	FakelagPrintConsoleTableStartToAudience(formatted, client);
	FakelagPrintConsoleTableColumnsToAudience(columns, client);

	if (client != 0)
	{
		for (int audience = 1; audience <= MaxClients; audience++)
		{
			if (!FakelagIsBalanceAudienceClient(audience))
			{
				continue;
			}

			CPrintToChat(audience, "%t %t", "Tag", "PairBalanceStarted");
		}
	}

	for (int index = 0; index < pairCount; index++)
	{
		int	  survivor		  = survivorClients[index];
		int	  infected		  = infectedClients[index];
		float survivorRaw	  = survivorPings[index];
		float infectedRaw	  = infectedPings[index];
		float survivorDisplay = FakelagEstimateNetGraphPingForClientMs(survivor, survivorRaw);
		float infectedDisplay = FakelagEstimateNetGraphPingForClientMs(infected, infectedRaw);
		float compensation	  = FloatAbs(survivorRaw - infectedRaw);

		SetGlobalTransTarget(client);
		if (compensation <= 0.0)
		{
			FakelagFormatPairBalanceRow(client, survivor, survivorDisplay, survivorRaw, infected, infectedDisplay, infectedRaw, compensation, 0, true, row, sizeof(row));
		}
		else
		{
			int adjustedClient = survivorRaw < infectedRaw ? survivor : infected;
			FakelagFormatPairBalanceRow(client, survivor, survivorDisplay, survivorRaw, infected, infectedDisplay, infectedRaw, compensation, adjustedClient, false, row, sizeof(row));
		}

		FakelagPrintConsoleTableLine(client, row);
		FakelagPrintConsoleTableLineToAudience(row, client);

	}

	for (int index = pairCount; index < survivorCount; index++)
	{
		float rawPing	  = survivorPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(survivorClients[index], rawPing);
		FakelagFormatUnpairedBalanceRow(client, survivorClients[index], displayPing, rawPing, true, row, sizeof(row));
		FakelagPrintConsoleTableLine(client, row);
		FakelagPrintConsoleTableLineToAudience(row, client);
	}

	for (int index = pairCount; index < infectedCount; index++)
	{
		float rawPing	  = infectedPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(infectedClients[index], rawPing);
		FakelagFormatUnpairedBalanceRow(client, infectedClients[index], displayPing, rawPing, false, row, sizeof(row));
		FakelagPrintConsoleTableLine(client, row);
		FakelagPrintConsoleTableLineToAudience(row, client);
	}

	int playerCount;
	int adjustedCount;
	int clearedCount;

	if (!FakelagApplyPairBalanceSilent(playerCount, pairCount, adjustedCount, clearedCount))
	{
		CReplyToCommand(client, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}

	SetGlobalTransTarget(client);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalanceConsoleApplied", playerCount, adjustedCount, clearedCount);
	FakelagPrintConsoleTableFinish(client, formatted);
	FakelagPrintConsoleTableFinishToAudience(formatted, client);

	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		CPrintToChat(audience, "%t %t", "Tag", "DetailsSentToTargetConsole");
	}

	if (client != 0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "PairBalanceStarted");
		CReplyToCommand(client, "%t %t", "Tag", "DetailsSentToConsole");
		return;
	}
}

stock void FakelagRunPairBalancePreviewCommand(int client)
{
	int	  survivorClients[MAXPLAYERS + 1];
	float survivorPings[MAXPLAYERS + 1];
	int	  infectedClients[MAXPLAYERS + 1];
	float infectedPings[MAXPLAYERS + 1];
	int	  survivorCount;
	int	  infectedCount;
	int	  pairCount;

	if (!FakelagPreparePairBalance(survivorClients, survivorPings, survivorCount, infectedClients, infectedPings, infectedCount, pairCount))
	{
		CReplyToCommand(client, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}

	char formatted[512];
	char columns[256];
	char row[256];
	SetGlobalTransTarget(client);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "PairBalanceConsoleTitle", pairCount);
	FakelagPrintConsoleTableStart(client, formatted);
	Format(columns, sizeof(columns), "%t", "PairBalanceTableColumns");
	FakelagPrintConsoleTableColumns(client, columns);

	int adjustedCount = 0;
	for (int index = 0; index < pairCount; index++)
	{
		int	  survivor		  = survivorClients[index];
		int	  infected		  = infectedClients[index];
		float survivorRaw	  = survivorPings[index];
		float infectedRaw	  = infectedPings[index];
		float survivorDisplay = FakelagEstimateNetGraphPingForClientMs(survivor, survivorRaw);
		float infectedDisplay = FakelagEstimateNetGraphPingForClientMs(infected, infectedRaw);
		float compensation	  = FloatAbs(survivorRaw - infectedRaw);
		int	  adjustedClient  = survivorRaw < infectedRaw ? survivor : infected;

		FakelagFormatPairBalanceRow(client, survivor, survivorDisplay, survivorRaw, infected, infectedDisplay, infectedRaw, compensation, adjustedClient, compensation <= 0.0, row, sizeof(row));
		FakelagPrintConsoleTableLine(client, row);

		if (compensation > 0.0)
		{
			adjustedCount++;
		}
	}

	for (int index = pairCount; index < survivorCount; index++)
	{
		float rawPing	  = survivorPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(survivorClients[index], rawPing);
		FakelagFormatUnpairedBalanceRow(client, survivorClients[index], displayPing, rawPing, true, row, sizeof(row));
		FakelagPrintConsoleTableLine(client, row);
	}

	for (int index = pairCount; index < infectedCount; index++)
	{
		float rawPing	  = infectedPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(infectedClients[index], rawPing);
		FakelagFormatUnpairedBalanceRow(client, infectedClients[index], displayPing, rawPing, false, row, sizeof(row));
		FakelagPrintConsoleTableLine(client, row);
	}

	SetGlobalTransTarget(client);
	Format(formatted, sizeof(formatted), "%t %t", "TagConsole", "BalancePreviewAppliedConsole", survivorCount + infectedCount, adjustedCount);
	FakelagPrintConsoleTableFinish(client, formatted);
	if (client == 0)
	{
		return;
	}

	CReplyToCommand(client, "%t %t", "Tag", "PreviewSentToConsole");
}
