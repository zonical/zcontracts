#include <sourcemod>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <zcontracts/zcontracts>
#include <zcontracts/zcontracts_tf2>
#include <tf_econ_data>

float g_LastValidProgressTime = -1.0;

ConVar g_TF2_AllowSetupProgress;
ConVar g_TF2_AllowRoundEndProgress;
ConVar g_TF2_AllowWaitingProgress;

TF2GameMode_Extensions g_TF2_GameModeExtension = TGE_NoExtension;

GlobalForward g_fOnGameModeExtCheck;

public Plugin myinfo =
{
	name = "ZContracts - TF2 Logic",
	author = "ZoNiCaL",
	description = "Creates TF2-specific events for the ZContract system and handles special TF2 logic.",
	version = ZCONTRACTS_PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_fOnGameModeExtCheck = new GlobalForward("OnTF2GameModeExtCheck", ET_Event);
	return APLRes_Success;
}

// Hook all of our game events.
public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_TF2)
	{
		SetFailState("This plugin is designed for TF2 only.");
	}

	// Hook player events.
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_healed", OnPlayerHealed);
	HookEvent("player_score_changed", OnPlayerScoreChanged);
	HookEvent("killed_capping_player", OnKilledCapper);
	HookEvent("environmental_death", OnWorldDeath);

	HookEvent("player_builtobject", OnObjectBuilt);
	HookEvent("player_upgradedobject", OnObjectUpgraded);
	HookEvent("object_destroyed", OnObjectDestroyed);

	HookEvent("payload_pushed", OnPayloadPushed);

	HookEvent("pass_get", OnPassGet);
	HookEvent("pass_score", OnPassScore);
	HookEvent("pass_free", OnPassFree);
	HookEvent("pass_pass_caught", OnPassCaught);
	HookEvent("pass_ball_stolen", OnBallStolen);
	HookEvent("pass_ball_blocked", OnPassBlocked);

	HookEvent("teamplay_point_captured", OnPointCaptured);
	HookEvent("teamplay_win_panel", OnWinPanel);
	HookEvent("teamplay_flag_event", OnFlagEvent);

	HookEvent("teamplay_round_win", TF2_OnRoundWin);
	HookEvent("teamplay_round_start", TF2_OnRoundStart);
	HookEvent("teamplay_waiting_begins", TF2_OnWaitingStart);
	HookEvent("teamplay_waiting_ends", TF2_OnWaitingEnd);
	HookEvent("teamplay_setup_finished", TF2_OnSetupEnd);

	CreateNative("SetTF2GameModeExt", Native_SetTF2GameModeExt);
	CreateNative("GetTF2GameModeExt", Native_GetTF2GameModeExt);

	g_TF2_AllowSetupProgress = CreateConVar("zctf2_allow_setup_trigger", "1", "If disabled, Objective progress will not be counted during setup time.");
	g_TF2_AllowRoundEndProgress = CreateConVar("zctf2_allow_roundend_trigger", "0", "If disabled, Objective progress will not be counted after a winner is declared and the next round starts.");
	g_TF2_AllowWaitingProgress = CreateConVar("zctf2_allow_waitingforplayers_trigger", "0", "If disabled, Objective progress will not be counted during the \"waiting for players\" period before a game starts.");
}

public void OnAllPluginsLoaded()
{
	// Check to see if we have ZContracts loaded.
	if (!LibraryExists("zcontracts"))
	{
		SetFailState("This plugin requires the main ZContracts plugin to function.");
	}
		// Check to see if we have tf_econ_data loaded.
	if (!LibraryExists("tf_econ_data"))
	{
		SetFailState("This plugin requires the \"tf_econ_data\" plugin to function.");
	}
}

// ============================= GAMEMODE EXTENSIONS =============================

