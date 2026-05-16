const int FAKELAG_GLOBAL_TABLE_INNER_WIDTH = 64;
const int FAKELAG_PAIR_TABLE_INNER_WIDTH   = 88;
const int FAKELAG_GLOBAL_NAME_WIDTH		   = 12;
const int FAKELAG_PAIR_NAME_WIDTH		   = 14;

enum struct FakelagConsoleName
{
	char display[64];
	bool usesUserIdFallback;
	int	 client;
}

enum struct FakelagConsoleReport
{
	int innerWidth;
	int legendClients[MAXPLAYERS + 1];
	int legendCount;
}

enum FakelagBalanceAction
{
	FakelagBalanceAction_Same = 0,
	FakelagBalanceAction_Clear,
	FakelagBalanceAction_Adjust
}

stock void
	FakelagResetConsoleReport(FakelagConsoleReport report)
{
	report.innerWidth  = FAKELAG_GLOBAL_TABLE_INNER_WIDTH;
	report.legendCount = 0;
}

stock void FakelagRegisterConsoleLegendClient(FakelagConsoleReport report, int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	for (int index = 0; index < report.legendCount; index++)
	{
		if (report.legendClients[index] == client)
		{
			return;
		}
	}

	if (report.legendCount >= sizeof(report.legendClients))
	{
		return;
	}

	report.legendClients[report.legendCount++] = client;
}

stock void FakelagPopulateConsolePanelFooter(ConsolePanel panel, int client, FakelagConsoleReport report)
{
	char legendAvg[256];
	char legendRaw[256];
	SetGlobalTransTarget(client);
	Format(legendAvg, sizeof(legendAvg), "%t", "BalanceTableLegendAvg");
	Format(legendRaw, sizeof(legendRaw), "%t", "BalanceTableLegendRaw");
	ConsolePanel_AddFooterLine(panel, legendAvg);
	ConsolePanel_AddFooterLine(panel, legendRaw);

	for (int index = 0; index < report.legendCount; index++)
	{
		int legendClient = report.legendClients[index];
		if (!IsClientInGame(legendClient))
		{
			continue;
		}

		char originalName[64];
		char trimmedOriginalName[96];
		char legendLine[192];
		GetClientName(legendClient, originalName, sizeof(originalName));
		ReplaceString(originalName, sizeof(originalName), "|", "/");
		ReplaceString(originalName, sizeof(originalName), "\n", " ");
		ReplaceString(originalName, sizeof(originalName), "\r", " ");
		ConsolePanel_BuildUtf8TrimmedText(originalName, trimmedOriginalName, sizeof(trimmedOriginalName), 24);
		Format(legendLine, sizeof(legendLine), "#%d = (%s)", GetClientUserId(legendClient), trimmedOriginalName);
		ConsolePanel_AddFooterUtf8Line(panel, legendLine);
	}
}

stock void FakelagInitializeGlobalConsolePanel(ConsolePanel panel, FakelagConsoleReport report, int client, const char[] title)
{
	ConsolePanel_Reset(panel);
	ConsolePanel_SetWidth(panel, FAKELAG_GLOBAL_TABLE_INNER_WIDTH);
	ConsolePanel_AddHeaderLine(panel, title);
	panel.table.columnCount = 0;
	panel.table.rowCount = 0;
	panel.table.buildingRow = false;

	strcopy(panel.table.columns[0].title, sizeof(panel.table.columns[0].title), "Jugador");
	panel.table.columns[0].width = 12;
	panel.table.columns[0].alignment = ConsoleTableAlignment_Left;
	panel.table.columns[0].typeHint = ConsoleTableCellType_String;

	strcopy(panel.table.columns[1].title, sizeof(panel.table.columns[1].title), "Avg");
	panel.table.columns[1].width = 5;
	panel.table.columns[1].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[1].typeHint = ConsoleTableCellType_Float;

	strcopy(panel.table.columns[2].title, sizeof(panel.table.columns[2].title), "Raw");
	panel.table.columns[2].width = 5;
	panel.table.columns[2].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[2].typeHint = ConsoleTableCellType_Float;

	strcopy(panel.table.columns[3].title, sizeof(panel.table.columns[3].title), "Resultado");
	panel.table.columns[3].width = 12;
	panel.table.columns[3].alignment = ConsoleTableAlignment_Left;
	panel.table.columns[3].typeHint = ConsoleTableCellType_String;

	strcopy(panel.table.columns[4].title, sizeof(panel.table.columns[4].title), "Loss");
	panel.table.columns[4].width = 4;
	panel.table.columns[4].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[4].typeHint = ConsoleTableCellType_Int;
	panel.table.columnCount = 5;
	FakelagPopulateConsolePanelFooter(panel, client, report);
}

