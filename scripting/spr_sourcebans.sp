// TODO: this is not complete yet. There's still some
// very important details to work out.

#include <sourcemod>
#include <webternet>  // hopefully added in (future) 1.7 sourcemod release
#include <smlib>
#include "include/spr.inc"
#include "spr/common.sp"

Handle g_hSourcbansURL = INVALID_HANDLE;

public Plugin:myinfo = {
    name = "[SPR] Sourcebans reporter",
    author = "splewis",
    description = "",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/smart-player-reports"
};

public OnPluginStart() {
    g_hSourcbansURL = CreateConVar("sm_spr_sourcebans_url", "", "URL for the sourcebans 'submit a ban' page, e.g., http://mycommunity/sourcebans/index.php?p=submit");
}

public OnDemoStop(int victim, char victim_name[], char victim_steamid[], char reason[], char demo_name[]) {
    char url[512];
    GetConVarString(g_hSourcbansURL, url, sizeof(url));

    Handle session = HTTP_CreateSession();
    Handle downloader = HTTP_CreateMemoryDownloader();
    Handle form = HTTP_CreateWebForm();

    HTTP_AddStringToWebForm(form, "PlayerName", victim_name);
    HTTP_AddStringToWebForm(form, "BanReason", reason);
    HTTP_AddStringToWebForm(form, "SubmitName", "???");
    HTTP_AddStringToWebForm(form, "EmailAddr", "???");
    HTTP_AddStringToWebForm(form, "server", "???");
    HTTP_AddFileToWebForm(form, "???", "???");
    HTTP_PostAndDownload(session, downloader, form, url, SubmitBanCallback);
}


public SubmitBanCallback(Handle session, status, Handle downloader, any:data) {
    CloseHandle(downloader);
    CloseHandle(session);
}