public void OnMapStart()
{
	g_LastValidProgressTime = -1.0;

	// Fire a forward that asks any other plugins if they
	// wish to set the GME themselves with SetTF2GameModeExt.
	Call_StartForward(g_fOnGameModeExtCheck);
	Action ShouldBlock;
	Call_Finish(ShouldBlock);

	// If a plugin developer overrides the gamemode extension in
	// the forward, don't worry about finding it ourselves.
	if (ShouldBlock < Plugin_Changed)
	{
		// Any map that deals with Control Points.
		int master_ent = -1;
		while ((master_ent = FindEntityByClassname(master_ent, "team_control_point_master")) != -1)
		{
			int point_ent = -1;

			int RedPoints = 0;
			int BluPoints = 0;

			while ((point_ent = FindEntityByClassname(point_ent, "team_control_point")) != -1)
			{
				int ThisTeam = GetEntProp(point_ent, Prop_Send, "m_iTeamNum");
				if (ThisTeam == view_as<int>(TFTeam_Red)) RedPoints++;
				if (ThisTeam == view_as<int>(TFTeam_Blue)) BluPoints++;
			}

			if (RedPoints < BluPoints) g_TF2_GameModeExtension = TGE_RedAttacksBlu;
			if (BluPoints < RedPoints) g_TF2_GameModeExtension = TGE_BluAttacksRed;
			if (RedPoints == BluPoints) g_TF2_GameModeExtension = TGE_Symmetrical;
		}
	}
	// Nothing was found.
	g_TF2_GameModeExtension = TGE_NoExtension;
}

public any Native_SetTF2GameModeExt(Handle plugin, int numParams)
{
    TF2GameMode_Extensions value = view_as<TF2GameMode_Extensions>(GetNativeCell(1));
    g_TF2_GameModeExtension = value;
    return true;
}

public any Native_GetTF2GameModeExt(Handle plugin, int numParams)
{
    return g_TF2_GameModeExtension;
}

// ============================= LOGIC =============================

