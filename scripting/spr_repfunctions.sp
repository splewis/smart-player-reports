#pragma semicolon 1

#include <sourcemod>
#include "include/spr.inc"
#include "spr/common.sp"

public Plugin:myinfo = {
    name = "[SPR] set reputation",
    author = "splewis",
    description = "",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnPluginStart() {
    LoadTranslations("common.phrases");
    RegAdminCmd("sm_rep", Command_Rep, ADMFLAG_ROOT);
}

public Action Command_Rep(int client, args) {
    char arg1[32];
    char arg2[32];
    if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
        int target = FindTarget(client, arg1, true, false);
        if (target != -1) {
            if (!SPR_HasReportInfo(target)) {
                ReplyToCommand(client, "Unable to get reputation info for %N", target);
            } else {
                if (args >= 2 && GetCmdArg(2, arg2, sizeof(arg2))) {
                    float dr = StringToFloat(arg2);
                    ReplyToCommand(client, "Reputation for %N: %f + %f = %f", target, SPR_GetReputation(target), dr, SPR_GetReputation(target) + dr);
                    SPR_ChangeReputation(target, dr);
                } else {
                    ReplyToCommand(client, "Reputation for %N: %f", target, SPR_GetReputation(target));
                }
            }
        }
    } else {
        ReplyToCommand(client, "Usage: sm_rep [player] <dr>");
    }
    return Plugin_Handled;
}
