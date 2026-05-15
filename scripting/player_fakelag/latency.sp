#define FAKELAG_PING_SAMPLE_COUNT 5

float g_ClientLatencySamples[MAXPLAYERS + 1][FAKELAG_PING_SAMPLE_COUNT];
int g_ClientLatencySampleCount[MAXPLAYERS + 1];
int g_ClientLatencySampleIndex[MAXPLAYERS + 1];

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
		int j = i - 1;

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
	int trimmedCount = 0;
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

	float appliedFakeLag = CFakeLag_HasPlayerLatency(client) ? CFakeLag_GetPlayerLatency(client) : 0.0;
	float basePingMs = rawPingMs - appliedFakeLag;
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
	int windowSize = FakelagGetEffectiveSampleWindow();
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

	int sampleIndex = g_ClientLatencySampleIndex[client];
	g_ClientLatencySamples[client][sampleIndex] = rawPingMs;
	g_ClientLatencySampleIndex[client] = (sampleIndex + 1) % FAKELAG_PING_SAMPLE_COUNT;

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
