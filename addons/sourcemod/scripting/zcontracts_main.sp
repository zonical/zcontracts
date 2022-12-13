// LIST:
// TODO: Port to CSGO
// TODO: Implement Creators.TF style hud
// TODO: Sounds for selecting contracts and getting progress
// TODO: Sound preference for client
// TODO: HUD preference for client
// TODO: Preferences saved to database

#pragma semicolon 1

// There are engine checks for game extensions!
#undef REQUIRE_EXTENSIONS
#define DEBUG

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <cstrike>
#include <morecolors>
#include <float>

#include <zcontracts/zcontracts>

Database g_DB;
Handle g_DatabaseUpdateTimer;

// Player Contracts.
Contract OldClientContracts[MAXPLAYERS+1];
Contract ClientContracts[MAXPLAYERS+1];

// ConVars.
ConVar g_UpdatesPerSecond;
ConVar g_DatabaseUpdateTime;
ConVar g_DisplayHudMessages;
ConVar g_PlaySounds;


#if defined DEBUG
ConVar g_DebugEvents;
ConVar g_DebugProcessing;
ConVar g_DebugQuery;
ConVar g_DebugProgress;
ConVar g_DebugSessions;
#endif

ConVar g_TF2_AllowSetupProgress;
ConVar g_TF2_AllowRoundEndProgress;
ConVar g_TF2_AllowWaitingProgress;

// Forwards
GlobalForward g_fOnObjectiveCompleted;
GlobalForward g_fOnContractCompleted;
GlobalForward g_fOnContractPreSave;
GlobalForward g_fOnObjectivePreSave;

float g_LastValidProgressTime = -1.0;

// This arraylist contains a list of objectives that we need to update.
ArrayList g_ObjectiveUpdateQueue;

// Preferences
bool PlayerSoundsEnabled[MAXPLAYERS+1] = { true, ... };

// Subplugins.
#include "zcontracts/contracts_schema.sp"
#include "zcontracts/contracts_timers.sp"
#include "zcontracts/contracts_database.sp"
#include "zcontracts/contracts_menu.sp"

public Plugin myinfo =
{
	name = "ZContracts - Custom Contract Logic",
	author = "ZoNiCaL",
	description = "Allows server operators to design their own contracts.",
	version = "alpha-1",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// ================ FORWARDS ================
	g_fOnObjectiveCompleted = new GlobalForward("OnContractObjectiveCompleted", ET_Ignore, Param_Cell, Param_String, Param_Array);
	g_fOnContractCompleted = new GlobalForward("OnContractCompleted", ET_Ignore, Param_Cell, Param_String, Param_Array);
	g_fOnContractPreSave = new GlobalForward("OnContractPreSave", ET_Event, Param_Cell, Param_String, Param_Array);
	g_fOnObjectivePreSave = new GlobalForward("OnObjectivePreSave", ET_Event, Param_Cell, Param_String, Param_Array);

	// ================ NATIVES ================
	CreateNative("SetClientContract", Native_SetClientContract);
	CreateNative("SetClientContractStruct", Native_SetClientContractStruct);
	CreateNative("GetClientContract", Native_GetClientContract);
	CreateNative("CallContrackerEvent", Native_CallContrackerEvent);

	CreateNative("SaveClientContractProgress", Native_SaveClientContractProgress);
	CreateNative("SaveClientObjectiveProgress", Native_SaveClientObjectiveProgress);
	CreateNative("SetContractProgressDatabase", Native_SetContractProgressDatabase);
	CreateNative("SetObjectiveProgressDatabase", Native_SetObjectiveProgressDatabase);
	CreateNative("SetObjectiveFiresDatabase", Native_SetObjectiveFiresDatabase);
	return APLRes_Success;
}