stock void FakelagAddGlobalConsolePanelRow(ConsolePanel panel, FakelagConsoleReport report, int client, int target, float displayPing, float rawPing, FakelagBalanceAction action, float compensation)
{
	char name[64];
	char result[32];
	int packetLossPercent = 0;
	FakelagGetConsoleClientName(report, target, name, sizeof(name), FAKELAG_GLOBAL_NAME_WIDTH);

	SetGlobalTransTarget(client);
	switch (action)
	{
		case FakelagBalanceAction_Adjust:
		{
			Format(result, sizeof(result), "%t", "BalanceTableActionAdjust", compensation);
			packetLossPercent = FakelagResolvePacketLossPercent(rawPing, compensation, rawPing + compensation);
		}
		case FakelagBalanceAction_Clear:
		{
			Format(result, sizeof(result), "%t", "BalanceTableActionClear");
		}
		default:
		{
			Format(result, sizeof(result), "%t", "BalanceTableActionSame");
		}
	}

	int rowIndex = panel.table.rowCount;
	panel.table.rows[rowIndex].cellCount = 5;

	panel.table.rows[rowIndex].cells[0].type = ConsoleTableCellType_String;
	strcopy(panel.table.rows[rowIndex].cells[0].stringValue, sizeof(panel.table.rows[rowIndex].cells[0].stringValue), name);

	panel.table.rows[rowIndex].cells[1].type = ConsoleTableCellType_Float;
	panel.table.rows[rowIndex].cells[1].floatValue = displayPing;
	panel.table.rows[rowIndex].cells[1].floatPrecision = 1;

	panel.table.rows[rowIndex].cells[2].type = ConsoleTableCellType_Float;
	panel.table.rows[rowIndex].cells[2].floatValue = rawPing;
	panel.table.rows[rowIndex].cells[2].floatPrecision = 1;

	panel.table.rows[rowIndex].cells[3].type = ConsoleTableCellType_String;
	strcopy(panel.table.rows[rowIndex].cells[3].stringValue, sizeof(panel.table.rows[rowIndex].cells[3].stringValue), result);

	panel.table.rows[rowIndex].cells[4].type = ConsoleTableCellType_Int;
	panel.table.rows[rowIndex].cells[4].intValue = packetLossPercent;

	panel.table.rowCount++;
}

stock void FakelagInitializePairConsolePanel(ConsolePanel panel, FakelagConsoleReport report, int client, const char[] title)
{
	ConsolePanel_Reset(panel);
	ConsolePanel_SetWidth(panel, FAKELAG_PAIR_TABLE_INNER_WIDTH);
	ConsolePanel_AddHeaderLine(panel, title);
	panel.table.columnCount = 0;
	panel.table.rowCount = 0;
	panel.table.buildingRow = false;

	strcopy(panel.table.columns[0].title, sizeof(panel.table.columns[0].title), "Survivor");
	panel.table.columns[0].width = 12;
	panel.table.columns[0].alignment = ConsoleTableAlignment_Left;
	panel.table.columns[0].typeHint = ConsoleTableCellType_String;

	strcopy(panel.table.columns[1].title, sizeof(panel.table.columns[1].title), "Avg");
	panel.table.columns[1].width = 5;
	panel.table.columns[1].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[1].typeHint = ConsoleTableCellType_Float;

	strcopy(panel.table.columns[2].title, sizeof(panel.table.columns[2].title), "Raw");
	panel.table.columns[2].width = 5;
	panel.table.columns[2].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[2].typeHint = ConsoleTableCellType_Float;

	strcopy(panel.table.columns[3].title, sizeof(panel.table.columns[3].title), "Infected");
	panel.table.columns[3].width = 12;
	panel.table.columns[3].alignment = ConsoleTableAlignment_Left;
	panel.table.columns[3].typeHint = ConsoleTableCellType_String;

	strcopy(panel.table.columns[4].title, sizeof(panel.table.columns[4].title), "Avg");
	panel.table.columns[4].width = 5;
	panel.table.columns[4].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[4].typeHint = ConsoleTableCellType_Float;

	strcopy(panel.table.columns[5].title, sizeof(panel.table.columns[5].title), "Raw");
	panel.table.columns[5].width = 5;
	panel.table.columns[5].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[5].typeHint = ConsoleTableCellType_Float;

	strcopy(panel.table.columns[6].title, sizeof(panel.table.columns[6].title), "Resultado");
	panel.table.columns[6].width = 18;
	panel.table.columns[6].alignment = ConsoleTableAlignment_Left;
	panel.table.columns[6].typeHint = ConsoleTableCellType_String;

	strcopy(panel.table.columns[7].title, sizeof(panel.table.columns[7].title), "Loss");
	panel.table.columns[7].width = 4;
	panel.table.columns[7].alignment = ConsoleTableAlignment_Right;
	panel.table.columns[7].typeHint = ConsoleTableCellType_Int;
	panel.table.columnCount = 8;
	FakelagPopulateConsolePanelFooter(panel, client, report);
}

