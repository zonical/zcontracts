#include <tf2>
#include <tf2_stocks>

ConVar g_TF2_AllowSetupProgress;
ConVar g_TF2_AllowRoundEndProgress;
ConVar g_TF2_AllowWaitingProgress;

TF2GameMode_Extensions g_TF2_GameModeExtension = TGE_NoExtension;

// Some gamemodes which have variations might not be detectable
// with the existance of a gamerules entity. Attack/Defend CP maps
// are an example of this.
enum TF2GameMode_Extensions
{
    TGE_NoExtension = 0,
    TGE_RedAttacksBlu = 1, // Standard A/D
    TGE_BluAttacksRed = 2, // Standard Payload
    TGE_Symmetrical = 3 // 3CP like Powerhouse or 5CP like Badlands
}

// Creates TF2 specific ConVar's.
void TF2_CreatePluginConVars()
{
    g_TF2_AllowSetupProgress = CreateConVar("zctf2_allow_setup_trigger", "1", "If disabled, Objective progress will not be counted during setup time.");
    g_TF2_AllowRoundEndProgress = CreateConVar("zctf2_allow_roundend_trigger", "0", "If disabled, Objective progress will not be counted after a winner is declared and the next round starts.");
    g_TF2_AllowWaitingProgress = CreateConVar("zctf2_allow_waitingforplayers_trigger", "0", "If disabled, Objective progress will not be counted during the \"waiting for players\" period before a game starts.");
}

// Hook events for TF2 related functions.
void TF2_CreateEventHooks()
{
	HookEvent("teamplay_round_win", TF2_OnRoundWin);
	HookEvent("teamplay_round_start", TF2_OnRoundStart);
	HookEvent("teamplay_waiting_begins", TF2_OnWaitingStart);
	HookEvent("teamplay_waiting_ends", TF2_OnWaitingEnd);
	HookEvent("teamplay_setup_finished", TF2_OnSetupEnd);
}

// ============ EVENT FUNCTIONS ============
public Action TF2_OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_TF2_AllowRoundEndProgress.BoolValue)
    {
        // Block any events from being processed after this time.
        g_LastValidProgressTime = GetGameTime() + 1.0; // Add an extra 
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

// Intended for contracts_schema.
void TF2_ConstructClassRestrictions(KeyValues ContractSchema, Contract ContractBuffer)
{
    if (ContractSchema.JumpToKey("classes", false))
    {
        ContractBuffer.m_bClass[TFClass_Scout]      = view_as<bool>(ContractSchema.GetNum("scout", 0));
        ContractBuffer.m_bClass[TFClass_Soldier]    = view_as<bool>(ContractSchema.GetNum("soldier", 0));
        ContractBuffer.m_bClass[TFClass_Pyro]       = view_as<bool>(ContractSchema.GetNum("pyro", 0));
        ContractBuffer.m_bClass[TFClass_DemoMan]    = view_as<bool>(ContractSchema.GetNum("demoman", 0));
        ContractBuffer.m_bClass[TFClass_Heavy]      = view_as<bool>(ContractSchema.GetNum("heavy", 0));
        ContractBuffer.m_bClass[TFClass_Engineer]   = view_as<bool>(ContractSchema.GetNum("engineer", 0));
        ContractBuffer.m_bClass[TFClass_Sniper]     = view_as<bool>(ContractSchema.GetNum("sniper", 0));
        ContractBuffer.m_bClass[TFClass_Medic]      = view_as<bool>(ContractSchema.GetNum("medic", 0));
        ContractBuffer.m_bClass[TFClass_Spy]        = view_as<bool>(ContractSchema.GetNum("spy", 0));
        
        // Return.
        ContractSchema.GoBack();
    }
    return;
}

// Intended for contracts_schema.
int TF2_GetTeamIndexFromString(const char[] team)
{
    if (StrEqual(team, "red")) return view_as<int>(TFTeam_Red);
    if (StrEqual(team, "blue") || StrEqual(team, "blu")) 
    {
        return view_as<int>(TFTeam_Blue);
    }

    return -1;
}

// Checks to see if the client's class matches.
bool TF2_IsCorrectClass(int client, Contract ClientContract)
{
    TFClassType Class = TF2_GetPlayerClass(client);
    if (Class == TFClass_Unknown) return false;
    return ClientContract.m_bClass[Class] == true;
}

// Checks to see if a GameRules entity exists on the current map.
bool TF2_ValidGameRulesEntityExists(const char[] classname)
{
	// Ignore if string is empty.
	if (StrEqual(classname, "")) return true;

	// Validate that we're actually checking for
	// a gamerules entity with a classname check.
	if (StrContains(classname, "tf_logic_") == -1) return false;

	// Try and find this entity.
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		return true;
	}
	return false;
}

// Sets the GME.
public any Native_SetTF2GameModeExt(Handle plugin, int numParams)
{
    TF2GameMode_Extensions value = view_as<TF2GameMode_Extensions>(GetNativeCell(1));
    g_TF2_GameModeExtension = value;
    return true;
}

TF2GameMode_Extensions TF2_GetCurrentMapGME()
{
    // Fire a forward that asks any other plugins if they
    // wish to set the GME themselves with SetTF2GameModeExt.
    Call_StartForward(g_fOnGameModeExtCheck);
    Action ShouldBlock;
    Call_Finish(ShouldBlock);

    if (ShouldBlock >= Plugin_Changed)
    {
        // If a plugin developer is smart and uses SetTF2GameModeExt in the forward,
        // we can just return the global.
        return g_TF2_GameModeExtension;
    }

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

        if (RedPoints < BluPoints) return TGE_RedAttacksBlu;
        if (BluPoints < RedPoints) return TGE_BluAttacksRed;
        if (RedPoints == BluPoints) return TGE_Symmetrical;
    }

    return TGE_NoExtension;
}