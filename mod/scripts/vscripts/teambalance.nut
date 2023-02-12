global function BTBInit

array <entity> playersWantingToBalance
table <string, float> lastMatchStats
table <string, int> timePlayed

struct {
	table<entity, float> lastmoved = {}
} file

enum eAntiAfkPlayerState {
    ACTIVE
    SUSPICIOUS
    AFK
}

int differenceMax = 1
int waitTime = 4
float suggestionLimit = 1.5
float activeLimit = 1.6
float stompLimit = 2.0
float voteFraction = 0.45
float relativeScoreDifference = 1.0
float suggestionTimer = 10.0
int afkThresold = 5
int afkTime = 70
int shuffle = 1

int rebalancedHasOccurred = 0
int waitedTime = 0
int matchElapsed = 0
int subtleRebalancePermitted = 0
int teamsBuilt = 0 // This is used to prevent team rebuild in round based modes

float accumulatedSuggestionImbalance = 0.0
float accumulatedStompImbalance = 0.0
float accumulatedActiveImbalance = 0.0

const SHUFFLE_RANDOMNESS = 0.05


void function BTBInit(){
    lastMatchStats["average"] <- 0.6666

    foreach (entity player in GetPlayerArray()){
        AddPlayerCallbacks( player )
    }

    differenceMax = GetConVarInt( "btb_difference_max" )
    waitTime = GetConVarInt( "btb_wait_time" )
    suggestionLimit = GetConVarFloat( "btb_suggestion_limit" )
    stompLimit = GetConVarFloat( "btb_stomp_limit" )
    activeLimit = GetConVarFloat( "btb_active_limit" )
    voteFraction = GetConVarFloat( "btb_vote_fraction" )
    afkThresold = GetConVarInt( "btb_afk_threshold" )
    afkTime = GetConVarInt( "btb_afk_time" )
    shuffle = GetConVarInt( "btb_shuffle" )

#if FSCC_ENABLED
    FSCC_CommandStruct command
    command.m_UsageUser = "teambalance"
    command.m_Description = "Vote for teams and scores to be rebalanced."
    command.m_Group = "BTB"
    command.m_Abbreviations = [ "tb", "tbal" ]
    command.Callback = BTB_BalanceVote
    FSCC_RegisterCommand( "teambalance", command )

    print("[BTB] FSU is installed! Running BTB with !teambalance voting enabled.")
#else
    print("[BTB] BetterTeamBalance is running")
#endif

    AddCallback_OnPlayerKilled( OnDeathBalance )
    AddCallback_OnClientConnected( AssignJoiningPlayer )
    AddCallback_OnClientConnected( AddPlayerCallbacks )
    AddCallback_OnClientDisconnected( DeletePlayerRecords )
    AddCallback_OnClientDisconnected( DeletePlayTime )
    AddCallback_OnPlayerRespawned( Moved )
    AddCallback_GameStateEnter( eGameState.Playing, Playing)

    if (shuffle == 1){
        AddCallback_GameStateEnter( eGameState.Prematch, Prematch)
        AddCallback_GameStateEnter( eGameState.Postmatch, Postmatch)
    }
}

void function DeletePlayTime(entity player){
    if (player.GetUID() in timePlayed){
        delete timePlayed[player.GetUID()]
    }
}

// Saves players and their rankscore into two convars for use during shuffle in next match
void function Postmatch(){
    if (rebalancedHasOccurred == 1){
        print("[BTB] There was a mid match rebalance, the round ended with scores: " + GameRules_GetTeamScore(TEAM_IMC) + "/" + GameRules_GetTeamScore(TEAM_MILITIA) )
    }
    else {
        print("[BTB] A mid match rebalance was not triggered, the round ended with scores: " + GameRules_GetTeamScore(TEAM_IMC) + "/" + GameRules_GetTeamScore(TEAM_MILITIA) )
    }

    print("[BTB] Saving player ranks to convar.....")

    string ranklist = ""
    string rankvaluelist = ""
    foreach( entity player in GetPlayerArray() ){
        if (ranklist == ""){
            ranklist = player.GetUID()
            rankvaluelist = CalculatePlayerRank(player).tostring()
        }
        else{
            ranklist = ranklist + "," + player.GetUID()
            rankvaluelist = rankvaluelist + "," + CalculatePlayerRank(player).tostring()
        }
    }
    SetConVarString( "uid_list", ranklist )
    SetConVarString( "rank_list", rankvaluelist )
    print("[BTB] DONE")
}


