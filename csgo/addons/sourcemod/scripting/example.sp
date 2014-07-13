#include <sourcemod>

public Plugin:myinfo = {
    name = "SPR example client plugin",
    author = "splewis",
    description = "SPR example plugin",
    version = "1.0",
    url = "https://github.com/splewis/smart-player-reports"
};

public bool:IsAdmin(client) {
    return CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK);
}

/**
 * Here's the important part.
 * All you need to do is add a function like this with the same name and signature.
 * A 0-weight report will generally have no effect (though it IS reported)
 * and negative-weight reports have no effect and are NOT reported.
 * Users are fully unaware of the weight of their report
 * You can do anything you want inside this function!
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
