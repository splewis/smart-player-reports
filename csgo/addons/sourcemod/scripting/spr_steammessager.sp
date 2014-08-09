#include <sourcemod>
#include <messagebot>
#include <smlib>
#include "include/spr.inc"
#include "spr/common.sp"

new String:g_BotUser[64] = "";
new String:g_BotPassword[64] = "";

public Plugin:myinfo = {
    name = "[SPR] Steam messager",
    author = "splewis",
    description = "Enhanced tools for player reports",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnMapStart() {
    ReadConfig();
}

public OnDemoStart(victim, String:victim_name[], String:victim_steamid[], String:reason[], String:demo_name[]) {
    decl String:hostname[128];
    Server_GetHostName(hostname, sizeof(hostname));
    decl String:msg[4196];
    Format(msg, sizeof(msg), "You have a new report to review: (%s, %s) on %s, recorded to %s",
           victim_name, victim_steamid, hostname, demo_name);
    MessageBot_SetSendMethod(SEND_METHOD_ONLINEAPI);
    MessageBot_SetLoginData(g_BotUser, g_BotPassword);
    MessageBot_SendMessage(Message_CallBack, msg);
}

public Message_CallBack(MessageBotResult:result, error) {
    if (result != RESULT_NO_ERROR) {
        LogError("MessageBot got an error:");
        LogError("result code = %d", result);
        LogError("error code = %d", error);
    }
}

static ReadConfig() {
    decl String:configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/spr_steammessager.cfg");

    if (!FileExists(configFile)) {
        LogError("The spr_steammessager config (%s) file does not exist", configFile);
        return;
    }

    new Handle:kv = CreateKeyValues("spr_steammessager");
    FileToKeyValues(kv, configFile);
    if (!KvGotoFirstSubKey(kv)) {
        LogError("The spr_steammessager config (%s) file was empty", configFile);
        return;
    }

    decl String:buffer[128];

    do {
        KvGetSectionName(kv, buffer, sizeof(buffer));
        if (StrEqual(buffer, "bot")) {
            KvGetString(kv, "username", g_BotUser, sizeof(g_BotUser));
            KvGetString(kv, "password", g_BotPassword, sizeof(g_BotPassword));
        } else {
            if (!MessageBot_IsRecipient(buffer)) {
                MessageBot_AddRecipient(buffer);
            }
        }
    } while (KvGotoNextKey(kv));
    KvRewind(kv);
}
