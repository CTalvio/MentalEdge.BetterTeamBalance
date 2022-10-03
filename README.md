# Better Team Balance

Yet another autobalance mod. Except it's a lot smorter and comes with additional features, all with the overarching goal of improving team balancing, so that we might enjoy challenging and even matches more often.

Relies on FSU for chat commands. Also you will want to disable FSUs built-in auto balance and team shuffle features.

If you do not, this mod will override those convars when a conflicting feature is enabled, in order to ensure proper functioning. This may not take during the first match after a server is started, however, so it is better to disable them directly.

Get FSU here: [Fifty's Server Utilities](https://northstar.thunderstore.io/package/Fifty/Server_Utilities/)

Alternatively, use my improved version avaialable here:

### Changelog

#### 1.2.4

- Further improved joining player handling
- Corrected some logging errors
- !balance command is now !teambalance
- Force rebalance can now trigger earlier (if conditions are met)
- Suggestion message is now sent even less frequently
- Overarching chat color theme support using MentalEdge.theme (included)

## Features

### Complex Team Balancing

This mod now uses a balancing system where each player is assigned a value based on their KD and contributed score. These values are then used to create two teams with equal total skill. This is able to account for players who are as good as several others put together.

Other balancing methods, such as the one used in the playervote mod and until now this mod, would sort players from best to worst, then go down the list sorting every other player into opposing teams. This works well, but in cases of very skilled players, this always creates a team in their favor. When they perhaps should get none who rival their skill on their team, they would still get half of the skilled players on the server as teammates.

For example, in a game with three players, the best player would go to team one, the next best to team two, but then the third best would go to team one again, even though team two is the one who needs help to go up against the best player.

This mod will in that scenario pit the two less skilled players against the single more skilled one. With this mod, highly skilled players and even to an extent cheaters will find themselves fighting against even odds.

Below is an example of how the mod rebalanced a match where one player was doing orders of magnitude better than the next best. In this match the automatic rebalance treshold was activated early on, allowing the remainder of the match to play out as seen in the screenshot.


![](https://i.imgur.com/QCvJ4hV.png)

#### Team Shuffle

- Player ranking information is saved into a couple convars at the end of a match
- At the beginning of the next match, the rankings are retrieved and used to inform the shuffle
- The shuffle incorporates *some* randomness, so as to leave room for variation
- Accounts for players leaving/joining between games, by waiting until the next match to actually build the teams
- Player scores are taken into account in Attrition, PvP, Skirmish, and Titan Brawl, in other modes, balancing is done based on KD alone

#### Mid-Match Rebalance

- Same algorithm as team shuffle, but without any randomness
- Redistributes points earned by players to their respective new teams (in round based modes, simply equalizes them)
- Can trigger on vote, and/or on crossing a configurable score imbalance detection threshold
- By default, only a threshold for informing players via chat about the "!balance" command when relevant, is used
- To activate balancing automatically, set the relevant threshold using the correct convar (check mod.json)
- Tresholds accumulate/decay, the score difference has to remain at or grow past the treshold in order for the relevant action to eventually trigger

#### Auto-Balance

- Handles joining players, placing them first onto the team most in need of bolstering
- When one team has too many players, one of them is swapped over on death (like FSU)
- Only swaps over a player, if that player is one that would make the match more even
- Before doing so, will wait a moment in case new players join
- Wait is disabled for the first 40 seconds of a match, in order to quickly level team imbalances due to possible leaving players
- Disabled for the last minute of a match, no victories ruined by a last second swap over to losing side

#### AFK Kicking

- Set a playercount, below which afk players waiting for the server to fill up, wont be kicked
- UIDs set as admin in FSU are immune

Check mod.json for all convars and config options.

### Changelogs for previous versions

#### 1.2.3

- Fixed joining player handling stacking the weaker team a bit too hard

#### 1.2.2

- Now handles joining players, placing them first onto the team most in need of bolstering
- Fixed bug that would cause shuffle/balance to sometimes fail keeping the playercounts equal between teams

#### 1.2.0

- **Vastly** improved team sorting/building algorithm, as explained above
- !balance vote can no longer be used during the first three and half minutes of a match
- !balance vote can no longer be used if teams are already balanced, or were already rebalanced
- Treshold trigger behaviour improved, should now trigger/not trigger more logically
- Auto-balance now has a team balance check, swaps that would exacerbate the lead of a team are avoided

#### 1.1.1

- Better team balancing/shuffle calculation (score weight reduced, KD weight increased)

#### 1.1.0

- New feature: Team shuffle between matches that will attempt to use stats from the previous game to create balanced teams
- New feature: The mod will now override FSU setting convars and disable a conflicting FSU feature, if the corresponing one is enabled in BTB
- Auto-balance now works immediately during the first 40 seconds of a match

#### 1.0.4

- Bugfix - the mod now runs again

#### 1.0.3

- Forced rebalance and chat suggestions can now both be enabled, with different activation thresholds
- Same as 1.0.2 but comes with sane defaults

#### 1.0.1

- Admin afk check fixed