public void OnPluginStart()
{
	// ================ CONVARS ================
	g_ConfigSearchPath = CreateConVar("zc_schema_search_path", "configs/zcontracts", "The path, relative to the \"sourcemods/\" directory, to find Contract definition files. Changing this Value will cause a reload of the Contract schema.");
	g_RequiredFileExt = CreateConVar("zc_schema_required_ext", ".txt", "The file extension that Contract definition files must have in order to be considered valid. Changing this Value will cause a reload of the Contract schema.");
	g_DisabledPath = CreateConVar("zc_schema_disabled_path", "configs/zcontracts/disabled", "If a search path has this string in it, any Contract's loaded in or derived from this path will not be loaded. Changing this Value will cause a reload of the Contract schema.");
	
	g_UpdatesPerSecond = CreateConVar("zc_updates_per_second", "8", "How many objective updates to process per second.");
	g_DatabaseUpdateTime = CreateConVar("zc_database_update_time", "30", "How long to wait before sending Contract updates to the database for all players.");
	g_DisplayHudMessages = CreateConVar("zc_display_hud_messages", "1", "If enabled, players will see a hint-box in their HUD when they gain progress on their Contract or an Objective.");
	g_PlaySounds = CreateConVar("zc_play_sounds", "1", "If enabled, sounds will play when interacting with the Contracker and when progress is made when a Contract is active.");

	g_TF2_AllowSetupProgress = CreateConVar("zctf2_allow_setup_trigger", "1", "If disabled, Objective progress will not be counted during setup time.");
	g_TF2_AllowRoundEndProgress = CreateConVar("zctf2_allow_roundend_trigger", "0", "If disabled, Objective progress will not be counted after a winner is declared and the next round starts.");
	g_TF2_AllowWaitingProgress = CreateConVar("zctf2_allow_waitingforplayers_trigger", "0", "If disabled, Objective progress will not be counted during the \"waiting for players\" period before a game starts.");

#if defined DEBUG
	g_DebugEvents = CreateConVar("zc_debug_print_events", "0", "Logs every time an event is sent.");
	g_DebugProcessing = CreateConVar("zc_debug_processing", "0", "Logs every time an event is processed.");
	g_DebugQuery = CreateConVar("zc_debug_queries", "0", "Logs every time a query is sent to the database.");
	g_DebugProgress = CreateConVar("zc_debug_progress", "0", "Logs every time player progress is incremented internally.");
	g_DebugSessions = CreateConVar("zc_debug_sessions", "0", "Logs every time a session is restored.");
#endif

	g_PlaySounds.AddChangeHook(OnPlaySoundsChange);
	g_DatabaseUpdateTime.AddChangeHook(OnDatabaseUpdateChange);
	g_ConfigSearchPath.AddChangeHook(OnSchemaConVarChange);
	g_RequiredFileExt.AddChangeHook(OnSchemaConVarChange);
	g_DisabledPath.AddChangeHook(OnSchemaConVarChange);

	// ================ EVENTS ================
	HookEvent("teamplay_round_win", OnRoundWin);
	HookEvent("teamplay_round_start", OnRoundStart);
	HookEvent("teamplay_waiting_begins", OnWaitingStart);
	HookEvent("teamplay_waiting_ends", OnWaitingEnd);
	HookEvent("teamplay_setup_finished", OnSetupEnd);

	// ================ SOUNDS ================
	PrecacheSound("CYOA.StaticFade");
	PrecacheSound("CYOA.NodeActivate");
	PrecacheSound("MatchMaking.RankUp");
	PrecacheSound("Quest.Alert");
	PrecacheSound("Quest.Decode");
	PrecacheSound("Quest.StatusTickNovice");

	// ================ CONTRACKER ================
	ProcessContractsSchema();
	CreateContractMenu();

	g_ObjectiveUpdateQueue = new ArrayList(sizeof(ObjectiveUpdate));
	CreateTimer(1.0, Timer_ProcessEvents, _, TIMER_REPEAT);
	g_DatabaseUpdateTimer = CreateTimer(g_DatabaseUpdateTime.FloatValue, Timer_SaveAllToDB, _, TIMER_REPEAT);

	// ================ DATABASE ================
	Database.Connect(GotDatabase, "zcontracts");

	// ================ PLAYER INIT ================
	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		OnClientPostAdminCheck(i);
	}

	// ================ COMMANDS ================
	RegAdminCmd("sm_setcontract", DebugSetContract, ADMFLAG_KICK);
	RegAdminCmd("sm_setcontractprogress", DebugSetContractProgress, ADMFLAG_BAN);
	RegAdminCmd("sm_setobjectiveprogress", DebugSetObjectiveProgress, ADMFLAG_BAN);
	RegAdminCmd("sm_setobjectivefires", DebugSetObjectiveFires, ADMFLAG_BAN);
	RegAdminCmd("sm_triggerevent", DebugTriggerEvent, ADMFLAG_BAN);
	RegAdminCmd("sm_savecontract", DebugSaveContract, ADMFLAG_KICK);
	//RegAdminCmd("sm_resetcontract", DebugResetContract, ADMFLAG_BAN);
	RegAdminCmd("sm_debugcontract", DebugContractInfo, ADMFLAG_ROOT);
	RegAdminCmd("zc_reload_contracts", ReloadContracts, ADMFLAG_ROOT);
	RegAdminCmd("zc_reload_database", ReloadDatabase, ADMFLAG_ROOT);


	RegConsoleCmd("sm_contract", OpenContrackerForClient);
	RegConsoleCmd("sm_contracts", OpenContrackerForClient);
	RegConsoleCmd("sm_c", OpenContrackerForClient);
}

// ============ SM FORWARD FUNCTIONS ============

public void OnClientPostAdminCheck(int client)
{
	// Reset variables.
	Contract BlankContract;
	ClientContracts[client] = BlankContract;
	OldClientContracts[client] = BlankContract;

	// Grab the players Contract from the last session.
	if (IsClientValid(client)
	&& !IsFakeClient(client)
	&& g_DB != null)
	{
		GrabContractFromLastSession(client);
	}
	
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;

}

public void OnClientDisconnect(int client)
{
	if (IsClientValid(client)
	&& !IsFakeClient(client)
	&& g_DB != null)
	{
		Contract ClientContract;
		GetClientContract(client, ClientContract);

		SaveClientContractProgress(client, ClientContracts[client]);
		for (int i = 0; i < ClientContract.m_hObjectives.Length; i++)
		{
			ContractObjective ClientContractObjective;
			ClientContract.GetObjective(i, ClientContractObjective);
			if (!ClientContractObjective.m_bInitalized) continue;

			SaveClientObjectiveProgress(client, ClientContract.m_sUUID, ClientContractObjective);
		}
	}

	Contract Blank;
	ClientContracts[client] = Blank;
	OldClientContracts[client] = Blank;
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;
}

public void OnMapStart()
{
	g_LastValidProgressTime = -1.0;
}

public void OnSchemaConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	ProcessContractsSchema();
	CreateContractMenu();
}

