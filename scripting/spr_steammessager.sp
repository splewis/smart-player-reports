#include <sourcemod>
#include <messagebot>
#include <smlib>
#include "include/spr.inc"
#include "spr/common.sp"

char g_BotUser[64] = "";
char g_BotPassword[64] = "";

public Plugin:myinfo = {
    name = "Smart player reports: steam messanger",
    author = "splewis",
    description = "Sends a steam message to a list of clients when a demo is started",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnMapStart() {
    MessageBot_ClearRecipients();
    ReadConfig();
}

public SPR_OnDemoStart(int victim, const char[] victim_name, const char[] victim_steamid, const char[] reason, const char[] demo_name) {
    char hostname[128];
    Server_GetHostName(hostname, sizeof(hostname));
    char msg[4196];
    Format(msg, sizeof(msg), "You have a new report to review: (%s, %s) on %s, recorded to %s. Reason: %s",
           victim_name, victim_steamid, hostname, demo_name, reason);
    MessageBot_SetSendMethod(SEND_METHOD_ONLINEAPI);
    MessageBot_SetLoginData(g_BotUser, g_BotPassword);
    MessageBot_SendMessage(Message_CallBack, msg);
}

public Message_CallBack(MessageBotResult:result, error) {
    if (result != RESULT_NO_ERROR) {
        LogError("MessageBot got an error when using bot user: %s", g_BotUser);
        LogError("result code = %d", result);
        LogError("error code = %d", error);
    }
}

public void ReadConfig() {
    char configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/spr_steammessager.cfg");

    if (!FileExists(configFile)) {
        LogError("The spr_steammessager config (%s) file does not exist", configFile);
        return;
    }

    Handle kv = CreateKeyValues("spr_steammessager");
    FileToKeyValues(kv, configFile);
    if (!KvGotoFirstSubKey(kv)) {
        LogError("The spr_steammessager config (%s) file was empty", configFile);
        return;
    }

    char buffer[128];

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
