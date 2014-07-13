smart-player-reports
=======================================
This is a Sourcmod plugin with some optional library code to allow for players to easily report abusive players.

It is brand new and should not be used yet.

Also see the [AlliedModders thread](TODO: link here).

### Features
- Logging to any of admins on the server, log files, MySQL database
- Automatic demo recording (highly configurable)
- Weighted reports (highly configurable)

### Download
Stable releases are in the [GitHub Releases](https://github.com/splewis/smart-player-reports/releases) section.

### Installation


### For plugin developers


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

