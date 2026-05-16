#include <core>

#if defined _custom_fakelag_included
#endinput
#endif
#define _custom_fakelag_included

enum CFakeLagChangeReason
{
	CFakeLagChange_Manual = 0,
	CFakeLagChange_Clear,
	CFakeLagChange_Disconnect
};

enum CFakeLagPacketLossMode
{
	CFakeLagPacketLoss_BernoulliUniform = 0,
	CFakeLagPacketLoss_GilbertElliott
};

enum struct CFakeLagNetworkProfile
{
	float lagMs;
	int packetLossPercent;
}

/**
 * @brief Set custom fake latency for the given player.
 *
 * @param client	Client index of the player to lag.
 * @param lagTime Amount of time to lag the packet, in milliseconds.
 *                Values less than or equal to 0 clear any existing fakelag.
 */
 native void CFakeLag_SetPlayerLatency(int client, float lagTime);

/**
 * @brief Get custom fake latency amount for the given player.
 *
 * @param client	Client index of the player to check latency for.
 */
 native float CFakeLag_GetPlayerLatency(int client);

/**
 * @brief Check whether the player currently has fake latency applied.
 *
 * @param client	Client index of the player to check.
 * @return		True if fake latency is currently active for the player.
 */
native bool CFakeLag_HasPlayerLatency(int client);

/**
 * @brief Clear custom fake latency for the given player.
 *
 * @param client	Client index of the player to clear.
 */
native void CFakeLag_ClearPlayerLatency(int client);

/**
 * @brief Set artificial packet loss percentage for the given player.
 *
 * @param client			Client index of the player to affect.
 * @param packetLossPercent	Packet loss percentage to apply, from 0 to 100.
 */
native void CFakeLag_SetPlayerPacketLoss(int client, int packetLossPercent);

/**
 * @brief Get artificial packet loss percentage for the given player.
 *
 * @param client	Client index of the player to inspect.
 * @return		Current artificial packet loss percentage.
 */
native int CFakeLag_GetPlayerPacketLoss(int client);

/**
 * @brief Check whether the player currently has artificial packet loss applied.
 *
 * @param client	Client index of the player to check.
 * @return		True if artificial packet loss is currently active for the player.
 */
native bool CFakeLag_HasPlayerPacketLoss(int client);

/**
 * @brief Clear artificial packet loss for the given player.
 *
 * @param client	Client index of the player to clear.
 */
native void CFakeLag_ClearPlayerPacketLoss(int client);

/**
 * @brief Set the packet loss simulation mode used by the extension.
 *
 * @param mode	Packet loss simulation mode.
 */
native void CFakeLag_SetPacketLossMode(CFakeLagPacketLossMode mode);

/**
 * @brief Get the packet loss simulation mode currently used by the extension.
 *
 * @return		Current packet loss simulation mode.
 */
native CFakeLagPacketLossMode CFakeLag_GetPacketLossMode();

/**
 * @brief Clear all stored fakelag profiles.
 *
 * Clears both artificial latency and artificial packet loss entries tracked by
 * the extension.
 */
native void CFakeLag_ClearAllPlayerProfiles();

/**
 * @brief Clear all stored fake latency entries.
 *
 * Legacy alias for CFakeLag_ClearAllPlayerProfiles().
 */
native void CFakeLag_ClearAllPlayerLatencies();

/**
 * @brief Check whether a client index can be targeted by Custom Fakelag.
 *
 * @param client	Client index to test.
 * @return		True if the client index is valid and not a fake client.
 */
native bool CFakeLag_IsClientSupported(int client);

/**
 * @brief Get the number of active fakelag profiles.
 *
 * A profile may contain artificial latency, artificial packet loss, or both.
 *
 * @return		Number of currently tracked player profiles.
 */
native int CFakeLag_GetProfiledClientCount();

/**
 * @brief Get the number of active fake latency entries.
 *
 * @return		Number of active lagged clients currently tracked.
 *
 * Legacy alias for CFakeLag_GetProfiledClientCount().
 */
native int CFakeLag_GetLaggedClientCount();

/**
 * @brief Build a network profile value from lag and packet loss settings.
 *
 * @param lagMs				Artificial latency in milliseconds.
 * @param packetLossPercent	Artificial packet loss percentage.
 * @return					Composed network profile.
 */
stock CFakeLagNetworkProfile CFakeLag_BuildNetworkProfile(float lagMs, int packetLossPercent)
{
	CFakeLagNetworkProfile profile;
	profile.lagMs = lagMs;
	profile.packetLossPercent = packetLossPercent;
	return profile;
}

/**
 * @brief Read the current fakelag profile for a player.
 *
 * @param client	Client index of the player to inspect.
 * @param profile	Output profile struct.
 */
stock void CFakeLag_GetPlayerProfile(int client, CFakeLagNetworkProfile profile)
{
	profile.lagMs = CFakeLag_GetPlayerLatency(client);
	profile.packetLossPercent = CFakeLag_GetPlayerPacketLoss(client);
}

/**
 * @brief Apply a full fakelag profile to a player.
 *
 * @param client	Client index of the player to affect.
 * @param profile	Profile to apply.
 */
stock void CFakeLag_ApplyPlayerProfile(int client, const CFakeLagNetworkProfile profile)
{
	CFakeLag_SetPlayerLatency(client, profile.lagMs);
	CFakeLag_SetPlayerPacketLoss(client, profile.packetLossPercent);
}

/**
 * @brief Clear the full fakelag profile for a player.
 *
 * @param client	Client index of the player to clear.
 */
stock void CFakeLag_ClearPlayerProfile(int client)
{
	CFakeLag_ClearPlayerPacketLoss(client);
	CFakeLag_ClearPlayerLatency(client);
}

/**
 * @brief Called before a player's fake latency changes.
 *
 * @param client	Client index being modified.
 * @param oldLag	Current lag value in milliseconds.
 * @param newLag	Requested lag value in milliseconds. Modify to override.
 * @param reason	Reason for the change request.
 * @return		Plugin_Continue to allow, Plugin_Changed to allow with edits,
 *              Plugin_Handled or Plugin_Stop to block the change.
 */
forward Action CFakeLag_OnSetPlayerLatency(int client, float oldLag, float &newLag, CFakeLagChangeReason reason);

/**
 * @brief Called after a player's fakelag profile changes.
 *
 * @param client	Client index that changed.
 * @param oldLag	Previous lag value in milliseconds.
 * @param oldPacketLossPercent	Previous packet loss percentage.
 * @param newLag	Applied lag value in milliseconds.
 * @param newPacketLossPercent	Applied packet loss percentage.
 * @param reason	Reason for the change.
 */
forward void CFakeLag_OnPlayerProfileChanged(int client, float oldLag, int oldPacketLossPercent, float newLag, int newPacketLossPercent, CFakeLagChangeReason reason);


public Extension __ext_custom_fakelag =
{
	name = "custom_fakelag",
	file = "custom_fakelag.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};
