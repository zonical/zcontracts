#include <sourcemod>
#include <sdkhooks>
#include <zcontracts/zcontracts>

public Plugin myinfo =
{
	name = "ZContracts - Event Logic",
	author = "ZoNiCaL",
	description = "Hooks game events into the ZContract system.",
	version = ZCONTRACTS_PLUGIN_VERSION,
	url = ""
};

// Hook all of our game events.
public void OnPluginStart()
{
	// Hook player events.
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_score", OnPlayerScore)

	// Okay okay okay. I get there are separate plugins for TF2 and CSGO.
	// But I'm going to make an exception here so that this plugin can be
	// made easily accessible and have Contract events work across games
	// with ease.
	switch (GetEngineVersion())
	{
		case Engine_TF2: HookEvent("teamplay_round_win", OnRoundWin);
		case Engine_CSGO: HookEvent("round_end", OnRoundWin);
	}
}

public void OnAllPluginsLoaded()
{
	// Check to see if we have ZContracts loaded.
	if (!LibraryExists("zcontracts"))
	{
		SetFailState("This plugin requires the main ZContracts plugin to function.");
	}
}

// Events relating to the attacker killing a victim.
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int assister = GetClientOfUserId(event.GetInt("assister"));
	
	// Make sure we're not the same.
	if (IsClientValid(attacker) && IsClientValid(victim) && attacker != victim)
	{
		CallContrackerEvent(attacker, "CONTRACTS_PLAYER_KILL", 1, true);
		CallContrackerEvent(victim, "CONTRACTS_PLAYER_DEATH", 1);
		if (IsClientValid(assister) && assister != attacker)
		{
			CallContrackerEvent(assister, "CONTRACTS_PLAYER_ASSIST_KILL", 1, true);
		}
	}

	if (IsClientValid(attacker) && attacker == victim)
	{
		CallContrackerEvent(attacker, "CONTRACTS_PLAYER_SUICIDE", 1, true);
	}

	return Plugin_Continue;
}

// Events relating to the attacker hurting a victim.
public Action OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int damage = event.GetInt("damageamount");
	
	if (IsClientValid(attacker) && IsClientValid(victim))
	{
		// Make sure we're not the same.
		if (attacker != victim)
		{
			CallContrackerEvent(attacker, "CONTRACTS_PLAYER_DEAL_DAMAGE", damage, true);
			CallContrackerEvent(victim, "CONTRACTS_PLAYER_TAKE_DAMAGE", damage, true);
		}
	}

	return Plugin_Continue;
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	CallContrackerEvent(client, "CONTRACTS_PLAYER_SPAWN", 1);
}

public Action OnPlayerScore(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	CallContrackerEvent(client, "CONTRACTS_PLAYER_SCORE", 1);
}

// Events relating to the round ending
public Action OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
	int team;

	switch (GetEngineVersion())
	{
		case Engine_TF2: team = event.GetInt("team");
		case Engine_CSGO: team = event.GetInt("winner");
	}

	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (!IsClientValid(i) || IsFakeClient(i)) continue;
		// Are we on the same team?
		if (GetClientTeam(i) == team)
		{
			CallContrackerEvent(i, "CONTRACTS_GAME_WIN_ROUND", 1);
		}
		else
		{
			CallContrackerEvent(i, "CONTRACTS_GAME_LOSE_ROUND", 1);
		}
	}
	return Plugin_Continue;
}
