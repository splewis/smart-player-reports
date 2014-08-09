#pragma semicolon 1
#include <sourcemod>
#include <smlib>
#include "spr/common.sp"



/***********************
 *                     *
 *  Global Variables   *
 *                     *
 ***********************/

new String:g_ReportStrings[][] = {
    "Being better than me",
    "Abusive voice chat",
    "Abusive text chat",
    "Hacking",
    "Griefing"
};

new String:g_ReportFields[][] = {
    "id INT NOT NULL AUTO_INCREMENT",
    "timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
    "reporter_steamid varchar(64) NOT NULL DEFAULT ''",
    "victim_name varchar(64) NOT NULL DEFAULT ''",
    "victim_steamid varchar(64) NOT NULL DEFAULT ''",
    "weight Float NOT NULL DEFAULT 0.0",
    "description varchar(256) NOT NULL DEFAULT ''",
    "server varchar(64) NOT NULL DEFAULT ''",
    "demo varchar(128) NOT NULL DEFAULT ''",
    "PRIMARY KEY (id)"
};

new String:g_PlayerFields[][] = {
    "steamid VARCHAR(64) NOT NULL DEFAULT '' PRIMARY KEY",
    "name VARCHAR(64) NOT NULL DEFAULT ''",
    "reputation FLOAT NOT NULL DEFAULT 10.0",
    "cumulative_weight FLOAT NOT NULL DEFAULT 0.0"
};

/** ConVar handles **/
new Handle:g_hDatabaseName = INVALID_HANDLE;
new Handle:g_hDemoDuration = INVALID_HANDLE;
new Handle:g_hLogToAdmins = INVALID_HANDLE;
new Handle:g_hLogToFile = INVALID_HANDLE;
new Handle:g_hReputationRecovery = INVALID_HANDLE;
new Handle:g_hVersion = INVALID_HANDLE;
new Handle:g_hWeightDecay = INVALID_HANDLE;
new Handle:g_hWeightSourcePlugin = INVALID_HANDLE;
new Handle:g_hWeightToDemo = INVALID_HANDLE;
new Handle:g_ReputationLossConstant = INVALID_HANDLE;

/** Forwards **/
new Handle:g_hOnReportFiled = INVALID_HANDLE;
new Handle:g_hOnDemoStart = INVALID_HANDLE;
new Handle:g_hOnDemoStop = INVALID_HANDLE;

/** Database interactions **/
new bool:g_dbConnected = false;
new Handle:db = INVALID_HANDLE;
new String:g_sqlBuffer[1024];

/** Reporting logic **/
new String:g_DemoName[PLATFORM_MAX_PATH];
new any:g_DemoReasonIndex = -1;
new any:g_DemoVictim = -1;
new String:g_DemoVictimSteamID[64] = "";
new String:g_DemoVictimName[64] = "";
new bool:g_Recording = false;
new bool:g_StopRecordingSignal = false;

new String:g_steamid[MAXPLAYERS+1][64];
new bool:g_FetchedData[MAXPLAYERS+1];
new Float:g_Reputation[MAXPLAYERS+1];
new Float:g_CumulativeWeight[MAXPLAYERS+1];

/** Which victim the client is trying to report **/
new any:g_Reporting[MAXPLAYERS+1] = 0;



/***************************
 *                         *
 *     Weight function     *
 *                         *
 ***************************/

public any:ReportWeightHandler(client, victim) {
    if (!CanReport(client, victim))
        return 0;

    decl String:plugin_weight_name[128];
    GetConVarString(g_hWeightSourcePlugin, plugin_weight_name, sizeof(plugin_weight_name));

    if (StrEqual("", plugin_weight_name)) {
        return DefaultReportWeight(client, victim);
    } else {
        new Handle:plugin = FindPluginByFile(plugin_weight_name);
        if (plugin == INVALID_HANDLE) {
            LogError("Failed to find plugin %s", plugin_weight_name);
            return DefaultReportWeight(client, victim);
        }

        new Function:report_weight_function = GetFunctionByName(plugin, "ReportWeight");
        if (report_weight_function == INVALID_FUNCTION) {
            LogError("Failed to find function %s in %s", "ReportWeight", plugin_weight_name);
            return DefaultReportWeight(client, victim);
        }

        new Float:result;
        Call_StartFunction(plugin, report_weight_function);
        Call_PushCell(client);
        Call_PushCell(victim);
        Call_Finish(result);
        return result;
    }
}

