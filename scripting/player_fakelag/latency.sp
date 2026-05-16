#define FAKELAG_PING_SAMPLE_COUNT 5

#define PlayerNetworkProfile	  CFakeLagNetworkProfile

stock float FakelagClamp(float value, float minValue, float maxValue)
{
	if (value < minValue)
	{
		return minValue;
	}

	if (value > maxValue)
	{
		return maxValue;
	}

	return value;
}

float	   g_ClientLatencySamples[MAXPLAYERS + 1][FAKELAG_PING_SAMPLE_COUNT];
int		   g_ClientLatencySampleCount[MAXPLAYERS + 1];
int		   g_ClientLatencySampleIndex[MAXPLAYERS + 1];

stock void FakelagCopyRecentLatencySamples(int client, float samples[FAKELAG_PING_SAMPLE_COUNT], int sampleCount)
{
	for (int offset = 0; offset < sampleCount; offset++)
	{
		int sampleIndex = g_ClientLatencySampleIndex[client] - 1 - offset;
		if (sampleIndex < 0)
		{
			sampleIndex += FAKELAG_PING_SAMPLE_COUNT;
		}

		samples[offset] = g_ClientLatencySamples[client][sampleIndex];
	}
}

stock void FakelagSortLatencySamples(float samples[FAKELAG_PING_SAMPLE_COUNT], int sampleCount)
{
	for (int i = 1; i < sampleCount; i++)
	{
		float value = samples[i];
		int	  j		= i - 1;

		while (j >= 0 && samples[j] > value)
		{
			samples[j + 1] = samples[j];
			j--;
		}

		samples[j + 1] = value;
	}
}

stock float FakelagAverageLatencySamples(const float samples[FAKELAG_PING_SAMPLE_COUNT], int sampleCount)
{
	float total = 0.0;
	for (int i = 0; i < sampleCount; i++)
	{
		total += samples[i];
	}

	return total / float(sampleCount);
}

stock float FakelagGetStableLatencyFromSamples(float samples[FAKELAG_PING_SAMPLE_COUNT], int sampleCount)
{
	if (sampleCount <= 0)
	{
		return -1.0;
	}

	if (sampleCount <= 2)
	{
		return FakelagAverageLatencySamples(samples, sampleCount);
	}

	FakelagSortLatencySamples(samples, sampleCount);

	if (sampleCount == 3)
	{
		return samples[1];
	}

	if (sampleCount == 4)
	{
		return (samples[1] + samples[2]) * 0.5;
	}

	float trimmed[FAKELAG_PING_SAMPLE_COUNT];
	int	  trimmedCount = 0;
	for (int i = 1; i < sampleCount - 1; i++)
	{
		trimmed[trimmedCount++] = samples[i];
	}

	return FakelagAverageLatencySamples(trimmed, trimmedCount);
}

stock int FakelagGetEffectiveSampleWindow()
{
	if (g_CvarSampleWindow == null)
	{
		return FAKELAG_PING_SAMPLE_COUNT;
	}

	int windowSize = g_CvarSampleWindow.IntValue;
	if (windowSize < 1)
	{
		return 1;
	}

	if (windowSize > FAKELAG_PING_SAMPLE_COUNT)
	{
		return FAKELAG_PING_SAMPLE_COUNT;
	}

	return windowSize;
}

stock float FakelagGetSamplingInterval()
{
	if (g_CvarSampleInterval == null)
	{
		return 1.0;
	}

	float interval = g_CvarSampleInterval.FloatValue;
	return interval < 0.1 ? 0.1 : interval;
}

stock float FakelagGetClientCurrentPingRawMs(int client)
{
	float latency = GetClientAvgLatency(client, NetFlow_Outgoing);
	if (latency < 0.0)
	{
		return -1.0;
	}

	return latency * 1000.0;
}

stock float FakelagGetClientBasePingRawMs(int client)
{
	float rawPingMs = FakelagGetClientCurrentPingRawMs(client);
	if (rawPingMs < 0.0)
	{
		return rawPingMs;
	}

	float appliedFakeLag = FakelagGetAppliedLagMs(client);
	float basePingMs	 = rawPingMs - appliedFakeLag;
	return basePingMs < 0.0 ? 0.0 : basePingMs;
}

stock float FakelagGetClientAveragePingRawMs(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return -1.0;
	}

	int sampleCount = g_ClientLatencySampleCount[client];
	if (sampleCount <= 0)
	{
		return FakelagGetClientBasePingRawMs(client);
	}

	int samplesToUse = sampleCount;
	int windowSize	 = FakelagGetEffectiveSampleWindow();
	if (samplesToUse > windowSize)
	{
		samplesToUse = windowSize;
	}

	float samples[FAKELAG_PING_SAMPLE_COUNT];
	FakelagCopyRecentLatencySamples(client, samples, samplesToUse);
	return FakelagGetStableLatencyFromSamples(samples, samplesToUse);
}

stock bool FakelagTryGetClientUpdateRate(int client, int &updateRate)
{
	char updateRateValue[16];
	if (!GetClientInfo(client, "cl_updaterate", updateRateValue, sizeof(updateRateValue)))
	{
		return false;
	}

	updateRate = StringToInt(updateRateValue);
	return updateRate > 0;
}

stock float FakelagEstimateNetGraphPingMs(float rawPingMs, int updateRate)
{
	if (rawPingMs < 0.0 || updateRate <= 0)
	{
		return rawPingMs;
	}

	float estimatedPing = rawPingMs - (500.0 / float(updateRate));
	return estimatedPing < 0.0 ? 0.0 : estimatedPing;
}

stock float FakelagEstimateNetGraphPingForClientMs(int client, float rawPingMs)
{
	int updateRate;
	if (!FakelagTryGetClientUpdateRate(client, updateRate))
	{
		return rawPingMs;
	}

	return FakelagEstimateNetGraphPingMs(rawPingMs, updateRate);
}

