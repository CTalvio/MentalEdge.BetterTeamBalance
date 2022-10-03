global function BTBInit

array <entity> playersWantingToBalance

struct PlayerRankArray{
    entity player
    float scorekd
}

struct {
	table<entity, float> lastmoved = {}
} file

enum eAntiAfkPlayerState {
    ACTIVE
    SUSPICIOUS
    AFK
}

int matchElapsed = 0
int differenceMax = 1
int waitTime = 4
int waitedTime = 0
float accumulatedSuggestionImbalance = 0.0
float accumulatedStompImbalance = 0.0
float suggestionLimit = 1.5
float stompLimit = 2.0
float voteFraction = 0.45
float relativeScoreDifference = 1.0
int rebalancedHasOccurred = 0
float suggestionTimer = 12.0
int afkThresold = 5
int afkTime = 70
int scoreKDShuffle = 1
int outlierCompensation = 1

const SHUFFLE_RANDOMNESS = 0.25


void function BTBInit(){
    differenceMax = GetConVarInt( "btb_difference_max" )
    waitTime = GetConVarInt( "btb_wait_time" )
    suggestionLimit = GetConVarFloat( "btb_suggestion_limit" )
    stompLimit = GetConVarFloat( "btb_stomp_limit" )
    voteFraction = GetConVarFloat( "btb_vote_fraction" )
    afkThresold = GetConVarInt( "btb_afk_threshold" )
    afkTime = GetConVarInt( "btb_afk_time" )
    scoreKDShuffle = GetConVarInt( "btb_skd_shuffle" )

    FSU_RegisterCommand( "teambalance",AccentOne( FSU_GetString("FSU_PREFIX") + "teambalance") + " - if enough players vote, teams and scores will be rebalanced.", "btb", BTB_BalanceVote, ["tbal", "tb"] )
    AddCallback_OnPlayerKilled( OnDeathAutobalance )
    AddCallback_OnClientConnected( AddPlayerCallbacks )
    AddCallback_OnClientConnected( AssignJoiningPlayer )
    AddCallback_OnClientDisconnected( DeletePlayerRecords )
    AddCallback_OnPlayerRespawned( Moved )
    foreach (entity player in GetPlayerArray()){
        AddPlayerCallbacks( player )
    }

    // Override any FSU convars to disable any features that conflict with enabled BTB features
//     if (differenceMax != 0){
//         SetConVarInt( "FSU_BALANCE_TEAMS_MID_GAME", 0 )
//     }
    if (scoreKDShuffle == 1){
//         SetConVarInt( "FSU_SHUFFLE_TEAMS_ON_MATCH_START", 0 )
        AddCallback_GameStateEnter( eGameState.Prematch, Prematch)
        AddCallback_GameStateEnter( eGameState.Postmatch, Postmatch)
    }

    thread BTBThread()
    print("[BTB] BetterTeamBalance is running")
}


// Saves players and their rankscore into two convars for use during shuffle in next match
void function Postmatch(){
    print("[BTB] Saving player ranks to convar")
    if (rebalancedHasOccurred == 1){
        print("[BTB] There was a mid match rebalance, the round ended with scores: " + GameRules_GetTeamScore(TEAM_IMC) + "/" + GameRules_GetTeamScore(TEAM_MILITIA) )
    }
    else {
        print("[BTB] A mid match rebalance was not triggered, the round ended with scores: " + GameRules_GetTeamScore(TEAM_IMC) + "/" + GameRules_GetTeamScore(TEAM_MILITIA) )
    }

    array<PlayerRankArray> playerRanks = GetPlayersSortedBySkill()
    string ranklist = ""
    string rankvaluelist = ""

    // Build string with UUIDs and save to convar
    for(int i = 0; i < GetPlayerArray().len(); i++){
        if (ranklist == ""){
            ranklist = playerRanks[i].player.GetUID()
        }
        else{
            ranklist = ranklist + "," + playerRanks[i].player.GetUID()
        }
    }
    SetConVarString( "uid_list", ranklist )

    // Build string with rankvalues and save to convar
    for(int i = 0; i < GetPlayerArray().len(); i++){
        if (rankvaluelist == ""){
            rankvaluelist = playerRanks[i].scorekd.tostring()
        }
        else{
            rankvaluelist = rankvaluelist + "," + playerRanks[i].scorekd.tostring()
        }
    }
    SetConVarString( "rank_list", rankvaluelist )
}