// Rebuilds the player rank array and appends any newcomers that joined in the interrim
void function Prematch(){
    if (GetPlayerArray().len() > 1 && GetConVarString( "uid_list" ) != "" && teamsBuilt == 0){
        print("[BTB] Pulling player ranks and shuffling teams")
        array <string> previusMatchUID = split( GetConVarString( "uid_list" ), "," )
        array <string> previusMatchRankValue = split( GetConVarString( "rank_list" ), "," )

        // Rebuild ranked player array, discarding any players no longer on the server
        float averageValue = 0
        for(int i = 0; i < previusMatchUID.len(); i++){
            float rankValue = previusMatchRankValue[i].tofloat() * RandomFloatRange( 1.0 - SHUFFLE_RANDOMNESS, 1.0 )
            lastMatchStats[previusMatchUID[i]] <- rankValue
            averageValue += rankValue

            foreach( entity player in GetPlayerArray() ){
                if ( previusMatchUID[i] == player.GetUID() ){
                    print("[BTB] Staying player: " + player.GetPlayerName() + " - " + rankValue)
                }
            }
        }

        if (lastMatchStats.len() > 2)
            lastMatchStats["average"] <- averageValue / lastMatchStats.len()

        // Add any new players who joined
        foreach( entity player in GetPlayerArray() ){
            if ( previusMatchUID.find( player.GetUID() ) == -1 ){
                print("[BTB] Joining player: " + player.GetPlayerName() )
            }
        }
        ExecuteStatsBalance()
    }
    else if( abs(GetPlayerArrayOfTeam(TEAM_IMC).len()-GetPlayerArrayOfTeam(TEAM_MILITIA).len()) > differenceMax ){
        waitedTime = waitTime
    }
    teamsBuilt = 1
}

void function Playing(){
    if( IsFFAGame() ){
        print("[BTB] THIS SERVER IS ON AN FFA GAMEMODE - RUNNING AFK KICK ONLY")
        BTBFallbackModeThread()
    }
    else
        thread BTBThread()
}

// Check if the match is close to ending
bool function IsMatchEnding(){
    int scoreLimit = ( GameMode_GetScoreLimit( "aitdm" )*0.8 ).tointeger()
    int timeLeft = GameTime_TimeLeftSeconds()

    int scoreImc = GameRules_GetTeamScore(TEAM_IMC)
    int scoreMil = GameRules_GetTeamScore(TEAM_MILITIA)

    if( scoreImc > scoreLimit || scoreMil > scoreLimit || timeLeft < 180 )
        return true

    return false
}

// Calculate a players ranking score
float function CalculatePlayerRank( entity player ){
    if( matchElapsed < 6 ){
        if (player.GetUID() in lastMatchStats)
            return lastMatchStats[player.GetUID()]
        else
            return lastMatchStats["average"]
    }

    float deaths = player.GetPlayerGameStat(PGS_DEATHS).tofloat()
    float kills = player.GetPlayerGameStat(PGS_KILLS).tofloat()
    float score = 0.0
    float time = 1.0
    if( player.GetUID() in timePlayed )
        time = timePlayed[player.GetUID()].tofloat() / 6.0
    float killrate
    float deathrate

    if (GAMETYPE == "aitdm")
        kills = player.GetPlayerGameStat(PGS_ASSAULT_SCORE).tofloat() / 5
    if (GAMETYPE == "cp"){
        score = player.GetPlayerGameStat(PGS_ASSAULT_SCORE).tofloat() / 200
        score += player.GetPlayerGameStat(PGS_DEFENSE_SCORE).tofloat() / 300
        kills *= 0.75
    }
    if (GAMETYPE == "fw"){
        score = player.GetPlayerGameStat(PGS_DEFENSE_SCORE).tofloat() / 200
        score += player.GetPlayerGameStat(PGS_ASSAULT_SCORE).tofloat() / 1500
        kills *= 0.75
    }

    if (kills == 0)
        killrate = 0.5 / time
    else
        killrate = (kills + score) / time

    if (deaths == 0)
        deathrate = 0.5 / time
    else
        deathrate = deaths / time

    // Check if this player was in the last match, and integrate it if they were
    if( !IsMatchEnding() && player.GetUID() in lastMatchStats )
        return ((killrate - ( deathrate / 2 )) + ((lastMatchStats[player.GetUID()])/2) ) / 1.5

    return killrate - ( deathrate / 2 )
}

// Calculate the strength of a team
float function CalculateTeamStrength( int team ){
    float teamStrength = 0.0
    foreach(entity player in GetPlayerArrayOfTeam(team) ){
        teamStrength += CalculatePlayerRank( player )
    }
    if( GetPlayerArrayOfTeam(team).len() == GetPlayerArrayOfTeam(GetOtherTeam(team)).len()+1 )
        teamStrength -= lastMatchStats["average"]/2.2
    return teamStrength
}