public void OnPlaySoundsChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (StringToInt(newValue) == 0)
	{
		for (int i = 0; i < MAXPLAYERS+1; i++) PlayerSoundsEnabled[i] = false;
	}
	else
	{
		// TODO: Load from database
	}
}

public Action ReloadContracts(int client, int args)
{
	ProcessContractsSchema();
	CreateContractMenu();
	return Plugin_Continue;
}

// ============ NATIVE FUNCTIONS ============

/**
 * Obtains a client's active Contract.
 *
 * @param client    Client index.
 * @param buffer    Buffer to store the client's contract.
 * @error           Client index is invalid.          
 */
public any Native_GetClientContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client)) 
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	SetNativeArray(2, ClientContracts[client], sizeof(Contract));
	return true;
}

/**
 * Processes an event for the client's active Contract.
 *
 * @param client    Client index.
 * @param event    	Event to process.
 * @param value		Value to send alongside this event.
 * @return			True if an event is successfully called, false if the client's contract isn't active.
 * @error           Client index is invalid or is a bot.   
 */
public any Native_CallContrackerEvent(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char event[MAX_EVENT_SIZE];
	GetNativeString(2, event, sizeof(event));
	int value = GetNativeCell(3);
	bool can_combine = GetNativeCell(4);

	if (!IsClientValid(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	if (IsFakeClient(client)) return false;
	if (GetGameTime() >= g_LastValidProgressTime && g_LastValidProgressTime != -1.0) return false;

	Contract ClientContract;
	GetClientContract(client, ClientContract);
	
	// Do we have a contract currently active?
	if (!ClientContract.IsContractInitalized() || ClientContract.IsContractComplete()) return false;

	if (g_DebugEvents.BoolValue)
	{
		LogMessage("[ZContracts] Event triggered by %N: %s, VALUE: %d", client, event, value);
	}

	// Try to add our objectives to the increment queue.
	for (int i = 0; i < ClientContract.m_hObjectives.Length; i++)
	{	
		ContractObjective ClientContractObjective;
		ClientContract.GetObjective(i, ClientContractObjective);

		if (!ClientContractObjective.m_bInitalized || ClientContractObjective.IsObjectiveComplete()) continue;

		// Check to see if we have this event in any of our objective event triggers.
		bool EventCheckPassed = false;
		for (int j = 0; j < ClientContractObjective.m_hEvents.Length; j++)
		{
			ContractObjectiveEvent ObjEvent;
			ClientContractObjective.m_hEvents.GetArray(j, ObjEvent, sizeof(ContractObjectiveEvent));

			if (StrEqual(ObjEvent.m_sEventName, event))
			{
				EventCheckPassed = true;
				break;
			}
		}
		if (!EventCheckPassed) continue;

		// Add to the queue for this client.
		if (can_combine && g_ObjectiveUpdateQueue.Length > 0)
		{
			bool ObjectiveUpdated = false;
			ObjectiveUpdate ObjUpdate;
			for (int k = 0; k < g_ObjectiveUpdateQueue.Length; k++)
			{
				g_ObjectiveUpdateQueue.GetArray(k, ObjUpdate);
				if (ObjUpdate.m_iClient != client) continue;
				if (ObjUpdate.m_iObjectiveID != ClientContractObjective.m_iInternalID) continue;
				if (!StrEqual(ObjUpdate.m_sUUID, ClientContract.m_sUUID)) continue;
				if (!StrEqual(ObjUpdate.m_sEvent, event)) continue;

				ObjUpdate.m_iValue += value;
				g_ObjectiveUpdateQueue.SetArray(k, ObjUpdate);
				ObjectiveUpdated = true;
				break;
			}

			// Move to the next objective to be added to the queue.
			if (ObjectiveUpdated) continue;
		}
		
		ObjectiveUpdate ObjUpdate;
		ObjUpdate.m_iClient = client;
		ObjUpdate.m_iValue = value;
		ObjUpdate.m_iObjectiveID = ClientContractObjective.m_iInternalID;
		ObjUpdate.m_sUUID = ClientContract.m_sUUID;
		ObjUpdate.m_sEvent = event;
		g_ObjectiveUpdateQueue.PushArray(ObjUpdate, sizeof(ObjectiveUpdate));
	}
	return true;
}

/**
 * Set a client's contract.
 *
 * @param client    Client index.
 * @param UUID    	The UUID of the contract.
 * @error           Client index is invalid or UUID is invalid.         
 */
public any Native_SetClientContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char UUID[MAX_UUID_SIZE];
	GetNativeString(2, UUID, sizeof(UUID));
	bool dont_save = GetNativeCell(3);
	bool dont_notify = GetNativeCell(4);

	// Are we a bot?
	if (!IsClientValid(client) || IsFakeClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

	// If we have a Contract already selected, save it's progress to the database.
	Contract OldClientContract;
	GetClientContract(client, OldClientContract);
	OldClientContract.m_bActive = false;
	OldClientContracts[client] = OldClientContract;

	if (OldClientContract.IsContractInitalized())
	{
		SaveClientContractProgress(client, OldClientContract);
		for (int i = 0; i < OldClientContract.m_hObjectives.Length; i++)
		{
			ContractObjective ClientContractObjective;
			OldClientContract.GetObjective(i, ClientContractObjective);
			if (!ClientContractObjective.m_bInitalized) continue;

			SaveClientObjectiveProgress(client, OldClientContract.m_sUUID, ClientContractObjective);
		}
	}

	// Get our Contract definition.
	Contract ClientContract;
	if (!CreateContractFromUUID(UUID, ClientContract))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID (%s) for client %d", UUID, client);
	}
	ClientContracts[client] = ClientContract;

	// Get the client's SteamID64.
	char steamid64[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

	// TODO: Can we make this into one query?
	char contract_query[1024];
	if (ClientContract.m_iContractType == Contract_ContractProgress)
	{
		g_DB.Format(contract_query, sizeof(contract_query),
		"SELECT * FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'", steamid64, UUID);
		g_DB.Query(CB_SetClientContract_Contract, contract_query, client);
	}
	char objective_query[1024];
	g_DB.Format(objective_query, sizeof(objective_query), 
	"SELECT * FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND (objective_id BETWEEN 0 AND %d) ORDER BY objective_id ASC;", 
	steamid64, ClientContract.m_sUUID, ClientContract.m_hObjectives.Length);
	g_DB.Query(CB_SetClientContract_Objective, objective_query, client);

	if (!dont_notify)
	{
		// Display the Contract to the client when we can.
		CreateObjectiveDisplay(client, ClientContract, true);
		CreateTimer(1.0, Timer_DisplayContractInfo, client, TIMER_REPEAT);
	}

	// Set this Contract as our current session.
	if (!dont_save) SaveContractSession(client, ClientContract.m_sUUID);

	LogMessage("[ZContracts] %N CONTRACT: Set Contract to: %s [ID: %s]", client, ClientContract.m_sContractName, ClientContract.m_sUUID);

	// Reset our current directory in the Contracker.
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;

	return true;
}

public any Native_SetClientContractStruct(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	Contract NewContract;
	GetNativeArray(2, NewContract, sizeof(Contract));
	bool dont_save = GetNativeCell(3);
	bool dont_notify = GetNativeCell(4);

	// Are we a bot?
	if (!IsClientValid(client) || IsFakeClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	if (NewContract.m_sUUID[0] != '{')
    {
        return ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", NewContract.m_sUUID);
    }

	// If we have a Contract already selected, save it's progress to the database.
	Contract OldClientContract;
	GetClientContract(client, OldClientContract);
	OldClientContract.m_bActive = false;
	OldClientContracts[client] = OldClientContract;

	if (OldClientContract.IsContractInitalized())
	{
		SaveClientContractProgress(client, OldClientContract);
		for (int i = 0; i < OldClientContract.m_hObjectives.Length; i++)
		{
			ContractObjective ClientContractObjective;
			OldClientContract.GetObjective(i, ClientContractObjective);
			if (!ClientContractObjective.m_bInitalized) continue;

			SaveClientObjectiveProgress(client, OldClientContract.m_sUUID, ClientContractObjective);
		}
	}

	ClientContracts[client] = NewContract;

	LogMessage("[ZContracts] %N CONTRACT: Set Contract to: %s [ID: %s]", client, NewContract.m_sContractName, NewContract.m_sUUID);

	if (!dont_notify)
	{
		// Display the Contract to the client when we can.
		CreateObjectiveDisplay(client, NewContract, false);
	}

	// Set this Contract as our current session.
	if (!dont_save) SaveContractSession(client, NewContract.m_sUUID);

	// Reset our current directory in the Contracker.
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;

	return true;
}


// Function for event timers.
public Action Timer_DisplayContractInfo(Handle hTimer, int client)
{
	static int Attempts = 0;

	// Get our contracts.
	Contract ClientContract;
	GetClientContract(client, ClientContract);
	
	if (ClientContract.m_bLoadedFromDatabase || Attempts >= 3)
	{
		CreateObjectiveDisplay(client, ClientContract, false);
		return Plugin_Stop;
	}

	Attempts++;
	return Plugin_Continue;
}

// ============ CONTRACKER SESSION ============

/**
 * Saves the client's Contract UUID to the database. If the client disconnects,
 * this value will be used to grab the Contract again on reconnect.
 *
 * @param client    	        Client index.
 * @error                       Client index is invalid. 
 */
void SaveContractSession(int client, char UUID[MAX_UUID_SIZE])
{
	if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}
	if (UUID[0] != '{')
	{
		ThrowError("Invalid UUID passed. (%s)", UUID);
	}

	// Get the client's SteamID64.
	char steamid64[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

	if (g_DebugSessions.BoolValue)
	{
		LogMessage("[ZContracts] %N SESSION: Attempting to save Contract session.", client);
	}

	char query[1024];
	g_DB.Format(query, sizeof(query),
		"INSERT INTO selected_contract (steamid64, contract_uuid) VALUES ('%s', '%s')"
	... " ON DUPLICATE KEY UPDATE contract_uuid = '%s'", steamid64, UUID, UUID);

	g_DB.Query(CB_SaveContractSession, query, client, DBPrio_High);
}

public void CB_SaveContractSession(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %N SESSION: Failed to save Contract session. [SQL ERR: %s]", client, error);
        }
        return;
    }
    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N SESSION: Successfuly saved Contract session.", client);
    }
}

