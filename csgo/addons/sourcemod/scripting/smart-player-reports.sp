#define PLUGIN_VERSION "1.0.0"
#define SPR_LIBRARY_VERSION PLUGIN_VERSION

#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <smlib>



/***********************
 *                     *
 *  Global Variables   *
 *                     *
 ***********************/

#define CHAT_PREFIX " \x04[SPR]\x01 "
#define REPORTS_TABLE_NAME "smart_player_reports"

 new String:g_ReportStrings[][] = {
    "Abusive voice chat",
    "Abusive text chat",
    "Hacking",
    "Griefing",
    "Breaking general server rules",
    "Other"
 };

/** ConVar handles **/
new Handle:g_hDemoDuration = INVALID_HANDLE;
new Handle:g_hDatabaseName = INVALID_HANDLE;
new Handle:g_hLogToAdmins = INVALID_HANDLE;
new Handle:g_hLogToDatabase = INVALID_HANDLE;
new Handle:g_hLogToFile = INVALID_HANDLE;
new Handle:g_hMaxSavedReports = INVALID_HANDLE;
new Handle:g_hReportsPerMap = INVALID_HANDLE;
new Handle:g_hVersion = INVALID_HANDLE;
new Handle:g_hWeightToDemo = INVALID_HANDLE;
new Handle:g_hWeightSourcePlugin = INVALID_HANDLE;

/** Database interactions **/
new bool:g_dbConnected = false;
new Handle:db = INVALID_HANDLE;
new String:g_sqlBuffer[1024];

/** Reporting logic **/
new bool:g_Recording = false;
new bool:g_StopRecordingSignal = false;

/** map(client -> report count) **/
new Handle:g_ReportCount = INVALID_HANDLE;

/** map(victim -> cumulative report weight) **/
new Handle:g_ReportedWeight = INVALID_HANDLE;

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

        new any:result;
        Call_StartFunction(plugin, report_weight_function);
        Call_PushCell(client);
        Call_PushCell(victim);
        Call_Finish(result);
        return result;
    }
}

public any:DefaultReportWeight(client, victim) {
    return 1;
}


/***********************
 *                     *
 * Sourcemod functions *
 *                     *
 ***********************/