// Rebuilds the player rank array and appends any newcomers that joined in the interrim
void function Prematch(){
    if (GetPlayerArray().len() > 1 && GetConVarString( "uid_list" ) != ""){
        print("[BTB] Pulling player ranks and shuffling teams")
        array <PlayerRankArray> playerRanks
        array <string> previusMatchUID = split( GetConVarString( "uid_list" ), "," )
        array <string> previusMatchRankValue = split( GetConVarString( "rank_list" ), "," )

        // Rebuild ranked player array, discarding any players no longer on the server
        for(int i = 0; i < split( GetConVarString( "uid_list" ), "," ).len(); i++){
            foreach( entity player in GetPlayerArray() ){
                if ( previusMatchUID[i] == player.GetUID() ){
                    PlayerRankArray temp
                    temp.player = player
                    temp.scorekd = previusMatchRankValue[i].tofloat() * RandomFloatRange( 1.0 - SHUFFLE_RANDOMNESS, 1.0 )
                    print("[BTB] Staying player: " + temp.player.GetPlayerName() + " - " + temp.scorekd)
                    playerRanks.append( temp )
                }
            }
        }
        // Add any new players who joined
        foreach( entity player in GetPlayerArray() ){
            if ( previusMatchUID.find( player.GetUID() ) == -1 ){
                PlayerRankArray temp
                temp.player = player
                temp.scorekd = 1.001
                print("[BTB] Joining player: " + temp.player.GetPlayerName() + " - " + temp.scorekd)
                playerRanks.append( temp )
            }
        }

        ExecuteStatsBalance( playerRanks )
    }
}


// Calculate a players ranking score
float function CalculatePlayerRank( entity player ){
    int deaths = player.GetPlayerGameStat(PGS_DEATHS)
    int kills = player.GetPlayerGameStat(PGS_KILLS)
    float kd = 0.0
    float score = 1.0
    if (GAMETYPE == "tdm" || GAMETYPE == "ps" || GAMETYPE == "ttdm"){
        score = (player.GetPlayerGameStat(PGS_KILLS) * 1.5 / 100) + 1
    }
    else if (GAMETYPE == "aitdm") {
        score = (player.GetPlayerGameStat(PGS_ASSAULT_SCORE) * 1.5 / 1000) + 1
    }

    if(deaths == 0){
        if (kills == 0){
            kd = 1.0
        }
        else{
            kd = 1.0 * kills / 0.9
        }
    }
    else{
        if (kills == 0){
            kd = 0.9 / deaths
        }
        else{
            kd = 1.0 * kills / deaths
        }
    }
    return score * kd
}


// Place a joining player onto the team in need of bolstering
void function AssignJoiningPlayer( entity player ){
    if (!IsFFAGame()){
        float playerTeamFactor = 1.0
        float otherTeamFactor = 1.0
        int playerTeam = GetPlayerArrayOfTeam(player.GetTeam()).len() - 1
        int otherTeam = GetPlayerArrayOfTeam(GetOtherTeam(player.GetTeam())).len()

        foreach(entity player in GetPlayerArrayOfTeam(player.GetTeam()) ){
            playerTeamFactor *= CalculatePlayerRank( player )
        }
        foreach(entity player in GetPlayerArrayOfTeam(GetOtherTeam(player.GetTeam())) ){
            otherTeamFactor *= CalculatePlayerRank( player )
        }

        if (playerTeamFactor >= otherTeamFactor && playerTeam >= otherTeam){
            SetTeam(player, GetOtherTeam(player.GetTeam()))
        }
        else if(playerTeam > otherTeam){
            SetTeam(player, GetOtherTeam(player.GetTeam()))
        }
    }
}