/**
 * Gets the last Contract the client selected from their last game session and
 * sets it as the active Contract.
 *
 * @param client    	        Client index.
 * @error                       Client index is invalid. 
 */
void GrabContractFromLastSession(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

    if (g_DebugSessions.BoolValue)
    {
        LogMessage("[ZContracts] %N SESSION: Attempting to grab last Contract session.", client);
    }

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT contract_uuid FROM selected_contract WHERE steamid64 = '%s'", steamid64);
    g_DB.Query(CB_GetContractFromLastSession, query, client, DBPrio_High);
}

public void CB_GetContractFromLastSession(Database db, DBResultSet results, const char[] error, int client)
{
    char UUID[MAX_UUID_SIZE];
    if (results.RowCount < 1)
    {
        if (g_DebugSessions.BoolValue)
        {
            LogMessage("[ZContracts] %N SESSION: No previous Contract session exists.", client);
        } 
        return;  
    }

    while (results.FetchRow())
    {
        results.FetchString(0, UUID, sizeof(UUID));
        SetClientContract(client, UUID, true);
    }
}

// ============ MAIN LOGIC FUNCTIONS ============

/**
 * Events that are sent through the native CallContrackerEvent will be placed into
 * a queue (g_ObjectiveUpdateQueue). Only a certain amount of events are processed
 * every second for performance reasons. Developers that implement the CallContrackerEvent
 * should find ways to reduce the amount of events they send (e.g zcontract_events,
 * OnPlayerHurt related functions).       
 */
