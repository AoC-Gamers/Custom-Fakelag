stock bool FakelagGetClientAccountKey(int client, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	if (!IsClientAuthorized(client))
	{
		return false;
	}

	int accountId = GetSteamAccountID(client);
	if (accountId <= 0)
	{
		return false;
	}

	IntToString(accountId, buffer, maxlen);
	return true;
}

stock void FakelagStoreProfileForClient(int client, float lag, int packetLossPercent)
{
	char accountKey[16];
	if (!FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
	{
		return;
	}

	g_PlayerLatencyByAccountId.SetValue(accountKey, view_as<int>(lag));
	g_PlayerPacketLossByAccountId.SetValue(accountKey, packetLossPercent);
	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Stored profile for %L (account %s): lag=%.1fms loss=%d%%", client, accountKey, lag, packetLossPercent);
	}
}

stock void FakelagSetDisconnectedState(int client, bool disconnected)
{
	char accountKey[16];
	if (!FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
	{
		return;
	}

	if (disconnected)
	{
		if (FakelagHasNetworkProfile(client) || g_PlayerLatencyByAccountId.ContainsKey(accountKey))
		{
			g_PlayerDisconnectedByAccountId.SetValue(accountKey, 1);
			if (FakelagIsDebugEnabled())
			{
				LogMessage("[player_fakelag] Marked %L as disconnected with persisted fakelag (account %s)", client, accountKey);
			}
		}
		return;
	}

	g_PlayerDisconnectedByAccountId.Remove(accountKey);
	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Cleared disconnect marker for %L (account %s)", client, accountKey);
	}
}

stock void FakelagForgetStoredLatency(int client)
{
	char accountKey[16];
	if (!FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
	{
		return;
	}

	g_PlayerLatencyByAccountId.Remove(accountKey);
	g_PlayerPacketLossByAccountId.Remove(accountKey);
	g_PlayerDisconnectedByAccountId.Remove(accountKey);
	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Forgot persisted fakelag profile for %L (account %s)", client, accountKey);
	}
}

stock bool FakelagTryGetStoredProfile(int client, float &lag, int &packetLossPercent)
{
	char accountKey[16];
	if (!FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
	{
		return false;
	}

	int storedLag;
	if (!g_PlayerLatencyByAccountId.GetValue(accountKey, storedLag))
	{
		return false;
	}

	packetLossPercent = 0;
	g_PlayerPacketLossByAccountId.GetValue(accountKey, packetLossPercent);
	lag = view_as<float>(storedLag);
	return true;
}

stock bool FakelagConsumeDisconnectedState(int client)
{
	char accountKey[16];
	if (!FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
	{
		return false;
	}

	int disconnected;
	if (!g_PlayerDisconnectedByAccountId.GetValue(accountKey, disconnected) || disconnected == 0)
	{
		return false;
	}

	g_PlayerDisconnectedByAccountId.Remove(accountKey);
	return true;
}

stock void FakelagQueueRestoreClientLatency(int client)
{
	if (client <= 0)
	{
		return;
	}

	RequestFrame(FakelagRestoreClientLatencyOnNextFrame, GetClientUserId(client));
}

void FakelagRestoreClientLatencyOnNextFrame(any data)
{
	int client = GetClientOfUserId(data);
	if (client <= 0)
	{
		return;
	}

	FakelagRestoreClientLatencyIfEligible(client);
}

stock void FakelagRestoreClientLatencyIfEligible(int client)
{
	if (!FakelagCanApplyLatencyToClient(client))
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restore skipped for client index %d: client is not currently eligible for fakelag", client);
		}
		return;
	}

	if (FakelagHasNetworkProfile(client))
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restore skipped for %L: client already has fakelag applied", client);
		}
		return;
	}

	float storedLag;
	int	  storedPacketLossPercent;
	if (!FakelagTryGetStoredProfile(client, storedLag, storedPacketLossPercent))
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restore skipped for %L: no persisted fakelag profile found", client);
		}
		return;
	}

	if (storedLag <= 0.0)
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restore skipped for %L: persisted fakelag was %.1fms", client, storedLag);
		}
		return;
	}

	bool restoredAfterDisconnect = FakelagConsumeDisconnectedState(client);
	FakelagApplyNetworkProfile(client, FakelagBuildNetworkProfile(storedLag, storedPacketLossPercent));
	if (FakelagIsDebugEnabled())
	{
		char accountKey[16];
		if (FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
		{
			LogMessage("[player_fakelag] Restored profile for %L (account %s): lag=%.1fms loss=%d%% after_disconnect=%d", client, accountKey, storedLag, storedPacketLossPercent, restoredAfterDisconnect);
		}
		else
		{
			LogMessage("[player_fakelag] Restored profile for client index %d: lag=%.1fms loss=%d%% after_disconnect=%d", client, storedLag, storedPacketLossPercent, restoredAfterDisconnect);
		}
	}
	if (restoredAfterDisconnect)
	{
		CPrintToChat(client, "%t %t", "Tag", "RestoredOnSelf", storedLag);
	}
}
