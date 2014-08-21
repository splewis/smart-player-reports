#define PLUGIN_VERSION "0.1.0-dev"
#define CHAT_PREFIX "[\x05SPR\x01] "
#define REPORTS_TABLE_NAME "spr_reports"
#define PLAYERS_TABLE_NAME "spr_players"
#define INTEGER_STRING_LENGTH 20 // max number of digits a 64-bit integer can use up as a string
                                 // this is for converting ints to strings when setting menu values/cookies

char g_sqlBuffer[1024];

/**
 * Function to identify if a client is valid and in game.
 */
stock bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}

stock bool IsPlayer(int client) {
    return IsValidClient(client) && !IsFakeClient(client);
}

/**
 * Adds an integer to a menu as a string choice.
 */
stock void AddMenuInt(Handle menu, any:value, String:display[]) {
    char buffer[INTEGER_STRING_LENGTH];
    IntToString(value, buffer, sizeof(buffer));
    AddMenuItem(menu, buffer, display);
}

/**
 * Gets an integer to a menu from a string choice.
 */
stock int GetMenuInt(Handle menu, any:param2) {
    char choice[INTEGER_STRING_LENGTH];
    GetMenuItem(menu, param2, choice, sizeof(choice));
    return StringToInt(choice);
}

/**
 * Adds a boolean to a menu as a string choice.
 */
stock void AddMenuBool(Handle menu, bool value, char display[]) {
    int convertedInt = value ? 1 : 0;
    AddMenuInt(menu, convertedInt, display);
}

/**
 * Gets a boolean to a menu from a string choice.
 */
stock bool GetMenuBool(Handle menu, any:param2) {
    return GetMenuInt(menu, param2) != 0;
}

stock bool IsAdmin(client) {
    return IsValidClient(client) && !IsFakeClient(client) && CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK);
}

stock void PluginMessageToAll(const char format[], any:...) {
    char formattedMsg[1024] = CHAT_PREFIX;
    char tmp[1024];
    VFormat(tmp, sizeof(tmp), msg, 2);
    StrCat(formattedMsg, sizeof(formattedMsg), tmp);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && !IsFakeClient(i)) {
            PrintToChat(i, formattedMsg);
        }
    }
}

stock void PluginMessageToAdmins(const char format[], any:...) {
    char formattedMsg[1024] = CHAT_PREFIX;
    char tmp[1024];
    VFormat(tmp, sizeof(tmp), format, 2);
    StrCat(formattedMsg, sizeof(formattedMsg), tmp);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && IsAdmin(i)) {
            PrintToChat(i, formattedMsg);
            PrintToConsole(i, formattedMsg);
        }
    }
}

stock void PluginMessage(int client, const char format[], any:...) {
    char formattedMsg[1024] = CHAT_PREFIX;
    char tmp[1024];
    VFormat(tmp, sizeof(tmp), format, 3);

    StrCat(formattedMsg, sizeof(formattedMsg), tmp);

    if (IsValidClient(client) && !IsFakeClient(client))
        PrintToChat(client, formattedMsg);
}

stock void SQL_CreateTable(Handle dbConnection, char table_name[], char fields[][], int num_fields) {
    Format(g_sqlBuffer, sizeof(g_sqlBuffer), "CREATE TABLE IF NOT EXISTS %s (", table_name);
    for (int i = 0; i < num_fields; i++) {
        StrCat(g_sqlBuffer, sizeof(g_sqlBuffer), fields[i]);
        if (i != num_fields - 1)
            StrCat(g_sqlBuffer, sizeof(g_sqlBuffer), ", ");
    }
    StrCat(g_sqlBuffer, sizeof(g_sqlBuffer), ");");
    SQL_FastQuery(dbConnection, g_sqlBuffer);
}