public Action Timer_ProcessEvents(Handle hTimer)
{
	int iProcessed = 0;
	for (;;)
	{
		if (g_ObjectiveUpdateQueue.Length == 0) break;
		if (iProcessed >= g_UpdatesPerSecond.IntValue) break;

		// Only process a certain amount of updates per frame.
		ObjectiveUpdate ObjUpdate;
		g_ObjectiveUpdateQueue.GetArray(0, ObjUpdate); // Get the first element of this array.
		g_ObjectiveUpdateQueue.Erase(0); // Erase the first element.

		int client = ObjUpdate.m_iClient;
		int value = ObjUpdate.m_iValue;
		int objective_id = ObjUpdate.m_iObjectiveID;
		char event[MAX_EVENT_SIZE];
		event = ObjUpdate.m_sEvent;
		char uuid[MAX_UUID_SIZE];
		uuid = ObjUpdate.m_sUUID;
		
		// Grab the objective from our client's contract.
		Contract ClientContract;
		GetClientContract(client, ClientContract);

		// Do our UUID's match?
		if (!StrEqual(uuid, ClientContract.m_sUUID) && StrEqual(uuid, OldClientContracts[client].m_sUUID))
		{
			ProcessLogicForContractObjective(OldClientContracts[client], objective_id, client, event, value);

			// Get the new progress and completion status for the old contract.
			ContractObjective OldObjective;
			OldClientContracts[client].GetObjective(objective_id, OldObjective);
			SaveClientObjectiveProgress(client, OldClientContracts[client].m_sUUID, OldObjective);
		}
		else
		{
			// Update progress.
			ProcessLogicForContractObjective(ClientContract, objective_id, client, event, value);
		}

		iProcessed++;
	}

	return Plugin_Continue;
}

/**
 * Tries to add to the progress of an Objective by comparing the event called
 * and seeing if it's hooked by any Objective Events. This handles logic such
 * as timer events and the actual incrementing or resetting of progress is
 * handled in the ContractObjective enum struct.
 * (see ContractObjective.TryIncrementProgress)
 *
 * @param ClientContract 	Contract struct to grab the objective from.
 * @param objective_id 	ID of the objective to be processed.
 * @param client    	Client index.
 * @param event    		Event to process.
 * @param value			Value to send alongside this event.
 */
