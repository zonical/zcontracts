#if defined __zcontracts_csgo_included
	#endinput
#endif

#define __zcontracts_csgo_included

#include <cstrike>

// ============================= SCHEMA FUNCTIONS =============================

stock int CSGO_GetTeamIndexFromString(const char[] team)
{
    if (StrEqual(team, "t") || StrEqual(team, "terrorists")) 
    {
        return CS_TEAM_T;
    }
    if (StrEqual(team, "ct")
    || StrEqual(team, "counterterrorists")
    || StrEqual(team, "counter-terrorists")) 
    {
        return CS_TEAM_CT;
    }
    return -1;
}

// Returns -1 if no int value can be assigned to gametype!
stock int CSGO_GetGameTypeIndexFromString(const char[] gametype)
{
    if (StrEqual(gametype, "casual")) return 0;
    if (StrEqual(gametype, "competitive")) return 0;
    if (StrEqual(gametype, "scrimcomp2v2") || StrEqual(gametype, "wingman")) return 0;
    if (StrEqual(gametype, "scrimcomp5v5") || StrEqual(gametype, "weapons_expert")) return 0;
    if (StrEqual(gametype, "gungameprogressive") || StrEqual(gametype, "armsrace")) return 1;
    if (StrEqual(gametype, "gungametrbomb") || StrEqual(gametype, "demolition")) return 1;
    if (StrEqual(gametype, "deathmatch") || StrEqual(gametype, "dm")) return 1;
    if (StrEqual(gametype, "training")) return 2;
    if (StrEqual(gametype, "custom")) return 3;
    if (StrEqual(gametype, "cooperative") || StrEqual(gametype, "guardian")) return 4;
    if (StrEqual(gametype, "coopstrike") || StrEqual(gametype, "coopmission")) return 4;
    if (StrEqual(gametype, "skirmish") || StrEqual(gametype, "wargames")) return 5;
    if (StrEqual(gametype, "survival") || StrEqual(gametype, "dangerzone")) return 6;

    return -1;
}

// Returns -1 if no int value can be assigned to gamemode!
int CSGO_GetGameModeIndexFromString(const char[] gamemode)
{
    if (StrEqual(gamemode, "casual")) return 0;
    if (StrEqual(gamemode, "competitive")) return 1;
    if (StrEqual(gamemode, "scrimcomp2v2") || StrEqual(gamemode, "wingman")) return 2
    if (StrEqual(gamemode, "scrimcomp5v5") || StrEqual(gamemode, "weapons_expert")) return 3;
    if (StrEqual(gamemode, "gungameprogressive") || StrEqual(gamemode, "armsrace")) return 0;
    if (StrEqual(gamemode, "gungametrbomb") || StrEqual(gamemode, "demolition")) return 1;
    if (StrEqual(gamemode, "deathmatch") || StrEqual(gamemode, "dm")) return 2;
    if (StrEqual(gamemode, "training")) return 0;
    if (StrEqual(gamemode, "custom")) return 0;
    if (StrEqual(gamemode, "cooperative") || StrEqual(gamemode, "guardian")) return 0;
    if (StrEqual(gamemode, "coopstrike") || StrEqual(gamemode, "coopmission")) return 1;
    if (StrEqual(gamemode, "skirmish") || StrEqual(gamemode, "wargames")) return 0;
    if (StrEqual(gamemode, "survival") || StrEqual(gamemode, "dangerzone")) return 0;

    return -1;
}

// Returns -1 if no int value can be assigned to gamemode!
int CSGO_GetSkirmishIndexFromString(const char[] name)
{
    if (StrEqual(name, "stabstabzap")) return 1;
    if (StrEqual(name, "flyingscoutsman")) return 3;
    if (StrEqual(name, "triggerdiscipline")) return 4;
    if (StrEqual(name, "headshots")) return 6;
    if (StrEqual(name, "huntergatherers")) return 7;
    if (StrEqual(name, "heavyassaultsuit")) return 8;
    if (StrEqual(name, "armsrace")) return 10;
    if (StrEqual(name, "demolition")) return 11;
    if (StrEqual(name, "retakes")) return 12;

    // This technically isn't used anymore in CSGO.
    if (StrEqual(name, "dm_freeforall")) return 2;

    // Skirmish ID's 5 and 9 are undefined. Configs exists for Bloodletter,
    // Bounty Hunter and Team Deathmatch (for some reason). These are not
    // included here in case the CSGO team adds more Skirmish IDs.
    // For more information, read: https://developer.valvesoftware.com/wiki/CS:GO_Game_Modes
    return -1;
}

// ============================= MISC FUNCTIONS =============================

stock int CSGO_GetGameTypeRestriction(KeyValues ContractConf)
{
    char gametype_id[16];
    ContractConf.GetString("game_type", gametype_id, sizeof(gametype_id), "-1");
    // Can we convert this to an integer straight away?
    if (StrEqual(gametype_id, "0")) return 0;
    if (StringToInt(gametype_id) != 0) return StringToInt(gametype_id);

    // Parse this custom string.
    return CSGO_GetGameTypeIndexFromString(gametype_id);
}

stock int CSGO_GetGameModeRestriction(KeyValues ContractConf)
{
    char gamemode_id[16];
    ContractConf.GetString("game_mode", gamemode_id, sizeof(gamemode_id), "-1");
    // Can we convert this to an integer straight away?
    if (StrEqual(gamemode_id, "0")) return 0;
    if (StringToInt(gamemode_id) != 0) return StringToInt(gamemode_id);

    // Parse this custom string.
    return CSGO_GetGameModeIndexFromString(gamemode_id);
}

stock int CSGO_GetSkirmishRestriction(KeyValues ContractConf)
{
    char skirmish_id[16];
    ContractConf.GetString("skirmish_id", skirmish_id, sizeof(skirmish_id), "-1");
    // Can we convert this to an integer straight away?
    // NOTE: ID 0 is not defined (see CSGO_GetSkirmishIndexFromString()).
    if (StringToInt(skirmish_id) >= 1) return StringToInt(skirmish_id);

    // Parse this custom string.
    return CSGO_GetSkirmishIndexFromString(skirmish_id);
}

stock bool CSGO_IsCorrectGameType(int game_type)
{
    ConVar GameType = FindConVar("game_type");
    if (GameType == null) return false;
    return GameType.IntValue == game_type;
}

stock bool CSGO_IsCorrectGameMode(int game_mode)
{
    ConVar GameMode = FindConVar("game_mode");
    if (GameMode == null) return false;
    return GameMode.IntValue == game_mode;
}

stock bool CSGO_IsCorrectSkirmishID(int skirmish_id)
{
    ConVar SkirmishID = FindConVar("sv_skirmish_id");
    if (SkirmishID == null) return false;
    return SkirmishID.IntValue == skirmish_id;
}