public Action OnContractCompletableCheck(int client, char UUID[MAX_UUID_SIZE])
{
	KeyValues ContractSchema = GetContractSchema(UUID);
	
	if (ContractSchema.JumpToKey(CONTRACT_DEF_TF2_CLASSES))
	{
		// Class check.
		TFClassType Class = TF2_GetPlayerClass(client);
		if (Class == TFClass_Unknown) return Plugin_Stop;

		// Construct temporary array.
		bool ClassCheckArray[10];
		ClassCheckArray[TFClass_Scout]      = view_as<bool>(ContractSchema.GetNum("scout", 0));
        ClassCheckArray[TFClass_Soldier]    = view_as<bool>(ContractSchema.GetNum("soldier", 0));
        ClassCheckArray[TFClass_Pyro]       = view_as<bool>(ContractSchema.GetNum("pyro", 0));
        ClassCheckArray[TFClass_DemoMan]    = view_as<bool>(ContractSchema.GetNum("demoman", 0));
        ClassCheckArray[TFClass_Heavy]      = view_as<bool>(ContractSchema.GetNum("heavy", 0));
        ClassCheckArray[TFClass_Engineer]   = view_as<bool>(ContractSchema.GetNum("engineer", 0));
        ClassCheckArray[TFClass_Sniper]     = view_as<bool>(ContractSchema.GetNum("sniper", 0));
        ClassCheckArray[TFClass_Medic]      = view_as<bool>(ContractSchema.GetNum("medic", 0));
        ClassCheckArray[TFClass_Spy]        = view_as<bool>(ContractSchema.GetNum("spy", 0));

		if (!ClassCheckArray[Class]) return Plugin_Stop;
		ContractSchema.Rewind();
	}

	// Gamemode extension check.
	char RequiredGameRulesEnt[64];
	ContractSchema.GetString("required_gamerules", RequiredGameRulesEnt, sizeof(RequiredGameRulesEnt));
	if (!StrEqual(RequiredGameRulesEnt, ""))
	{
		if (!TF2_ValidGameRulesEntityExists(RequiredGameRulesEnt)) return Plugin_Stop;
	}
	if ((ContractSchema.GetNum("gamemode_extension", view_as<int>(TGE_NoExtension)) != view_as<int>(TGE_NoExtension)) 
	&& (ContractSchema.GetNum("gamemode_extension", view_as<int>(TGE_NoExtension)) != view_as<int>(g_TF2_GameModeExtension))) return Plugin_Stop;

	// Active weapon checks.
	char ActiveWeaponSlot[64];
	ContractSchema.GetString("active_weapon_slot", ActiveWeaponSlot, sizeof(ActiveWeaponSlot));
	if (!StrEqual(ActiveWeaponSlot, ""))
	{
		int ActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(ActiveWeapon))
		{
			int ItemDef = GetEntProp(ActiveWeapon, Prop_Send, "m_iItemDefinitionIndex");
			if (!TF2Econ_IsValidItemDefinition(ItemDef)) return Plugin_Stop;

			int LoadoutSlot = TF2Econ_GetItemLoadoutSlot(ItemDef, TF2_GetPlayerClass(client));
			char LoadoutSlotName[64];
			TF2Econ_TranslateLoadoutSlotIndexToName(LoadoutSlot, LoadoutSlotName, sizeof(LoadoutSlotName));
			if (!StrEqual(LoadoutSlotName, ActiveWeaponSlot)) return Plugin_Stop;
		}
	}

	char ActiveWeaponName[64];
	ContractSchema.GetString("active_weapon_name", ActiveWeaponName, sizeof(ActiveWeaponName));
	int SchemaItemDef = ContractSchema.GetNum("active_weapon_itemdef", -1);
	if ((!StrEqual(ActiveWeaponName, "")) || (SchemaItemDef != -1 && TF2Econ_IsValidItemDefinition(SchemaItemDef)))
	{
		bool ItemFound = true;
		int ActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(ActiveWeapon))
		{
			int ItemDef = GetEntProp(ActiveWeapon, Prop_Send, "m_iItemDefinitionIndex");
			if (!TF2Econ_IsValidItemDefinition(ItemDef)) ItemFound = false;

			if (!StrEqual(ActiveWeaponName, ""))
			{
				char WeaponName[64];
				TF2Econ_GetItemName(ItemDef, WeaponName, sizeof(WeaponName));
				if (!StrEqual(ActiveWeaponName, WeaponName)) ItemFound = false;
			}
			// Item definition index.
			if (SchemaItemDef !=  ItemDef) ItemFound = false;
		}
		if (!ItemFound) return Plugin_Stop;
	}

	char InventoryItemName[64];
	ContractSchema.GetString("inventory_item_name", InventoryItemName, sizeof(InventoryItemName))
	char InventoryItemClassname[64];
	ContractSchema.GetString("inventory_item_classname", InventoryItemClassname, sizeof(InventoryItemClassname));
	SchemaItemDef = ContractSchema.GetNum("inventory_item_itemdef", -1);

	if ((!StrEqual(InventoryItemName, "")) || 
	(!StrEqual(InventoryItemClassname, "")) ||
	(SchemaItemDef != -1 && TF2Econ_IsValidItemDefinition(SchemaItemDef)))
	{
		bool ItemFound = false;
		// Loop through all weapons.
		for (int i = TFWeaponSlot_Primary; i < TFWeaponSlot_Item2; i++)
		{
			if (ItemFound) break;

			int SlotWeapon = GetPlayerWeaponSlot(client, i);
			if (IsValidEntity(SlotWeapon))
			{
				int ItemDef = GetEntProp(SlotWeapon, Prop_Send, "m_iItemDefinitionIndex");
				if (!TF2Econ_IsValidItemDefinition(ItemDef)) continue;

				// Economy name.
				if (!StrEqual(InventoryItemName, ""))
				{
					char WeaponName[64];
					TF2Econ_GetItemName(ItemDef, WeaponName, sizeof(WeaponName));
					if (StrEqual(InventoryItemName, WeaponName))
					{
						ItemFound = true;
						break;
					}
				}
				// Weapon classname.
				if (!StrEqual(InventoryItemClassname, ""))
				{
					char WeaponClassName[64];
					GetEntityClassname(SlotWeapon, WeaponClassName, sizeof(WeaponClassName));
					if (StrContains(WeaponClassName, InventoryItemClassname) != -1)
					{
						ItemFound = true;
						break;
					}
				}
				// Item definition index.
				if (SchemaItemDef == ItemDef)
				{
					ItemFound = true;
					break;
				}
			}
		}
		// Loop through all cosmetics.
		int Next = GetEntPropEnt(client, Prop_Data, "m_hMoveChild");
		while (Next != -1 && !ItemFound)
		{
			int CosmeticItem = Next;
			Next = GetEntPropEnt(CosmeticItem, Prop_Data, "m_hMovePeer");
			if (IsValidEntity(CosmeticItem))
			{
				// Only deal with wearable entities.
				char ClassName[64];
				GetEntityClassname(CosmeticItem, ClassName, sizeof(ClassName));
				if (StrContains(ClassName, "tf_wearable") == -1) continue;

				int ItemDef = GetEntProp(CosmeticItem, Prop_Send, "m_iItemDefinitionIndex");
				if (!TF2Econ_IsValidItemDefinition(ItemDef)) continue;
				// Economy name.
				if (!StrEqual(InventoryItemName, ""))
				{
					char CosmeticName[64];
					TF2Econ_GetItemName(ItemDef, CosmeticName, sizeof(CosmeticName));
					if (StrEqual(InventoryItemName, CosmeticName)) ItemFound = true;
				}
				// Item classname.
				if (!StrEqual(InventoryItemClassname, ""))
				{
					char ItemClassName[64];
					GetEntityClassname(CosmeticItem, ItemClassName, sizeof(ItemClassName));
					if (StrContains(ItemClassName, InventoryItemClassname) != -1)
					{
						ItemFound = true;
						break;
					}
				}
				// Item definition index.
				if (SchemaItemDef == ItemDef)
				{
					ItemFound = true;
					break;
				}
			}
		}

		if (!ItemFound) return Plugin_Stop;
	}


	// All good! :)
	return Plugin_Continue;
}