public Float:DefaultReportWeight(client, victim) {
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
    g_hDemoDuration = CreateConVar("sm_spr_demo_duration", "240.0", "Max length of a demo. The demo will be shorter if the map ends before this time runs out.", _, true, 30.0);
    g_hLogToAdmins = CreateConVar("sm_spr_log_to_admins", "1", "Should info about reports/demos be printed to admins on the server?");
    g_hLogToFile = CreateConVar("sm_spr_log_to_file", "1", "Should info about reports/demos be put into a sourcemod/logs file?");
    g_hDatabaseName = CreateConVar("sm_spr_database_name", "smart_player_reports", "Database to use in configs/databases.cfg");
    g_hWeightToDemo = CreateConVar("sm_spr_weight_to_demo", "10.0", "Report weight required to trigger a demo. Use a negative to never demo, 0.0 to always demo, higher values to require more weight.");
    g_hWeightSourcePlugin = CreateConVar("sm_spr_weight_source_plugin_filename", "", "Other plugin filename that provides a WeightFunction(client, victim) function. You must include the .smx extension. Use empty string for no external plugin.");
    g_hReputationRecovery = CreateConVar("sm_spr_reputation_recovery_per_minute", "0.02", "Increase in player reputation per minute of playtime");
    g_ReputationLossConstant = CreateConVar("sm_spr_reputation_loss_constant", "1.5", "Reputation loss = this constant / weight of report");
    g_hWeightDecay = CreateConVar("sm_spr_weight_decay_per_minute", "0.01", "Decrease in player weight per minute of playtime");

    /** Config file **/
    AutoExecConfig(true, "smart-player-reports", "sourcemod");

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
        Call_PushString(g_ReportStrings[g_DemoReasonIndex]);
        Call_PushString(g_DemoName);
        Call_Finish();
    }
}

public OnClientPostAdminCheck(client) {
    if (IsClientInGame(client) && !IsFakeClient(client) && g_dbConnected) {
        GetClientAuthString(client, g_steamid[client], 64);
        DB_AddPlayer(client);
    }
}

public OnClientDisconnect(client) {
    if (db != INVALID_HANDLE)
        DB_WritePlayerInfo(client);
    g_FetchedData[client] = false;
    if (g_DemoVictim == client)
        g_DemoVictim = -1;
}

public Event_OnRoundPostStart(Handle:event, const String:name[], bool:dontBroadcast) {
    if (g_StopRecordingSignal) {
        g_Recording = false;
        g_StopRecordingSignal = false;
        ServerCommand("tv_stoprecord");
        Call_StartForward(g_hOnDemoStop);
        Call_PushCell(g_DemoVictim);
        Call_PushString(g_DemoVictimName);
        Call_PushString(g_DemoVictimSteamID);
        Call_PushString(g_ReportStrings[g_DemoReasonIndex]);
        Call_PushString(g_DemoName);
        Call_Finish();
    }
}



/**********************************
 *                                *
 *   Player reporting functions   *
 *                                *
 **********************************/

public Action:Timer_ReputationIncrease(Handle:timer) {
    new Float:dr = GetConVarFloat(g_hReputationRecovery);
    new Float:dw = GetConVarFloat(g_hWeightDecay);
    for (new i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            g_Reputation[i] += dr;
            if (g_CumulativeWeight[i] > 0.0)
                g_CumulativeWeight[i] -= dw;
        }
    }
    return Plugin_Continue;
}

 public CanReport(reporter, victim) {
    if (!IsValidClient(reporter) || !IsValidClient(victim) || IsFakeClient(reporter) || IsFakeClient(victim) || reporter == victim)
        return false;
    return true;
 }

/**
 * Hook for player chat actions.
 */
public Action:Command_Say(client, const String:command[], argc) {
    decl String:cmd[192];

    if (GetCmdArgString(cmd, sizeof(cmd)) < 1) {
        return Plugin_Continue;

    } else {
        // Get command args
        StripQuotes(cmd);
        decl String:buffers[4][192];
        new numArgs = ExplodeString(cmd, " ", buffers, sizeof(buffers), 192);
        decl String:arg1[192];
        decl String:arg2[192];
        strcopy(arg1, sizeof(arg1), buffers[0]);
        strcopy(arg2, sizeof(arg2), buffers[1]);
        StripQuotes(arg1);
        StripQuotes(arg2);

        // Is this a report?
        new bool:isReport = false;
        new String:reportChatCommands[][] = { ".report", "!report" };
        for (new i = 0; i < sizeof(reportChatCommands); i++) {
            if (strcmp(buffers[0][0], reportChatCommands[i], false) == 0) {
                isReport = true;
            }
        }

        // File the report
        if (isReport) {
            if (numArgs <= 1) {
                ReportPlayerMenu(client);
            } else {
                new target = FindTarget(client, arg2, true, false);
                if (IsValidClient(target) && !IsFakeClient(target))
                    ReportReasonMenu(client, target);
            }
            return Plugin_Handled;
        } else {
            return Plugin_Continue;
        }

    }
}

