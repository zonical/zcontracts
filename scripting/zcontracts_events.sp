#include <sourcemod>
#include <sdkhooks>
#include <zcontracts/zcontracts>

int g_PlayerDamageDealt[MAXPLAYERS+1];
int g_PlayerDamageTaken[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "ZContracts - Event Logic",
	author = "ZoNiCaL",
	description = "Hooks game events into the ZContract system.",
	version = "alpha-1",
	url = ""
};

// Hook all of our game events.
public void OnPluginStart()
{
	// Hook player events.
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_spawn", OnPlayerSpawn);

	HookEvent("teamplay_round_win", OnRoundWin);

	// Scoop damage related events and merge them into one event that gets fired
	// once a second.
	CreateTimer(3.0, Timer_ScoopDamage, _, TIMER_REPEAT);
	
	for (int i = 0; i < MAXPLAYERS + 1; i++)
	{
		g_PlayerDamageDealt[i] = 0;
		g_PlayerDamageTaken[i] = 0;
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
			CallContrackerEvent(assister, "CONTRACTS_PLAYER_ASSIST_KILL", 1);
		}
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
			g_PlayerDamageDealt[attacker] += damage;
			g_PlayerDamageTaken[victim] += damage;
		}
	}

	return Plugin_Continue;
}

public Action Timer_ScoopDamage(Handle hTimer)
{
	for (int i = 0; i < MAXPLAYERS + 1; i++)
	{
		if (!IsClientValid(i) || IsFakeClient(i)) continue;
		
		// Award damage dealt event.
		if (g_PlayerDamageDealt[i] != 0)
		{
			CallContrackerEvent(i, "CONTRACTS_PLAYER_DEAL_DAMAGE", g_PlayerDamageDealt[i]);
			g_PlayerDamageDealt[i] = 0;
		}
		// Award damage taken event.
		if (g_PlayerDamageTaken[i] != 0)
		{
			CallContrackerEvent(i, "CONTRACTS_PLAYER_TAKE_DAMAGE", g_PlayerDamageTaken[i]);
			g_PlayerDamageTaken[i] = 0;
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	CallContrackerEvent(client, "CONTRACTS_PLAYER_SPAWN", 1);
}

// Events relating to the round ending
public Action OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
	int team = event.GetInt("team");
	//int winreason = event.GetInt("winreason");

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

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
