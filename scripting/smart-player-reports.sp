#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include "spr/common.sp"
#include "include/spr.inc"



/***********************
 *                     *
 *  Global Variables   *
 *                     *
 ***********************/

char g_ReportStrings[][] = {
    "Being better than me",
    "Abusive voice chat",
    "Abusive text chat",
    "Hacking",
    "Griefing"
};

char g_ReportFields[][] = {
    "id INT NOT NULL AUTO_INCREMENT",
    "timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
    "reporter_steamid varchar(72) NOT NULL DEFAULT ''",
    "victim_name varchar(72) NOT NULL DEFAULT ''",
    "victim_steamid varchar(72) NOT NULL DEFAULT ''",
    "weight Float NOT NULL DEFAULT 0.0",
    "description varchar(256) NOT NULL DEFAULT ''",
    "server varchar(72) NOT NULL DEFAULT ''",
    "demo varchar(128) NOT NULL DEFAULT ''",
    "PRIMARY KEY (id)"
};

char g_PlayerFields[][] = {
    "steamid VARCHAR(72) NOT NULL DEFAULT '' PRIMARY KEY",
    "name VARCHAR(72) NOT NULL DEFAULT ''",
    "reputation FLOAT NOT NULL DEFAULT 10.0",
    "cumulative_weight FLOAT NOT NULL DEFAULT 0.0"
};

/** ConVar handles **/
Handle g_hAllowPlayerReports = INVALID_HANDLE;
Handle g_hAlwaysSaveRecords = INVALID_HANDLE;
Handle g_hDatabaseName = INVALID_HANDLE;
Handle g_hDemoDuration = INVALID_HANDLE;
Handle g_hReputationRecovery = INVALID_HANDLE;
Handle g_hVersion = INVALID_HANDLE;
Handle g_hWeightDecay = INVALID_HANDLE;
Handle g_hWeightSourcePlugin = INVALID_HANDLE;
Handle g_hWeightToDemo = INVALID_HANDLE;
Handle g_ReputationLossConstant = INVALID_HANDLE;

/** Forwards **/
Handle g_hOnReportFiled = INVALID_HANDLE;
Handle g_hOnDemoStart = INVALID_HANDLE;
Handle g_hOnDemoStop = INVALID_HANDLE;

/** Database interactions **/
bool g_dbConnected = false;
Handle db = INVALID_HANDLE;

/** Reporting logic **/
char g_DemoName[PLATFORM_MAX_PATH];
char g_DemoReason[256];
int g_DemoVictim = -1;
char g_DemoVictimSteamID[32] = "";
char g_DemoVictimName[32] = "";
bool g_Recording = false;
bool g_StopRecordingSignal = false;

char g_steamid[MAXPLAYERS+1][32];
bool g_FetchedData[MAXPLAYERS+1];
float g_Reputation[MAXPLAYERS+1];
float g_CumulativeWeight[MAXPLAYERS+1];

/** Which victim the client is trying to report **/
int g_Reporting[MAXPLAYERS+1] = 0;



/***************************
 *                         *
 *     Weight function     *
 *                         *
 ***************************/

public float ReportWeightHandler(int client, int victim) {
    if (!CanReport(client, victim))
        return 0.0;

    char plugin_weight_name[128];
    GetConVarString(g_hWeightSourcePlugin, plugin_weight_name, sizeof(plugin_weight_name));

    if (StrEqual("", plugin_weight_name)) {
        return DefaultReportWeight(client, victim);
    } else {
        Handle plugin = FindPluginByFile(plugin_weight_name);
        if (plugin == INVALID_HANDLE) {
            LogError("Failed to find plugin %s", plugin_weight_name);
            return DefaultReportWeight(client, victim);
        }

        Function report_weight_function = GetFunctionByName(plugin, "ReportWeight");
        if (report_weight_function == INVALID_FUNCTION) {
            LogError("Failed to find function %s in %s", "ReportWeight", plugin_weight_name);
            return DefaultReportWeight(client, victim);
        }

        float result = 0.0;
        Call_StartFunction(plugin, report_weight_function);
        Call_PushCell(client);
        Call_PushCell(victim);
        Call_Finish(result);
        return result;
    }
}

public float DefaultReportWeight(int client, int victim) {
    return 1.0;
}



/***********************
 *                     *
 * Sourcemod functions *
 *                     *
 ***********************/