stock void FakelagAddPairConsolePanelRow(ConsolePanel panel, FakelagConsoleReport report, int client, int survivor, float survivorDisplay, float survivorRaw, int infected, float infectedDisplay, float infectedRaw, FakelagBalanceAction action, float compensation, int adjustedClient)
{
	char survivorName[64];
	char infectedName[64];
	char result[40];
	int packetLossPercent = 0;
	FakelagGetConsoleClientName(report, survivor, survivorName, sizeof(survivorName), 12);
	FakelagGetConsoleClientName(report, infected, infectedName, sizeof(infectedName), 12);

	SetGlobalTransTarget(client);
	if (action != FakelagBalanceAction_Adjust)
	{
		Format(result, sizeof(result), "%t", "BalanceTableActionSame");
	}
	else
	{
		char adjustedName[64];
		FakelagGetConsoleClientName(report, adjustedClient, adjustedName, sizeof(adjustedName), 10);
		Format(result, sizeof(result), "%t", "PairBalanceTableActionAdjust", adjustedName, compensation);
		float adjustedRawPing = adjustedClient == survivor ? survivorRaw : infectedRaw;
		packetLossPercent = FakelagResolvePacketLossPercent(adjustedRawPing, compensation, adjustedRawPing + compensation);
	}

	int rowIndex = panel.table.rowCount;
	panel.table.rows[rowIndex].cellCount = 8;

	panel.table.rows[rowIndex].cells[0].type = ConsoleTableCellType_String;
	strcopy(panel.table.rows[rowIndex].cells[0].stringValue, sizeof(panel.table.rows[rowIndex].cells[0].stringValue), survivorName);

	panel.table.rows[rowIndex].cells[1].type = ConsoleTableCellType_Float;
	panel.table.rows[rowIndex].cells[1].floatValue = survivorDisplay;
	panel.table.rows[rowIndex].cells[1].floatPrecision = 1;

	panel.table.rows[rowIndex].cells[2].type = ConsoleTableCellType_Float;
	panel.table.rows[rowIndex].cells[2].floatValue = survivorRaw;
	panel.table.rows[rowIndex].cells[2].floatPrecision = 1;

	panel.table.rows[rowIndex].cells[3].type = ConsoleTableCellType_String;
	strcopy(panel.table.rows[rowIndex].cells[3].stringValue, sizeof(panel.table.rows[rowIndex].cells[3].stringValue), infectedName);

	panel.table.rows[rowIndex].cells[4].type = ConsoleTableCellType_Float;
	panel.table.rows[rowIndex].cells[4].floatValue = infectedDisplay;
	panel.table.rows[rowIndex].cells[4].floatPrecision = 1;

	panel.table.rows[rowIndex].cells[5].type = ConsoleTableCellType_Float;
	panel.table.rows[rowIndex].cells[5].floatValue = infectedRaw;
	panel.table.rows[rowIndex].cells[5].floatPrecision = 1;

	panel.table.rows[rowIndex].cells[6].type = ConsoleTableCellType_String;
	strcopy(panel.table.rows[rowIndex].cells[6].stringValue, sizeof(panel.table.rows[rowIndex].cells[6].stringValue), result);

	panel.table.rows[rowIndex].cells[7].type = ConsoleTableCellType_Int;
	panel.table.rows[rowIndex].cells[7].intValue = packetLossPercent;

	panel.table.rowCount++;
}

