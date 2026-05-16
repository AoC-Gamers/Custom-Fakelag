

public int Native_ApplyBalance(Handle plugin, int numParams)
{
	float targetPing;
	int	  highestClient;
	int	  playerCount;
	int	  adjustedCount;
	int	  clearedCount;

	bool  result = FakelagApplyBalanceSilent(targetPing, highestClient, playerCount, adjustedCount, clearedCount);
	SetNativeCellRef(1, view_as<int>(targetPing));
	SetNativeCellRef(2, highestClient);
	SetNativeCellRef(3, playerCount);
	SetNativeCellRef(4, adjustedCount);
	SetNativeCellRef(5, clearedCount);
	return result;
}

public int Native_PreviewBalance(Handle plugin, int numParams)
{
	float targetPing;
	int	  highestClient;
	int	  playerCount;

	bool  result = FakelagPreviewBalanceSilent(targetPing, highestClient, playerCount);
	SetNativeCellRef(1, view_as<int>(targetPing));
	SetNativeCellRef(2, highestClient);
	SetNativeCellRef(3, playerCount);
	return result;
}

public int Native_StartBalanceVote(Handle plugin, int numParams)
{
	int initiator = numParams >= 1 ? GetNativeCell(1) : 0;

	if (initiator != 0 && !IsHumanInGame(initiator))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not a valid human initiator", initiator);
	}

	if (!FakelagCanStartBalanceVote(initiator))
	{
		return false;
	}

	float highestPing;
	int	  highestClient;
	int	  playerCount;
	if (!FakelagPreviewBalanceSilent(highestPing, highestClient, playerCount))
	{
		return false;
	}

	Handle vote = CreateBuiltinVote(FakeLagBalanceVoteHandler, BuiltinVoteType_Custom_YesNo, BUILTINVOTE_ACTIONS_DEFAULT);
	if (vote == null)
	{
		return false;
	}

	char voteQuestion[128];
	// BuiltinVotes expects the final text here; phrase keys are not localized at render time.
	Format(voteQuestion, sizeof(voteQuestion), "%T", "BalanceVoteQuestion", LANG_SERVER);

	g_FakeLagBalanceVote = vote;
	SetBuiltinVoteArgument(vote, voteQuestion);
	SetBuiltinVoteInitiator(vote, initiator == 0 ? BUILTINVOTES_SERVER_INDEX : initiator);
	SetBuiltinVoteResultCallback(vote, FakeLagBalanceVoteResultHandler);

	if (!DisplayBuiltinVoteToAllNonSpectators(vote, 20))
	{
		g_FakeLagBalanceVote = null;
		delete vote;
		return false;
	}

	if (initiator > 0)
	{
		FakeClientCommand(initiator, "Vote Yes");
	}

	if (initiator > 0)
	{
		FakelagNotifyVoteAudience("BalanceVoteAnnounce", initiator);
		return true;
	}

	FakelagNotifyVoteAudience("BalanceVoteStartedServer");

	return true;
}

public int Native_IsBalanceVoteInProgress(Handle plugin, int numParams)
{
	return g_FakeLagBalanceVote != null;
}

public Action CFakeLag_OnSetPlayerLatency(int client, float oldLag, float &newLag, CFakeLagChangeReason reason)
{
	Action result = Plugin_Continue;

	Call_StartForward(g_FwdOnSetPlayerLatency);
	Call_PushCell(client);
	Call_PushFloat(oldLag);
	Call_PushFloatRef(newLag);
	Call_PushCell(reason);
	Call_Finish(result);

	return result;
}

public void CFakeLag_OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason)
{
	if (oldLag != newLag)
	{
		FakelagResetClientLatencySamples(client);
	}

	if (newLag > 0.0 || newPacketLossPercent > 0)
	{
		FakelagStoreProfileForClient(client, newLag, newPacketLossPercent);
		if (reason != CFakeLagChange_Disconnect)
		{
			FakelagSetDisconnectedState(client, false);
		}
	}
	else if (g_ForgetLatencyOnNextClear[client])
	{
		g_ForgetLatencyOnNextClear[client] = false;
		FakelagForgetStoredLatency(client);
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Cleared persisted fakelag for %L due to explicit clear command", client);
		}
	}
	else if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Preserved persisted fakelag for %L while active latency was cleared implicitly (reason=%d)", client, reason);
	}

	Call_StartForward(g_FwdOnPlayerProfileChanged);
	Call_PushCell(client);
	Call_PushFloat(oldLag);
	Call_PushCell(oldPacketLossPercent);
	Call_PushFloat(newLag);
	Call_PushCell(newPacketLossPercent);
	Call_PushCell(reason);
	Call_Finish();
}