// Calculate what the strength of a team would be, if the player were to be removed, and replacement added instead
float function CalculateTeamStrengtWithout( entity player, entity replacement ){
    float teamStrength = CalculatePlayerRank(replacement)
    int team = player.GetTeam()
    foreach(entity teamMember in GetPlayerArrayOfTeam(team) ){
        if(teamMember != player)
            teamStrength += CalculatePlayerRank( teamMember )
    }
    if( GetPlayerArrayOfTeam(team).len() == GetPlayerArrayOfTeam(GetOtherTeam(team)).len()+1 )
        teamStrength -= lastMatchStats["average"]/2.2
    return teamStrength
}

// Execute best possible swap with another player to improve team balance
void function ExecuteBestPossibleSwap( entity teamMember){
    float strengthDifference = fabs(CalculateTeamStrength( TEAM_MILITIA ) - CalculateTeamStrength( TEAM_IMC ))

    // Find best possible other swap
    float lastStrengthDifference = 100
    entity opponentToSwap
    foreach( entity player in GetPlayerArrayOfTeam(GetOtherTeam(teamMember.GetTeam())) ){
        float newStrengthDifference = fabs(CalculateTeamStrengtWithout( player, teamMember ) - CalculateTeamStrengtWithout( teamMember, player ))
        if ( lastStrengthDifference > newStrengthDifference ){
            opponentToSwap = player
            lastStrengthDifference = newStrengthDifference
        }
    }

    // Execute the swap if it meets requirements
    if( strengthDifference > lastStrengthDifference ){
        SetTeam( teamMember, GetOtherTeam( teamMember.GetTeam() ) )
        SetTeam( opponentToSwap, GetOtherTeam( opponentToSwap.GetTeam() ) )
    }
    if(IsAlive(teamMember) && GetGameState() == eGameState.Prematch){
        teamMember.Die()
        print("[BTB] Why is this player alive? Killing them.")
    }
    if(IsAlive(opponentToSwap) && GetGameState() == eGameState.Prematch){
        opponentToSwap.Die()
        print("[BTB] Why is this player alive? Killing them.")
    }
}

// Place a joining player onto the team most in need of bolstering
void function AssignJoiningPlayer( entity player ){
    if (!IsFFAGame()){
        float playerTeamFactor = CalculateTeamStrength(player.GetTeam())
        float otherTeamFactor = CalculateTeamStrength(GetOtherTeam(player.GetTeam()))
        int playerTeam = GetPlayerArrayOfTeam(player.GetTeam()).len() - 1
        int otherTeam = GetPlayerArrayOfTeam(GetOtherTeam(player.GetTeam())).len()

        if (playerTeamFactor >= otherTeamFactor && playerTeam >= otherTeam)
            SetTeam(player, GetOtherTeam(player.GetTeam()))
        else if(playerTeam > otherTeam)
            SetTeam(player, GetOtherTeam(player.GetTeam()))
    }
}

// Execute insidious mode balancing, always executes during first 80 seconds of a match
void function OnDeathBalance( entity victim, entity attacker, var damageInfo ){
    if (subtleRebalancePermitted == 1 || matchElapsed < 10){
        float strengthDifference = fabs(CalculateTeamStrength( TEAM_MILITIA ) - CalculateTeamStrength( TEAM_IMC ))

        array <entity> deadOpposingPlayers
        foreach(entity player in GetPlayerArrayOfTeam(GetOtherTeam(victim.GetTeam())) ){
            if( !IsAlive(player) )
               deadOpposingPlayers.append(player)
        }

        float lastStrengthDifference = 100
        entity opponentToSwap
        foreach(entity player in deadOpposingPlayers){
            float newStrengthDifference = fabs(CalculateTeamStrengtWithout( player, victim ) - CalculateTeamStrengtWithout( victim, player ))
            if ( lastStrengthDifference > newStrengthDifference ){
                opponentToSwap = player
                lastStrengthDifference = newStrengthDifference
            }
        }

        if( strengthDifference > lastStrengthDifference && activeLimit < (strengthDifference - lastStrengthDifference) ){
            SetTeam( victim, GetOtherTeam( victim.GetTeam() ) )
            SetTeam( opponentToSwap, GetOtherTeam( opponentToSwap.GetTeam() ) )
            subtleRebalancePermitted = 0
            if( accumulatedStompImbalance > 0 )
                accumulatedStompImbalance -= 8
            print("[BTB] Team balance has been improved by switching the teams of " + victim.GetPlayerName() + " and " + opponentToSwap.GetPlayerName() + ".")
        }
    }
    thread PlayerCountAutobalance(victim)
}

