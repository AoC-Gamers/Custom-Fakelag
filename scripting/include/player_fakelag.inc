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