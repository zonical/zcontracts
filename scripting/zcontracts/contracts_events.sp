#include <sdkhooks>

// Hook all of our game events.
public void HookEvents()
{
	// Hook player events.
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("teamplay_round_win", OnRoundWin);
	
	for (int i = 0; i < MAXPLAYERS + 1; i++)
	{
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
	if (IsClientValid(attacker) && IsClientValid(victim)
		&& attacker != victim)
	{
		CallContrackerEvent(attacker, "CONTRACTS_PLAYER_KILL", 1);
		CallContrackerEvent(victim, "CONTRACTS_PLAYER_DEATH", 1);
		if (IsClientValid(assister) && assister != attacker)
		{
			CallContrackerEvent(assister, "CONTRACTS_PLAYER_ASSIST_KILL", 1);
		}
	}
}

// Events relating to the attacker hurting a victim.
public Action OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int damage = event.GetInt("damageamount");
	
	// Make sure we're not the same.
	if (attacker != victim)
	{
		// Award an event for the killer.
		CallContrackerEvent(attacker, "CONTRACTS_PLAYER_DEAL_DAMAGE", damage);
		// Award an event for the person who died.
		CallContrackerEvent(victim, "CONTRACTS_PLAYER_TAKE_DAMAGE", damage);
	}
}

// Events relating to the round ending
public Action OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
	int team = event.GetInt("team");
	//int winreason = event.GetInt("winreason");

	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (IsClientValid(i)) continue;
		// Are we on the same team?
		if (GetClientTeam(i) == team)
		{
			CallContrackerEvent(i, "CONTRACTS_PLAYER_WIN_ROUND", 1);
		}
	}
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