public Action OnProcessContractLogic(int client, char UUID[MAX_UUID_SIZE], int objective, 
char event[MAX_EVENT_SIZE], int value)
{
	if (GetGameTime() >= g_LastValidProgressTime && g_LastValidProgressTime != -1.0) return Plugin_Stop;
	
	// All good! :)
	return Plugin_Continue;
}

public Action TF2_OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_TF2_AllowRoundEndProgress.BoolValue)
    {
        // Block any events from being processed after this time.
        g_LastValidProgressTime = GetGameTime() + 1.0; // Add an extra second to let events catch up.
    }
    else
    {
        g_LastValidProgressTime = -1.0;
    }
    return Plugin_Continue;
}

public Action TF2_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (view_as<bool>(GameRules_GetProp("m_bInSetup")) && !g_TF2_AllowSetupProgress.BoolValue)
    {
        // Block any events from being processed after this time.
        g_LastValidProgressTime = GetGameTime();
    }
    else
    {
        g_LastValidProgressTime = -1.0;
    }
    return Plugin_Continue;
}

public Action TF2_OnWaitingStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_TF2_AllowWaitingProgress.BoolValue)
    {
        // Block any events from being processed after this time.
        g_LastValidProgressTime = GetGameTime();
    }
    else
    {
        g_LastValidProgressTime = -1.0;
    }
    return Plugin_Continue;
}

public Action TF2_OnWaitingEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_LastValidProgressTime = -1.0;
    return Plugin_Continue;
}

public Action TF2_OnSetupEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_LastValidProgressTime = -1.0;
    return Plugin_Continue;
}


// ============================= TF2 SPECIFIC EVENTS =============================

