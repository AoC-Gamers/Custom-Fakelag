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
 * @brief Clear all stored fake latency entries.
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
 * @brief Get the number of active fake latency entries.
 *
 * @return		Number of active lagged clients currently tracked.
 */
native int CFakeLag_GetLaggedClientCount();

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
 * @brief Called after a player's fake latency changes.
 *
 * @param client	Client index that changed.
 * @param oldLag	Previous lag value in milliseconds.
 * @param newLag	Applied lag value in milliseconds.
 * @param reason	Reason for the change.
 */
forward void CFakeLag_OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason);


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