stock void FakelagAddUnpairedConsolePanelRow(ConsolePanel panel, FakelagConsoleReport report, int client, int target, float displayPing, float rawPing, bool survivorSide)
{
	char name[64];
	char result[32];
	FakelagGetConsoleClientName(report, target, name, sizeof(name), 12);

	SetGlobalTransTarget(client);
	Format(result, sizeof(result), "%t", "BalanceTableActionClear");

	int rowIndex = panel.table.rowCount;
	panel.table.rows[rowIndex].cellCount = 8;
	if (survivorSide)
	{
		panel.table.rows[rowIndex].cells[0].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[0].stringValue, sizeof(panel.table.rows[rowIndex].cells[0].stringValue), name);
		panel.table.rows[rowIndex].cells[1].type = ConsoleTableCellType_Float;
		panel.table.rows[rowIndex].cells[1].floatValue = displayPing;
		panel.table.rows[rowIndex].cells[1].floatPrecision = 1;
		panel.table.rows[rowIndex].cells[2].type = ConsoleTableCellType_Float;
		panel.table.rows[rowIndex].cells[2].floatValue = rawPing;
		panel.table.rows[rowIndex].cells[2].floatPrecision = 1;
		panel.table.rows[rowIndex].cells[3].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[3].stringValue, sizeof(panel.table.rows[rowIndex].cells[3].stringValue), "-");
		panel.table.rows[rowIndex].cells[4].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[4].stringValue, sizeof(panel.table.rows[rowIndex].cells[4].stringValue), "-");
		panel.table.rows[rowIndex].cells[5].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[5].stringValue, sizeof(panel.table.rows[rowIndex].cells[5].stringValue), "-");
	}
	else
	{
		panel.table.rows[rowIndex].cells[0].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[0].stringValue, sizeof(panel.table.rows[rowIndex].cells[0].stringValue), "-");
		panel.table.rows[rowIndex].cells[1].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[1].stringValue, sizeof(panel.table.rows[rowIndex].cells[1].stringValue), "-");
		panel.table.rows[rowIndex].cells[2].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[2].stringValue, sizeof(panel.table.rows[rowIndex].cells[2].stringValue), "-");
		panel.table.rows[rowIndex].cells[3].type = ConsoleTableCellType_String;
		strcopy(panel.table.rows[rowIndex].cells[3].stringValue, sizeof(panel.table.rows[rowIndex].cells[3].stringValue), name);
		panel.table.rows[rowIndex].cells[4].type = ConsoleTableCellType_Float;
		panel.table.rows[rowIndex].cells[4].floatValue = displayPing;
		panel.table.rows[rowIndex].cells[4].floatPrecision = 1;
		panel.table.rows[rowIndex].cells[5].type = ConsoleTableCellType_Float;
		panel.table.rows[rowIndex].cells[5].floatValue = rawPing;
		panel.table.rows[rowIndex].cells[5].floatPrecision = 1;
	}
	panel.table.rows[rowIndex].cells[6].type = ConsoleTableCellType_String;
	strcopy(panel.table.rows[rowIndex].cells[6].stringValue, sizeof(panel.table.rows[rowIndex].cells[6].stringValue), result);
	panel.table.rows[rowIndex].cells[7].type = ConsoleTableCellType_Int;
	panel.table.rows[rowIndex].cells[7].intValue = 0;
	panel.table.rowCount++;
}

stock void FakelagRenderConsolePanelToBalanceAudience(ConsolePanel panel, int excludedClient = 0)
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

		ConsolePanel_RenderToClient(panel, audience);
	}
}

stock void FakelagNotifyGlobalBalanceTarget(int target, float compensation)
{
	if (!IsHumanInGame(target))
	{
		return;
	}

	if (compensation > 0.0)
	{
		CPrintToChat(target, "%t %t", "Tag", "BalanceTargetAdjusted", compensation);
	}
	else
	{
		CPrintToChat(target, "%t %t", "Tag", "BalanceTargetUnchanged");
	}
}

stock void FakelagNotifyGlobalBalancePreviewTarget(int target, int initiator, float compensation)
{
	if (!IsHumanInGame(target))
	{
		return;
	}

	if (compensation > 0.0 && initiator > 0 && initiator != target)
	{
		CPrintToChat(target, "%t %t", "Tag", "BalancePreviewTargetAdjustedByAdmin", initiator, compensation);
	}
	else if (compensation > 0.0)
	{
		CPrintToChat(target, "%t %t", "Tag", "BalancePreviewTargetAdjusted", compensation);
	}
	else if (initiator > 0 && initiator != target)
	{
		CPrintToChat(target, "%t %t", "Tag", "BalancePreviewTargetUnchangedByAdmin", initiator);
	}
	else
	{
		CPrintToChat(target, "%t %t", "Tag", "BalancePreviewTargetUnchanged");
	}
}

