#define PLUGIN_VERSION "0.1.0-dev"
#define REPORTS_TABLE_NAME "spr_reports"
#define PLAYERS_TABLE_NAME "spr_players"
#define INTEGER_STRING_LENGTH 20 // max number of digits a 64-bit integer can use up as a string
                                 // this is for converting ints to strings when setting menu values/cookies

/**
 * Function to identify if a client is valid and in game.
 */
stock bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}

stock bool IsPlayer(int client) {
    return IsValidClient(client) && !IsFakeClient(client);
}

stock bool IsPlayerAdmin(int client) {
    return IsPlayer(client) && GetAdminFlag(GetUserAdmin(client), Admin_Kick);
}

/**
 * Adds an integer to a menu as a string choice.
 */
stock void AddMenuInt(Handle menu, int value, const char[] display) {
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
stock void AddMenuBool(Handle menu, bool value, const char[] display) {
    int convertedInt = value ? 1 : 0;
    AddMenuInt(menu, convertedInt, display);
}

/**
 * Gets a boolean to a menu from a string choice.
 */
stock bool GetMenuBool(Handle menu, any:param2) {
    return GetMenuInt(menu, param2) != 0;
}

stock void PluginMessageToAll(const char[] format, any:...) {
    char formattedMsg[1024];
    VFormat(formattedMsg, sizeof(formattedMsg), format, 2);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            PrintToChat(i, formattedMsg);
        }
    }
}

stock void PluginMessageToAdmins(const char[] format, any:...) {
    char formattedMsg[1024];
    VFormat(formattedMsg, sizeof(formattedMsg), format, 2);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayerAdmin(i)) {
            PrintToChat(i, formattedMsg);
        }
    }
}

stock void PluginMessage(int client, const char[] format, any:...) {
    char formattedMsg[1024];
    VFormat(formattedMsg, sizeof(formattedMsg), format, 3);

    if (IsValidClient(client) && !IsFakeClient(client))
        PrintToChat(client, formattedMsg);
}

stock void SQL_CreateTable(Handle db_connection, const char[] table_name, const char[][] fields, int num_fields) {
    char buffer[1024];
    Format(buffer, sizeof(buffer), "CREATE TABLE IF NOT EXISTS %s (", table_name);
    for (int i = 0; i < num_fields; i++) {
        StrCat(buffer, sizeof(buffer), fields[i]);
        if (i != num_fields - 1)
            StrCat(buffer, sizeof(buffer), ", ");
    }
    StrCat(buffer, sizeof(buffer), ")");

    if (!SQL_FastQuery(db_connection, buffer)) {
        char err[255];
        SQL_GetError(db_connection, err, sizeof(err));
        LogError(err);
    }
}

stock void SQL_AddColumn(Handle db_connection, const char[] table_name, const char[] column_info) {
    char buffer[1024];
    Format(buffer, sizeof(buffer), "ALTER TABLE %s ADD COLUMN %s", table_name, column_info);
    if (!SQL_FastQuery(db_connection, buffer)) {
        char err[255];
        SQL_GetError(db_connection, err, sizeof(err));
        if (StrContains(err, "Duplicate column name", false) == -1) {
            LogError(err);
        }
    }
}
