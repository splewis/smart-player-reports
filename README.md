smart-player-reports
=======================================

This is a sourcemod plugin for dealing with abusive players. It's name has "smart" in it because it tries to help admins deal with these reports by:
- **Storing a 'weight' to a report** (by default all reports are weight 1 - but you can implement your own function to compute weights)
- **Automatically recording to a demo** (via ``tv_record``) if there are enough reports for a player
- **Logging** to admins on the server, a log file, or a MySQL database

**Note: this plugin only supports CS:GO due to how it works with GOTV demo files**

While I consider it smart to do these and a step up from some other plugins, the main design decision is to **keep it simple, stupid**.
As such this plugin is *very* lightweight in its implementation.
If you want a more complete reporting solution, check out [CallAdmin](https://forums.alliedmods.net/showthread.php?t=213670).
I don't plan on duplicating its features.
This plugin was meant to solve my personal problem of not being around on my servers, so a steam message about a hacker did me no good. I needed a demo.

For now, this is only the plugin code.
In the future I may add some helper scripts to fetch demo files, add support to zip & upload demo files, or a web interface to view the player report tables.
If you're interested in any of these, let me know in the [Issues Section](https://github.com/splewis/smart-player-reports/issues).


### Player Commands
All of the following can be used by players on the server:

- **.report**
- **!report**
- **/report**
- **/report playername**
- **sm_report**
- **sm_report playername**
- **!report playername** (warning: everyone will see this in chat!)


### Download
Stable releases are in the [GitHub Releases](https://github.com/splewis/smart-player-reports/releases) section.


### Installation
Unpack the smart-player-reports.zip file and copy the plugin binary **smart-player-reports.smx** to your plugins folder.
When the plugin starts up for the first time, it will create **cfg/sourcemod/smart-player-reports.cfg**, which you will most likely want to tweak.


### ConVars

- **sm_spr_database_name**: database in databases.cfg to use (default "smart_player_reports")
- **sm_spr_demo_duration**: after how long should a demo be stopped "(default 240.0")
- **sm_spr_log_to_admins**: should report info be printed to admins in chat (default 1)
- **sm_spr_log_to_database**: should reports create records in a MySQL database (default 1)
- **sm_spr_log_to_file**: should reports be logged to a file (default 1)
- **sm_spr_max_reports_in_plugin**: max reports to save within the plugin before clearing (default 1000)
- **sm_spr_reports_per_map**: number of reports a player can use per map (default 1)
- **sm_spr_weight_source_plugin_filename**: what plugin, if any, is providing a ReportWeight function (default "")
- **sm_spr_weight_to_demo**: how many report weight is needed to create a demo (default 10)


Note that the plugin stored *cumulative weights** for each player (stored in a trie by steamid).
When a player is reported, the weight of that report is added to the cumulative weight.
Once that weight reaches a threshold, a demo is recorded.

The cumulative weights are what is being cleared by ``sm_spr_max_reports_in_plugin``, since you don't want to let it grow too much.


### For plugin developers

An important cvar is ``sm_spr_weight_source_plugin_filename``. This defines a plugin name (with the .smx at the end!) that is supplying a function ``public any:ReportWeight(client, victim)``.

Example from [example.sp](https://github.com/splewis/smart-player-reports/blob/master/csgo/addons/sourcemod/scripting/example.sp)
```
/**
 * All you need to do is add a function like this with the same name and signature.
 * A 0-weight report will generally have no effect (though it IS reported)
 * and negative-weight reports have no effect and are NOT reported.
 * Users are fully unaware of the weight of their report
 * You can do anything you want inside this function!
 */
public any:ReportWeight(client, victim) {
    new weight = 1;

    // Count admins more heavily
    if (IsAdmin(client))
        weight += 2;

    // If no admin on the server, count reports more
    new bool:admin_on_server = false;
    for (new i = 1; i <= MaxClients; i++) {
        if (IsAdmin(i)) {
            admin_on_server = true;
            break;
        }
    }
    if (!admin_on_server)
        weight += 2;

    // You could even count reporters with a short steam ID more!
    decl String:steamid[64];
    if (GetClientAuthString(client, steamid, sizeof(steamid)) && strlen(steamid) < 10)
        weight += 1;

    return weight;
}
```

Note that the **function name must be** ``ReportWeight`` and there is **no include file**.
This is intentional with my goal of keeping things simple.

I'm aware things like plugin libraries, forwards, and natives exist.

### GOTV demos

You need to enable gotv to use the demo-recording feature. Adding the following to your ``server.cfg`` will work:

    tv_enable 1
    tv_delaymapchange 0
    tv_delay 30
    tv_deltacache 2
    tv_dispatchmode 1
    tv_maxclients 1
    tv_maxrate 0
    tv_overridemaster 0
    tv_relayvoice 1
    tv_snapshotrate 20
    tv_timeout 60
    tv_transmitall 1

Of course, you can tweak the values.


### Using the MySQL database

	mysql> describe player_reports;

	+------------------+--------------+------+-----+-------------------+----------------+
	| Field            | Type         | Null | Key | Default           | Extra          |
	+------------------+--------------+------+-----+-------------------+----------------+
	| id               | int(11)      | NO   | PRI | NULL              | auto_increment |
	| timestamp        | timestamp    | NO   |     | CURRENT_TIMESTAMP |                |
	| reporter_name    | varchar(64)  | NO   |     |                   |                |
	| reporter_steamid | varchar(64)  | NO   |     |                   |                |
	| reported_name    | varchar(64)  | NO   |     |                   |                |
	| reported_steamid | varchar(64)  | NO   |     |                   |                |
	| weight           | int(11)      | NO   |     | 0                 |                |
	| description      | varchar(256) | NO   |     |                   |                |
	| server           | varchar(64)  | NO   |     |                   |                |
	| demo             | varchar(128) | NO   |     |                   |                |
	+------------------+--------------+------+-----+-------------------+----------------+

Currently there are no tools for actually using the reports in the database.
If you have any ideas, let me know in the [Issues Section](https://github.com/splewis/smart-player-reports/issues).

A simple php page with an login password would go a long way to making this more useful.