public Plugin:myinfo = {
    name = "[SPR] Smart player reports base plugin",
    author = "splewis",
    description = "Enhanced tools for player reports",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnPluginStart() {
    LoadTranslations("common.phrases");

    /** ConVars **/
    g_hAllowPlayerReports = CreateConVar("sm_spr_allow_player_reports", "1", "Whether players are allowed to use the report commands");
    g_hAlwaysSaveRecords = CreateConVar("sm_always_save_record", "1", "If 0, reports that don't have a demo will not be sent to the database.");
    g_hDatabaseName = CreateConVar("sm_spr_database_name", "smart_player_reports", "Database to use in configs/databases.cfg");
    g_hDemoDuration = CreateConVar("sm_spr_demo_duration", "240.0", "Max length of a demo. The demo will be shorter if the map ends before this time runs out.", _, true, 30.0);
    g_hReputationRecovery = CreateConVar("sm_spr_reputation_recovery_per_minute", "0.02", "Increase in player reputation per minute of playtime");
    g_hWeightDecay = CreateConVar("sm_spr_weight_decay_per_minute", "0.01", "Decrease in player weight per minute of playtime");
    g_hWeightSourcePlugin = CreateConVar("sm_spr_weight_source_plugin_filename", "", "Other plugin filename that provides a WeightFunction(client, victim) function. You must include the .smx extension. Use empty string for no external plugin.");
    g_hWeightToDemo = CreateConVar("sm_spr_weight_to_demo", "10.0", "Report weight required to trigger a demo. Use a negative to never demo, 0.0 to always demo, higher values to require more weight.");
    g_ReputationLossConstant = CreateConVar("sm_spr_reputation_loss_constant", "1.5", "Reputation loss = this constant / weight of report");

    /** Config file **/
    AutoExecConfig(true, "smart-player-reports");

    /** Version cvar **/
    g_hVersion = CreateConVar("sm_smart_player_reports_version", PLUGIN_VERSION, "Current smart player reports version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
    SetConVarString(g_hVersion, PLUGIN_VERSION);

    /** Commands **/
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say2");
    AddCommandListener(Command_Say, "say_team");
    RegConsoleCmd("sm_report", Command_Report);

    /** Event Hooks **/
    HookEvent("round_poststart", Event_OnRoundPostStart);

    /** Forwards **/
    g_hOnReportFiled = CreateGlobalForward("OnReportFiled", ET_Ignore, Param_Cell, Param_Cell, Param_Float, Param_String);
    g_hOnDemoStart = CreateGlobalForward("OnDemoStart", ET_Ignore, Param_Cell, Param_String, Param_String, Param_String, Param_String);
    g_hOnDemoStop = CreateGlobalForward("OnDemoStop", ET_Ignore, Param_Cell, Param_String, Param_String, Param_String, Param_String);

    CreateTimer(60.0, Timer_ReputationIncrease, _, TIMER_REPEAT);

}

public OnMapStart() {
    g_steamid[0] = "SERVER";
    g_Recording = false;
    g_StopRecordingSignal = false;
    if (!g_dbConnected) {
        DB_Connect();
    }
}

public OnMapEnd() {
    if (g_Recording) {
        g_Recording = false;
        Call_StartForward(g_hOnDemoStop);
        Call_PushCell(g_DemoVictim);
        Call_PushString(g_DemoVictimName);
        Call_PushString(g_DemoVictimSteamID);
        Call_PushString(g_DemoReason);
        Call_PushString(g_DemoName);
        Call_Finish();
    }
}

public OnClientPostAdminCheck(int client) {
    if (IsClientInGame(client) && !IsFakeClient(client) && g_dbConnected &&
        GetClientAuthId(client, AuthId_Steam2, g_steamid[client], 32)) {

        DB_AddPlayer(client);
    }
}

public OnClientDisconnect(int client) {
    if (db != INVALID_HANDLE)
        DB_WritePlayerInfo(client);
    g_FetchedData[client] = false;
    if (g_DemoVictim == client)
        g_DemoVictim = -1;
}

public Event_OnRoundPostStart(Handle event, const char name[], bool dontBroadcast) {
    if (g_StopRecordingSignal) {
        g_Recording = false;
        g_StopRecordingSignal = false;
        ServerCommand("tv_stoprecord");
        Call_StartForward(g_hOnDemoStop);
        Call_PushCell(g_DemoVictim);
        Call_PushString(g_DemoVictimName);
        Call_PushString(g_DemoVictimSteamID);
        Call_PushString(g_DemoReason);
        Call_PushString(g_DemoName);
        Call_Finish();
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char error[], err_max) {
    CreateNative("CreateServerReport", Native_CreateServerReport);
    CreateNative("HasReportInfo", Native_HasReportInfo);
    CreateNative("GetReputation", Native_GetReputation);
    CreateNative("SetReputation", Native_SetReputation);
    CreateNative("ChangeReputation", Native_ChangeReputation);
    RegPluginLibrary("smart-player-reports");
    return APLRes_Success;
}

public Native_CreateServerReport(Handle plugin, numParams) {
    int client = GetNativeCell(1);
    char reason[256];
    GetNativeString(2, reason, sizeof(reason));
    float weight = GetNativeCell(3);
    ReportWithWeight(0, client, reason, weight);
    return true;
}


public Native_HasReportInfo(Handle plugin, numParams) {
    int client = GetNativeCell(1);
    return g_FetchedData[client];
}

public Native_GetReputation(Handle plugin, numParams) {
    int client = GetNativeCell(1);
    return _:g_Reputation[client];
}

public Native_SetReputation(Handle plugin, numParams) {
    int client = GetNativeCell(1);
    float reputation = Float:GetNativeCell(2);
    g_Reputation[client] = reputation;
}

public Native_ChangeReputation(Handle plugin, numParams) {
    int client = GetNativeCell(1);
    float delta = Float:GetNativeCell(2);
    g_Reputation[client] += delta;
}



/**********************************
 *                                *
 *   Player reporting functions   *
 *                                *
 **********************************/

public Action Timer_ReputationIncrease(Handle timer) {
    float dr = GetConVarFloat(g_hReputationRecovery);
    float dw = GetConVarFloat(g_hWeightDecay);
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            g_Reputation[i] += dr;
            if (g_CumulativeWeight[i] > 0.0)
                g_CumulativeWeight[i] -= dw;
        }
    }
    return Plugin_Continue;
}

 public bool CanReport(int reporter, int victim) {
    if (!IsValidClient(victim) || IsFakeClient(victim) || reporter == victim)
        return false;
    return true;
 }

/**
 * Hook for player chat actions.
 */
public Action Command_Say(int client, const char command[], int argc) {
    char cmd[192];

    if (GetCmdArgString(cmd, sizeof(cmd)) < 1) {
        return Plugin_Continue;

    } else {
        // Get command args
        StripQuotes(cmd);
        char buffers[4][192];
        int numArgs = ExplodeString(cmd, " ", buffers, sizeof(buffers), 192);
        char arg1[192];
        char arg2[192];
        strcopy(arg1, sizeof(arg1), buffers[0]);
        strcopy(arg2, sizeof(arg2), buffers[1]);
        StripQuotes(arg1);
        StripQuotes(arg2);

        // Is this a report?
        bool isReport = false;
        char reportChatCommands[][] = { ".report", "!report" };
        for (int i = 0; i < sizeof(reportChatCommands); i++) {
            if (strcmp(buffers[0][0], reportChatCommands[i], false) == 0) {
                isReport = true;
            }
        }

        // File the report
        if (isReport) {
            if (numArgs <= 1) {
                ReportPlayerMenu(client);
            } else {
                int target = FindTarget(client, arg2, true, false);
                if (IsValidClient(target) && !IsFakeClient(target))
                    ReportReasonMenu(client, target);
            }
            return Plugin_Handled;
        } else {
            return Plugin_Continue;
        }

    }
}

public Action Command_Report(int client, args) {
    char arg1[32];
    if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
        int target = FindTarget(client, arg1, true, false);
        if (IsValidClient(target) && !IsFakeClient(target)) {
            ReportReasonMenu(client, target);
        }
    } else {
        ReportPlayerMenu(client);
    }
}

