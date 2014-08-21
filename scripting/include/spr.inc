// Function for calculating weight of a report.
forward float ReportWeight(int client, int victim);

// Called whenever a non-negative weight report is filed.
forward OnReportFiled(int reporter, int victim, float weight, char reason[]);

// Called whenever a demo starts recording.
forward OnDemoStart(int victim, char victim_name[], char victim_steamid[], char reason[], char demo_name[]);

// Called whenever a demo is finished recording.
// Realize that the victim may have left in the time since the demo started,
// so the victim client index may be invalid now. If the victim left,
// -1 will be passed for their client index.
forward OnDemoStop(int victim, char victim_name[], char victim_steamid[], char reason[], char demo_name[]);
