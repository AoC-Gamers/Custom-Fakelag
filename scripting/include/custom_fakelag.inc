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
 * @brief Set the full fakelag profile for the given player.
 *
 * Applies artificial latency and artificial packet loss in a single operation.
 *
 * @param client			Client index of the player to affect.
 * @param lagTime			Artificial latency in milliseconds.
 * @param packetLossPercent	Artificial packet loss percentage to apply, from 0 to 100.
 */
native void CFakeLag_SetPlayerProfile(int client, float lagTime, int packetLossPercent);

/**
 * @brief Read the full fakelag profile for the given player.
 *
 * @param client	Client index of the player to inspect.
 * @param profile	Output profile struct.
 * @return		True if the player currently has an active profile.
 */
native bool CFakeLag_GetPlayerProfile(int client, CFakeLagNetworkProfile profile);

/**
 * @brief Check whether the player currently has an active fakelag profile.
 *
 * @param client	Client index of the player to check.
 * @return		True if the player has artificial latency, packet loss, or both.
 */
native bool CFakeLag_HasPlayerProfile(int client);

/**
 * @brief Clear the full fakelag profile for the given player.
 *
 * @param client	Client index of the player to clear.
 */
native void CFakeLag_ClearPlayerProfile(int client);

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
 * @brief Reset the full internal state of the extension.
 *
 * Clears all active fakelag profiles and any internal packet loss simulation
 * state so the extension behaves as if no players had ever been modified.
 */
native void CFakeLag_ResetState();

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

/**
 * @brief Called after the extension changes packet loss simulation mode.
 *
 * Changing mode resets all active fakelag state before the new mode is
 * adopted.
 *
 * @param oldMode	Previous packet loss simulation mode.
 * @param newMode	New packet loss simulation mode.
 */
forward void CFakeLag_OnPacketLossModeChanged(CFakeLagPacketLossMode oldMode, CFakeLagPacketLossMode newMode);


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
