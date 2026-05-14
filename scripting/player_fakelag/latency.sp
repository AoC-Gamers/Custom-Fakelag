stock float FakelagGetClientAveragePingRawMs(int client)
{
	float latency = GetClientAvgLatency(client, NetFlow_Outgoing);
	if (latency < 0.0)
	{
		return -1.0;
	}

	return latency * 1000.0;
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