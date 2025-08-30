# Better Team Balance

Yet another autobalance mod. Highly configurable, aims to get the teamcompositions right the first time by using stats from the previous match as well as NuTone, so that no mid-match faffing about is needed. Or is at least kept to the smallest amount tolerable. Tons of features, all with the overarching goal of improving team balancing, while being as un-annoying as possible, so that we might enjoy challenging and even matches more often. Full featurelist below.

![](https://i.imgur.com/p6iEUx6.jpg)

Relies on FSU for chat commands. If using FSU, you will want to disable its built-in auto balance and team shuffle features.

Get FSU here: [Fifty's Server Utilities](https://northstar.thunderstore.io/package/Fifty/Server_Utilities/)

You can also run BTB without FSU, although this will disable teambalancing by vote, parties, and nemeses. All automatic features will work.

### The more powerful (and hence disruptive) team balancing features are disabled by default!
### By default, this is what BTB will do:

- Shuffle teams between rounds, using data from NuTone and the previous match, to keep them balanced
    - Then, teams are adjusted further if needed (someone left/joined), and locked after 60 seconds
- Place any joining player on the team that needs more help
    - If needed, switch the team of another recently joined player for better teams
- Auto-level the player count between teams, but only after waiting 20 seconds for new joins (unless one team is empty)
    - Only swap over a player that would make teams more even, never less
- Allow rebalance by vote (and suggest it when relevant)
- Allow players to form parties and choose a nemesis
- Kick any players that are AFK for 70 seconds
- Will not automatically rebalance teams (can be enabled)
- Will not level team-strength by subtly swapping the teams of players (insidious mode, can be enabled)

If this sounds good to you, you can install BTB on your server with zero configuration. The default config is intended to do the basics of what anyone would need, prioritizing not annoying anyone playing on the server. If you would like to enable/disable or tweak the behaviour of BTB, check mod.json

![](https://i.imgur.com/d40b3Zk.png)

### Changelog

#### 3.3.0

- NuTone support (Replaces Tone API functionality)
    - Participating servers contribute player stats, BTB can use those stats for better team balancing
    - No API key needed for read access, all servers running BTB can use the data for teambalancing
    - Stats submission mod: https://github.com/nutone-tf/nutone-server

## Features

![](https://i.imgur.com/m8ybaWt.jpg)

### Complex Team Balancing

BTB uses a balancing system where each player is assigned a value based on their kill-, death- and objectiverates. These values are then used to try and create two teams with equal total strength. This is able to account for players who are as good as several others put together.

Other balancing methods, such as the one used in the playervote mod and for a time even in this mod, would sort players from best to worst, then go down the list sorting every other player into opposing teams. This works well, but in cases of very skilled players, this always creates a team in their favor. When they perhaps should get none who rival their skill on their team, they would still get half of the skilled players on the server as teammates.

For example, in a game with three players, the best player would go to team one, the next best to team two, but then the third best would go to team one again, even though team two is the one who needs help to go up against the best player.

BTB will in that scenario pit the two less skilled players against the single more skilled one. With BTB, highly skilled players and even to an extent cheaters will find themselves fighting against even odds.

#### Parties and Nemeses

- Parties
    - Players can invite other players to form a party
    - If anyone is on opposite teams, teams will be minimally adjusted to unite the party
    - Parties are kept together through any team balancing, and across multiple matches
    - Party members can see the locations of their fellow party members
    - Party strength check, parties that would stomp are not allowed
- Nemesis
    - Mark someone as your nemesis
    - Nemeses are kept on opposite teams

#### Team Shuffle

- Player ranking information is saved into convars at the end of each match
- At the beginning of a match, this data is retrieved and used to inform the shuffle
- The shuffle incorporates *some* randomness, so as to leave room for variation
- Accounts for players leaving/joining between games, by waiting until the next match to actually build the teams
- Will make on the fly changes during a 60 second grace period at the start, if any players leave/join, throwing teams off balance
- Objectiverates are used in Attrition, Frontier War, LTS, TB, and Amped Hardpoint
    - In other modes only kill- and deathrates are considered

#### Mid-Match Rebalance

- Same algorithm as team shuffle, but without any randomness
- Redistributes points earned by players to their respective new teams (in round based modes, and for example hardpoint or fw, simply equalizes them)
- Can trigger on vote, and/or on crossing a configurable imbalance threshold
- By default, only informing players via chat about the "!teambalance" command, when relevant, is enabled
- To activate balancing automatically, set the relevant threshold using the correct convar (check mod.json)
- The thresold value represents a relative score difference, for example, 1.5 would trigger when points are 150 to 100
    - The detection is not this simple however, several other checks are in play to reduce false positives
    - Even if the threshold is crossed, will only trigger if winning team is snowballing and losing team seems too weak to make a come-back
    - Sane values are 1.4-2.2

#### Auto-PlayerCount-Balance

- Joining players are always placed first onto the team more in need of bolstering
- When one team has too many players, one of them is swapped over on death
- Only swaps over a player, if swapping that player makes sense, will not rob the losing team of its best player
- Before a swap can occur, BTB will wait a bit in case a new player joins to balance things out instead
- Disabled for the last three minutes of a match, no victories ruined by a last second swap over to losing side

#### Auto-TeamStrength-Balance - DISABLED BY DEFAULT

- Active balancing aka "insidious mode"
- This is **DISABLED BY DEFAULT** and must be enabled with a convar (check mod.json)
- Set an imbalance treshold above which insidious mode is activated (a fairly low one is recommended, 1.5-1.7)
- If team balance appears to be snowballing, BTB will swap the teams of two suitable players
    - A weak player will be moved to the strong team, and a strong player to the weak one
    - The swap can only occur while both players are dead
- BTB will then wait and see if the snowballing is arrested, and only do another swap, if not
- The thresold value represents a relative score difference, for example, 1.5 would trigger when points are 150 to 100
    - The detection is not this simple however, several other checks are in play to reduce false positives
    - Even if the threshold is crossed, will only trigger if winning team is snowballing and losing team seems too weak to make a come-back
    - Sane values are 1.4-2.2

#### AFK Kicking

- Set a playercount, below which afk players waiting for the server to fill up, wont be kicked
- UIDs set as admin in FSU are immune

### Changelogs for previous versions

#### 3.3.0

- Fixed rare crash on player disconnect
- Fixed parties not persisting through several matches

#### 3.2.1-2

- Fixed FFA fallback mode
- Non-crash bugfix

#### 3.2.0

- New feature: Recent join balancing
    - Actively balance teams, only switching the teams of players who have joined in the last 60 seconds
    - Allows adjustment of teams as players join, without annoying players that have "settled in"
    - Better teams when a server first picks up, or when a lot of players come and go

#### 3.1.2

- Added objectiverate calculation for Bounty Hunt
- Added score redistribution on rebalance for Bounty hunt

#### 3.1.1

- Update to Tone API v2

#### 3.1.0

- New Feature: Now able to access the Tone API to grab an initial player skill estimate based on their global stats
    - Affects the skill value of a player, for the first five minutes they play on the server
- Another party crash fix

#### 3.0.2

- Fix occasional server crash on player disconnect
- Fix party/nemesis info tip displaying almost every spawn

#### 3.0.1

- Fix crash when running without FSU
- AFK fallback improved (now does even less stuff that doesn't work in FFA)

#### 3.0.0

- New feature: Parties and Nemeses
    - Parties
        - Invite other players to form a party
        - If someone is on the opposite team, teams will be minimally adjusted to bring them to the same team
        - Parties are kept together through any re-balancing, and across multiple matches
        - Party members can see the locations of their fellow party members
        - Party strength check, parties that would stomp are not allowed
    - Nemesis
        - Mark someone as your nemesis
        - Nemeses are kept on opposite teams
- Improved RUI and chat messages, informing players on the server about what BTB is doing
- Added FFA fallback mode, runs AFK detection only
- Objectiverate calculations added for Frontier War and Hardpoint
- Match start re-adjustmet
    - Default grace period reduced to 60 seconds
    - Added minimum improvement thresold, adjustments that only help a tiny bit wont be made (should reduce excessive team changes)

#### 2.0.1

- Objectiverate calculation added for Titan Brawl and LTS

#### 2.0.0

- Significant changes under the hood!!
    - Vastly reduced false positives
    - Imbalance detection is no longer based solely on team scores
    - Will now detect if the lead team is snowballing
    - Will now detect if the losing team is strong enough to make a come-back
- Improved player strength calculation
    - New kill-/death-/objectiverate based strength calculation, improved accuracy with players who only play part of a match
    - Takes into consideration scores in "objective" based modes (Frontier War, Hardpoint, Attrition)
    - Self-calibrating average player strength value (used when a player is too new to have accurate stats)
    - This also improves team strength calculation, better balancing when teams have mismatched playercounts
- Will now readjust teams on the fly during the first 90 seconds of a match
    - Triggers if players leave/join after initial pre-match teambuild in this time window
    - This allows BTB to compensate if the teamcomp is thrown off right at the start
    - Will keep changes to the minimum possible, and make them discreetly (while players are dead)
    - Team comp does not get messed with further after the 90 second grace period

#### 1.3.1-3

- Bugfix
- Fix crash on rebalance vote

#### 1.3.0

- Updated for FSU2!
- Can now be used without FSU, albeit without the ability for players to vote for a rebalance
- Imbalance detection has been improved
    - Now takes into account calculated team strength, not just score
    - A game where the stronger team is losing, will not be detected as imbalanced
- Can now be run with FFA gamemodes, without crashing, though only AFK kicking will work for obvious reasons

#### 1.2.6

- Fixed active limit convar being commented out

#### 1.2.5

- New feature: insidious mode
    - Active balancing aka "insidious mode"
    - Set a score difference treshold above which insidious mode is activated
    - When crossed, the mod will compare team strenghts using the balancing algorithm
    - If team balance appears to be getting worse (snowballing) the mod will swap two suitable players teams
    - The swap can only occur while they are dead
    - Then it will wait and see if team strength begins to develop towards even, and only act again, if not
- RUI support
- Fixed round based modes triggering team rebuild on each round

#### 1.2.4

- Further improved joining player handling
- Corrected some logging errors
- !balance command is now !teambalance/!tb
- Force rebalance can now trigger earlier (if conditions are met)
- Suggestion message is now sent even less frequently
- Overarching chat color theme support using MentalEdge.theme (included)
- Removed automatic disabling of FSU auto-balance/shuffle for comptaibility with FSU-fvnk

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