public void ReportPlayerMenu(int client) {
    Handle menu = CreateMenu(ReportPlayerMenuHandler);
    SetMenuTitle(menu, "Who are you reporting?");
    SetMenuExitButton(menu, true);
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (CanReport(client, i)) {
            char display[32];
            Format(display, sizeof(display), "%N", i);
            AddMenuInt(menu, i, display);
            count++;
        }
    }

    if (count > 0) {
        DisplayMenu(menu, client, 15);
    } else {
        PluginMessage(client, "There is nobody to report right now!");
        CloseHandle(menu);
    }
}

public ReportPlayerMenuHandler(Handle menu, MenuAction action, param1, param2) {
    if (action == MenuAction_Select) {
        int client = param1;
        int choice = GetMenuInt(menu, param2);
        ReportReasonMenu(client, choice);
    } else if (action == MenuAction_End) {
        CloseHandle(menu);
    }
}

public void ReportReasonMenu(int client, int victim) {
    if (!CanReport(client, victim))
        return;

    g_Reporting[client] = victim;
    Handle menu = CreateMenu(ReportReasonMenuHandler);
    SetMenuTitle(menu, "Why are you reporting them?");
    for (int i = 0; i < sizeof(g_ReportStrings); i++)
        AddMenuInt(menu, i, g_ReportStrings[i]);
    DisplayMenu(menu, client, 15);
}