void ProcessLogicForContractObjective(Contract ClientContract, int objective_id, int client, const char[] event, int value)
{
	if (!ClientContract.IsContractInitalized()) return;
	if (ClientContract.IsContractComplete()) return;

	if (g_DebugProcessing.BoolValue)
	{
		LogMessage("[ZContracts] Processing event [%s, %d] for %N", event, value, client);
	}

	// Get our objective.
	ContractObjective Objective;
	ClientContract.GetObjective(objective_id, Objective);
	if (Objective.IsObjectiveComplete()) return;

	// For TF2, perform a class check.
	if (GetEngineVersion() == Engine_TF2)
	{
		TFClassType Class = TF2_GetPlayerClass(client);
		if (Class == TFClass_Unknown) return;
		if (!ClientContract.m_bClass[Class]) return;
	}

	char Map[256];
	GetCurrentMap(Map, sizeof(Map));
	if (!StrEqual(Map, "") && StrContains(Map, ClientContract.m_sMapRestriction) == -1) return;
	if (!PerformWeaponCheck(ClientContract, client)) return;

	// Loop over all of our objectives and see if this event matches.
	for (int i = 0; i < Objective.m_hEvents.Length; i++)
	{
		ContractObjectiveEvent ObjEvent;
		Objective.m_hEvents.GetArray(i, ObjEvent);
		
		// Does this event match?
		if (StrEqual(ObjEvent.m_sEventName, event))
		{
			// Do we have a timer going?
			if (ObjEvent.m_hTimer != INVALID_HANDLE)
			{
				TriggerTimeEvent(Objective, ObjEvent, "OnThreshold");
			}
			else 
			{
				if (ObjEvent.m_hTimer == INVALID_HANDLE && ObjEvent.m_fTime != 0.0)
				{
					// Create a datapack for our timer so we can pass our objective and event through.
					DataPack TimerData;
					
					// Create our timer. (see contracts_timers.sp)
					ObjEvent.m_hTimer = CreateDataTimer(ObjEvent.m_fTime, EventTimer, TimerData, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					TimerData.WriteCell(client); // Pass through our client so we can get our contract.
					TimerData.WriteCell(Objective.m_iInternalID); // Pass through our internal ID so we know which objective to look for.
					TimerData.WriteCell(ObjEvent.m_iInternalID); // Pass through the current event index so we know which event we're looking for in our objective.
					// ^^ The reason we do these two things as we can't pass enum structs through into a DataPack.
				}
			}

			// Add to our event threshold.
			ObjEvent.m_iCurrentThreshold += value;
			if (ObjEvent.m_iCurrentThreshold >= ObjEvent.m_iThreshold)
			{
				// What type of value are we? Are we incrementing or resetting?
				if (StrEqual(ObjEvent.m_sEventType, "increment"))
				{
					switch (ClientContract.m_iContractType)
					{
						case Contract_ObjectiveProgress: IncrementObjectiveProgress(client, value, ClientContract, Objective);
						case Contract_ContractProgress: IncrementContractProgress(client, value, ClientContract, Objective);
					}

					// Reset our threshold.
					ObjEvent.m_iCurrentThreshold = 0;
				}
				else if (StrEqual(ObjEvent.m_sEventType, "reset"))
				{
					// Reset all event thresholds.
					for (int h = 0; h < Objective.m_hEvents.Length; h++)
					{
						ContractObjectiveEvent m_hEventToReset;
						Objective.m_hEvents.GetArray(h, m_hEventToReset);
						m_hEventToReset.m_iCurrentThreshold = 0;
						Objective.m_hEvents.SetArray(h, m_hEventToReset);
					}
				}
				
				// Cancel our timer now that we've reached our threshold.
				if (ObjEvent.m_hTimer != INVALID_HANDLE)
				{
					CloseHandle(ObjEvent.m_hTimer);
					ObjEvent.m_hTimer = INVALID_HANDLE;
				}
			}
		
			Objective.m_hEvents.SetArray(i, ObjEvent);
			Objective.m_bNeedsDBSave = true;
			ClientContract.SaveObjective(objective_id, Objective);
			ClientContract.m_bNeedsDBSave = true;
			ClientContracts[client] = ClientContract;
		}
	}
	// Print that this objective is complete.
	if (Objective.IsObjectiveComplete() && !ClientContract.IsContractComplete())
	{
		if (g_DebugProgress.BoolValue)
		{
			LogMessage("[ZContracts] %N PROGRESS: Objective completed [ID: %s, OBJ: %d]",
			client, ClientContract.m_sUUID, Objective.m_iInternalID);
		}

		// Print to chat.
		CPrintToChat(client,
		"{green}[ZC]{default} Congratulations! You have completed the objective: {lightgreen}\"%s\"{default}",
		Objective.m_sDescription);
		
		Call_StartForward(g_fOnObjectiveCompleted);
		Call_PushCell(client);
		Call_PushString(ClientContract.m_sUUID);
		Call_PushArray(Objective, sizeof(ContractObjective));
		Call_Finish();

		SaveClientObjectiveProgress(client, ClientContract.m_sUUID, Objective);
	}

	// Is our contract now complete?
	if (ClientContract.IsContractComplete())
	{
		if (PlayerSoundsEnabled[client]) EmitGameSoundToClient(client, "MatchMaking.RankUp");

		if (g_DebugProgress.BoolValue)
		{
			LogMessage("[ZContracts] %N PROGRESS: Contract completed [ID: %s]",
			client, ClientContract.m_sUUID);
		}

		// Print to chat.
		CPrintToChat(client,
		"{green}[ZC]{default} Congratulations! You have completed the contract: {lightgreen}\"%s\"{default}",
		ClientContract.m_sContractName);

		Call_StartForward(g_fOnContractCompleted);
		Call_PushCell(client);
		Call_PushString(ClientContract.m_sUUID);
		Call_PushArray(ClientContract, sizeof(Contract));
		Call_Finish();

		SaveClientContractProgress(client, ClientContract);
	}
}

void IncrementContractProgress(int client, int value, Contract ClientContract, ContractObjective ClientContractObjective)
{
	if (PlayerSoundsEnabled[client]) EmitGameSoundToClient(client, "Quest.StatusTickNovice");

	// Add progress to our Contract.
	if (ClientContract.m_bNoMultiplication) ClientContract.m_iProgress += ClientContractObjective.m_iAward;
	else if (ClientContractObjective.m_bNoMultiplication) ClientContract.m_iProgress += ClientContractObjective.m_iAward;
	else ClientContract.m_iProgress += ClientContractObjective.m_iAward * value;

	// Cap our progress and amount of fires.
	ClientContract.m_iProgress = Int_Min(ClientContract.m_iProgress, ClientContract.m_iMaxProgress);
	if (!ClientContractObjective.m_bInfinite)
	{
		ClientContractObjective.m_iFires++;
		ClientContractObjective.m_iFires = Int_Min(ClientContractObjective.m_iFires, ClientContractObjective.m_iMaxFires);
	}

	// Print HINT text to chat.
	if (g_DisplayHudMessages.BoolValue)
	{							
		char MessageText[256];
		if (ClientContractObjective.m_bNoMultiplication)
		{
			MessageText = "\"%s\" (%s [%d/%dCP]) +%dCP";
			PrintHintText(client, MessageText, ClientContractObjective.m_sDescription,
			ClientContract.m_sContractName, ClientContract.m_iProgress,
			ClientContract.m_iMaxProgress, ClientContractObjective.m_iAward);
		}
		else
		{
			MessageText = "\"%s\" %dx (%s [%d/%dCP]) +%dCP";
			PrintHintText(client, MessageText, ClientContractObjective.m_sDescription,
			value, ClientContract.m_sContractName, ClientContract.m_iProgress,
			ClientContract.m_iMaxProgress, ClientContractObjective.m_iAward * value);
		}
	}
	if (g_DebugProgress.BoolValue)
	{
		LogMessage("[ZContracts] %N PROGRESS: Increment event triggered [ID: %s, CP: %d]",
		client, ClientContract.m_sUUID, ClientContract.m_iProgress);
	}

	// Save progress to DB.
	ClientContract.m_bNeedsDBSave = true;
}

void IncrementObjectiveProgress(int client, int value, Contract ClientContract, ContractObjective ClientContractObjective)
{
	if (PlayerSoundsEnabled[client]) EmitGameSoundToClient(client, "Quest.StatusTickNovice");

	// Add progress to our Objective.
	if (ClientContractObjective.m_bNoMultiplication) ClientContractObjective.m_iProgress += ClientContractObjective.m_iAward;
	else ClientContractObjective.m_iProgress += ClientContractObjective.m_iAward * value;
	
	if (!ClientContractObjective.m_bInfinite)
	{
		ClientContractObjective.m_iProgress = Int_Min(ClientContractObjective.m_iProgress, ClientContractObjective.m_iMaxProgress);
	}

	// Display HINT message to the client.
	if (g_DisplayHudMessages.BoolValue)
	{
		char MessageText[256];
		if (ClientContractObjective.m_bNoMultiplication)
		{
			MessageText = "\"%s\" (%s [%d/%d]) +%d";
			PrintHintText(client, MessageText, ClientContractObjective.m_sDescription,
			ClientContract.m_sContractName, ClientContractObjective.m_iProgress,
			ClientContractObjective.m_iMaxProgress, ClientContractObjective.m_iAward);
		}
		else
		{
			MessageText = "\"%s\" %dx (%s [%d/%d]) +%d";
			PrintHintText(client, MessageText, ClientContractObjective.m_sDescription,
			value, ClientContract.m_sContractName, ClientContractObjective.m_iProgress,
			ClientContractObjective.m_iMaxProgress, ClientContractObjective.m_iAward * value);
		}
	}
	if (g_DebugProgress.BoolValue)
	{
		LogMessage("[ZContracts] %N PROGRESS: Increment event triggered [ID: %s, OBJ: %d, CP: %d]",
		client, ClientContract.m_sUUID, ClientContractObjective.m_iInternalID, ClientContractObjective.m_iProgress);
	}

	// Save progress to DB.
	ClientContractObjective.m_bNeedsDBSave = true;
}

bool PerformWeaponCheck(Contract ClientContract, int client)
{
	// TODO: Weapon check
	if (!StrEqual("", ClientContract.m_sWeaponItemDefRestriction)
	|| !StrEqual("", ClientContract.m_sWeaponClassnameRestriction))
	{
		int ClientWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(ClientWeapon))
		{
			// Classname check:
			if (!StrEqual("", ClientContract.m_sWeaponClassnameRestriction))
			{
				char Classname[64];
				GetEntityClassname(ClientWeapon, Classname, sizeof(Classname));
				if (!StrContains(Classname, ClientContract.m_sWeaponClassnameRestriction)) return false;
			}
			// Item definition index check:
			if (!StrEqual("", ClientContract.m_sWeaponItemDefRestriction))
			{
				int DefIndex = GetEntProp(ClientWeapon, Prop_Send, "m_iItemDefinitionIndex");
				if (DefIndex != StringToInt(ClientContract.m_sWeaponItemDefRestriction)) return false;
			}
		}
	}
	return true;
}

