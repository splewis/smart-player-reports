/**
 * Note that this plugin requires Voiceaanounce_ex to function;
 * see https://forums.alliedmods.net/showthread.php?t=245384
 */

#include <sourcemod>
#include <messagebot>
#include <smlib>
#include <voiceannounce_ex>
#include "include/spr.inc"
#include "spr/common.sp"

// TODO: move all of these into convars
#define MIN_TIME_TO_REPORT 120.0
#define MIN_RATIO_TO_REPORT 0.5
#define CHECK_INTERVAL 5.0
#define REPORT_WEIGHT 7.0

float g_MicUseTime[MAXPLAYERS+1];

public Plugin:myinfo = {
    name = "[SPR] Mic spam detector",
    author = "splewis",
    description = "Files reports on behalf of the server when mic spam is detected",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnPluginStart() {
    CreateTimer(CHECK_INTERVAL, Timer_CheckAllMics, _, TIMER_REPEAT);
}

public OnClientConnected(int client) {
    g_MicUseTime[client] = 0.0;
}

public Action Timer_CheckAllMics(Handle timer) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsClientSpeaking(i)) {
            CheckPlayerMicUsage(i);
            g_MicUseTime[i] += CHECK_INTERVAL;
        }
    }

    return Plugin_Continue;
}

public void CheckPlayerMicUsage(int client) {
    float ratio = g_MicUseTime[client] / Client_GetMapTime(client);
    if (Client_GetMapTime(client) >= MIN_TIME_TO_REPORT && ratio > MIN_RATIO_TO_REPORT) {
        CreateServerReport(client, "Mic spam", REPORT_WEIGHT);
        // Not really accurate anymore - but prevents future reports since we already
        // got one.
        g_MicUseTime[client] = 0.0;
    }
}
