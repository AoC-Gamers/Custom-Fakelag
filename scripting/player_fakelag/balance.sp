stock void FakelagGetConsoleClientName(int client, char[] buffer, int maxlen, int maxWidth)
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

stock bool FakelagClearPlayerLatencyExplicit(int client, int &adjusted, int &cleared)
{
	PlayerNetworkProfile effective;
	if (FakelagClearNetworkProfileResult(client, effective, true) != FakelagProfile_Changed) return false;
	if (FakelagProfileIsActive(effective)) adjusted++;
	else cleared++;
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

// One selection and one proposed profile per session. Observations are taken
// immediately after each native, then checked again before reporting. A later
// forward that invalidates an observation makes it unavailable, never zero.
enum struct FakelagBalanceParticipant
{
	int client;
	int userId;
	int partner; // Index in the operation, -1 for an unpaired/global participant.
	char name[64];
	char originalName[64];
	float rawPing;
	float displayPing;
	PlayerNetworkProfile proposed;
	PlayerNetworkProfile effective;
	FakelagProfileResult result;
}

enum struct FakelagBalanceOperation
{
	FakelagBalanceParticipant participants[MAXPLAYERS + 1];
	int count;
	int pairCount;
	int epoch;
	int highestClient;
	float targetPing;
	bool pairs;
	bool complete;
	int adjusted;
	int cleared;
	int unchanged;
	int unavailable;
}

stock void FakelagAddBalanceParticipant(FakelagBalanceOperation operation, int client, float rawPing, float targetPing)
{
	int index = operation.count++;
	operation.participants[index].client = client;
	operation.participants[index].userId = GetClientUserId(client);
	operation.participants[index].partner = -1;
	operation.participants[index].rawPing = rawPing;
	operation.participants[index].displayPing = FakelagEstimateNetGraphPingForClientMs(client, rawPing);
	operation.participants[index].result = FakelagProfile_Unavailable;
	float lag = targetPing > rawPing ? targetPing - rawPing : 0.0;
	operation.participants[index].proposed = FakelagBuildNetworkProfile(lag, FakelagResolvePacketLossPercent(rawPing, lag, targetPing));

	char safe[64], identity[16];
	IntToString(operation.participants[index].userId, identity, sizeof(identity));
	int nameWidth = 17 - 1 - strlen(identity);
	if (nameWidth > 10) nameWidth = 10;
	FakelagGetConsoleClientName(client, safe, sizeof(safe), nameWidth);
	if (safe[0] == '#') strcopy(operation.participants[index].name, 64, safe);
	else Format(operation.participants[index].name, 64, "%s#%d", safe, operation.participants[index].userId);
	GetClientName(client, operation.participants[index].originalName, 64);
	ReplaceString(operation.participants[index].originalName, 64, "|", "/");
	ReplaceString(operation.participants[index].originalName, 64, "\n", " ");
	ReplaceString(operation.participants[index].originalName, 64, "\r", " ");
}

stock bool FakelagPrepareBalanceOperation(FakelagBalanceOperation operation, bool pairs, bool preview = false)
{
	operation.count = operation.pairCount = 0;
	operation.adjusted = operation.cleared = operation.unchanged = operation.unavailable = 0;
	operation.pairs = pairs;
	operation.complete = false;
	operation.epoch = g_Runtime.intentEpoch;
	operation.highestClient = 0;
	operation.targetPing = 0.0;
	if (g_Runtime.clearingIntent || (!preview && CFakeLag_IsLanBlocked())) return false;
	int clients[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	if (!pairs)
	{
		int count = FakelagCollectBalanceCandidates(clients, pings, operation.targetPing, operation.highestClient);
		for (int index = 0; index < count; index++) FakelagAddBalanceParticipant(operation, clients[index], pings[index], operation.targetPing);
		return count > 0;
	}

	int infected[MAXPLAYERS + 1];
	float infectedPings[MAXPLAYERS + 1];
	int survivorCount, infectedCount;
	if (!FakelagPreparePairBalance(clients, pings, survivorCount, infected, infectedPings, infectedCount, operation.pairCount)) return false;
	for (int index = 0; index < operation.pairCount; index++)
	{
		float target = pings[index] > infectedPings[index] ? pings[index] : infectedPings[index];
		int first = operation.count;
		FakelagAddBalanceParticipant(operation, clients[index], pings[index], target);
		FakelagAddBalanceParticipant(operation, infected[index], infectedPings[index], target);
		operation.participants[first].partner = first + 1;
		operation.participants[first + 1].partner = first;
	}
	for (int index = operation.pairCount; index < survivorCount; index++) FakelagAddBalanceParticipant(operation, clients[index], pings[index], pings[index]);
	for (int index = operation.pairCount; index < infectedCount; index++) FakelagAddBalanceParticipant(operation, infected[index], infectedPings[index], infectedPings[index]);
	return true;
}

stock bool FakelagBalanceSessionIsCurrent(const FakelagBalanceOperation operation, int index)
{
	int client = operation.participants[index].client;
	if (operation.epoch != g_Runtime.intentEpoch || GetClientOfUserId(operation.participants[index].userId) != client
		|| !FakelagCanApplyLatencyToClient(client)) return false;
	int partner = operation.participants[index].partner;
	return partner < 0 || GetClientOfUserId(operation.participants[partner].userId) == operation.participants[partner].client;
}

stock void FakelagCountBalanceResults(FakelagBalanceOperation operation)
{
	operation.adjusted = operation.cleared = operation.unchanged = operation.unavailable = 0;
	operation.complete = true;
	for (int index = 0; index < operation.count; index++)
	{
		switch (operation.participants[index].result)
		{
			case FakelagProfile_Changed:
			{
				if (FakelagProfileIsActive(operation.participants[index].effective)) operation.adjusted++;
				else operation.cleared++;
			}
			case FakelagProfile_Unchanged: operation.unchanged++;
			default:
			{
				operation.unavailable++;
				operation.complete = false;
			}
		}
	}
}

stock bool FakelagApplyBalanceOperation(FakelagBalanceOperation operation)
{
	for (int step = 0; step < operation.count; step++)
	{
		int index = step;
		// Preserve the balancer's original order: clear the higher-ping member
		// before adjusting the lower one, while retaining S/I report order.
		if (operation.pairs && step < operation.pairCount * 2)
		{
			int first = step - (step % 2);
			if (operation.participants[first + 1].rawPing > operation.participants[first].rawPing)
				index = step % 2 == 0 ? first + 1 : first;
		}
		if (operation.epoch != g_Runtime.intentEpoch || CFakeLag_IsLanBlocked() || g_Runtime.clearingIntent) break;
		if (!FakelagBalanceSessionIsCurrent(operation, index)) continue;
		int client = operation.participants[index].client;
		if (FakelagProfileIsActive(operation.participants[index].proposed))
		{
			operation.participants[index].result = FakelagApplyNetworkProfile(client, operation.participants[index].proposed, operation.participants[index].effective);
		}
		else operation.participants[index].result = FakelagClearNetworkProfileResult(client, operation.participants[index].effective, true);
		// An unavailable post-forward observation cannot authorize the rest of
		// the old operation. Normal vetoes remain observable unchanged states.
		if (operation.participants[index].result == FakelagProfile_Unavailable) break;
	}
	// Do not attribute a captured result to a replacement session, or claim an
	// earlier observation still holds after a later forward reset/modified it.
	for (int index = 0; index < operation.count; index++)
	{
		if (!FakelagBalanceSessionIsCurrent(operation, index)) operation.participants[index].result = FakelagProfile_Unavailable;
		if (operation.participants[index].result == FakelagProfile_Unavailable) continue;
		PlayerNetworkProfile current;
		FakelagGetNetworkProfile(operation.participants[index].client, current);
		if (!FakelagProfilesEqual(current, operation.participants[index].effective)) operation.participants[index].result = FakelagProfile_Unavailable;
	}
	FakelagCountBalanceResults(operation);
	return operation.complete;
}

stock void FakelagNotifyBalanceResults(const FakelagBalanceOperation operation)
{
	for (int index = 0; index < operation.count; index++)
	{
		if (operation.participants[index].result != FakelagProfile_Changed || !FakelagBalanceSessionIsCurrent(operation, index)) continue;
		int client = operation.participants[index].client;
		if (!FakelagProfileIsActive(operation.participants[index].effective)) CPrintToChat(client, "%t %t", "Tag", "TargetSelfCleared");
		else
		{
			char lag[24];
			Format(lag, sizeof(lag), "%.1f", operation.participants[index].effective.lagMs);
			CPrintToChat(client, "%t %t", "Tag", "BalanceObservedProfile", lag, operation.participants[index].effective.packetLossPercent);
		}
	}
}

stock void FakelagInitializeBalancePanel(ConsolePanel panel, const FakelagBalanceOperation operation, int audience, bool preview)
{
	ConsolePanel_Reset(panel);
	ConsolePanel_SetWidth(panel, operation.pairs ? 96 : 76);
	char text[128];
	Format(text, sizeof(text), "%T", operation.pairs ? "BalancePairsReport" : "BalanceGlobalReport", audience);
	ConsolePanel_AddHeaderLine(panel, text);
	Format(text, sizeof(text), "%T", preview ? "BalanceProposalHeader" : "BalanceObservationHeader", audience);
	ConsolePanel_AddHeaderLine(panel, text);
	if (!preview && !operation.complete)
	{
		Format(text, sizeof(text), "%T", "BalanceReportPartial", audience);
		ConsolePanel_AddHeaderLine(panel, text);
	}
	// Both participants receive their own result row. Profile values have their
	// own typed columns, so zero latency with positive loss remains visible.
	char keys[7][32] = {"ConsoleColumnPlayer", "ConsoleColumnPartner", "ConsoleColumnAvg", "ConsoleColumnRaw", "ConsoleColumnResult", "ConsoleColumnLag", "ConsoleColumnLoss"};
	int widths[7] = {17, 17, 5, 5, 19, 7, 5};
	for (int column = 0; column < 7; column++)
	{
		if (column == 1 && !operation.pairs) continue;
		Format(text, sizeof(text), "%T", keys[column], audience);
		ConsoleTable_AddColumn(panel.table, text, widths[column], column >= 2 && column != 4 ? ConsoleTableAlignment_Right : ConsoleTableAlignment_Left, column == 6 ? ConsoleTableCellType_Int : (column >= 2 && column != 4 ? ConsoleTableCellType_Float : ConsoleTableCellType_String));
	}
	Format(text, sizeof(text), "%T", "BalanceTableLegendAvg", audience); ConsolePanel_AddFooterLine(panel, text);
	Format(text, sizeof(text), "%T", "BalanceTableLegendRaw", audience); ConsolePanel_AddFooterLine(panel, text);
	if (preview)
	{
		Format(text, sizeof(text), "%T", "BalanceProposalFooter", audience);
		ConsolePanel_AddFooterLine(panel, text);
	}
	else
	{
		Format(text, sizeof(text), "%T", "BalanceObservedCounts", audience, operation.adjusted, operation.cleared);
		ConsolePanel_AddFooterLine(panel, text);
		Format(text, sizeof(text), "%T", "BalanceUnchangedCounts", audience, operation.unchanged, operation.unavailable);
		ConsolePanel_AddFooterLine(panel, text);
	}
}

stock void FakelagAddBalanceResultRow(ConsolePanel panel, const FakelagBalanceOperation operation, int index, int audience, bool preview)
{
	ConsoleTable_BeginRow(panel.table);
	ConsoleTable_AddStringCell(panel.table, operation.participants[index].name);
	if (operation.pairs)
	{
		int partner = operation.participants[index].partner;
		ConsoleTable_AddStringCell(panel.table, partner < 0 ? "-" : operation.participants[partner].name);
	}
	ConsoleTable_AddFloatCell(panel.table, operation.participants[index].displayPing, 1);
	ConsoleTable_AddFloatCell(panel.table, operation.participants[index].rawPing, 1);
	char action[64];
	PlayerNetworkProfile profile;
	bool available = preview || operation.participants[index].result != FakelagProfile_Unavailable;
	if (preview)
	{
		profile = operation.participants[index].proposed;
		Format(action, sizeof(action), "%T", FakelagProfileIsActive(profile) ? "BalanceProposeProfile" : "BalanceProposeEmpty", audience);
	}
	else
	{
		profile = operation.participants[index].effective;
		char key[32];
		if (!available) strcopy(key, sizeof(key), "BalanceResultUnavailable");
		else if (operation.participants[index].result == FakelagProfile_Unchanged) strcopy(key, sizeof(key), "BalanceResultUnchanged");
		else strcopy(key, sizeof(key), FakelagProfileIsActive(profile) ? "BalanceResultAdjusted" : "BalanceResultCleared");
		Format(action, sizeof(action), "%T", key, audience);
	}
	ConsoleTable_AddStringCell(panel.table, action);
	if (available)
	{
		ConsoleTable_AddFloatCell(panel.table, profile.lagMs, 1);
		ConsoleTable_AddIntCell(panel.table, profile.packetLossPercent);
	}
	else
	{
		ConsoleTable_AddStringCell(panel.table, "-");
		ConsoleTable_AddStringCell(panel.table, "-");
	}
	ConsoleTable_EndRow(panel.table);
}

stock void FakelagRenderBalanceOperation(const FakelagBalanceOperation operation, int audience, bool preview)
{
	ConsolePanel panel;
	// Pagination preserves every participant without changing the table library.
	for (int first = 0; first < operation.count; first += CONSOLE_TABLE_MAX_ROWS)
	{
		FakelagInitializeBalancePanel(panel, operation, audience, preview);
		for (int index = first; index < operation.count && index < first + CONSOLE_TABLE_MAX_ROWS; index++)
		{
			FakelagAddBalanceResultRow(panel, operation, index, audience, preview);
			if (operation.participants[index].name[0] == '#')
			{
				char legend[128];
				Format(legend, sizeof(legend), "#%d = %s", operation.participants[index].userId, operation.participants[index].originalName);
				ConsolePanel_AddFooterUtf8Line(panel, legend);
			}
		}
		ConsolePanel_RenderToClient(panel, audience);
	}
}

stock void FakelagRunBalanceReport(int initiator, bool pairs, bool preview)
{
	FakelagBalanceOperation operation;
	if (!FakelagPrepareBalanceOperation(operation, pairs, preview))
	{
		CReplyToCommand(initiator, "%t %t", "Tag", "BalanceNoPlayers");
		return;
	}
	int initiatorId = initiator > 0 ? GetClientUserId(initiator) : 0;
	if (!preview)
	{
		FakelagApplyBalanceOperation(operation); // Native errors abort before any report.
		if (operation.epoch != g_Runtime.intentEpoch || CFakeLag_IsLanBlocked())
		{
			if (initiator == 0 || GetClientOfUserId(initiatorId) == initiator) CReplyToCommand(initiator, "%t %t", "Tag", "BalanceReportInterrupted");
			return;
		}
		FakelagNotifyBalanceResults(operation);
	}
	if (initiator == 0 || GetClientOfUserId(initiatorId) == initiator) FakelagRenderBalanceOperation(operation, initiator, preview);
	for (int audience = 1; audience <= MaxClients; audience++)
	{
		if (audience == initiator || !FakelagIsBalanceAudienceClient(audience)) continue;
		FakelagRenderBalanceOperation(operation, audience, preview);
	}
}

stock bool FakelagApplyBalanceSilent(float &targetPing, int &highestClient, int &playerCount, int &adjustedCount, int &clearedCount)
{
	FakelagBalanceOperation operation;
	bool prepared = FakelagPrepareBalanceOperation(operation, false);
	bool result = prepared && FakelagApplyBalanceOperation(operation);
	targetPing = operation.targetPing;
	highestClient = operation.highestClient;
	playerCount = operation.count;
	adjustedCount = operation.adjusted;
	clearedCount = operation.cleared;
	return result;
}

stock bool FakelagApplyPairBalanceSilent(int &playerCount, int &pairCount, int &adjustedCount, int &clearedCount)
{
	FakelagBalanceOperation operation;
	bool result = FakelagPrepareBalanceOperation(operation, true) && FakelagApplyBalanceOperation(operation);
	playerCount = operation.count;
	pairCount = operation.pairCount;
	adjustedCount = operation.adjusted;
	clearedCount = operation.cleared;
	return result;
}

stock bool FakelagPreviewBalanceSilent(float &targetPing, int &highestClient, int &playerCount)
{
	FakelagBalanceOperation operation;
	bool result = FakelagPrepareBalanceOperation(operation, false, true);
	targetPing = operation.targetPing;
	highestClient = operation.highestClient;
	playerCount = operation.count;
	return result;
}

stock void FakelagRunBalanceCommand(int client) { FakelagRunBalanceReport(client, false, false); }
stock void FakelagRunPairBalanceCommand(int client) { FakelagRunBalanceReport(client, true, false); }
stock void FakelagRunBalancePreviewCommand(int client) { FakelagRunBalanceReport(client, false, true); }
stock void FakelagRunPairBalancePreviewCommand(int client) { FakelagRunBalanceReport(client, true, true); }
