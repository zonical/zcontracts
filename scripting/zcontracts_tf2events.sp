#include <sourcemod>
#include <sdkhooks>
#include <zcontracts/zcontracts>
#include <tf2_stocks>

int g_PlayerFullCritDamageDealt[MAXPLAYERS+1];
int g_PlayerMiniCritDamageDealt[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "ZContracts - TF2 Event Logic",
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

	HookEvent("payload_pushed", OnPayloadPushed);
	HookEvent("teamplay_point_captured", OnPointCaptured);

	// Scoop damage related events and merge them into one event that gets fired
	// every three seconds.
	CreateTimer(3.0, Timer_ScoopDamage, _, TIMER_REPEAT);
	
	for (int i = 0; i < MAXPLAYERS + 1; i++)
	{
		g_PlayerFullCritDamageDealt[i] = 0;
		g_PlayerMiniCritDamageDealt[i] = 0;
	}
}

public Action Timer_ScoopDamage(Handle hTimer)
{
	for (int i = 0; i < MAXPLAYERS + 1; i++)
	{
		if (!IsClientValid(i) || IsFakeClient(i)) continue;
		
		// Award full crit damage event.
		if (g_PlayerFullCritDamageDealt[i] != 0)
		{
			CallContrackerEvent(i, "CONTRACTS_TF2_PLAYER_DEAL_FULLCRIT", g_PlayerFullCritDamageDealt[i]);
			g_PlayerFullCritDamageDealt[i] = 0;
		}
		// Award damage taken event.
		if (g_PlayerMiniCritDamageDealt[i] != 0)
		{
			CallContrackerEvent(i, "CONTRACTS_TF2_PLAYER_DEAL_MINICRIT", g_PlayerMiniCritDamageDealt[i]);
			g_PlayerMiniCritDamageDealt[i] = 0;
		}
	}
	return Plugin_Continue;
}

// Events relating to the attacker killing a victim.
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int death_flags = event.GetInt("death_flags");
	
	// Make sure we're not the same.
	if (IsClientValid(attacker) && IsClientValid(victim) && attacker != victim)
	{
		if (death_flags & TF_DEATHFLAG_KILLERDOMINATION) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_DOMINATION", 1);
		if (death_flags & TF_DEATHFLAG_KILLERREVENGE) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_REVENGE", 1);

		switch (event.GetInt("crit_type"))
		{
			case 1: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_MINICRIT", 1);
			case 2: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_FULLCRIT", 1);
		}

		switch (event.GetInt("customkill"))
		{
			case TF_CUSTOM_HEADSHOT: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_HEADSHOT", 1);
			case TF_CUSTOM_BACKSTAB: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_BACKSTAB", 1);

			case TF_CUSTOM_TAUNT_HADOUKEN: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_HADOUKEN", 1);
			case TF_CUSTOM_TAUNT_HIGH_NOON: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_HIGHNOON", 1);
			case TF_CUSTOM_TAUNT_GRAND_SLAM: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_GRANDSLAM", 1);
			case TF_CUSTOM_TAUNT_FENCING: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_FENCING", 1);
			case TF_CUSTOM_TAUNT_ARROW_STAB: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_ARROWSTAB", 1);
			case TF_CUSTOM_TAUNT_GRENADE: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_GRENADE", 1);
			case TF_CUSTOM_TAUNT_BARBARIAN_SWING: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_BARBSWING", 1);
			case TF_CUSTOM_TAUNT_UBERSLICE: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_UBERSLICE", 1);
			case TF_CUSTOM_TAUNT_ENGINEER_SMASH: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_ENGIESMASH", 1);
			case TF_CUSTOM_TAUNT_ENGINEER_ARM: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_ENGIEARM", 1);
			case TF_CUSTOM_TAUNT_ARMAGEDDON: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_ARMAGEDDON", 1);
			case TF_CUSTOM_TAUNT_ALLCLASS_GUITAR_RIFF: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_GUITAR", 1);

			case TF_CUSTOM_TELEFRAG: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_TELEFRAG", 1);
			case TF_CUSTOM_PUMPKIN_BOMB: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_PUMPKINBOMB", 1);
			case TF_CUSTOM_DECAPITATION: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_DECAPITATION", 1);
			case TF_CUSTOM_CHARGE_IMPACT: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_CHARGEIMPACT", 1);
			case TF_CUSTOM_SHOTGUN_REVENGE_CRIT: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_REVENGECRIT", 1);
			case TF_CUSTOM_FISH_KILL: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_FISHKILL", 1);
			case TF_CUSTOM_BOOTS_STOMP: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_BOOTS", 1);
			case TF_CUSTOM_PLASMA: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_PLASMA", 1);
			case TF_CUSTOM_PLASMA_CHARGED: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_PLASMA", 1);
			case TF_CUSTOM_PLASMA_GIB: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_PLASMA", 1);
			
			case TF_CUSTOM_SPELL_TELEPORT: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_TELEPORT", 1);
			case TF_CUSTOM_SPELL_SKELETON: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_SKELETON", 1);
			case TF_CUSTOM_SPELL_MIRV: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_MIRV", 1);
			case TF_CUSTOM_SPELL_METEOR: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_METEOR", 1);
			case TF_CUSTOM_SPELL_LIGHTNING: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_LIGHTNING", 1);
			case TF_CUSTOM_SPELL_FIREBALL: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_FIREBALL", 1);
			case TF_CUSTOM_SPELL_MONOCULUS: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_MONOCULUS", 1);
			case TF_CUSTOM_SPELL_BATS: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_BATS", 1);
			case TF_CUSTOM_SPELL_TINY: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_SPELL_TINY", 1);
			case TF_CUSTOM_KART: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_KART", 1);
			case TF_CUSTOM_GIANT_HAMMER: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_HAMMER", 1);
			case TF_CUSTOM_RUNE_REFLECT: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_RUNE", 1);
			case TF_CUSTOM_SLAP_KILL: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_SLAP", 1);

			case TF_CUSTOM_TAUNTATK_GASBLAST: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_GASBLAST", 1);
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
		if (attacker == victim) return Plugin_Continue;

		if (event.GetBool("crit")) g_PlayerFullCritDamageDealt[attacker] += damage;
		if (event.GetBool("minicrit")) g_PlayerMiniCritDamageDealt[attacker] += damage;


	}

	return Plugin_Continue;
}


public Action OnPayloadPushed(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("pusher");
	float progress = event.GetFloat("distance");
	PrintToChat(client, "%N progress: %d", client, progress);
	CallContrackerEvent(client, "CONTRACTS_TF2_PL_ESCORT", 1);
		
	return Plugin_Continue;
}

public Action OnPointCaptured(Event event, const char[] name, bool dontBroadcast)
{
	char cappers[64];
	event.GetString("cappers", cappers, sizeof(cappers));
	for (int i = 0; i < strlen(cappers); i++)
	{
		int client = view_as<int>(cappers[i]);
		PrintToChatAll("%d", client);
		if (!IsClientValid(client) || IsFakeClient(client)) continue;
		CallContrackerEvent(client, "CONTRACTS_TF2_CAPTURE_POINT", 1);
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


// don't ask.
stock float fmodf(float num, float denom)
{
    return num - denom * RoundToFloor(num / denom);
}

stock float operator%(float oper1, float oper2)
{
    return fmodf(oper1, oper2);
}