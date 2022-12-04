#include <sourcemod>
#include <sdkhooks>
#include <zcontracts/zcontracts>
#include <tf2>
#include <tf2_stocks>

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
	HookEvent("player_healed", OnPlayerHealed);

	HookEvent("player_builtobject", OnObjectBuilt);
	HookEvent("player_upgradedobject", OnObjectUpgraded);
	HookEvent("object_destroyed", OnObjectDestroyed);

	HookEvent("payload_pushed", OnPayloadPushed);
	HookEvent("teamplay_point_captured", OnPointCaptured);
	HookEvent("teamplay_win_panel", OnWinPanel);
}

// Events relating to the attacker killing a victim.
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int death_flags = event.GetInt("death_flags");

	char weapon[128];
	event.GetString("weapon", weapon, sizeof(weapon));
	
	// Make sure we're not the same.
	if (IsClientValid(attacker) && IsClientValid(victim) && attacker != victim)
	{
		if (death_flags & TF_DEATHFLAG_KILLERDOMINATION) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_DOMINATION", 1, true);
		if (death_flags & TF_DEATHFLAG_KILLERREVENGE) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_REVENGE", 1, true);

		switch (event.GetInt("crit_type"))
		{
			case 1: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_MINICRIT", 1, true);
			case 2: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_FULLCRIT", 1, true);
		}

		switch (event.GetInt("customkill"))
		{
			case TF_CUSTOM_HEADSHOT: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_HEADSHOT", 1, true);
			case TF_CUSTOM_BACKSTAB: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_BACKSTAB", 1, true);
		}

		if (StrContains(weapon, "obj_minisentry") != -1 || StrContains(weapon, "obj_sentrygun") != -1)
		{
			CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_SENTRY", 1, true);
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

		if (event.GetBool("crit")) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_DEAL_FULLCRIT", damage, true);
		if (event.GetBool("minicrit")) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_DEAL_MINICRIT", damage, true);
	}

	return Plugin_Continue;
}

public Action OnPlayerHealed(Event event, const char[] name, bool dontBroadcast)
{
	int patient = GetClientOfUserId(event.GetInt("patient"));
	int healer = GetClientOfUserId(event.GetInt("healer"));
	int amount = event.GetInt("amount");

	if (!IsClientValid(patient) || !IsClientValid(healer)) return Plugin_Continue;
	if (patient == healer) return Plugin_Continue;

	CallContrackerEvent(healer, "CONTRACTS_TF2_PLAYER_HEAL", amount, true);

	return Plugin_Continue;
}

// Award MVP's.
public Action OnWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	int mvp1 = GetClientOfUserId(event.GetInt("player_1"));
	int mvp2 = GetClientOfUserId(event.GetInt("player_2"));
	int mvp3 = GetClientOfUserId(event.GetInt("player_3"));
	
	if (IsClientValid(mvp1)) CallContrackerEvent(mvp1, "CONTRACTS_TF2_PLAYER_MVP", 1);
	if (IsClientValid(mvp2)) CallContrackerEvent(mvp2, "CONTRACTS_TF2_PLAYER_MVP", 1);
	if (IsClientValid(mvp3)) CallContrackerEvent(mvp3, "CONTRACTS_TF2_PLAYER_MVP", 1);

	return Plugin_Continue;
}


public Action OnObjectBuilt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientValid(client)) return Plugin_Continue;

	TFObjectType building = view_as<TFObjectType>(event.GetInt("object"));
	switch (building)
	{
		case TFObject_Sentry: CallContrackerEvent(client, "CONTRACTS_TF2_BUILD_SENTRY", 1);
		case TFObject_Dispenser: CallContrackerEvent(client, "CONTRACTS_TF2_BUILD_DISPENSER", 1);
		case TFObject_Teleporter: CallContrackerEvent(client, "CONTRACTS_TF2_BUILD_TELEPORTER", 1);
	}

	return Plugin_Continue;
}


public Action OnObjectUpgraded(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientValid(client)) return Plugin_Continue;

	TFObjectType building = view_as<TFObjectType>(event.GetInt("object"));
	switch (building)
	{
		case TFObject_Sentry: CallContrackerEvent(client, "CONTRACTS_TF2_UPGRADE_SENTRY", 1);
		case TFObject_Dispenser: CallContrackerEvent(client, "CONTRACTS_TF2_UPGRADE_DISPENSER", 1);
		case TFObject_Teleporter: CallContrackerEvent(client, "CONTRACTS_TF2_UPGRADE_TELEPORTER", 1);
	}

	return Plugin_Continue;
}

public Action OnObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsClientValid(attacker)) return Plugin_Continue;

	TFObjectType building = view_as<TFObjectType>(event.GetInt("objecttype"));
	bool was_building = event.GetBool("was_building");

	if (was_building) CallContrackerEvent(attacker, "CONTRACTS_TF2_DESTROY_WHILE_BUILDING", 1);
	switch (building)
	{
		case TFObject_Sentry: CallContrackerEvent(attacker, "CONTRACTS_TF2_DESTROY_SENTRY", 1);
		case TFObject_Dispenser: CallContrackerEvent(attacker, "CONTRACTS_TF2_DESTROY_DISPENSER", 1);
		case TFObject_Teleporter: CallContrackerEvent(attacker, "CONTRACTS_TF2_DESTROY_TELEPORTER", 1);
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