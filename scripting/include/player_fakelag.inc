#if defined _player_fakelag_included
	#endinput
#endif
#define _player_fakelag_included

/**
 * @brief Apply the current fake lag balance plan immediately.
 *
 * @param targetPing		Receives the target ping in milliseconds.
 * @param highestClient	Receives the client with the highest measured ping.
 * @param playerCount	Receives the number of players considered for balancing.
 * @param adjustedCount	Receives the number of players that received additional fakelag.
 * @param clearedCount	Receives the number of players whose fakelag was cleared.
 * @return			True if a valid balance plan was found and applied.
 */
native bool PlayerFakelag_ApplyBalance(float &targetPing, int &highestClient, int &playerCount, int &adjustedCount, int &clearedCount);

/**
 * @brief Calculate the current fake lag balance plan without applying it.
 *
 * @param targetPing		Receives the target ping in milliseconds.
 * @param highestClient	Receives the client with the highest measured ping.
 * @param playerCount	Receives the number of players considered for balancing.
 * @return			True if a valid balance plan was found.
 */
native bool PlayerFakelag_PreviewBalance(float &targetPing, int &highestClient, int &playerCount);

/**
 * @brief Start a built-in vote for the fake lag balancer.
 *
 * @param initiator		Client index that starts the vote, or 0 for server.
 * @return			True if the vote was started.
 */
native bool PlayerFakelag_StartBalanceVote(int initiator = 0);

/**
 * @brief Check whether a fake lag balance vote started by this plugin is active.
 *
 * @return			True if the plugin currently has a balance vote in progress.
 */
native bool PlayerFakelag_IsBalanceVoteInProgress();

/**
 * @brief Called before player_fakelag applies or clears fakelag on a player.
 *
 * @param client		Client index being modified.
 * @param oldLag		Current lag value in milliseconds.
 * @param newLag		Requested lag value in milliseconds. Modify to override.
 * @param reason		Reason for the change request.
 * @return		Plugin_Continue to allow, Plugin_Changed to allow with edits,
 *              Plugin_Handled or Plugin_Stop to block the change.
 */
forward Action PlayerFakelag_OnSetPlayerLatency(int client, float oldLag, float &newLag, CFakeLagChangeReason reason);

/**
 * @brief Called after player_fakelag applies or clears fakelag on a player.
 *
 * @param client		Client index that changed.
 * @param oldLag		Previous lag value in milliseconds.
 * @param newLag		Applied lag value in milliseconds.
 * @param reason		Reason for the change.
 */
forward void PlayerFakelag_OnPlayerLatencyChanged(int client, float oldLag, float newLag, CFakeLagChangeReason reason);

/**
 * @brief Called when player_fakelag is being unloaded.
 *
 * This forward is fired at the beginning of OnPluginEnd(), before active votes
 * are cancelled and before all fake lag entries are cleared.
 */
forward void PlayerFakelag_OnPluginEnd();

public SharedPlugin __pl_player_fakelag =
{
	name = "player_fakelag",
	file = "player_fakelag.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_player_fakelag_SetNTVOptional()
{
	MarkNativeAsOptional("PlayerFakelag_ApplyBalance");
	MarkNativeAsOptional("PlayerFakelag_PreviewBalance");
	MarkNativeAsOptional("PlayerFakelag_StartBalanceVote");
	MarkNativeAsOptional("PlayerFakelag_IsBalanceVoteInProgress");
}
#endif