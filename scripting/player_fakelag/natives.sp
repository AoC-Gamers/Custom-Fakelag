public int Native_ApplyBalance(Handle plugin, int numParams)
{
	float targetPing;
	int highestClient;
	int playerCount;
	int adjustedCount;
	int clearedCount;

	bool result = FakelagApplyBalanceSilent(targetPing, highestClient, playerCount, adjustedCount, clearedCount);
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
	int highestClient;
	int playerCount;

	bool result = FakelagPreviewBalanceSilent(targetPing, highestClient, playerCount);
	SetNativeCellRef(1, view_as<int>(targetPing));
	SetNativeCellRef(2, highestClient);
	SetNativeCellRef(3, playerCount);
	return result;
}

public int Native_StartBalanceVote(Handle plugin, int numParams)
{
	int initiator = numParams >= 1 ? GetNativeCell(1) : 0;

	if (initiator != 0 && (!IsClientInGame(initiator) || IsFakeClient(initiator)))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not a valid human initiator", initiator);
	}

	if (!FakelagCanStartBalanceVote(initiator))
	{
		return false;
	}

	float highestPing;
	int highestClient;
	int playerCount;
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
	FakelagGetBalanceVoteQuestion(voteQuestion, sizeof(voteQuestion));

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
		FakelagNotifyVoteAudience("FakelagBalanceVoteAnnounce", initiator);
	}
	else {
		FakelagNotifyVoteAudience("FakelagBalanceVoteStartedServer");
	}

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

public void CFakeLag_OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason)
{
	Call_StartForward(g_FwdOnPlayerLatencyChanged);
	Call_PushCell(client);
	Call_PushFloat(oldLag);
	Call_PushFloat(newLag);
	Call_PushCell(reason);
	Call_Finish();
}