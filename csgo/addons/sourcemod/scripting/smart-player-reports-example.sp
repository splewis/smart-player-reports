#include <sourcemod>
#include <cstrike>

/***********************
 *                     *
 * Sourcemod functions *
 *                     *
 ***********************/

public Plugin:myinfo = {
    name = "SPR example client plugin",
    author = "splewis",
    description = "SPR example plugin",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-report"
};

public OnPluginStart() {
    LoadTranslations("common.phrases");
}

public OnMapStart() {
    g_Recording = false;
    g_StopRecordingSignal = false;
    if (!g_dbConnected && GetConVarInt(g_hLogToDatabase) != 0) {
        DB_Connect();
    }
}

public OnMapEnd() {
    ClearTrie(g_ReportCount);
    if (GetTrieSize(g_ReportedWeight) >= GetConVarInt(g_hMaxSavedReports))
        ClearTrie(g_ReportedWeight);
}

public any:DefaultReportWeight(client, victim) {
    return 1;
}