// Check if playercount balancing is needed on death, always executes during first 40 seconds of a match
void function PlayerCountAutobalance( entity victim ){
    wait 1
    if( waitedTime >= waitTime && matchElapsed < 5){
        if ( differenceMax == 0 || IsFFAGame() || GetPlayerArray().len() == 1 || abs(GetPlayerArrayOfTeam(TEAM_IMC).len() - GetPlayerArrayOfTeam(TEAM_MILITIA).len()) <= differenceMax || GameTime_TimeLeftSeconds() < 60 ){
            return
        }

        // Compare victims teams size
        if ( GetPlayerArrayOfTeam(victim.GetTeam()).len() < GetPlayerArrayOfTeam(GetOtherTeam(victim.GetTeam())).len() ){
            return
        }

        // Check if switching this player over would create significantly worse teams
        float victimTeamStrength = CalculateTeamStrength( victim.GetTeam() )
        float opposingTeamStrength = CalculateTeamStrength( GetOtherTeam(victim.GetTeam()) )
        float currentStrengthDifference = fabs(victimTeamStrength-opposingTeamStrength)

        float victimTeamStrengthWithoutVictim = 0.0
        float opposingTeamStreanthWithVictim = CalculatePlayerRank( victim )

        foreach(entity player in GetPlayerArrayOfTeam(victim.GetTeam()) ){
            if( player != victim)
                victimTeamStrengthWithoutVictim += CalculatePlayerRank( player )
        }
        victimTeamStrengthWithoutVictim = victimTeamStrengthWithoutVictim / ( GetPlayerArrayOfTeam(victim.GetTeam()).len() - 1 )

        foreach(entity player in GetPlayerArrayOfTeam(GetOtherTeam(victim.GetTeam())) ){
            opposingTeamStreanthWithVictim += CalculatePlayerRank( player )
        }
        opposingTeamStreanthWithVictim = opposingTeamStreanthWithVictim / ( GetPlayerArrayOfTeam(GetOtherTeam(victim.GetTeam())).len() + 1 )

        float potentialStrengthDifference = fabs(opposingTeamStreanthWithVictim-victimTeamStrengthWithoutVictim)

        if( potentialStrengthDifference > currentStrengthDifference )
            return

        // Passed checks, balance the teams
        print("[BTB] The team of " + victim.GetPlayerName() + " has been switched")
        SetTeam( victim, GetOtherTeam( victim.GetTeam() ) )
    #if FSCC_ENABLED
        FSU_PrivateChatMessage( victim, "%FYour team has been switched to balance the game!")
    #else
        Chat_ServerPrivateMessage( victim, "%FYour team has been switched to balance the game!", false)
    #endif
        NSSendPopUpMessageToPlayer( victim, "Your team has been switched!" )
        waitedTime = 1
    }
}

#if FSCC_ENABLED
// Count votes for !balance, and activate, when enough have voted for it
void function BTB_BalanceVote ( entity player, array < string > args ){
    if ( GetMapName() == "mp_lobby" ){

        FSU_PrivateChatMessage( player, "%ECan't balance in lobby")
        return
    }

    if ( GetGameState() != eGameState.Playing ){
        FSU_PrivateChatMessage( player, "%ECan't balance in this game state")
        return
    }

    if ( rebalancedHasOccurred == 1 ){
        FSU_PrivateChatMessage( player, "%ETeams have already been balanced!")
        return
    }

    int scoreDifference = abs(GameRules_GetTeamScore(TEAM_IMC) - GameRules_GetTeamScore(TEAM_MILITIA))

    if ( scoreDifference < 90 ){
        FSU_PrivateChatMessage( player, "%EThere is no need for a rebalance!")
        return
    }

    if ( GetPlayerArray().len() < 6 ){
        FSU_PrivateChatMessage( player, "%ENot enough players for a good rebalance!")
        return
    }

    if ( matchElapsed < 18 ){
        FSU_PrivateChatMessage( player, "%EIt is too soon for a rebalance!")
        return
    }

    if ( playersWantingToBalance.find( player ) != -1 ){
        FSU_PrivateChatMessage( player, "%EYou have already voted!")
        return
    }

    int required_players = int ( GetPlayerArray().len() * voteFraction )
    if ( required_players == 0 ){
        required_players = 1
    }

    if ( playersWantingToBalance.len() == 0 ){
        thread VoteHUD()
    }

    playersWantingToBalance.append( player )
    FSU_PrivateChatMessage( player, "%SYou voted to rebalance teams!")

    if ( playersWantingToBalance.len() >= required_players ){
        print("[BTB] Team skill balancing triggered by vote")
        ExecuteStatsBalance()
        rebalancedHasOccurred = 1
    }
}