public Action:Command_Report(client, args) {
    new String:arg1[32];
    if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
        new target = FindTarget(client, arg1, true, false);
        if (IsValidClient(target) && !IsFakeClient(target)) {
            ReportReasonMenu(client, target);
        }
    } else {
        ReportPlayerMenu(client);
    }
}

public ReportPlayerMenu(client) {
    new Handle:menu = CreateMenu(ReportPlayerMenuHandler);
    SetMenuTitle(menu, "Who are you reporting?");
    SetMenuExitButton(menu, true);
    new count = 0;
    for (new i = 1; i <= MaxClients; i++) {
        if (CanReport(client, i)) {
            decl String:display[64];
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

public ReportPlayerMenuHandler(Handle:menu, MenuAction:action, param1, param2) {
    if (action == MenuAction_Select) {
        new client = param1;
        new choice = GetMenuInt(menu, param2);
        ReportReasonMenu(client, choice);
    } else if (action == MenuAction_End) {
        CloseHandle(menu);
    }
}

public ReportReasonMenu(client, victim) {
    if (!CanReport(client, victim))
        return;

    g_Reporting[client] = victim;
    new Handle:menu = CreateMenu(ReportReasonMenuHandler);
    SetMenuTitle(menu, "Why are you reporting them?");
    for (new i = 0; i < sizeof(g_ReportStrings); i++)
        AddMenuInt(menu, i, g_ReportStrings[i]);
    DisplayMenu(menu, client, 15);
}

public ReportReasonMenuHandler(Handle:menu, MenuAction:action, param1, param2) {
    if (action == MenuAction_Select) {
        new client = param1;
        new reason_index = GetMenuInt(menu, param2);
        if (reason_index != 0)
            Report(client, g_Reporting[client], reason_index);
    } else if (action == MenuAction_End) {
        CloseHandle(menu);
    }
}

public Report(reporter, victim, reason_index) {
    PluginMessage(reporter, "Thank you for your report.");
    if (!CanReport(reporter, victim))
        return;

    new Float:weight = ReportWeightHandler(reporter, victim);
    if (weight < 0.0)
        return;

    Call_StartForward(g_hOnReportFiled);
    Call_PushCell(reporter);
    Call_PushCell(victim);
    Call_PushFloat(weight);
    Call_PushString(g_ReportStrings[reason_index]);
    Call_Finish();

    g_Reputation[reporter] -= GetConVarFloat(g_ReputationLossConstant) * weight;
    if (g_Reputation[reporter] < 0.0)
        return;

    new Float:demo_weight = GetConVarFloat(g_hWeightToDemo);
    new bool:log_to_admin = GetConVarInt(g_hLogToAdmins) != 0;
    new bool:log_to_file = GetConVarInt(g_hLogToFile) != 0;
    new Float:demo_length = GetConVarFloat(g_hDemoDuration);

    decl String:reporter_name[64];
    decl String:victim_name[64];
    decl String:victim_name_sanitized[64];
    decl String:ip[40];
    decl String:server[64];
    decl String:hostname[128];

    GetClientName(reporter, reporter_name, sizeof(reporter_name));
    GetClientName(victim, victim_name, sizeof(victim_name));
    SQL_EscapeString(db, victim_name, victim_name_sanitized, sizeof(victim_name));

    Server_GetIPString(ip, sizeof(ip));
    Format(server, sizeof(server), "%s:%d", ip, Server_GetPort());
    Server_GetHostName(hostname, sizeof(hostname));

    g_CumulativeWeight[victim] += weight;

    if (log_to_admin) {
        PluginMessageToAdmins("%N reported \x03%L \x01for %s",
                              reporter, victim, g_ReportStrings[reason_index]);
    }


    new timeStamp = GetTime();
    decl String:formattedTime[128];
    FormatTime(formattedTime, sizeof(formattedTime), "%Y-%m-%d_%H-%M", timeStamp);

    decl String:logFormattedTime[128];
    FormatTime(logFormattedTime, sizeof(logFormattedTime), "%Y-%m-%d", timeStamp);
    decl String:logFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, logFile, sizeof(logFile), "logs/smart_player_reports_%s.log", logFormattedTime);
    if (log_to_file) {
        LogToFile(logFile, "%L reported %L, weight: %f, reason: %s",
                  reporter, victim, weight, g_ReportStrings[reason_index]);
    }

    if (!g_Recording && g_CumulativeWeight[victim] >= demo_weight && demo_weight >= 0.0) {
        g_CumulativeWeight[victim] -= demo_weight;

        g_Recording = true;
        g_StopRecordingSignal = false;

        decl String:steamid_no_colons[64];
        strcopy(steamid_no_colons, 64, g_steamid[victim]);
        steamid_no_colons[7] = '-';
        steamid_no_colons[9] = '-';

        // format for tv_record command
        Format(g_DemoName, sizeof(g_DemoName), "report_%s_%s", steamid_no_colons, formattedTime);
        ServerCommand("tv_record \"%s\"", g_DemoName);
        CreateTimer(demo_length, Timer_StopDemo, _, TIMER_FLAG_NO_MAPCHANGE);

        // reformat with .dem extension for storage
        Format(g_DemoName, sizeof(g_DemoName), "report_%s_%s.dem", steamid_no_colons, formattedTime);
        if (log_to_admin)
            PluginMessageToAdmins("Now recording to \x04%s", g_DemoName);
        if (log_to_file)
            LogToFile(logFile, "Now recording to %s", g_DemoName);

        g_DemoVictim = victim;
        g_DemoReasonIndex = reason_index;
        strcopy(g_DemoVictimName, sizeof(g_DemoVictimName), victim_name);
        strcopy(g_DemoVictimSteamID, sizeof(g_DemoVictimSteamID), g_steamid[victim]);
        Call_StartForward(g_hOnDemoStart);
        Call_PushCell(victim);
        Call_PushString(g_DemoVictimName);
        Call_PushString(g_DemoVictimSteamID);
        Call_PushString(g_ReportStrings[reason_index]);
        Call_PushString(g_DemoName);
        Call_Finish();

    } else {
        Format(g_DemoName, sizeof(g_DemoName), "");
    }

    if (g_dbConnected) {
        Format(g_sqlBuffer, sizeof(g_sqlBuffer), "INSERT IGNORE INTO %s (reporter_steamid,victim_name,victim_steamid,weight,server,description,demo) VALUES ('%s', '%s', '%s', %f, '%s', '%s', '%s');",
            REPORTS_TABLE_NAME,
            g_steamid[reporter],
            victim_name_sanitized, g_steamid[victim],
            weight, server, g_ReportStrings[reason_index], g_DemoName);

        SQL_TQuery(db, SQLErrorCheckCallback, g_sqlBuffer);
    }
}

public Action:Timer_StopDemo(Handle:timer) {
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
public DB_Connect() {
    new String:error[255];
    new String:dbName[128];
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

public DB_AddPlayer(client) {
    // player name
    if (StrEqual(g_steamid[client], "")) {
        LogError("No steamid for %N", client);
        return;
    }

    decl String:name[64];
    GetClientName(client, name, sizeof(name));
    decl String:sanitized_name[64];
    SQL_EscapeString(db, name, sanitized_name, sizeof(name));

    // insert if not already in the table
    Format(g_sqlBuffer, sizeof(g_sqlBuffer), "INSERT IGNORE INTO %s (steamid,name) VALUES ('%s', '%s');",
           PLAYERS_TABLE_NAME, g_steamid[client], sanitized_name);
    SQL_TQuery(db, SQLErrorCheckCallback, g_sqlBuffer);

    // update the player name
    Format(g_sqlBuffer, sizeof(g_sqlBuffer), "UPDATE %s SET name = '%s' WHERE steamid = '%s'",
           PLAYERS_TABLE_NAME, sanitized_name, g_steamid[client]);
    SQL_TQuery(db, SQLErrorCheckCallback, g_sqlBuffer);

    Format(g_sqlBuffer, sizeof(g_sqlBuffer), "SELECT reputation, cumulative_weight FROM %s WHERE steamid = '%s';",
           PLAYERS_TABLE_NAME, g_steamid[client]);
    SQL_TQuery(db, T_FetchValues, g_sqlBuffer, client);
}

public T_FetchValues(Handle:owner, Handle:hndl, const String:error[], any:data) {
    new client = data;
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

public DB_WritePlayerInfo(client) {
    if (g_FetchedData[client]) {
        Format(g_sqlBuffer, sizeof(g_sqlBuffer), "UPDATE %s SET cumulative_weight = %f, reputation = %f WHERE steamid = '%s';",
               PLAYERS_TABLE_NAME, g_CumulativeWeight[client], g_Reputation[client], g_steamid[client]);
        SQL_TQuery(db, SQLErrorCheckCallback, g_sqlBuffer);
    }
}

/**
 * Generic SQL threaded query error callback.
 */
public SQLErrorCheckCallback(Handle:owner, Handle:hndl, const String:error[], any:data) {
    if (!StrEqual("", error)) {
        db = INVALID_HANDLE;
        g_dbConnected = false;
        LogError("Last Connect SQL Error: %s", error);
    }
}



/******************************
 *                            *
 *     Generic functions      *
 *                            *
 ******************************/

#define INTEGER_STRING_LENGTH 20 // max number of digits a 64-bit integer can use up as a string
                                 // this is for converting ints to strings when setting menu values/cookies

/**
 * Function to identify if a client is valid and in game.
 */
stock bool:IsValidClient(client) {
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}

stock bool:IsPlayer(client) {
    return IsValidClient(client) && !IsFakeClient(client);
}

/**
 * Adds an integer to a menu as a string choice.
 */
stock AddMenuInt(Handle:menu, any:value, String:display[]) {
    decl String:buffer[INTEGER_STRING_LENGTH];
    IntToString(value, buffer, sizeof(buffer));
    AddMenuItem(menu, buffer, display);
}

/**
 * Gets an integer to a menu from a string choice.
 */
stock any:GetMenuInt(Handle:menu, any:param2) {
    decl String:choice[INTEGER_STRING_LENGTH];
    GetMenuItem(menu, param2, choice, sizeof(choice));
    return StringToInt(choice);
}

/**
 * Adds a boolean to a menu as a string choice.
 */
stock AddMenuBool(Handle:menu, bool:value, String:display[]) {
    new convertedInt = value ? 1 : 0;
    AddMenuInt(menu, convertedInt, display);
}

/**
 * Gets a boolean to a menu from a string choice.
 */
stock bool:GetMenuBool(Handle:menu, any:param2) {
    return GetMenuInt(menu, param2) != 0;
}

stock bool:IsAdmin(client) {
    return IsValidClient(client) && !IsFakeClient(client) && CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK);
}

stock PluginMessageToAll(const String:msg[], any:...) {
    new String:formattedMsg[1024] = CHAT_PREFIX;
    decl String:tmp[1024];
    VFormat(tmp, sizeof(tmp), msg, 2);
    StrCat(formattedMsg, sizeof(formattedMsg), tmp);

    for (new i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && !IsFakeClient(i)) {
            PrintToChat(i, formattedMsg);
        }
    }
}

stock PluginMessageToAdmins(const String:msg[], any:...) {
    new String:formattedMsg[1024] = CHAT_PREFIX;
    decl String:tmp[1024];
    VFormat(tmp, sizeof(tmp), msg, 2);
    StrCat(formattedMsg, sizeof(formattedMsg), tmp);

    for (new i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && IsAdmin(i)) {
            PrintToChat(i, formattedMsg);
            PrintToConsole(i, formattedMsg);
        }
    }
}

stock PluginMessage(client, const String:msg[], any:...) {
    new String:formattedMsg[1024] = CHAT_PREFIX;
    decl String:tmp[1024];
    VFormat(tmp, sizeof(tmp), msg, 3);

    StrCat(formattedMsg, sizeof(formattedMsg), tmp);

    if (IsValidClient(client) && !IsFakeClient(client))
        PrintToChat(client, formattedMsg);
}

public SQL_CreateTable(Handle:db_connection, String:table_name[], String:fields[][], num_fields) {
    Format(g_sqlBuffer, sizeof(g_sqlBuffer), "CREATE TABLE IF NOT EXISTS %s (", table_name);
    for (new i = 0; i < num_fields; i++) {
        StrCat(g_sqlBuffer, sizeof(g_sqlBuffer), fields[i]);
        if (i != num_fields - 1)
            StrCat(g_sqlBuffer, sizeof(g_sqlBuffer), ", ");
    }
    StrCat(g_sqlBuffer, sizeof(g_sqlBuffer), ");");
    SQL_FastQuery(db_connection, g_sqlBuffer);
}