stock void FakelagNotifyPairBalanceTarget(int target, int partner, float compensation)
{
	if (!IsHumanInGame(target) || !IsHumanInGame(partner))
	{
		return;
	}

	if (compensation > 0.0)
	{
		CPrintToChat(target, "%t %t", "Tag", "PairBalanceTargetAdjusted", partner, compensation);
	}
	else
	{
		CPrintToChat(target, "%t %t", "Tag", "PairBalanceTargetUnchanged", partner);
	}
}

stock void FakelagNotifyPairBalancePreviewTarget(int target, int partner, int initiator, float compensation)
{
	if (!IsHumanInGame(target) || !IsHumanInGame(partner))
	{
		return;
	}

	if (compensation > 0.0 && initiator > 0 && initiator != target)
	{
		CPrintToChat(target, "%t %t", "Tag", "PairBalancePreviewTargetAdjustedByAdmin", initiator, partner, compensation);
	}
	else if (compensation > 0.0)
	{
		CPrintToChat(target, "%t %t", "Tag", "PairBalancePreviewTargetAdjusted", partner, compensation);
	}
	else
	{
		CPrintToChat(target, "%t %t", "Tag", "PairBalancePreviewTargetUnchanged", partner);
	}
}

stock void FakelagGetConsoleClientName(FakelagConsoleReport report, int client, char[] buffer, int maxlen, int maxWidth)
{
	char original[64];
	GetClientName(client, original, sizeof(original));
	ReplaceString(original, sizeof(original), "|", "/");
	ReplaceString(original, sizeof(original), "\n", " ");
	ReplaceString(original, sizeof(original), "\r", " ");

	char consoleSafe[64];
	int	 inputIndex			  = 0;
	int	 outputIndex		  = 0;
	int	 charCount			  = 0;
	bool truncated			  = false;
	bool hadMultibyteOrUnsafe = false;

	while (original[inputIndex] != '\0' && outputIndex < sizeof(consoleSafe) - 1)
	{
		if (charCount >= maxWidth)
		{
			truncated = true;
			break;
		}

		int charBytes = GetCharBytes(original[inputIndex]);
		if (charBytes > 1)
		{
			hadMultibyteOrUnsafe = true;
			inputIndex += charBytes;
			continue;
		}

		char ch = original[inputIndex];
		if (ch < ' ' || ch > '~')
		{
			hadMultibyteOrUnsafe = true;
		}
		else
		{
			consoleSafe[outputIndex++] = ch;
			charCount++;
		}

		inputIndex++;
	}

	if (original[inputIndex] != '\0')
	{
		truncated = true;
	}

	consoleSafe[outputIndex] = '\0';

	if (consoleSafe[0] == '\0' || hadMultibyteOrUnsafe)
	{
		FakelagRegisterConsoleLegendClient(report, client);
		Format(buffer, maxlen, "#%d", GetClientUserId(client));
		return;
	}

	if (!truncated || maxWidth <= 3)
	{
		strcopy(buffer, maxlen, consoleSafe);
		return;
	}

	int visibleLength = strlen(consoleSafe);
	if (visibleLength > maxWidth - 3)
	{
		consoleSafe[maxWidth - 3] = '\0';
	}

	Format(buffer, maxlen, "%s...", consoleSafe);
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
	if (!FakelagHasNetworkProfile(client))
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
			FakelagNotifyPairBalanceTarget(survivor, infected, 0.0);
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
			FakelagNotifyPairBalanceTarget(infected, survivor, 0.0);
			adjustedCount++;
			continue;
		}

		FakelagNotifyPairBalanceTarget(survivor, infected, 0.0);
		FakelagNotifyPairBalanceTarget(infected, survivor, 0.0);

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

stock void FakelagFormatGlobalBalanceConsoleTitle(FakelagConsoleReport report, int client, int initiator, int highestClient, float displayHighestPing, float highestPing, char[] buffer, int maxlen)
{
	char highestName[64];
	FakelagGetConsoleClientName(report, highestClient, highestName, sizeof(highestName), 24);

	SetGlobalTransTarget(client);
	if (initiator > 0)
	{
		char initiatorName[64];
		FakelagGetConsoleClientName(report, initiator, initiatorName, sizeof(initiatorName), 24);
		Format(buffer, maxlen, "%t", "BalanceConsoleTitleByAdmin", initiatorName, highestName, displayHighestPing, highestPing);
		return;
	}

	Format(buffer, maxlen, "%t", "BalanceConsoleTitle", highestName, displayHighestPing, highestPing);
}

