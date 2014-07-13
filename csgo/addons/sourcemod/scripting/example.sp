#include <sourcemod>
#include "include/smart-player-reports.inc"

public Plugin:myinfo = {
    name = "SPR example client plugin",
    author = "splewis",
    description = "SPR example plugin",
    version = "1.0",
    url = "https://github.com/splewis/smart-player-reports"
};

public OnLibraryAdded(const String:name[]) {
    if (StrEqual(name, "smart-player-reports")) {
        SPR_RegisterWeightFunction("ReportWeight");
    }
}

public bool:IsAdmin(client) {
    return CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK);
}

/**
 * Here's the important part.
 * All you need to do is add a function like this (return any, take 2 any parameters)
 * and call RegisterWeightFunction with the function name somewhere, probably in
 * the plugin startup code.
 */
public any:ReportWeight(client, victim) {
    new weight = 1;

    // Count admins more heavily
    if (IsAdmin(client))
        weight += 2;

    // If no admin on the server, count reports more
    new bool:admin_on_server = false;
    for (new i = 1; i <= MaxClients; i++) {
        if (IsAdmin(i)) {
            admin_on_server = true;
            break;
        }
    }
    if (!admin_on_server)
        weight += 2;

    // You could even count reporters with a short steam ID more!
    decl String:steamid[64];
    if (GetClientAuthString(client, steamid, sizeof(steamid)) && strlen(steamid) < 10)
        weight += 1;

    return weight;
}
