// Called whenever a non-negative weight report is filed.
forward OnReportFiled(reporter, victim, Float:weight, String:reason[]);

// Called whenever a demo starts recording.
forward OnDemoStart(victim, victim_name, victim_steamid, String:reason[], String:demo_name[]);

// Called whenever a demo is finished recording.
forward OnDemoStop(victim, victim_name, victim_steamid, String:reason[], String:demo_name[]);