stock void FakelagFormatPairBalanceConsoleTitle(FakelagConsoleReport report, int client, int initiator, int pairCount, char[] buffer, int maxlen)
{
	SetGlobalTransTarget(client);
	if (initiator > 0)
	{
		char initiatorName[64];
		FakelagGetConsoleClientName(report, initiator, initiatorName, sizeof(initiatorName), 24);
		Format(buffer, maxlen, "%t", "PairBalanceConsoleTitleByAdmin", initiatorName, pairCount);
		return;
	}

	Format(buffer, maxlen, "%t", "PairBalanceConsoleTitle", pairCount);
}

stock void FakelagApplyBalance(FakelagConsoleReport report, int admin, ConsolePanel panel, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int adjusted = 0;
	int cleared	 = 0;

	for (int index = 0; index < count; index++)
	{
		int	  target		= clients[index];
		float rawPing		= pings[index];
		float compensation	= targetPing - rawPing;
		float displayPing	= FakelagEstimateNetGraphPingForClientMs(target, rawPing);
		bool  clearedClient = false;

		if (compensation <= 0.0)
		{
			FakelagNotifyGlobalBalanceTarget(target, 0.0);

			if (FakelagHasNetworkProfile(target))
			{
				g_ForgetLatencyOnNextClear[target] = true;
				FakelagClearNetworkProfile(target);
				cleared++;
				clearedClient = true;
			}

			FakelagAddGlobalConsolePanelRow(panel, report, admin, target, displayPing, rawPing, clearedClient ? FakelagBalanceAction_Clear : FakelagBalanceAction_Same, compensation);
			continue;
		}

		FakelagApplyNetworkProfile(target, FakelagBuildNetworkProfile(compensation, FakelagResolvePacketLossPercent(rawPing, compensation, targetPing)));
		adjusted++;
		FakelagNotifyGlobalBalanceTarget(target, compensation);
		FakelagAddGlobalConsolePanelRow(panel, report, admin, target, displayPing, rawPing, FakelagBalanceAction_Adjust, compensation);
	}
}

stock void FakelagPreviewBalance(FakelagConsoleReport report, int admin, ConsolePanel panel, const int clients[MAXPLAYERS + 1], const float pings[MAXPLAYERS + 1], int count, float targetPing)
{
	int adjusted = 0;

	for (int index = 0; index < count; index++)
	{
		int	  target	   = clients[index];
		float rawPing	   = pings[index];
		float compensation = targetPing - rawPing;
		float displayPing  = FakelagEstimateNetGraphPingForClientMs(target, rawPing);

		if (compensation <= 0.0)
		{
			FakelagAddGlobalConsolePanelRow(panel, report, admin, target, displayPing, rawPing, FakelagHasNetworkProfile(target) ? FakelagBalanceAction_Clear : FakelagBalanceAction_Same, compensation);
			continue;
		}

		adjusted++;
		FakelagAddGlobalConsolePanelRow(panel, report, admin, target, displayPing, rawPing, FakelagBalanceAction_Adjust, compensation);
	}
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
			if (FakelagHasNetworkProfile(target))
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
	int					 targets[MAXPLAYERS + 1];
	float				 pings[MAXPLAYERS + 1];
	float				 highestPing;
	int					 highestClient;
	int					 count;
	bool				 consoleNoticeSent[MAXPLAYERS + 1];
	FakelagConsoleReport report;
	ConsolePanel		 panel;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return;
	}

	FakelagResetConsoleReport(report);
	float displayHighestPing = FakelagGetClientAveragePingMs(highestClient);
	char  formatted[512];
	FakelagFormatGlobalBalanceConsoleTitle(report, client, client, highestClient, displayHighestPing, highestPing, formatted, sizeof(formatted));
	FakelagInitializeGlobalConsolePanel(panel, report, client, formatted);

	for (int index = 0; index < count; index++)
	{
		consoleNoticeSent[targets[index]] = true;
	}

	FakelagApplyBalance(report, client, panel, targets, pings, count, highestPing);
	ConsolePanel_RenderToClient(panel, client);
	FakelagRenderConsolePanelToBalanceAudience(panel, client);

	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		if (audience == client)
		{
			continue;
		}

		if (consoleNoticeSent[audience])
		{
			continue;
		}

		CPrintToChat(audience, "%t %t", "Tag", "DetailsSentToTargetConsole");
	}

	if (client != 0 && !consoleNoticeSent[client])
	{
		CPrintToChat(client, "%t %t", "Tag", "DetailsSentToConsole");
	}
}