// Check if playercount balancing is needed on death
void function OnDeathAutobalance( entity victim, entity attacker, var damageInfo ){
    if( waitedTime >= waitTime ){
        if ( differenceMax == 0 || IsFFAGame() || GetPlayerArray().len() == 1 || abs(GetPlayerArrayOfTeam(TEAM_IMC).len() - GetPlayerArrayOfTeam(TEAM_MILITIA).len()) <= differenceMax || GameTime_TimeLeftSeconds() < 60 ){
            return
        }

        // Compare victims teams size
        if ( GetPlayerArrayOfTeam(victim.GetTeam()).len() < GetPlayerArrayOfTeam(GetOtherTeam(victim.GetTeam())).len() ){
            return
        }

        // Check if switching this player over would create significantly worse teams
        float victimTeam = 1.0
        float opposingTeam = 1.0
        foreach(entity player in GetPlayerArrayOfTeam( victim.GetTeam() )){
            victimTeam *= CalculatePlayerRank( player )
        }
        foreach(entity player in GetPlayerArrayOfTeam( GetOtherTeam( victim.GetTeam() ) )){
            opposingTeam *= CalculatePlayerRank( player )
        }
        if ( fabs(victimTeam - opposingTeam) < fabs((opposingTeam*CalculatePlayerRank(victim)) - (victimTeam/CalculatePlayerRank(victim))) - 0.12 ){
            return
        }

        // Passed checks, balance the teams
        print("[BTB] The team of " + victim.GetPlayerName() + " has been switched")
        SetTeam( victim, GetOtherTeam( victim.GetTeam() ) )
        Chat_ServerPrivateMessage( victim, AdminColor("Your team has been switched to balance the game!"), false )
        waitedTime = 1
    }
}

// Count votes for !balance, and activate, when enough have voted for it
void function BTB_BalanceVote ( entity player, array < string > args ){
    if ( GetMapName() == "mp_lobby" ){
        Chat_ServerPrivateMessage( player, ErrorColor("Can't balance in lobby"), false )
        return
    }

    if ( GetGameState() != eGameState.Playing ){
        Chat_ServerPrivateMessage( player, ErrorColor("Can't balance in this game state"), false )
        return
    }

    if ( rebalancedHasOccurred == 1 ){
        Chat_ServerPrivateMessage( player, ErrorColor("Teams have already been balanced!"), false )
        return
    }

    if ( GameRules_GetTeamScore(TEAM_MILITIA) > GameRules_GetTeamScore(TEAM_IMC) ){
        relativeScoreDifference = 1.0 * GameRules_GetTeamScore(TEAM_MILITIA) / GameRules_GetTeamScore(TEAM_IMC)
    }
    else{
        relativeScoreDifference = 1.0 * GameRules_GetTeamScore(TEAM_IMC) / GameRules_GetTeamScore(TEAM_MILITIA)
    }

    if ( relativeScoreDifference < 1.2 ){
        Chat_ServerPrivateMessage( player, ErrorColor("There is no need for a rebalance!"), false )
        return
    }

    if ( GetPlayerArray().len() < 6 ){
        Chat_ServerPrivateMessage( player, ErrorColor("Not enough players for a good rebalance!"), false )
        return
    }

    if ( matchElapsed < 21 ){
        Chat_ServerPrivateMessage( player, ErrorColor("It is too soon for a rebalance!"), false )
        return
    }

    if ( playersWantingToBalance.find( player ) != -1 ){
        Chat_ServerPrivateMessage( player, ErrorColor("You have already voted!"), false )
        return
    }

    playersWantingToBalance.append( player )


    int required_players = int ( GetPlayerArray().len() * voteFraction )
    if ( required_players == 0 ){
        required_players = 1
    }

    if ( playersWantingToBalance.len() >= required_players ){
        print("[BTB] Team skill balancing triggered by vote")
        ExecuteStatsBalance( GetPlayersSortedBySkill() )
        Chat_ServerBroadcast( SuccessColor("Teams and scores have rebalanced!") )
        rebalancedHasOccurred = 1
    }
    else{
        Chat_ServerBroadcast( AccentTwo("[" + playersWantingToBalance.len() + "/" + required_players + "]") + AnnounceColor(" players want to rebalance the teams and scores, ") + AccentOne(FSU_GetString("FSU_PREFIX") + "teambalance") + AnnounceColor(".") )
    }
}

