global function BTBToneInit
global function BTBGetToneKD

table <string, float> toneKDs
array <string> previusMatchUID
string toneurl
bool toneEnabled = false

void function BTBToneInit(){
    toneurl = GetConVarString( "btb_tone_url" )
    toneEnabled = GetConVarBool( "btb_tone" )

    if( toneEnabled ){
        previusMatchUID = split( GetConVarString( "uid_list" ), "," )
        AddCallback_OnClientConnecting( CheckPlayer )
    }
}

float function BTBGetToneKD( entity player ){
    if( player.GetPlayerName() in toneKDs ){
        return toneKDs[player.GetPlayerName()]
    }

    return 0.0
}

void function CheckPlayer( entity player ){

    // Only get the stats of new players
    foreach( uid in previusMatchUID )
        if( uid == player.GetUID() )
            return

    print("[BTB][NuTone API] Attempting to get stats for " + player.GetPlayerName())
    SaveToneKD( player.GetUID() )
}

void function SaveToneKD(string uid){

    HttpRequest request = { ... }
    request.method = HttpRequestMethod.GET
    request.url = toneurl + uid

    void functionref( HttpRequestResponse ) OnSuccess = void function ( HttpRequestResponse response )
    {
        try{
            if(response.statusCode == 200){
                table decoded = DecodeJSON(response.body)
                string user = expect string(decoded["name"])
                float kd = expect int(decoded["kills"]).tofloat() / expect int(decoded["deaths"]).tofloat()
                toneKDs[user] <- kd
                print("[BTB][NuTone API] Succesfully grabbed stats for " + user + ": " + kd )
            }else{
                print("[BTB][NuTone API] NuTone does not have stats for this player")
            }
        }catch(exception){
            print("[BTB][NuTone API] There was a response, but it could not be decoded")
            print(response.body)
        }
    }

    void functionref( HttpRequestFailure ) OnFailure = void function ( HttpRequestFailure failure )
    {
        print("[BTB][NuTone API] NuTone server unavailable")
        print("[BTB][NuTone API] " + failure.errorMessage )
    }

    NSHttpRequest(request, OnSuccess, OnFailure)
}
