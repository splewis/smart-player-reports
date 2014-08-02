#include <sourcemod>
#include <messagebot>
#include <smlib>
#include "include/spr.inc"
#include "spr/common.sp"

new Handle:kv;
new String:g_BotUser[64] = "";
new String:g_BotPassword[64] = "";

public Plugin:myinfo = {
    name = "[SPR] Steam messager",
    author = "splewis",
    description = "Enhanced tools for player reports",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnPluginStart() {
    MessageBot_SetSendMethod(SEND_METHOD_ONLINEAPI);
    RegAdminCmd("sm_spr_steam_user", Command_SetBotUser, ADMFLAG_ROOT, "");
    RegAdminCmd("sm_spr_steam_password", Command_SetBotPassword, ADMFLAG_ROOT, "");
    RegAdminCmd("sm_spr_add", Command_AddRecipient, ADMFLAG_ROOT, "");
    RegAdminCmd("sm_spr_remove", Command_RemoveRecipient, ADMFLAG_ROOT, "");
}

public OnMapStart() {
    ReadConfig();
}

public OnMapEnd() {
    WriteConfig();
}

public OnDemoStart(victim, victim_name, victim_steamid, String:reason[], String:demo_name[]) {
    decl String:hostname[128];
    Server_GetHostName(hostname, sizeof(hostname));
    decl String:msg[1024];
    Format(msg, sizeof(msg), "You have a new report to review: (%s, %s) on %s, recorded to %s",
           victim_name, victim_steamid, hostname, demo_name);
    MessageBot_SendMessage(Message_CallBack, msg);
}

public Message_CallBack(MessageBotResult:result, error) {
    if (result != RESULT_NO_ERROR) {
        LogError("MessageBot got an error:");
        LogError("result code = %d", result);
        LogError("error code = %d", error);
    }
}

public Action:Command_SetBotUser(client, args) {
    ThrowError("[Command_SetBotUser] Unimplemented");
}

public Action:Command_SetBotPassword(client, args) {
    ThrowError("[Command_SetBotPassword] Unimplemented");
}

public Action:Command_AddRecipient(client, args) {
    ThrowError("[Command_AddRecipient] Unimplemented");
}

public Action:Command_RemoveRecipient(client, args) {
    ThrowError("[Command_RemoveRecipient] Unimplemented");
}

static ReadConfig() {
    decl String:configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/spr_steammessager.cfg");

    if (!FileExists(configFile)) {
        LogMessage("The spr_steammessager config (%s) file does not exist", configFile);
        return;
    }

    kv = CreateKeyValues("BoxLocationsAndAngles");
    FileToKeyValues(kv, configFile);
    if (!KvGotoFirstSubKey(kv)) {
        LogMessage("The spr_steammessager config (%s) file was empty", configFile);
        return;
    }

    do {
        decl String:key[128];
        decl String:value[128];
        KvGetSectionName(kv, key, sizeof(key));
        KvGetString(kv, NULL_STRING, value, sizeof(value));

        if (StrEqual(key, "bot_user")) {
            SetLoginUser(value);
        } else if (StrEqual(key, "bot_password")) {
            SetLoginPassword(value);
        } else {
            AddRecipient(value);
        }

    } while (KvGotoNextKey(kv));
    KvRewind(kv);
}

static WriteConfig() {
    decl String:configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), "configs/spr_steammessager.cfg");
    KeyValuesToFile(kv, configFile);
}

static SetLoginUser(String:username[]) {
    strcopy(g_BotUser, sizeof(g_BotUser), username);
    MessageBot_SetLoginData(g_BotUser, g_BotPassword);
}

static SetLoginPassword(String:password[]) {
    strcopy(g_BotPassword, sizeof(g_BotPassword), password);
    MessageBot_SetLoginData(g_BotUser, g_BotPassword);
}

static AddRecipient(String:steamid[]) {
    if (!MessageBot_IsRecipient(steamid)) {
        if (!MessageBot_AddRecipient(steamid)) {
            LogError("Failed to add %s to messagebot list", steamid);
        }
    }
}

static RemoveRecipient(String:steamid[]) {
    MessageBot_RemoveRecipient(steamid);
}
