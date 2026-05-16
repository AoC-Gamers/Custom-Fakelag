stock void FakelagReplyPlayerStatus(int client, int target)
{
	if (!CFakeLag_IsClientSupported(target))
	{
		CReplyToCommand(client, "%t %t", "Tag", "PlayerInvalidHumanTarget", target);
		return;
	}

	float averagePingRaw	 = FakelagGetClientAveragePingRawMs(target);
	float averagePingDisplay = FakelagEstimateNetGraphPingForClientMs(target, averagePingRaw);
	float fakeLag			 = FakelagGetAppliedLagMs(target);
	int   packetLossPercent  = FakelagGetAppliedPacketLossPercent(target);
	bool  isLagged			 = FakelagHasNetworkProfile(target);
	int   averagePingDisplayInt = RoundToNearest(averagePingDisplay);
	int   averagePingRawInt = RoundToNearest(averagePingRaw);
	int   fakeLagInt = RoundToNearest(fakeLag);

	if (!isLagged)
	{
		CPrintToChat(client, "%t %t", "Tag", "StatusDisabled", target, averagePingDisplayInt, averagePingRawInt);
		return;
	}

	CPrintToChat(client, "%t %t", "Tag", "StatusEnabled", target, averagePingDisplayInt, averagePingRawInt, fakeLagInt, packetLossPercent);
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
	int   firstDisplayInt = RoundToNearest(firstDisplay);
	int   secondDisplayInt = RoundToNearest(secondDisplay);
	int   differenceInt = RoundToNearest(difference);

	CPrintToChat(client, "%t %t", "Tag", "CompareResult", firstTarget, firstDisplayInt, secondTarget, secondDisplayInt, differenceInt);
	CReplyToCommand(client, "%t %t", "Tag", "CompareResult", firstTarget, firstDisplay, secondTarget, secondDisplay, difference);

	if (difference <= 0.0)
	{
		return;
	}

	int higherTarget = firstRaw >= secondRaw ? firstTarget : secondTarget;
	CPrintToChat(client, "%t %t", "Tag", "CompareHigher", higherTarget, differenceInt);
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

stock void FakelagGetPacketLossModeName(int client, CFakeLagPacketLossMode mode, char[] buffer, int maxlen)
{
	switch (mode)
	{
		case CFakeLagPacketLoss_GilbertElliott:
		{
			Format(buffer, maxlen, "%T", "PacketLossModeGilbertElliott", client);
		}
		default:
		{
			Format(buffer, maxlen, "%T", "PacketLossModeBernoulli", client);
		}
	}
}

stock void FakelagQueueApplyDefaultPacketLossMode()
{
	if (g_DefaultPacketLossModeApplyQueued)
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Default packet loss mode apply already queued");
		}
		return;
	}

	g_DefaultPacketLossModeApplyQueued = true;
	RequestFrame(FakelagApplyDefaultPacketLossModeOnNextFrame);
}

void FakelagApplyDefaultPacketLossModeOnNextFrame(any data)
{
	g_DefaultPacketLossModeApplyQueued = false;
	FakelagApplyDefaultPacketLossMode();
}

stock void FakelagApplyDefaultPacketLossMode()
{
	if (g_CvarDefaultPacketLossMode == null)
	{
		return;
	}

	CFakeLagPacketLossMode mode = view_as<CFakeLagPacketLossMode>(g_CvarDefaultPacketLossMode.IntValue);
	CFakeLagPacketLossMode currentMode = CFakeLag_GetPacketLossMode();
	if (currentMode == mode)
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Packet loss mode already matches default (%d); skipping mode-change flow", view_as<int>(mode));
		}
		return;
	}

	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Applying default packet loss mode change: current=%d target=%d", view_as<int>(currentMode), view_as<int>(mode));
	}

	if (FakelagGetActiveProfileCount() <= 0)
	{
		ConVar extensionLossModeCvar = FindConVar("sm_custom_fakelag_loss_mode");
		if (extensionLossModeCvar != null)
		{
			if (FakelagIsDebugEnabled())
			{
				LogMessage("[player_fakelag] No active profiles; setting sm_custom_fakelag_loss_mode directly to %d", view_as<int>(mode));
			}

			extensionLossModeCvar.IntValue = view_as<int>(mode);
			return;
		}

		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] sm_custom_fakelag_loss_mode cvar not found; falling back to native mode change");
		}
	}

	FakelagSnapshotProfilesForModeChange();
	CFakeLag_SetPacketLossMode(mode);
	FakelagQueueModeChangeRestore();
}

stock void FakelagSnapshotProfilesForModeChange()
{
	g_ModeChangeRestorePending = false;
	int snapshotCount = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		g_ModeChangeRestoreLag[client] = 0.0;
		g_ModeChangeRestoreLoss[client] = 0;
		g_ModeChangeRestoreUserId[client] = 0;

		if (!IsHumanInGame(client))
		{
			continue;
		}

		PlayerNetworkProfile profile;
		if (!FakelagGetNetworkProfile(client, profile))
		{
			continue;
		}

		if (profile.lagMs <= 0.0)
		{
			continue;
		}

		g_ModeChangeRestoreLag[client] = profile.lagMs;
		g_ModeChangeRestoreLoss[client] = profile.packetLossPercent;
		g_ModeChangeRestoreUserId[client] = GetClientUserId(client);
		g_ModeChangeRestorePending = true;
		snapshotCount++;

		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Snapshot fakelag profile for %L before mode change: lag=%.1fms loss=%d%% userid=%d", client, profile.lagMs, profile.packetLossPercent, g_ModeChangeRestoreUserId[client]);
		}
	}

	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Mode-change snapshot completed: %d active profile(s) captured", snapshotCount);
	}
}

stock void FakelagQueueModeChangeRestore()
{
	if (!g_ModeChangeRestorePending)
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] No active fakelag profiles to restore after mode change");
		}
		return;
	}

	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Scheduling mode-change profile restore on next frame");
	}

	RequestFrame(FakelagRestoreProfilesAfterModeChange);
}

void FakelagRestoreProfilesAfterModeChange(any data)
{
	int restoredCount = 0;
	int skippedCount = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		float lagMs = g_ModeChangeRestoreLag[client];
		int packetLossPercent = g_ModeChangeRestoreLoss[client];
		int userId = g_ModeChangeRestoreUserId[client];

		g_ModeChangeRestoreLag[client] = 0.0;
		g_ModeChangeRestoreLoss[client] = 0;
		g_ModeChangeRestoreUserId[client] = 0;

		if (lagMs <= 0.0 || userId <= 0)
		{
			continue;
		}

		int currentClient = GetClientOfUserId(userId);
		if (currentClient <= 0 || !FakelagCanApplyLatencyToClient(currentClient))
		{
			skippedCount++;
			if (FakelagIsDebugEnabled())
			{
				LogMessage("[player_fakelag] Skipped mode-change restore for userid=%d: client unavailable or ineligible", userId);
			}
			continue;
		}

		FakelagApplyNetworkProfile(currentClient, FakelagBuildNetworkProfile(lagMs, packetLossPercent));
		restoredCount++;
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restored profile after mode change for %L: lag=%.1fms loss=%d%%", currentClient, lagMs, packetLossPercent);
		}
	}

	g_ModeChangeRestorePending = false;
	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Mode-change restore finished: restored=%d skipped=%d", restoredCount, skippedCount);
	}
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