void function VoteHUD(){
    // Announce the starting of a vote
    if(GetConVarBool("FSV_ENABLE_RUI")){
        foreach ( entity player in GetPlayerArray() ){
            NSSendAnnouncementMessageToPlayer( player, "TEAM REBALANCE VOTE STARTED", "Use '!tb' in chat to add your vote.", <1,0,0>, 0, 1 )
        }
        wait 1
        foreach ( entity player in GetPlayerArray() ){
            NSCreateStatusMessageOnPlayer( player, "", playersWantingToBalance.len() + "/" + int(GetPlayerArray().len()*voteFraction) + " have voted to rebalance teams", "teambalance"  )
        }
    }
    if(GetConVarBool("FSV_ENABLE_CHATUI")){
        FSU_ChatBroadcast(  "A vote to rebalance the teams been started! Use %H%Ptb %Nto vote. %T" + int(GetPlayerArray().len()*voteFraction) + " votes will be needed." )
    }

    int timer = GetConVarInt("btb_vote_duration")
    int nextUpdate = timer
    int lastVotes = playersWantingToBalance.len()

    while(timer > 0 && playersWantingToBalance.len() < int(GetPlayerArray().len()*voteFraction)){
        if(timer == nextUpdate){
            int minutes = int(floor(timer / 60))
            string seconds = string(timer - (minutes * 60))
            if (timer - (minutes * 60) < 10){
                seconds = "0"+seconds
            }
            if(GetConVarBool("FSV_ENABLE_RUI")){
                foreach (entity player in GetPlayerArray()) {
                    NSEditStatusMessageOnPlayer( player, minutes + ":" + seconds, playersWantingToBalance.len() + "/" + int(GetPlayerArray().len()*voteFraction) + " have voted to rebalance teams", "teambalance" )
                }
            }
            if(GetConVarBool("FSV_ENABLE_CHATUI") && playersWantingToBalance.len() != lastVotes){
                FSU_ChatBroadcast( "%F[%T"+minutes + ":" + seconds+" %FREMAINING]%H "+ playersWantingToBalance.len() + "/" + int(GetPlayerArray().len()*voteFraction) + "%N have voted to rebalance teams and scores. %T Use %H%Ptb %Tto vote." )
                lastVotes = playersWantingToBalance.len()
            }
            nextUpdate -= 5
        }
        timer -= 1
        wait 1
    }

    if(GetConVarBool("FSV_ENABLE_RUI")){
        if(playersWantingToBalance.len() >= int(GetPlayerArray().len()*voteFraction)){
            foreach ( entity player in GetPlayerArray() ){
                NSSendAnnouncementMessageToPlayer( player, "TEAMS HAVE BEEN REBALANCED", "Teams and scores have been rebalanced by vote!", <1,0,0>, 0, 1 )
            }
            wait 0.1
            foreach ( entity player in GetPlayerArray() ){
                NSEditStatusMessageOnPlayer( player, "PASS", "Teams and have been rebalanced!", "teambalance" )
            }
        }
        else{
            foreach (entity player in GetPlayerArray()) {
                NSEditStatusMessageOnPlayer( player, "FAIL", "Not enough votes to rebalance teams!", "teambalance" )
            }
        }
    }
    if (GetConVarBool("FSV_ENABLE_CHATUI") ){
        if(playersWantingToBalance.len() >= int(GetPlayerArray().len()*voteFraction)){
            FSU_ChatBroadcast("Final vote received! %STeams have been rebalanced!")
        }
        else{
            FSU_ChatBroadcast("%EThe vote to rebalance teams has failed! %NNot enough votes.")
        }
    }

    playersWantingToBalance.clear()
    wait 10
    foreach ( entity player in GetPlayerArray() ){
        NSDeleteStatusMessageOnPlayer( player, "teambalance" )
    }
}
#endif