stock void FakelagRunBalancePreviewCommand(int client)
{
	int					 targets[MAXPLAYERS + 1];
	float				 pings[MAXPLAYERS + 1];
	float				 highestPing;
	int					 highestClient;
	int					 count;
	FakelagConsoleReport report;
	ConsolePanel		 panel;

	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return;
	}

	FakelagResetConsoleReport(report);
	float displayHighestPing = FakelagGetClientAveragePingMs(highestClient);
	char  formatted[512];
	bool  consoleNoticeSent[MAXPLAYERS + 1];
	FakelagFormatGlobalBalanceConsoleTitle(report, client, client, highestClient, displayHighestPing, highestPing, formatted, sizeof(formatted));
	FakelagInitializeGlobalConsolePanel(panel, report, client, formatted);

	for (int index = 0; index < count; index++)
	{
		consoleNoticeSent[targets[index]] = true;

		int	  target					  = targets[index];
		float rawPing					  = pings[index];
		float compensation				  = highestPing - rawPing;
		float displayPing				  = FakelagEstimateNetGraphPingForClientMs(target, rawPing);
		FakelagNotifyGlobalBalancePreviewTarget(target, client, compensation);
		FakelagAddGlobalConsolePanelRow(panel, report, client, target, displayPing, rawPing, FakelagHasNetworkProfile(target) ? FakelagBalanceAction_Clear : FakelagBalanceAction_Same, compensation);
	}

	int adjusted = 0;
	for (int index = 0; index < count; index++)
	{
		if (highestPing - pings[index] > 0.0)
		{
			adjusted++;
		}
	}

	ConsolePanel_RenderToClient(panel, client);
	FakelagRenderConsolePanelToBalanceAudience(panel, client);

	if (client == 0)
	{
		return;
	}

	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		if (audience == client)
		{
			continue;
		}

		if (consoleNoticeSent[audience])
		{
			continue;
		}

		CPrintToChat(audience, "%t %t", "Tag", "DetailsSentToTargetConsole");
	}

	if (!consoleNoticeSent[client])
	{
		CPrintToChat(client, "%t %t", "Tag", "PreviewSentToConsole");
	}
}

stock void FakelagRunPairBalanceCommand(int client)
{
	int					 survivorClients[MAXPLAYERS + 1];
	float				 survivorPings[MAXPLAYERS + 1];
	int					 infectedClients[MAXPLAYERS + 1];
	float				 infectedPings[MAXPLAYERS + 1];
	int					 survivorCount;
	int					 infectedCount;
	int					 pairCount;
	FakelagConsoleReport report;
	ConsolePanel		 panel;

	if (!FakelagPreparePairBalance(survivorClients, survivorPings, survivorCount, infectedClients, infectedPings, infectedCount, pairCount))
	{
		CPrintToChat(client, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}

	FakelagResetConsoleReport(report);
	report.innerWidth = FAKELAG_PAIR_TABLE_INNER_WIDTH;
	char formatted[512];
	bool consoleNoticeSent[MAXPLAYERS + 1];
	FakelagFormatPairBalanceConsoleTitle(report, client, client, pairCount, formatted, sizeof(formatted));
	FakelagInitializePairConsolePanel(panel, report, client, formatted);

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
		consoleNoticeSent[survivor] = true;
		consoleNoticeSent[infected] = true;

		if (compensation <= 0.0)
		{
			FakelagAddPairConsolePanelRow(panel, report, client, survivor, survivorDisplay, survivorRaw, infected, infectedDisplay, infectedRaw, FakelagBalanceAction_Same, compensation, 0);
		}
		else
		{
			int adjustedClient = survivorRaw < infectedRaw ? survivor : infected;
			FakelagAddPairConsolePanelRow(panel, report, client, survivor, survivorDisplay, survivorRaw, infected, infectedDisplay, infectedRaw, FakelagBalanceAction_Adjust, compensation, adjustedClient);
		}
	}

	for (int index = pairCount; index < survivorCount; index++)
	{
		float rawPing	  = survivorPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(survivorClients[index], rawPing);
		FakelagAddUnpairedConsolePanelRow(panel, report, client, survivorClients[index], displayPing, rawPing, true);
	}

	for (int index = pairCount; index < infectedCount; index++)
	{
		float rawPing	  = infectedPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(infectedClients[index], rawPing);
		FakelagAddUnpairedConsolePanelRow(panel, report, client, infectedClients[index], displayPing, rawPing, false);
	}

	int playerCount;
	int adjustedCount;
	int clearedCount;

	if (!FakelagApplyPairBalanceSilent(playerCount, pairCount, adjustedCount, clearedCount))
	{
		CPrintToChat(client, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}

	ConsolePanel_RenderToClient(panel, client);
	FakelagRenderConsolePanelToBalanceAudience(panel, client);

	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		if (audience == client)
		{
			continue;
		}

		if (consoleNoticeSent[audience])
		{
			continue;
		}

		CPrintToChat(audience, "%t %t", "Tag", "DetailsSentToTargetConsole");
	}

	if (client != 0 && !consoleNoticeSent[client])
	{
		CPrintToChat(client, "%t %t", "Tag", "DetailsSentToConsole");
		return;
	}
}

