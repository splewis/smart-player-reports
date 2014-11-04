#include <sourcemod>
#include "include/spr.inc"
// Note: you don't actually need to include the spr.inc file, but
// it's good practice to do so. That way you get a error
// if the signature of ReportWeight doesn't match what it
// should be.

public Plugin:myinfo = {
    name = "Smart player reports: example weight function",
    author = "splewis",
    description = "SPR example plugin",
    version = "1.0.0",
    url = "https://github.com/splewis/smart-player-reports"
};

public bool IsAdmin(client) {
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
public float ReportWeight(int client, int victim) {
    float weight = 1.0;

    // Might want to ignore people that make too many reports!
    if (SPR_GetReputation(client) < 0.0)
        return SPR_IGNORE_REPORT;

    // Count admins more heavily
    if (IsAdmin(client))
        weight += 2.0;

    // If no admin on the server, count reports more
    bool admin_on_server = false;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsAdmin(i)) {
            admin_on_server = true;
            break;
        }
    }
    if (!admin_on_server)
        weight += 2.0;

    return weight;
}

public SPR_OnReportFiled(int reporter, int victim, float weight, const char reason[]) {
    PrintToServer("%N reported %N with weight %f", reporter, victim, weight);
}

public SPR_OnDemoStart(int victim, const char victim_name[], const char victim_steamid[], const char reason[], const char demo_name[]) {
    PrintToServer("Started recording %s", demo_name);
}

public SPR_OnDemoStop(int victim, const char victim_name[], const char victim_steamid[], const char reason[], const char demo_name[]) {
    PrintToServer("Finished recording %s", demo_name);
}