// Execute balanced team rebuild
void function ExecuteStatsBalance(){
    subtleRebalancePermitted = 0
    float currentStrengthDifference = fabs( CalculateTeamStrength(TEAM_IMC) - CalculateTeamStrength(TEAM_MILITIA) )
    float improvement = 1
    int pass = 0

    print( "[BTB] Initial team strength difference: " + currentStrengthDifference )

    while( pass < 6 && improvement != 0){
        pass++

        foreach(player in GetPlayerArray())
            ExecuteBestPossibleSwap( player )

        improvement = currentStrengthDifference - (fabs( CalculateTeamStrength(TEAM_IMC) - CalculateTeamStrength(TEAM_MILITIA) ))

        currentStrengthDifference = fabs( CalculateTeamStrength(TEAM_IMC) - CalculateTeamStrength(TEAM_MILITIA) )

        print( "[BTB] PASS " + pass + " - Team strength difference improved by " + improvement + " to: " + currentStrengthDifference )
    }

    print( "[BTB] No further improvement possible. Achieved a team strength difference of: " + currentStrengthDifference)

    //Redistribute scores
    if ( GetGameState() == eGameState.Playing ){
        if (GAMETYPE == "tdm" || GAMETYPE == "ps" || GAMETYPE == "aitdm" || GAMETYPE == "ttdm"){
            AddTeamScore( TEAM_IMC, -GameRules_GetTeamScore(TEAM_IMC))
            AddTeamScore( TEAM_MILITIA, -GameRules_GetTeamScore(TEAM_MILITIA))

            // Loop through each player, adding up their scores for their teams
            foreach (entity player in GetPlayerArray()){
                if (GAMETYPE == "tdm" || GAMETYPE == "ps" || GAMETYPE == "ttdm"){
                    AddTeamScore( player.GetTeam(), player.GetPlayerGameStat(PGS_KILLS))
                }
                else if (GAMETYPE == "aitdm"){
                    AddTeamScore( player.GetTeam(), player.GetPlayerGameStat(PGS_ASSAULT_SCORE))

                    //Scale team score to account for a missing player if teams are uneven
                    int imcPlayers = GetPlayerArrayOfTeam(TEAM_IMC).len()
                    int militiaPlayers = GetPlayerArrayOfTeam(TEAM_MILITIA).len()
                    if (imcPlayers > 0 && militiaPlayers > 0){
                        if (imcPlayers > militiaPlayers){
                            AddTeamScore( TEAM_MILITIA, GameRules_GetTeamScore(TEAM_MILITIA) * (((militiaPlayers + 1) / imcPlayers) - 1 ) )
                        }
                        else if (militiaPlayers > imcPlayers){
                            AddTeamScore( TEAM_IMC, GameRules_GetTeamScore(TEAM_IMC) * (((imcPlayers + 1) / imcPlayers) - 1 ) )
                        }
                    }
                }
            }
        }
        // If not one of the supported game modes, simply level the scores, rounding down
        else {
            int totalScore = int ( 0.5 * (GameRules_GetTeamScore(TEAM_IMC) + GameRules_GetTeamScore(TEAM_MILITIA)))
            AddTeamScore( TEAM_IMC, totalScore - GameRules_GetTeamScore(TEAM_IMC))
            AddTeamScore( TEAM_MILITIA, totalScore - GameRules_GetTeamScore(TEAM_MILITIA))
        }
    }
}

