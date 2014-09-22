#if defined _spr_included
  #endinput
#endif
#define _spr_included

// Function for calculating weight of a report.
forward float ReportWeight(int client, int victim);

// Called whenever a non-negative weight report is filed.
forward void OnReportFiled(int reporter, int victim, float weight, char reason[]);

// Called whenever a demo starts recording.
forward void OnDemoStart(int victim, char victim_name[], char victim_steamid[], char reason[], char demo_name[]);

// Called whenever a demo is finished recording.
// Realize that the victim may have left in the time since the demo started,
// so the victim client index may be invalid now. If the victim left,
// -1 will be passed for their client index.
forward void OnDemoStop(int victim, char victim_name[], char victim_steamid[], char reason[], char demo_name[]);

// Files a report on a player on behalf of the server.
// This is useful for automatic-detection of offending players.
native void CreateServerReport(int victim, char reason[], float weight);
native bool HasReportInfo(int client);
native float GetReputation(int client);
native void SetReputation(int client, float reputation);

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
    MarkNativeAsOptional("CreateServerReport");
    MarkNativeAsOptional("HasReportInfo");
    MarkNativeAsOptional("GetReputation");
    MarkNativeAsOptional("SetReputation");
}
#endif
