// Function for calculating weight of a report.
forward Float:ReportWeight(client, victim);

// Called whenever a non-negative weight report is filed.
forward OnReportFiled(reporter, victim, Float:weight, String:reason[]);

// Called whenever a demo starts recording.
forward OnDemoStart(victim, String:victim_name[], String:victim_steamid[], String:reason[], String:demo_name[]);

// Called whenever a demo is finished recording.
forward OnDemoStop(victim, String:victim_name[], String:victim_steamid[], String:reason[], String:demo_name[]);
