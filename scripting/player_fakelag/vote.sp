stock bool FakelagCanUseBuiltinVotes()
{
	return GetFeatureStatus(FeatureType_Native, "CreateBuiltinVote") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "DisplayBuiltinVote") == FeatureStatus_Available;
}

stock bool FakelagTryCollectBalance(int client, int targets[MAXPLAYERS + 1], float pings[MAXPLAYERS + 1], float &highestPing, int &highestClient, int &count)
{
	count = FakelagCollectBalanceCandidates(targets, pings, highestPing, highestClient);
	if (count <= 0 || highestClient <= 0 || highestPing < 0.0)
	{
		CReplyToCommand(client, "%t %t", "Tag", "BalanceNoPlayers");
		return false;
	}

	return true;
}

stock bool FakelagCanStartBalanceVote(int client)
{
	if (!FakelagCanUseBuiltinVotes())
	{
		CReplyToCommand(client, "%t %t", "Tag", "BalanceVoteUnavailable");
		return false;
	}

	if (!IsNewBuiltinVoteAllowed() || g_FakeLagBalanceVote != null)
	{
		int delay = CheckBuiltinVoteDelay();
		if (delay > 0)
		{
			CReplyToCommand(client, "%t %t", "Tag", "BalanceVoteDelay", delay);
			return false;
		}

		CReplyToCommand(client, "%t %t", "Tag", "BalanceVoteInProgress");
		return false;
	}

	return true;
}

stock bool FakelagCanStartGlobalBalanceVote(int client)
{
	int	  targets[MAXPLAYERS + 1];
	float pings[MAXPLAYERS + 1];
	float highestPing;
	int	  highestClient;
	int	  count;
	if (!FakelagTryCollectBalance(client, targets, pings, highestPing, highestClient, count))
	{
		return false;
	}

	return FakelagCanStartBalanceVote(client);
}

stock bool FakelagCanStartPairBalanceVote(int client)
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
		return false;
	}

	return FakelagCanStartBalanceVote(client);
}

stock void FakelagStartBalanceVote(int initiator, int mode, const char[] questionPhrase, const char[] announcePhrase, const char[] startedPhrase)
{
	Handle vote = CreateBuiltinVote(FakeLagBalanceVoteHandler, BuiltinVoteType_Custom_YesNo, BUILTINVOTE_ACTIONS_DEFAULT);
	if (vote == null)
	{
		CReplyToCommand(initiator, "%t %t", "Tag", "BalanceVoteUnavailable");
		return;
	}

	char voteQuestion[128];
	Format(voteQuestion, sizeof(voteQuestion), "%T", questionPhrase, LANG_SERVER);

	g_BalanceVoteMode	 = mode;
	g_FakeLagBalanceVote = vote;
	SetBuiltinVoteArgument(vote, voteQuestion);
	SetBuiltinVoteInitiator(vote, initiator);
	SetBuiltinVoteResultCallback(vote, FakeLagBalanceVoteResultHandler);

	if (!DisplayBuiltinVoteToAllNonSpectators(vote, 20))
	{
		g_BalanceVoteMode	 = 0;
		g_FakeLagBalanceVote = null;
		delete vote;
		CReplyToCommand(initiator, "%t %t", "Tag", "BalanceVoteInProgress");
		return;
	}

	FakeClientCommand(initiator, "Vote Yes");
	FakelagNotifyVoteAudience(announcePhrase, initiator);
	CPrintToChat(initiator, "%t %t", "Tag", startedPhrase);
}

stock void FakelagNotifyVoteAudience(const char[] phrase, int initiator = 0)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!FakelagIsBalanceAudienceClient(client))
		{
			continue;
		}

		if (initiator > 0 && client == initiator)
		{
			continue;
		}

		if (initiator > 0)
		{
			CPrintToChat(client, "%t %t", "Tag", phrase, initiator);
			continue;
		}

		CPrintToChat(client, "%t %t", "Tag", phrase);
	}
}

public void FakeLagBalanceVoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	if (action != BuiltinVoteAction_End)
	{
		return;
	}

	if (g_FakeLagBalanceVote == vote)
	{
		g_FakeLagBalanceVote = null;
		g_BalanceVoteMode	 = 0;
	}

	delete vote;
}

public void FakeLagBalanceVoteResultHandler(Handle vote, int numVotes, int numClients, const int[][] clientInfo, int numItems, const int[][] itemInfo)
{
	if (numItems < 1 || itemInfo[0][BUILTINVOTEINFO_ITEM_INDEX] != BUILTINVOTES_VOTE_YES)
	{
		if (g_BalanceVoteMode == 1)
		{
			FakelagNotifyVoteAudience("PairBalanceVoteFailed");
		}
		else
		{
			FakelagNotifyVoteAudience("BalanceVoteFailed");
		}

		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
		return;
	}

	char votePassed[128];
	// DisplayBuiltinVotePass also needs pre-rendered text instead of a translation key.
	if (g_BalanceVoteMode == 1)
	{
		FakelagNotifyVoteAudience("PairBalanceVotePassed");
		Format(votePassed, sizeof(votePassed), "%T", "PairBalanceVotePassedTitle", LANG_SERVER);
	}
	else
	{
		FakelagNotifyVoteAudience("BalanceVotePassed");
		Format(votePassed, sizeof(votePassed), "%T", "BalanceVotePassedTitle", LANG_SERVER);
	}

	DisplayBuiltinVotePass(vote, votePassed);
	if (g_BalanceVoteMode == 1)
	{
		FakelagRunPairBalanceCommand(0);
		return;
	}

	FakelagRunBalanceCommand(0);
}