// Main thread
void function BTBThread(){
    float previousStrengthDifference = 0.0
    int previousAbsoluteScoreDifference = 0

    wait 10
    while ( GetGameState() == eGameState.Playing ){

        // Increment player time played counters
        foreach(entity player in GetPlayerArray())
            if(player.GetUID() in timePlayed )
                timePlayed[player.GetUID()] += 1
            else
                timePlayed[player.GetUID()] <- 1

        // Check for player count imbalance
        if (differenceMax != 0 && !IsFFAGame() && GetPlayerArray().len() > 1){
            int difference = abs(GetPlayerArrayOfTeam(TEAM_IMC).len() - GetPlayerArrayOfTeam(TEAM_MILITIA).len())

            if (difference > differenceMax)
                waitedTime += difference - differenceMax
            else{
                waitedTime = 0
            }
        }

        // Check for team skill imbalance
        if (suggestionLimit != 0 || stompLimit != 0 || activeLimit != 0){

            int imcScore = GameRules_GetTeamScore(TEAM_IMC)
            int militiaScore = GameRules_GetTeamScore(TEAM_MILITIA)
            int absoluteScoreDifference = abs( imcScore - militiaScore )

            float imcTeamStrength = CalculateTeamStrength(TEAM_IMC)
            float milTeamStrength = CalculateTeamStrength(TEAM_MILITIA)
            float strengthDifference = fabs( imcTeamStrength - milTeamStrength )

            // Calculate the relative difference of the score between teams
            if (militiaScore > imcScore)
                relativeScoreDifference = 1.0 * militiaScore / imcScore
            else
                relativeScoreDifference = 1.0 * imcScore / militiaScore


            // Determine whether the team in the lead is also the stronger team
            bool leadTeamIsStronger = false
            if( imcScore > militiaScore && imcTeamStrength > milTeamStrength || militiaScore > imcScore && milTeamStrength > imcTeamStrength)
                leadTeamIsStronger = true

            // Determine whether the leading team is snowballing
            bool isMatchSnowballing = false
            if( strengthDifference >= previousStrengthDifference || absoluteScoreDifference >= previousAbsoluteScoreDifference)
                isMatchSnowballing = true

            previousStrengthDifference = strengthDifference
            previousAbsoluteScoreDifference = absoluteScoreDifference

            print("[BTBDEBUG] Team strength difference: " + strengthDifference)
            print("[BTBDEBUG] Absolute score difference: " + absoluteScoreDifference)
            print("[BTBDEBUG] Is lead team stronger: " + leadTeamIsStronger)

            //General requirement switch
            if (matchElapsed > 14 && absoluteScoreDifference > 50 && rebalancedHasOccurred == 0 && !IsMatchEnding() && GetPlayerArray().len() > 3){

            #if FSCC_ENABLED
                // Suggestion switch
                if ( suggestionLimit != 0 ){

                    // Accrue a value if above the treshold, decay when below
                    if ( leadTeamIsStronger && isMatchSnowballing && relativeScoreDifference > suggestionLimit && strengthDifference > suggestionLimit || leadTeamIsStronger && isMatchSnowballing && absoluteScoreDifference > suggestionLimit*100 && strengthDifference > suggestionLimit ){
                        accumulatedSuggestionImbalance += 1.0 + (absoluteScoreDifference.tofloat() / 100 )
                        print("[BTB] Accumulating suggestion imbalance/threshold: " + accumulatedSuggestionImbalance + " / " + suggestionTimer)
                    }
                    else{
                        accumulatedSuggestionImbalance -= 0.5
                        if (accumulatedSuggestionImbalance < 0){
                            accumulatedSuggestionImbalance = 0
                            suggestionTimer = 10.0
                        }
                        else
                            print("[BTB] Decaying suggestion imbalance/threshold: " + accumulatedSuggestionImbalance + " / " + suggestionTimer)
                    }

                    // Activate suggestion for rebalance when accrued enough value, set a new treshold when to suggest again
                    if (accumulatedSuggestionImbalance > suggestionTimer){
                        print("[BTB] Match is uneven, suggesting rebalance")
                        FSU_ChatBroadcast( "Looks like this match is uneven, if you'd like to rebalance the teams and their scores, use %H%Pteambalance%N.")
                        suggestionTimer += suggestionTimer * 2
                    }
                }
            #endif

                // Check for team strength imbalance
                if ( activeLimit != 0 && subtleRebalancePermitted == 0){
                    // Accrue a value if above the treshold, decay when below
                    if ( leadTeamIsStronger && isMatchSnowballing && relativeScoreDifference > activeLimit && strengthDifference > activeLimit || leadTeamIsStronger && absoluteScoreDifference > activeLimit*100 && strengthDifference > activeLimit ){
                        accumulatedActiveImbalance += 1.0 + ( absoluteScoreDifference.tofloat() / 100 )
                        print("[BTB] Accumulating active imbalance/threshold: " + accumulatedActiveImbalance + " / 12")
                    }
                    else{
                        accumulatedActiveImbalance -= 0.5
                        if (accumulatedActiveImbalance < 0)
                            accumulatedActiveImbalance = 0
                        else
                            print("[BTB] Decaying active imbalance/threshold: " + accumulatedActiveImbalance + " / 12")
                    }

                    // When enough value accrued allow insidious/active rebalancing
                    if (accumulatedActiveImbalance > 12){
                        print("[BTB] Active/Insidious rebalancing has been triggered! Looking for candidates.")
                        subtleRebalancePermitted = 1
                        accumulatedActiveImbalance = 0
                    }
                }

                // Forced rebalance switch
                if ( stompLimit != 0 ){
                    // Accrue a value if above the treshold, decay when below
                    if ( leadTeamIsStronger && isMatchSnowballing && relativeScoreDifference > stompLimit && strengthDifference > stompLimit || leadTeamIsStronger && isMatchSnowballing && absoluteScoreDifference > stompLimit*120 && strengthDifference > stompLimit ){
                        accumulatedStompImbalance += 1.0 + (absoluteScoreDifference.tofloat() / 120 )
                        print("[BTB] Accumulating stomp imbalance/threshold: " + accumulatedStompImbalance + " / 16")
                    }
                    else{
                        accumulatedStompImbalance -= 0.5
                        if (accumulatedStompImbalance < 0)
                            accumulatedStompImbalance = 0
                        else
                            print("[BTB] Decaying stomp imbalance/threshold: " + accumulatedStompImbalance + " / 16")
                    }

                    // Activate forced rebalance when accrued enough value
                    if (accumulatedStompImbalance > 16 && matchElapsed > 16){
                        print("[BTB] Match is very uneven, forcing rebalance")
                    #if FSCC_ENABLED
                        FSU_ChatBroadcast( "%EVery uneven match detected! %NTeams and scores have been automatically rebalanced.")
                    #else
                        Chat_ServerBroadcast( "\x1b[38;5;203mVery uneven match detected! \x1b[0mTeams and scores have been automatically rebalanced." )
                    #endif
                        foreach( entity player in GetPlayerArray()){
                            NSSendAnnouncementMessageToPlayer( player, "TEAMS HAVE BEEN AUTO-REBALANCED!", "Detected a very uneven match! Scores have also been leveled.", <1,0,0>, 0, 1 )
                        }
                        ExecuteStatsBalance()
                        rebalancedHasOccurred = 1
                    }
                }
            }
            else{
                if (accumulatedSuggestionImbalance > 0){
                    accumulatedSuggestionImbalance -= 0.5
                    if (accumulatedSuggestionImbalance < 0){
                        accumulatedSuggestionImbalance = 0
                        suggestionTimer = 10.0
                    }
                    else
                        print("[BTB] Decaying suggestion imbalance/threshold: " + accumulatedSuggestionImbalance + " / " + suggestionTimer)
                }
                if (accumulatedActiveImbalance > 0){
                    accumulatedActiveImbalance -= 0.5
                    if (accumulatedActiveImbalance < 0)
                        accumulatedActiveImbalance = 0
                    else
                        print("[BTB] Decaying active imbalance/threshold: " + accumulatedActiveImbalance + " / 12")
                }
                if (accumulatedStompImbalance > 0){
                    accumulatedStompImbalance -= 0.5
                    if (accumulatedStompImbalance < 0)
                        accumulatedStompImbalance = 0
                    else
                        print("[BTB] Decaying stomp imbalance/threshold: " + accumulatedStompImbalance + " / 16")
                }
            }
        }

        // Check for AFK players
        if (afkThresold != 0 && GetPlayerArray().len() > afkThresold){
            foreach (entity player in GetPlayerArray()){

                // Remove data if player has left match
                if ( !player.IsPlayer() ){
                    DeletePlayerRecords( player )
                    break
                }

            #if FSA_ENABLED
                // Ignore if player is FSU admin
                if (FSA_IsAdmin(player))
                    break
            #endif

                // Warn or kick player
                switch (GetAfkState(player)){
                    case eAntiAfkPlayerState.SUSPICIOUS:
                    #if FSCC_ENABLED
                        FSU_PrivateChatMessage( player, "%EYou will soon be kicked for being AFK! MOVE!!!")
                    #else
                        Chat_ServerPrivateMessage( player, "\x1b[38;5;203mYou will soon be kicked for being AFK! MOVE!!!", false)
                    #endif
                        NSSendPopUpMessageToPlayer( player, "YOU ARE AFK! MOVE!!!")
                        print("[BTB] AFK player has been warned")
                        break

                    case eAntiAfkPlayerState.AFK:
                        print("[BTB] AFK player kicked: " + player.GetPlayerName() + " - " + player.GetUID())
                        ServerCommand("kickid "+ player.GetUID())
                        break
                }
            }
        }
        matchElapsed += 1
        wait 10
    }
}