// Events relating to the attacker killing a victim.
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int death_flags = event.GetInt("death_flags");
	int damagebits = event.GetInt("damagebits");

	if (!IsClientValid(attacker)) return Plugin_Continue;
	if (IsFakeClient(attacker)) return Plugin_Continue;

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
			case TF_CUSTOM_TELEFRAG: CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_TELEFRAG", 1, true);
			case TF_CUSTOM_CROC: CallContrackerEvent(victim, "CONTRACTS_TF2_PLAYER_DEATH_CROC", 1);
		}

		if (StrContains(weapon, "obj_minisentry") != -1 || StrContains(weapon, "obj_sentrygun") != -1)
		{
			CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_SENTRY", 1, true);
		}

		// Reflecting:
		if (StrContains(weapon, "deflect") != -1) CallContrackerEvent(attacker, "CONTRACTS_TF2_KILL_REFLECT", 1, true);

		// Ground check:
		if (!(GetEntityFlags(attacker) & FL_ONGROUND)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_WHILE_AIRBORNE", 1, true);
		if (!(GetEntityFlags(victim) & FL_ONGROUND)) CallContrackerEvent(victim, "CONTRACTS_TF2_PLAYER_KILL_AIRBORNE_ENEMY", 1, true);

		// Conditions check:
		if (TF2_IsPlayerInCondition(attacker, TFCond_GrapplingHook)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_GRAPPLING", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_GrapplingHookSafeFall)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_GRAPPLING", 1, true);
	
		// Mannpower Conditions:
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneStrength)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILL_STRENGTH", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneHaste)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_HASTE", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneRegen)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_REGEN", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneResist)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_RESIST", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneVampire)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_VAMPIRE", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RunePrecision)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_PRECISION", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneAgility)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_AGILITY", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneKnockout)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_KNOCKOUT", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_RuneImbalance)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_IMBALANCE", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_CritRuneTemp)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_CRIT", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_KingRune)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_KING", 1, true);
		if (TF2_IsPlayerInCondition(attacker, TFCond_PlagueRune)) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_KILLRUNE_PLAGUE", 1, true);
	}

	// Assister.
	int assister = GetClientOfUserId(event.GetInt("assister"));
	if (!IsClientValid(assister)) return Plugin_Continue;
	if (IsFakeClient(assister)) return Plugin_Continue;
	if (victim != assister)
	{
		if (TF2_IsPlayerInCondition(attacker, TFCond_Ubercharged)) CallContrackerEvent(assister, "CONTRACTS_TF2_PLAYER_ASSIST_UBER_TEAMMATE", 1, true);
		if (TF2_IsPlayerInCondition(assister, TFCond_Ubercharged)) CallContrackerEvent(assister, "CONTRACTS_TF2_PLAYER_ASSIST_WHILE_UBERED", 1, true);

		if (death_flags & TF_DEATHFLAG_ASSISTERDOMINATION) CallContrackerEvent(assister, "CONTRACTS_TF2_PLAYER_DOMINATION", 1, true);
		if (death_flags & TF_DEATHFLAG_ASSISTERREVENGE) CallContrackerEvent(assister, "CONTRACTS_TF2_PLAYER_REVENGE", 1, true);
	}

	// Damage types.
	if (damagebits & DMG_VEHICLE) CallContrackerEvent(victim, "CONTRACTS_TF2_PLAYER_DEATH_TRAIN", 1);
	if (damagebits & DMG_FALL) CallContrackerEvent(victim, "CONTRACTS_TF2_PLAYER_DEATH_FALL", 1);
	if (damagebits & DMG_NERVEGAS) CallContrackerEvent(victim, "CONTRACTS_TF2_PLAYER_DEATH_SAWBLADE", 1);

	return Plugin_Continue;
}

// Events relating to the attacker hurting a victim.
public Action OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int damage = event.GetInt("damageamount");

	//if (IsFakeClient(attacker)) return Plugin_Continue;
	
	if (IsClientValid(attacker) && IsClientValid(victim))
	{
		// Make sure we're not the same.
		if (attacker == victim) return Plugin_Continue;

		if (event.GetBool("crit")) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_DEAL_FULLCRIT", damage, true);
		if (event.GetBool("minicrit")) CallContrackerEvent(attacker, "CONTRACTS_TF2_PLAYER_DEAL_MINICRIT", damage, true);
	}

	return Plugin_Continue;
}

// Events relating to the attacker killing a victim.
public Action OnPlayerScoreChanged(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int client = event.GetInt("player");
	if (!IsClientValid(client)) return Plugin_Continue;
	int delta = event.GetInt("delta");
	if (delta > 0) CallContrackerEvent(client, "CONTRACTS_PLAYER_SCORE", 1, true);
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
	if (IsFakeClient(client)) return Plugin_Continue;

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

	int assister = GetClientOfUserId(event.GetInt("assister"));
	if (IsClientValid(assister))
	{
		CallContrackerEvent(assister, "CONTRACTS_TF2_ASSIST_OBJECT_DESTROY", 1);
		if (TF2_IsPlayerInCondition(assister, TFCond_Ubercharged))
		{
			CallContrackerEvent(assister, "CONTRACTS_TF2_ASSIST_OBJECT_DESTROY_UBERED", 1);
		}
	}

	int owner = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientValid(owner)) return Plugin_Continue;
	switch (building)
	{
		case TFObject_Sentry: CallContrackerEvent(owner, "CONTRACTS_TF2_SENTRY_DESTROYED", 1);
		case TFObject_Dispenser: CallContrackerEvent(owner, "CONTRACTS_TF2_DISPENSER_DESTROYED", 1);
		case TFObject_Teleporter: CallContrackerEvent(owner, "CONTRACTS_TF2_TELEPORTER_DESTROYED", 1);
	}

	return Plugin_Continue;
}

public Action OnPayloadPushed(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("pusher"));
	if (!IsClientValid(client)) return Plugin_Continue;
	if (IsFakeClient(client)) return Plugin_Continue;
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
		if (!IsClientValid(client) || IsFakeClient(client)) continue;
		CallContrackerEvent(client, "CONTRACTS_TF2_CAPTURE_POINT", 1);
	}
	return Plugin_Continue;
}