// Execute balancing
void function ExecuteStatsBalance( array<PlayerRankArray> playerRanks ){

    float imcTeamFactor = 1.0
    float milTeamFactor = 1.0
    array <int> imcIndex = [0]
    array <int> milIndex = [1]

    // Initial team division, get as close to equal as possible assigning one player at a time and keeping team sizes equal
    for(int i = 0; i < GetPlayerArray().len(); i++){
        // Start by placing two best players onto opposing teams
        if ( i == 0 ){
            SetTeam(playerRanks[i].player, TEAM_IMC)
            imcTeamFactor = playerRanks[i].scorekd
        }
        else if( i == 1 ){
            SetTeam(playerRanks[i].player, TEAM_MILITIA)
            milTeamFactor = playerRanks[i].scorekd
        }

        // Go through the next players in pairs, placing the better of each pair onto the weaker team and vice versa
        if ( !IsEven(i) && i > 1 ){
            if ( imcIndex.len() < milIndex.len() ){
                SetTeam(playerRanks[i].player, TEAM_IMC)
                imcTeamFactor *= playerRanks[i].scorekd
                imcIndex.append(i)
            }
            else{
                SetTeam(playerRanks[i].player, TEAM_MILITIA)
                milTeamFactor *= playerRanks[i].scorekd
                milIndex.append(i)
            }
        }
        else if( i > 1 ){
            if ( imcTeamFactor < milTeamFactor ){
                SetTeam(playerRanks[i].player, TEAM_IMC)
                imcTeamFactor *=  playerRanks[i].scorekd
                imcIndex.append(i)
            }
            else{
                SetTeam(playerRanks[i].player, TEAM_MILITIA)
                milTeamFactor *= playerRanks[i].scorekd
                milIndex.append(i)
            }
        }
    }

// Debugging prints
//     foreach( int i in imcIndex ){
//         print ( "[BTB] TEAM IMC - RANK:" + i + " - " + playerRanks[i].player.GetPlayerName() )
//     }
//     foreach( int i in milIndex ){
//         print ( "[BTB] TEAM MIL - RANK:" + i + " - " + playerRanks[i].player.GetPlayerName() )
//     }

    print( "[BTB] Initial team strength difference: " + fabs(imcTeamFactor-milTeamFactor) )

    // If at least four players present, attempt to refine team balancing further, should it be needed
    if ( GetPlayerArray().len() > 3 && fabs(imcTeamFactor - milTeamFactor) > 0.10){
        for (int loop = 0 ; loop < (GetPlayerArray().len()/2)-1.5 ; loop++) {
            float newImcFactor
            float newMilFactor

            // Check which team needs better players (determines angle of diagonal swap)
            if ( imcTeamFactor < milTeamFactor ){
                newImcFactor = imcTeamFactor/playerRanks[imcIndex[loop+1]].scorekd*playerRanks[milIndex[loop]].scorekd
                newMilFactor = milTeamFactor/playerRanks[milIndex[loop]].scorekd*playerRanks[imcIndex[loop+1]].scorekd

                // If this swap would be better, perform it
                if ( fabs(newImcFactor - newMilFactor) < fabs(imcTeamFactor - milTeamFactor) ){

                    //Set teams
                    SetTeam( playerRanks[imcIndex[loop+1]].player, TEAM_MILITIA )
                    SetTeam( playerRanks[milIndex[loop]].player, TEAM_IMC )
                    // Debugging print
                    //print( "[BTB] " + playerRanks[imcIndex[loop+1]].player.GetPlayerName() + " was swapped with " + playerRanks[milIndex[loop]].player.GetPlayerName() )

                    // Do a switcharoo of team indexes
                    int imcToMil = imcIndex[loop+1]
                    int milToImc = milIndex[loop]
                    imcIndex.insert( loop , milToImc )
                    milIndex.insert( loop , imcToMil )
                    milIndex.remove( milIndex.find(milToImc) )
                    imcIndex.remove( imcIndex.find(imcToMil) )

                    // Apply new factors
                    imcTeamFactor = newImcFactor
                    milTeamFactor = newMilFactor
                }
            }
            else {
                newImcFactor = imcTeamFactor/playerRanks[imcIndex[loop]].scorekd*playerRanks[milIndex[loop+1]].scorekd
                newMilFactor = milTeamFactor/playerRanks[milIndex[loop+1]].scorekd*playerRanks[imcIndex[loop]].scorekd

                // If this swap would be better, perform it
                if ( fabs(newImcFactor - newMilFactor) < fabs(imcTeamFactor - milTeamFactor) ){

                    //Set teams
                    SetTeam( playerRanks[imcIndex[loop]].player, TEAM_MILITIA )
                    SetTeam( playerRanks[milIndex[loop+1]].player, TEAM_IMC )
                    // Debugging print
                    //print( "[BTB] " + playerRanks[imcIndex[loop]].player.GetPlayerName() + " was swapped with " + playerRanks[milIndex[loop+1]].player.GetPlayerName() )

                    // Do a switcharoo of team indexes
                    int imcToMil = imcIndex[loop]
                    int milToImc = milIndex[loop+1]
                    imcIndex.insert( loop , milToImc )
                    milIndex.insert( loop , imcToMil )
                    imcIndex.remove( imcIndex.find(imcToMil) )
                    milIndex.remove( milIndex.find(milToImc) )

                    // Apply new factors
                    imcTeamFactor = newImcFactor
                    milTeamFactor = newMilFactor
                }
            }

            // Calculate potential of vertical swap
            newImcFactor = imcTeamFactor/playerRanks[imcIndex[loop+1]].scorekd*playerRanks[milIndex[loop+1]].scorekd
            newMilFactor = milTeamFactor/playerRanks[milIndex[loop+1]].scorekd*playerRanks[imcIndex[loop+1]].scorekd

            // If this swap would be better, perform it
            if ( fabs(newImcFactor - newMilFactor) < fabs(imcTeamFactor - milTeamFactor) ){

                //Set teams
                SetTeam( playerRanks[imcIndex[loop+1]].player, TEAM_MILITIA )
                SetTeam( playerRanks[milIndex[loop+1]].player, TEAM_IMC )
                // Debugging print
                //print( "[BTB] " + playerRanks[imcIndex[loop+1]].player.GetPlayerName() + " was swapped with " + playerRanks[milIndex[loop+1]].player.GetPlayerName() )

                // Do a switcharoo of team indexes
                int imcToMil = imcIndex[loop+1]
                int milToImc = milIndex[loop+1]
                imcIndex.insert( loop+1 , milToImc )
                milIndex.insert( loop+1 , imcToMil )
                milIndex.remove( milIndex.find(milToImc) )
                imcIndex.remove( imcIndex.find(imcToMil) )


                // Apply new factors
                imcTeamFactor = newImcFactor
                milTeamFactor = newMilFactor
            }

            print( "[BTB] Pass " + (loop+1) + " - team strength difference: " + fabs(imcTeamFactor-milTeamFactor) )

// Debugging prints
//             foreach( int i in imcIndex ){
//                 print ( "[BTB] TEAM IMC - RANK: " + i + " - " + playerRanks[i].player.GetPlayerName() )
//             }
//             foreach( int i in milIndex ){
//                 print ( "[BTB] TEAM MIL - RANK: " + i + " - " + playerRanks[i].player.GetPlayerName() )
//             }

            // Stop loop if small enough difference achieved
            if ( fabs(imcTeamFactor - milTeamFactor) < 0.10 ){
                break
            }
        }
    }

    print( "[BTB] Final team strength difference: " + fabs(imcTeamFactor-milTeamFactor) )

// Debugging prints
//     imcTeamFactor = 1.0
//     milTeamFactor = 1.0
//     for(int i = 0; i < GetPlayerArray().len(); i++){
//         if (playerRanks[i].player.GetTeam() == TEAM_IMC){
//             imcTeamFactor *= playerRanks[i].scorekd
//         }
//         else{
//             milTeamFactor *= playerRanks[i].scorekd
//         }
//     }
//
//     print( "[BTB] Confirm imcTeamStrength: " + imcTeamFactor )
//     print( "[BTB] COnfirm milTeamStrength: " + milTeamFactor )

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

// Sort players by their ranking
array<PlayerRankArray> function GetPlayersSortedBySkill(){
    array <PlayerRankArray> pskdArr
    foreach (entity player in GetPlayerArray()) {
        PlayerRankArray temp
        temp.player = player
        temp.scorekd = CalculatePlayerRank(player)
        pskdArr.append(temp)
    }
    pskdArr.sort(PlayerRankArraySort)
    return pskdArr
}

int function PlayerRankArraySort(PlayerRankArray data1, PlayerRankArray data2)
{
  if ( data1.scorekd == data2.scorekd )
    return 0
  return data1.scorekd < data2.scorekd ? 1 : -1
}


// Main thread
void function BTBThread(){
    wait 10
    while (true){
        wait 10

        // Check for player count imbalance
        if (differenceMax != 0 && !IsFFAGame() && GetPlayerArray().len() > 1 && GameTime_TimeLeftSeconds() > 60){
            int difference = abs(GetPlayerArrayOfTeam(TEAM_IMC).len() - GetPlayerArrayOfTeam(TEAM_MILITIA).len())

            if (difference > differenceMax)
                waitedTime += difference - differenceMax
            else{
                waitedTime = 0
            }
            if (matchElapsed < 4){
                waitedTime = 30
            }
        }

        // Check for score imbalance
        int imcScore = GameRules_GetTeamScore(TEAM_IMC)
        int militiaScore = GameRules_GetTeamScore(TEAM_MILITIA)

        if (suggestionLimit != 0 || stompLimit != 0 ){
            if (matchElapsed > 14 && imcScore > 5 && militiaScore > 5 && rebalancedHasOccurred == 0 && GameTime_TimeLeftSeconds() > 300 && GetPlayerArray().len() > 5){

                // Calculate the relative difference of the score between teams
                if (militiaScore > imcScore){
                    relativeScoreDifference = 1.0 * militiaScore / imcScore
                }
                else{
                    relativeScoreDifference = 1.0 * imcScore / militiaScore
                }

                // Accrue a value if above the treshold, decay when below
                if (suggestionLimit != 0 && relativeScoreDifference > suggestionLimit){
                    accumulatedSuggestionImbalance += 1.0 + ((relativeScoreDifference - suggestionLimit) * 1.5 )
                    print("[BTB] accumulated suggestion imbalance/threshold: " + accumulatedSuggestionImbalance + " / " + suggestionTimer)
                }
                else{
                    accumulatedSuggestionImbalance -= 1.5
                    if (accumulatedSuggestionImbalance < 0){
                        accumulatedSuggestionImbalance = 0
                        suggestionTimer = 12.0
                    }
                    else{
                        print("[BTB] accumulated suggestion imbalance/threshold: " + accumulatedSuggestionImbalance + " / " + suggestionTimer)
                    }
                }
                // Activate suggestion for rebalance when accrued enough value, set a new treshold when to suggest again
                if (accumulatedSuggestionImbalance > suggestionTimer){
                    print("[BTB] Match is uneven, suggesting rebalance")
                    Chat_ServerBroadcast( AnnounceColor("Looks like this match is uneven, if you'd like to rebalance the teams and their scores, use ") + AccentOne(FSU_GetString("FSU_PREFIX") + "teambalance") + AnnounceColor(".") )
                    suggestionTimer += suggestionTimer * 1.4
                }

                // Accrue a value if above the treshold, decay when below
                if (stompLimit != 0 && relativeScoreDifference > stompLimit){
                    accumulatedStompImbalance += 1.0 + ((relativeScoreDifference - stompLimit) * 1.5)
                    print("[BTB] accumulated stomp imbalance/threshold: " + accumulatedStompImbalance + " / 18")
                }
                else{
                    accumulatedStompImbalance = -1.5
                    if (accumulatedStompImbalance < 0){
                        accumulatedStompImbalance = 0
                    }
                    else {
                        print("[BTB] accumulated stomp imbalance/threshold: " + accumulatedStompImbalance + " / 18")
                    }
                }
                // Activate forced rebalance when accrued enough value
                if (accumulatedStompImbalance > 18 && matchElapsed > 18){
                    print("[BTB] Match is very uneven, forcing rebalance")
                    Chat_ServerBroadcast( ErrorColor("Very uneven match detected! ") + AnnounceColor("Teams and scores have been automatically rebalanced.") )
                    ExecuteStatsBalance( GetPlayersSortedBySkill() )
                    rebalancedHasOccurred = 1
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

                // Ignore if player is FSU admin
                if (CheckAdmin(player)){
                    break
                }

                // Warn or kick player
                switch (GetAfkState(player)){
                    case eAntiAfkPlayerState.SUSPICIOUS:
                        Chat_ServerPrivateMessage( player, ErrorColor("You will soon be kicked for being AFK! MOVE!!!"), false )
                        SendHudMessage( player, "YOU ARE AFK! MOVE!!!", -1, 0.35, 255, 80, 80, 255, 0.15, 5, 0.15 )
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
    }
}

bool function CheckAdmin( entity player ){
    foreach (string uid in FSU_GetArray("FSU_ADMIN_UIDS")){
        if( player.GetUID() == uid ){
            return true
        }
    }
    return false
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