// FFA Fallback thread
void function BTBFallbackModeThread(){
    wait 10
    while (true){
        wait 10

        // Check for AFK players
        if (afkThresold != 0 && GetPlayerArray().len() > afkThresold){
            foreach (entity player in GetPlayerArray()){

                // Remove data if player has left match
                if ( !player.IsPlayer() ){
                    DeletePlayerRecords( player )
                    break
                }

            #if FSA_ENABLED
                // Ignore if player is FSU admin
                if (FSA_IsAdmin(player))
                    break
            #endif

                // Warn or kick player
                switch (GetAfkState(player)){
                    case eAntiAfkPlayerState.SUSPICIOUS:
                    #if FSCC_ENABLED
                        FSU_PrivateChatMessage( player, "%EYou will soon be kicked for being AFK! MOVE!!!")
                    #else
                        Chat_ServerPrivateMessage( player, "\x1b[38;5;203mYou will soon be kicked for being AFK! MOVE!!!", false)
                    #endif
                        NSSendPopUpMessageToPlayer( player, "YOU ARE AFK! MOVE!!!")
                        print("[BTB] AFK player has been warned")
                        break

                    case eAntiAfkPlayerState.AFK:
                        print("[BTB] AFK player kicked: " + player.GetPlayerName() + " - " + player.GetUID())
                        ServerCommand("kickid "+ player.GetUID())
                        break
                }
            }
        }
    }
}

int function GetAfkState( entity player ){
    float localgrace = afkTime * 1.0
    float warn = afkTime * 0.43
    if ( player in file.lastmoved){
        float lastmove = file.lastmoved[ player ]
        if (Time() > lastmove + (localgrace - warn)){

            if (Time() > lastmove + localgrace){
                return eAntiAfkPlayerState.AFK
            }
            return eAntiAfkPlayerState.SUSPICIOUS
        }
    }
    return eAntiAfkPlayerState.ACTIVE
}

void function Moved( entity player ){
    file.lastmoved[ player ] <- Time()
}

bool function bMoved( entity player ){
    Moved( player )
    return true
}

void function AddPlayerCallbacks( entity player ){
    AddPlayerPressedForwardCallback( player, bMoved )
    AddPlayerPressedBackCallback( player, bMoved )
    AddPlayerPressedLeftCallback( player, bMoved )
    AddPlayerPressedRightCallback( player, bMoved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.JUMP, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.DODGE, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.LEAVE_GROUND, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.TOUCH_GROUND, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.MANTLE, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.BEGIN_WALLRUN, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.END_WALLRUN, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.BEGIN_WALLHANG, Moved )
    AddPlayerMovementEventCallback( player, ePlayerMovementEvents.END_WALLHANG, Moved )
}

void function DeletePlayerRecords( entity player ){
    if (player in file.lastmoved){
        delete file.lastmoved[ player ]
    }
}