// ============ EVENT FUNCTIONS ============
public Action OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_TF2_AllowRoundEndProgress.BoolValue)
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

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast)
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

public Action OnWaitingStart(Event event, const char[] name, bool dontBroadcast)
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

public Action OnWaitingEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_LastValidProgressTime = -1.0;
	return Plugin_Continue;
}

public Action OnSetupEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_LastValidProgressTime = -1.0;
	return Plugin_Continue;
}

// ============ DEBUG FUNCTIONS ============

/**
 * Usage: Sets the activators Contract using a provided UUID.
 * (see contract definition files)
**/
public Action DebugSetContract(int client, int args)
{	
	// Grab UUID.
	char sUUID[64];
	GetCmdArg(1, sUUID, sizeof(sUUID));
	PrintToChat(client, "Setting contract: %s", sUUID);
	
	SetClientContract(client, sUUID);
	return Plugin_Handled;
}

/**
 * Usage: Prints out the activators Contract. Providing no arguments
 * will print information about the Contract. Providing one argument
 * will print information about the Objective index.
**/
public Action DebugContractInfo(int client, int args)
{	
	Contract ClientContract;
	GetClientContract(client, ClientContract);

	if (args == 0)
	{
		PrintToConsole(client,
			"---------------------------------------------\n"
		... "Contract Initalized: %d\n"
		... "Contract Name: %s\n"
		... "Contract UUID: %s\n"
		... "Contract Directory: %s\n"
		... "Contract Progress Type: %d\n"
		... "Contract Progress: %d/%d\n"
		... "Contract Objective Count: %d\n"
		... "Is Contract Complete: %d\n"
		... "[INFO] To debug an objective, type sm_debugcontract [objective_index]"
		... "---------------------------------------------",
		ClientContract.IsContractInitalized(), ClientContract.m_sContractName, ClientContract.m_sUUID, ClientContract.m_sDirectoryPath, ClientContract.m_iContractType,
		ClientContract.m_iProgress, ClientContract.m_iMaxProgress, ClientContract.m_hObjectives.Length, ClientContract.IsContractComplete());
	}
	if (args == 1)
	{
		char sArg[4];
		GetCmdArg(1, sArg, sizeof(sArg));
		int iID = StringToInt(sArg);

		ContractObjective ClientContractObjective;
		ClientContract.GetObjective(iID, ClientContractObjective);

		PrintToConsole(client,
			"---------------------------------------------\n"
		... "Contract Name: %s\n"
		... "Contract UUID: %s\n"
		... "Contract Progress Type: %d\n"
		... "Objective Initalized: %d\n"
		... "Objective Internal ID: %d\n"
		... "Objective Is Infinite: %d\n"
		... "Objective Award: %d\n"
		... "Objective Progress: %d/%d\n"
		... "Objective Fires: %d/%d\n"
		... "Objective Event Count: %d\n"
		... "Use No Multiplication %d\n"
		... "Is Objective Complete %d\n"
		... "Needs Database Save %d\n"
		... "[INFO] To debug an objective, type sm_debugcontract [objective_index]\n"
		... "---------------------------------------------",
		ClientContract.m_sContractName, ClientContract.m_sUUID, ClientContract.m_iContractType, ClientContractObjective.m_bInitalized,
		ClientContractObjective.m_iInternalID, ClientContractObjective.m_bInfinite, ClientContractObjective.m_iAward,
		ClientContractObjective.m_iProgress, ClientContractObjective.m_iMaxProgress, ClientContractObjective.m_iFires, ClientContractObjective.m_iMaxFires,
		ClientContractObjective.m_hEvents.Length, ClientContractObjective.m_bNoMultiplication,
		ClientContractObjective.IsObjectiveComplete(), ClientContractObjective.m_bNeedsDBSave);
	}
	
	return Plugin_Handled;
}

