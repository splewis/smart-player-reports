#if defined _spr_included
  #endinput
#endif
#define _spr_included

#define SPR_IGNORE_REPORT -1.0

// Function for calculating weight of a report.
forward float ReportWeight(int client, int victim);

// Called whenever a non-negative weight report is filed.
forward void OnReportFiled(int reporter, int victim, float weight, const char reason[]);

// Called whenever a demo starts recording.
forward void OnDemoStart(int victim, const char victim_name[], const char victim_steamid[], const char reason[], const char demo_name[]);

// Called whenever a demo is finished recording.
// Realize that the victim may have left in the time since the demo started,
// so the victim client index may be invalid now. If the victim left,
// -1 will be passed for their client index.
forward void OnDemoStop(int victim, const char victim_name[], const char victim_steamid[], const char reason[], const char demo_name[]);

// Files a report on a player on behalf of the server.
// This is useful for automatic-detection of offending players.
native void SPR_CreateServerReport(int victim, const char reason[], float weight=1.0, bool forceDemo=false);
native bool SPR_HasReportInfo(int client);
native float SPR_GetReputation(int client);
native void SPR_SetReputation(int client, float reputation);
native void SPR_ChangeReputation(int client, float delta);
native int SPR_RecordingTarget();

public SharedPlugin:__pl_spr = {
    name = "smart-player-reports",
    file = "smart-player-reports.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_spr_SetNTVOptional() {
    MarkNativeAsOptional("SPR_CreateServerReport");
    MarkNativeAsOptional("SPR_HasReportInfo");
    MarkNativeAsOptional("SPR_GetReputation");
    MarkNativeAsOptional("SPR_SetReputation");
    MarkNativeAsOptional("SPR_ChangeReputation");
    MarkNativeAsOptional("SPR_RecordingTarget");
}
#endif