public ReportReasonMenuHandler(Handle menu, MenuAction action, param1, param2) {
    if (action == MenuAction_Select) {
        int client = param1;
        int reasonIndex = GetMenuInt(menu, param2);
        if (reasonIndex != 0)
            Report(client, g_Reporting[client], reasonIndex);
    } else if (action == MenuAction_End) {
        CloseHandle(menu);
    }
}

public void ReportWithWeight(int reporter, int victim, char reason[], float weight) {
    if (GetConVarInt(g_hAllowPlayerReports) == 0 && reporter != 0)
        return;

    PluginMessage(reporter, "Thank you for your report.");
    if (!CanReport(reporter, victim) || !IsPlayer(victim))
        return;

    if (weight < 0.0)
        return;

    Call_StartForward(g_hOnReportFiled);
    Call_PushCell(reporter);
    Call_PushCell(victim);
    Call_PushFloat(weight);
    Call_PushString(reason);
    Call_Finish();

    if (reporter > 0) {
        g_Reputation[reporter] -= GetConVarFloat(g_ReputationLossConstant) * weight;
        if (g_Reputation[reporter] < 0.0)
            return;
    }

    float demo_weight = GetConVarFloat(g_hWeightToDemo);
    float demo_length = GetConVarFloat(g_hDemoDuration);

    char reporter_name[32];
    char victim_name[32];
    char reporter_name_sanitized[72];
    char victim_name_sanitized[72];

    GetNames(reporter, reporter_name, reporter_name_sanitized);
    GetNames(victim, victim_name, victim_name_sanitized);

    char ip[40];
    char server[64];

    Server_GetIPString(ip, sizeof(ip));
    Format(server, sizeof(server), "%s:%d", ip, Server_GetPort());

    g_CumulativeWeight[victim] += weight;
    bool recordingDemo = false;

    if (!g_Recording && g_CumulativeWeight[victim] >= demo_weight && demo_weight >= 0.0) {
        recordingDemo = true;
        g_CumulativeWeight[victim] -= demo_weight;

        g_Recording = true;
        g_StopRecordingSignal = false;

        char steamid_no_colons[64];
        strcopy(steamid_no_colons, 64, g_steamid[victim]);
        steamid_no_colons[7] = '-';
        steamid_no_colons[9] = '-';

        int timeStamp = GetTime();
        char formattedTime[128];
        FormatTime(formattedTime, sizeof(formattedTime), "%Y-%m-%d_%H-%M", timeStamp);

        // format for tv_record command
        Format(g_DemoName, sizeof(g_DemoName), "report_%s_%s", steamid_no_colons, formattedTime);
        ServerCommand("tv_record \"%s\"", g_DemoName);
        CreateTimer(demo_length, Timer_StopDemo, _, TIMER_FLAG_NO_MAPCHANGE);

        // reformat with .dem extension for storage
        Format(g_DemoName, sizeof(g_DemoName), "report_%s_%s.dem", steamid_no_colons, formattedTime);

        g_DemoVictim = victim;
        strcopy(g_DemoReason, sizeof(g_DemoReason), reason);
        strcopy(g_DemoVictimName, sizeof(g_DemoVictimName), victim_name);
        strcopy(g_DemoVictimSteamID, sizeof(g_DemoVictimSteamID), g_steamid[victim]);
        Call_StartForward(g_hOnDemoStart);
        Call_PushCell(victim);
        Call_PushString(g_DemoVictimName);
        Call_PushString(g_DemoVictimSteamID);
        Call_PushString(reason);
        Call_PushString(g_DemoName);
        Call_Finish();

    } else {
        Format(g_DemoName, sizeof(g_DemoName), "");
    }

    if (g_dbConnected && (GetConVarInt(g_hAlwaysSaveRecords) != 0 || recordingDemo)) {
        char buffer[1024];
        Format(buffer, sizeof(buffer), "INSERT IGNORE INTO %s (reporter_steamid,victim_name,victim_steamid,weight,server,description,demo) VALUES ('%s', '%s', '%s', %f, '%s', '%s', '%s');",
            REPORTS_TABLE_NAME,
            g_steamid[reporter],
            victim_name_sanitized, g_steamid[victim],
            weight, server, reason, g_DemoName);
        SQL_TQuery(db, SQLErrorCheckCallback, buffer);
    }
}

public void Report(int reporter, int victim, int reasonIndex) {
    ReportWithWeight(reporter, victim, g_ReportStrings[reasonIndex], ReportWeightHandler(reporter, victim));
}