public Action DebugSetContractProgress(int client, int args)
{
	if (args < 3)
	{
		ReplyToCommand(client, "[ZC] Usage: sm_setcontractprogress <target> <uuid> <value>");
		return Plugin_Handled;
	}

	char Targets[64];
	GetCmdArg(1, Targets, sizeof(Targets));
	char UUID[64];
	GetCmdArg(2, UUID, sizeof(UUID));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			Targets,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		SetContractProgressDatabase(target_list[i], UUID, GetCmdArgInt(3));
	}

	return Plugin_Handled;
}

public Action DebugSetObjectiveProgress(int client, int args)
{
	if (args < 4)
	{
		ReplyToCommand(client, "[ZC] Usage: sm_setobjectiveprogress <target> <uuid> <objective> <value>");
		return Plugin_Handled;
	}

	char Targets[64];
	GetCmdArg(1, Targets, sizeof(Targets));
	char UUID[64];
	GetCmdArg(2, UUID, sizeof(UUID));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			Targets,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		SetObjectiveProgressDatabase(target_list[i], UUID, GetCmdArgInt(3), GetCmdArgInt(4));
	}

	return Plugin_Handled;
}

public Action DebugSetObjectiveFires(int client, int args)
{
	if (args < 4)
	{
		ReplyToCommand(client, "[ZC] Usage: sm_setobjectivefires <target> <uuid> <objective> <value>");
		return Plugin_Handled;
	}

	char Targets[64];
	GetCmdArg(1, Targets, sizeof(Targets));
	char UUID[64];
	GetCmdArg(2, UUID, sizeof(UUID));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			Targets,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		SetObjectiveFiresDatabase(target_list[i], UUID, GetCmdArgInt(3), GetCmdArgInt(4));
	}

	return Plugin_Handled;
}

public Action DebugTriggerEvent(int client, int args)
{
	if (args < 3)
	{
		ReplyToCommand(client, "[ZC] Usage: sm_triggerevent <target> <event> <value>");
		return Plugin_Handled;
	}

	char Targets[64];
	GetCmdArg(1, Targets, sizeof(Targets));
	char EventName[MAX_EVENT_SIZE];
	GetCmdArg(2, EventName, sizeof(EventName));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			Targets,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		CallContrackerEvent(target_list[i], EventName, GetCmdArgInt(3), false);
	}

	return Plugin_Handled;
}

public Action DebugSaveContract(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[ZC] Usage: sm_savecontract <target>");
		return Plugin_Handled;
	}

	char Targets[64];
	GetCmdArg(1, Targets, sizeof(Targets));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			Targets,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		Contract ClientContract;
		GetClientContract(target_list[i], ClientContract);
		if (!ClientContract.IsContractInitalized()) continue;

		SaveClientContractProgress(target_list[i], ClientContract);
		for (int j = 0; j < ClientContract.m_hObjectives.Length; j++)
		{
			ContractObjective ClientContractObjective;
			ClientContract.GetObjective(i, ClientContractObjective);
			if (!ClientContractObjective.m_bInitalized) continue;

			SaveClientObjectiveProgress(client, ClientContract.m_sUUID, ClientContractObjective);
		}
	}

	return Plugin_Handled;
}
// ============ UTILITY FUNCTIONS ============

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