public Action OnKilledCapper(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	// Make sure we're not the same.
	if (IsClientValid(attacker))
	{
		CallContrackerEvent(attacker, "CONTRACTS_TF2_KILL_CAPPER", 1, true);
	}
	return Plugin_Continue;
}

public Action OnFlagEvent(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("attacker"));
	int event_type = event.GetInt("eventtype");
	if (!IsClientValid(client)) return Plugin_Continue;

	switch (event_type)
	{
		case TF_FLAGEVENT_PICKEDUP: CallContrackerEvent(client, "CONTRACTS_TF2_FLAG_PICKUP", 1);
		case TF_FLAGEVENT_CAPTURED: CallContrackerEvent(client, "CONTRACTS_TF2_FLAG_CAPTURE", 1);
		case TF_FLAGEVENT_DEFENDED: CallContrackerEvent(client, "CONTRACTS_TF2_FLAG_DEFEND", 1);
		case TF_FLAGEVENT_RETURNED: CallContrackerEvent(client, "CONTRACTS_TF2_FLAG_RETURN", 1);
	}
	return Plugin_Continue;
} 

public Action OnPassGet(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("owner");
	if (!IsClientValid(client)) return Plugin_Continue;
	CallContrackerEvent(client, "CONTRACTS_TF2_PASS_GET", 1);
	return Plugin_Continue;
}

public Action OnPassScore(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("scorer");
	if (!IsClientValid(client)) return Plugin_Continue;
	CallContrackerEvent(client, "CONTRACTS_TF2_PASS_SCORE", 1);
	return Plugin_Continue;
}

public Action OnPassFree(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("owner");
	int attacker = event.GetInt("attacker");
	if (!IsClientValid(client)) return Plugin_Continue;
	CallContrackerEvent(client, "CONTRACTS_TF2_PASS_LOSE_BALL", 1);
	if (!IsClientValid(attacker)) return Plugin_Continue;
	if (attacker == client) return Plugin_Continue;
	CallContrackerEvent(attacker, "CONTRACTS_TF2_PASS_ATTACK", 1);
	return Plugin_Continue;
}

public Action OnPassCaught(Event event, const char[] name, bool dontBroadcast)
{
	int passer = event.GetInt("passer");
	int catcher = event.GetInt("catcher");
	if (!IsClientValid(passer)) return Plugin_Continue;
	CallContrackerEvent(passer, "CONTRACTS_TF2_PASS_BALL", 1);
	if (!IsClientValid(catcher)) return Plugin_Continue;
	if (catcher == passer) return Plugin_Continue;
	CallContrackerEvent(catcher, "CONTRACTS_TF2_PASS_CATCH", 1);
	return Plugin_Continue;
}

public Action OnBallStolen(Event event, const char[] name, bool dontBroadcast)
{
	int victim = event.GetInt("victim");
	int attacker = event.GetInt("attacker");
	if (!IsClientValid(victim)) return Plugin_Continue;
	CallContrackerEvent(victim, "CONTRACTS_TF2_PASS_LOSE_BALL", 1);
	if (!IsClientValid(attacker)) return Plugin_Continue;
	if (attacker == victim) return Plugin_Continue;
	CallContrackerEvent(attacker, "CONTRACTS_TF2_PASS_STEAL", 1);
	return Plugin_Continue;
}

public Action OnPassBlocked(Event event, const char[] name, bool dontBroadcast)
{
	int owner = event.GetInt("owner");
	int blocker = event.GetInt("blocker");
	if (!IsClientValid(owner)) return Plugin_Continue;
	CallContrackerEvent(owner, "CONTRACTS_TF2_PASS_LOSE_BALL", 1);
	if (!IsClientValid(blocker)) return Plugin_Continue;
	if (blocker == owner) return Plugin_Continue;
	CallContrackerEvent(blocker, "CONTRACTS_TF2_PASS_BLOCK", 1);
	return Plugin_Continue;
}

public Action OnWorldDeath(Event event, const char[] name, bool dontBroadcast)
{
	int killer = event.GetInt("killer");
	if (!IsClientValid(killer)) return Plugin_Continue;
	CallContrackerEvent(killer, "CONTRACTS_TF2_PLAYER_KILL_WORLD", 1);
	return Plugin_Continue;
}