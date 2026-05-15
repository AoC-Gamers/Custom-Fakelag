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

stock void FakelagStoreLatencyForClient(int client, float lag)
{
	char accountKey[16];
	if (!FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
	{
		return;
	}

	g_PlayerLatencyByAccountId.SetValue(accountKey, view_as<int>(lag));
	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Stored %.1fms for %L (account %s)", lag, client, accountKey);
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
		if (CFakeLag_HasPlayerLatency(client) || g_PlayerLatencyByAccountId.ContainsKey(accountKey))
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
	g_PlayerDisconnectedByAccountId.Remove(accountKey);
	if (FakelagIsDebugEnabled())
	{
		LogMessage("[player_fakelag] Forgot persisted fakelag for %L (account %s)", client, accountKey);
	}
}

stock bool FakelagTryGetStoredLatency(int client, float &lag)
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

	if (CFakeLag_HasPlayerLatency(client))
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restore skipped for %L: client already has fakelag applied", client);
		}
		return;
	}

	float storedLag;
	if (!FakelagTryGetStoredLatency(client, storedLag))
	{
		if (FakelagIsDebugEnabled())
		{
			LogMessage("[player_fakelag] Restore skipped for %L: no persisted fakelag found", client);
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
	CFakeLag_SetPlayerLatency(client, storedLag);
	if (FakelagIsDebugEnabled())
	{
		char accountKey[16];
		if (FakelagGetClientAccountKey(client, accountKey, sizeof(accountKey)))
		{
			LogMessage("[player_fakelag] Restored %.1fms for %L (account %s, after_disconnect=%d)", storedLag, client, accountKey, restoredAfterDisconnect);
		}
		else
		{
			LogMessage("[player_fakelag] Restored %.1fms for client index %d (after_disconnect=%d)", storedLag, client, restoredAfterDisconnect);
		}
	}
	if (restoredAfterDisconnect)
	{
		CPrintToChat(client, "%t %t", "Tag", "FakelagRestoredOnSelf", storedLag);
	}
}