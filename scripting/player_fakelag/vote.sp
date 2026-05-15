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
		CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceNoPlayers");
		return false;
	}

	return true;
}

stock bool FakelagCanStartBalanceVote(int client)
{
	if (!FakelagCanUseBuiltinVotes())
	{
		CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceVoteUnavailable");
		return false;
	}

	if (!IsNewBuiltinVoteAllowed() || g_FakeLagBalanceVote != null)
	{
		int delay = CheckBuiltinVoteDelay();
		if (delay > 0)
		{
			CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceVoteDelay", delay);
			return false;
		}

		CReplyToCommand(client, "%t %t", "Tag", "FakelagBalanceVoteInProgress");
		return false;
	}

	return true;
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
			CReplyToCommand(client, "%t %t", "Tag", phrase, initiator);
			continue;
		}

		CReplyToCommand(client, "%t %t", "Tag", phrase);
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
	}

	delete vote;
}

public void FakeLagBalanceVoteResultHandler(Handle vote, int numVotes, int numClients, const int[][] clientInfo, int numItems, const int[][] itemInfo)
{
	if (numItems < 1 || itemInfo[0][BUILTINVOTEINFO_ITEM_INDEX] != BUILTINVOTES_VOTE_YES)
	{
		FakelagNotifyVoteAudience("FakelagBalanceVoteFailed");
		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
		return;
	}

	FakelagNotifyVoteAudience("FakelagBalanceVotePassed");
	char votePassed[128];
	// DisplayBuiltinVotePass also needs pre-rendered text instead of a translation key.
	Format(votePassed, sizeof(votePassed), "%T", "FakelagBalanceVotePassedTitle", LANG_SERVER);
	DisplayBuiltinVotePass(vote, votePassed);
	FakelagRunBalanceCommand(0);
}