public Action Timer_StopDemo(Handle timer) {
    if (g_Recording)
        g_StopRecordingSignal = true;
}



/******************************
 *                            *
 *   Database Interactions    *
 *                            *
 ******************************/

 /**
 * Attempts to connect to the database.
 * Creates the table if needed.
 */
public void DB_Connect() {
    char error[255];
    char dbName[128];
    GetConVarString(g_hDatabaseName, dbName, sizeof(dbName));

    db = SQL_Connect(dbName, true, error, sizeof(error));
    if (db == INVALID_HANDLE) {
        g_dbConnected = false;
        LogError("Could not connect: %s", error);
    } else {
        SQL_LockDatabase(db);
        SQL_CreateTable(db, REPORTS_TABLE_NAME, g_ReportFields, sizeof(g_ReportFields));
        SQL_CreateTable(db, PLAYERS_TABLE_NAME, g_PlayerFields, sizeof(g_PlayerFields));
        SQL_UnlockDatabase(db);
        g_dbConnected = true;
    }
}

public void DB_AddPlayer(int client) {
    // player name
    if (StrEqual(g_steamid[client], "")) {
        LogError("No steamid for %N", client);
        return;
    }

    char name[32];
    char sanitized_name[72];
    GetNames(client, name, sanitized_name);

    // insert if not already in the table
    char buffer[1024];
    Format(buffer, sizeof(buffer), "INSERT IGNORE INTO %s (steamid,name) VALUES ('%s', '%s');",
           PLAYERS_TABLE_NAME, g_steamid[client], sanitized_name);
    SQL_TQuery(db, Callback_Insert, buffer, GetClientSerial(client));

}

public Callback_Insert(Handle owner, Handle hndl, const char error[], int serial) {
    if (!StrEqual("", error)) {
        LogError("Last Connect SQL Error: %s", error);
    } else {
        int client = GetClientFromSerial(serial);
        if (client == 0)
            return;

        int id = GetSteamAccountID(client);

        if (id > 0) {
            char name[32];
            char sanitized_name[72];
            GetNames(client, name, sanitized_name);

            char buffer[1024];
            Format(buffer, sizeof(buffer), "UPDATE %s SET name = '%s' WHERE steamid = '%s'",
                   PLAYERS_TABLE_NAME, sanitized_name, g_steamid[client]);
            SQL_TQuery(db, SQLErrorCheckCallback, buffer);

            Format(buffer, sizeof(buffer), "SELECT reputation, cumulative_weight FROM %s WHERE steamid = '%s';",
                   PLAYERS_TABLE_NAME, g_steamid[client]);
            SQL_TQuery(db, Callback_FetchValues, buffer, serial);
        }
    }
}

public Callback_FetchValues(Handle owner, Handle hndl, const char error[], int serial) {
    int client = GetClientFromSerial(serial);
    g_FetchedData[client] = false;
    if (!IsPlayer(client))
        return;

    if (hndl == INVALID_HANDLE) {
        LogError("Query failed: (error: %s)", error);
    } else if (SQL_FetchRow(hndl)) {
        g_Reputation[client] = SQL_FetchFloat(hndl, 0);
        g_CumulativeWeight[client] = SQL_FetchFloat(hndl, 1);
        g_FetchedData[client] = true;
    } else {
        LogError("Couldnt' get results for %N", client);
    }
}

public void DB_WritePlayerInfo(int client) {
    if (g_FetchedData[client]) {
        char buffer[256];
        Format(buffer, sizeof(buffer), "UPDATE %s SET cumulative_weight = %f, reputation = %f WHERE steamid = '%s';",
               PLAYERS_TABLE_NAME, g_CumulativeWeight[client], g_Reputation[client], g_steamid[client]);
        SQL_TQuery(db, SQLErrorCheckCallback, buffer);
    }
}

/**
 * Generic SQL threaded query error callback.
 */
public SQLErrorCheckCallback(Handle owner, Handle hndl, const char error[], data) {
    if (!StrEqual("", error)) {
        db = INVALID_HANDLE;
        g_dbConnected = false;
        LogError("Last Connect SQL Error: %s", error);
    }
}

public bool GetNames(int client, char name[32], char sanitized[72]) {
    if (client == 0) {
        Format(name, sizeof(name), "SERVER");
    } else {
        if (!GetClientName(client, name, sizeof(name))) {
            LogError("Failed to get name for %L", client);
            return false;
        }
    }

    if (!SQL_EscapeString(db, name, sanitized, sizeof(sanitized))) {
        LogError("Failed to get sanitized name for %L", client);
        return false;
    }

    return true;
}