public Plugin:myinfo = {
    name = "Smart player report (SPR)",
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
    g_hLogToDatabase = CreateConVar("sm_spr_log_to_database", "1", "Should info about reports/demos be put into a MySQL database? Add a section for smart_player_reports to databases.cfg if needed. Data goes in the smart_player_reports table.");
    g_hLogToFile = CreateConVar("sm_spr_log_to_file", "1", "Should info about reports/demos be put into a sourcemod/logs file?");
    g_hMaxSavedReports = CreateConVar("sm_spr_max_reports_in_plugin", "1000", "Maximum number of (in-plugin) report weight values saved. The plugin tracks the report weight for each client reported, but must periodically clear the data - this number if the max reports being saved on the plugin. This has no effect on the logs or database results.");
    g_hReportsPerMap = CreateConVar("sm_spr_reports_per_map", "1", "How frequently can players make reports?");
    g_hDatabaseName = CreateConVar("sm_spr_database_name", "smart_player_reports", "Database to use in configs/databases.cfg");
    g_hWeightToDemo = CreateConVar("sm_spr_weight_to_demo", "5", "Report weight required to trigger a demo. Use -1 to never demo, 0 to always demo, higher values to require more weight.");
    g_hWeightSourcePlugin = CreateConVar("sm_spr_weight_source_plugin_filename", "", "Other plugin filename that provides a WeightFunction(client, victim) function. You must include the .smx extension. Use empty string for no external plugin.");

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

    g_ReportCount = CreateTrie();
    g_ReportedWeight = CreateTrie();
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

public Event_OnRoundPostStart(Handle:event, const String:name[], bool:dontBroadcast) {
    if (g_StopRecordingSignal) {
        g_Recording = false;
        g_StopRecordingSignal = false;
        ServerCommand("tv_stoprecord");
    }
}



/**********************************
 *                                *
 *   Player reporting functions   *
 *                                *
 **********************************/

 public CanReport(client, victim) {
    if (!IsValidClient(client) || !IsValidClient(victim) || IsFakeClient(client) || IsFakeClient(victim) || client == victim)
        return false;
    return true;
 }

 /**
 * Hook for player chat actions.
 */
public Action:Command_Say(client, const String:command[], argc) {
    decl String:text[192];
    if (GetCmdArgString(text, sizeof(text)) < 1)
        return Plugin_Continue;

    StripQuotes(text);

    // TODO(splewis): get .report <name> to work!

    new String:reportChatCommands[][] = { ".report", "!report" };
    for (new i = 0; i < sizeof(reportChatCommands); i++) {
        if (strcmp(text[0], reportChatCommands[i], false) == 0) {
            Command_Report(client, 0);
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

public Action:Command_Report(client, args) {
    new String:arg1[32];
    if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
        new target = FindTarget(client, arg1, true, false);
        if (target != -1 || !IsValidClient(target) || IsFakeClient(target)) {
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

    decl String:reporter_steamid[64];
    decl String:reported_steamid[64];
    GetClientAuthString(client, reporter_steamid, sizeof(reporter_steamid));
    GetClientAuthString(victim, reported_steamid, sizeof(reported_steamid));

    new report_count = 0;
    if (!GetTrieValue(g_ReportCount, reporter_steamid, report_count)) {
        report_count = 0;
    }
    report_count++;
    SetTrieValue(g_ReportCount, reporter_steamid, report_count);
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
        Report(client, g_Reporting[client], reason_index);
    } else if (action == MenuAction_End) {
        CloseHandle(menu);
    }
}

public Report(client, victim, reason_index) {
    if (!CanReport(client, victim))
        return;

    PluginMessage(client, "Thank you for your report.");

    new any:demo_weight = GetConVarInt(g_hWeightToDemo);
    new bool:log_to_db = GetConVarInt(g_hLogToDatabase) != 0;
    new bool:log_to_admin = GetConVarInt(g_hLogToAdmins) != 0;
    new bool:log_to_file = GetConVarInt(g_hLogToFile) != 0;
    new Float:demo_length = GetConVarFloat(g_hDemoDuration);
    new any:weight = ReportWeightHandler(client, victim);

    // Ignore negative weight reports
    if (weight < 0)
        return;

    decl String:reporter_name[64];
    decl String:reporter_steamid[64];
    decl String:reported_name[64];
    decl String:reported_steamid[64];
    decl String:ip[40];
    decl String:server[64];
    decl String:demo[128];

    GetClientName(client, reporter_name, sizeof(reporter_name));
    GetClientAuthString(client, reporter_steamid, sizeof(reporter_steamid));

    // Ignore someone that has used up their reports
    new report_count = 0;
    GetTrieValue(g_ReportCount, reporter_steamid, report_count);
    if (report_count > GetConVarInt(g_hReportsPerMap))
        return;

    GetClientName(victim, reported_name, sizeof(reported_name));
    GetClientAuthString(victim, reported_steamid, sizeof(reported_steamid));
    Server_GetIPString(ip, sizeof(ip));
    Format(server, sizeof(server), "%s:%d", ip, Server_GetPort());
    Format(demo, sizeof(demo), "");

    new any:current_weight = 0;
    if (!GetTrieValue(g_ReportedWeight, reported_steamid, current_weight)){
        current_weight = 0;
    }
    current_weight += weight;
    SetTrieValue(g_ReportedWeight, reported_steamid, current_weight);

    if (log_to_admin) {
        PluginMessageToAdmins("%N reported \x03%L: \x01weight \x04%d", client, victim, weight);
    }

    if (log_to_file) {
        new timeStamp = GetTime();
        decl String:formattedTime[128];
        FormatTime(formattedTime, sizeof(formattedTime), "%Y-%m-%d", timeStamp);

        decl String:logFile[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, logFile, sizeof(logFile), "logs/smart_player_reports_%s.log", formattedTime);
    }

    if (!g_Recording && current_weight >= demo_weight && demo_weight >= 0) {
        current_weight -= weight;
        SetTrieValue(g_ReportedWeight, reporter_steamid, current_weight);

        g_Recording = true;
        g_StopRecordingSignal = false;

        new timeStamp = GetTime();
        decl String:formattedTime[64];
        FormatTime(formattedTime, sizeof(formattedTime), "%F_%R", timeStamp);

        decl String:fileName[128];
        Format(fileName, sizeof(fileName), "report_%N_%s", victim, formattedTime);

        ServerCommand("tv_record %s", fileName);
        CreateTimer(demo_length, Timer_StopDemo, _, TIMER_FLAG_NO_MAPCHANGE);

        Format(demo, sizeof(demo), "%s.dem", fileName);

        if (log_to_admin)
            PluginMessageToAdmins("Now recording to \x04%s", fileName);
    }

    if (log_to_db) {
        if (!g_dbConnected)
            DB_Connect();

        if (g_dbConnected) {
            Format(g_sqlBuffer, sizeof(g_sqlBuffer), "INSERT INTO %s (reporter_name,reporter_steamid,reported_name,reported_steamid,weight,server,description,demo) VALUES ('%s', '%s', '%s', '%s', %d, '%s', '%s');",
                REPORTS_TABLE_NAME, reporter_name,reporter_steamid,reported_name,reported_steamid,weight,server,g_ReportStrings[reason_index],demo);
            SQL_TQuery(db, SQLErrorCheckCallback, g_sqlBuffer);
        }
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
        CreateTables();
        SQL_UnlockDatabase(db);
        g_dbConnected = true;
    }
}

public CreateTables() {
    Format(g_sqlBuffer, sizeof(g_sqlBuffer), "CREATE TABLE IF NOT EXISTS %s (id int NOT NULL AUTO_INCREMENT, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,reporter_name varchar(64) NOT NULL DEFAULT '', reporter_steamid varchar(64) NOT NULL DEFAULT '', reported_name varchar(64) NOT NULL DEFAULT '', reported_steamid varchar(64) NOT NULL DEFAULT '', weight int NOT null DEFAULT 0, description varchar(256) NOT NULL DEFAULT '', server varchar(64) NOT NULL DEFAULT '', demo varchar(128) NOT NULL DEFAULT '', PRIMARY KEY (id));",
           REPORTS_TABLE_NAME);
    SQL_FastQuery(db, g_sqlBuffer);
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