stock void FakelagRunPairBalancePreviewCommand(int client)
{
	int					 survivorClients[MAXPLAYERS + 1];
	float				 survivorPings[MAXPLAYERS + 1];
	int					 infectedClients[MAXPLAYERS + 1];
	float				 infectedPings[MAXPLAYERS + 1];
	int					 survivorCount;
	int					 infectedCount;
	int					 pairCount;
	FakelagConsoleReport report;
	ConsolePanel		 panel;

	if (!FakelagPreparePairBalance(survivorClients, survivorPings, survivorCount, infectedClients, infectedPings, infectedCount, pairCount))
	{
		CPrintToChat(client, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}

	FakelagResetConsoleReport(report);
	report.innerWidth = FAKELAG_PAIR_TABLE_INNER_WIDTH;
	char formatted[512];
	bool consoleNoticeSent[MAXPLAYERS + 1];
	FakelagFormatPairBalanceConsoleTitle(report, client, client, pairCount, formatted, sizeof(formatted));
	FakelagInitializePairConsolePanel(panel, report, client, formatted);

	int adjustedCount = 0;
	for (int index = 0; index < pairCount; index++)
	{
		int	  survivor				= survivorClients[index];
		int	  infected				= infectedClients[index];
		float survivorRaw			= survivorPings[index];
		float infectedRaw			= infectedPings[index];
		float survivorDisplay		= FakelagEstimateNetGraphPingForClientMs(survivor, survivorRaw);
		float infectedDisplay		= FakelagEstimateNetGraphPingForClientMs(infected, infectedRaw);
		float compensation			= FloatAbs(survivorRaw - infectedRaw);
		int	  adjustedClient		= survivorRaw < infectedRaw ? survivor : infected;
		consoleNoticeSent[survivor] = true;
		consoleNoticeSent[infected] = true;

		if (compensation > 0.0)
		{
			int partner = adjustedClient == survivor ? infected : survivor;
			FakelagNotifyPairBalancePreviewTarget(adjustedClient, partner, client, compensation);
			FakelagNotifyPairBalancePreviewTarget(partner, adjustedClient, client, 0.0);
		}
		else
		{
			FakelagNotifyPairBalancePreviewTarget(survivor, infected, client, 0.0);
			FakelagNotifyPairBalancePreviewTarget(infected, survivor, client, 0.0);
		}

		FakelagAddPairConsolePanelRow(panel, report, client, survivor, survivorDisplay, survivorRaw, infected, infectedDisplay, infectedRaw, compensation <= 0.0 ? FakelagBalanceAction_Same : FakelagBalanceAction_Adjust, compensation, adjustedClient);

		if (compensation > 0.0)
		{
			adjustedCount++;
		}
	}

	for (int index = pairCount; index < survivorCount; index++)
	{
		float rawPing	  = survivorPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(survivorClients[index], rawPing);
		FakelagAddUnpairedConsolePanelRow(panel, report, client, survivorClients[index], displayPing, rawPing, true);
	}

	for (int index = pairCount; index < infectedCount; index++)
	{
		float rawPing	  = infectedPings[index];
		float displayPing = FakelagEstimateNetGraphPingForClientMs(infectedClients[index], rawPing);
		FakelagAddUnpairedConsolePanelRow(panel, report, client, infectedClients[index], displayPing, rawPing, false);
	}

	ConsolePanel_RenderToClient(panel, client);
	FakelagRenderConsolePanelToBalanceAudience(panel, client);

	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (!FakelagIsBalanceAudienceClient(audience))
		{
			continue;
		}

		if (audience == client)
		{
			continue;
		}

		if (consoleNoticeSent[audience])
		{
			continue;
		}

		CPrintToChat(audience, "%t %t", "Tag", "DetailsSentToTargetConsole");
	}

	if (client == 0)
	{
		return;
	}

	if (!consoleNoticeSent[client])
	{
		CPrintToChat(client, "%t %t", "Tag", "PreviewSentToConsole");
	}
}