stock int FakelagResolvePacketLossPercent(float basePingMs, float addedLagMs, float targetPingMs)
{
	if (basePingMs < 0.0 || addedLagMs <= 0.0 || targetPingMs < 0.0)
	{
		return 0;
	}

	float baseCeiling  = g_CvarLossBaseCeilingMs != null ? g_CvarLossBaseCeilingMs.FloatValue : 60.0;
	float baseSpan	   = g_CvarLossBaseSpanMs != null ? g_CvarLossBaseSpanMs.FloatValue : 40.0;
	float targetFloor  = g_CvarLossTargetFloorMs != null ? g_CvarLossTargetFloorMs.FloatValue : 40.0;
	float targetSpan   = g_CvarLossTargetSpanMs != null ? g_CvarLossTargetSpanMs.FloatValue : 40.0;
	float addedFloor   = g_CvarLossAddedFloorMs != null ? g_CvarLossAddedFloorMs.FloatValue : 25.0;
	float addedSpan	   = g_CvarLossAddedSpanMs != null ? g_CvarLossAddedSpanMs.FloatValue : 35.0;
	float maxPercent   = g_CvarLossMaxPercent != null ? float(g_CvarLossMaxPercent.IntValue) : 2.0;

	float baseFactor   = FakelagClamp((baseCeiling - basePingMs) / baseSpan, 0.0, 1.0);
	float targetFactor = FakelagClamp((targetPingMs - targetFloor) / targetSpan, 0.0, 1.0);
	float addedFactor  = FakelagClamp((addedLagMs - addedFloor) / addedSpan, 0.0, 1.0);
	float lossFloat	   = maxPercent * baseFactor * targetFactor * addedFactor;
	return RoundToNearest(FakelagClamp(lossFloat, 0.0, maxPercent));
}

stock PlayerNetworkProfile FakelagBuildNetworkProfile(float lagMs, int packetLossPercent)
{
	return CFakeLag_BuildNetworkProfile(lagMs, packetLossPercent);
}

stock void FakelagApplyNetworkProfile(int client, const PlayerNetworkProfile profile)
{
	CFakeLag_SetPlayerProfile(client, profile.lagMs, profile.packetLossPercent);
}

stock void FakelagClearNetworkProfile(int client)
{
	CFakeLag_ClearPlayerProfile(client);
}

stock bool FakelagHasNetworkProfile(int client)
{
	return CFakeLag_HasPlayerProfile(client);
}

stock bool FakelagGetNetworkProfile(int client, PlayerNetworkProfile profile)
{
	return CFakeLag_GetPlayerProfile(client, profile);
}

stock float FakelagGetAppliedLagMs(int client)
{
	PlayerNetworkProfile profile;
	if (!FakelagGetNetworkProfile(client, profile))
	{
		return 0.0;
	}

	return profile.lagMs;
}

stock int FakelagGetAppliedPacketLossPercent(int client)
{
	PlayerNetworkProfile profile;
	if (!FakelagGetNetworkProfile(client, profile))
	{
		return 0;
	}

	return profile.packetLossPercent;
}

stock int FakelagGetActiveProfileCount()
{
	return CFakeLag_GetProfiledClientCount();
}

stock float FakelagGetClientAveragePingMs(int client)
{
	float rawPingMs = FakelagGetClientAveragePingRawMs(client);
	if (rawPingMs < 0.0)
	{
		return rawPingMs;
	}

	return FakelagEstimateNetGraphPingForClientMs(client, rawPingMs);
}

stock void FakelagResetClientLatencySamples(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_ClientLatencySampleCount[client] = 0;
	g_ClientLatencySampleIndex[client] = 0;

	for (int index = 0; index < FAKELAG_PING_SAMPLE_COUNT; index++)
	{
		g_ClientLatencySamples[client][index] = 0.0;
	}
}

stock void FakelagSampleClientLatency(int client)
{
	if (!IsHumanInGame(client))
	{
		return;
	}

	float rawPingMs = FakelagGetClientBasePingRawMs(client);
	if (rawPingMs < 0.0)
	{
		return;
	}

	int sampleIndex								= g_ClientLatencySampleIndex[client];
	g_ClientLatencySamples[client][sampleIndex] = rawPingMs;
	g_ClientLatencySampleIndex[client]			= (sampleIndex + 1) % FAKELAG_PING_SAMPLE_COUNT;

	if (g_ClientLatencySampleCount[client] < FAKELAG_PING_SAMPLE_COUNT)
	{
		g_ClientLatencySampleCount[client]++;
	}
}

stock void FakelagStartLatencySampling()
{
	FakelagRestartLatencySampling();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanInGame(client))
		{
			continue;
		}

		FakelagResetClientLatencySamples(client);
	}
}

stock void FakelagRestartLatencySampling()
{
	if (g_LatencySamplingTimer != null)
	{
		delete g_LatencySamplingTimer;
		g_LatencySamplingTimer = null;
	}

	g_LatencySamplingTimer = CreateTimer(FakelagGetSamplingInterval(), FakelagLatencySamplingTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

stock void FakelagStopLatencySampling()
{
	// During plugin unload the timer handle may already be invalidated by the
	// runtime before OnPluginEnd finishes. Detach our reference instead of
	// forcing another close on a stale handle.
	g_LatencySamplingTimer = null;

	for (int client = 1; client <= MaxClients; client++)
	{
		FakelagResetClientLatencySamples(client);
	}
}

public Action FakelagLatencySamplingTimer(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		FakelagSampleClientLatency(client);
	}

	return Plugin_Continue;
}

public void FakelagOnSamplingSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	FakelagRestartLatencySampling();
}
