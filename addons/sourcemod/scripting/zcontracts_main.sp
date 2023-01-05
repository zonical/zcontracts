#pragma semicolon 1
#pragma newdecls required

// There are engine checks for game extensions!
#undef REQUIRE_EXTENSIONS
#define DEBUG

#include <sourcemod>
#include <sdktools>
#include <float>

#include <zcontracts/zcontracts>

Database g_DB = null;
Handle g_DatabaseUpdateTimer;
Handle g_DatabaseRetryTimer;

// Player Contracts.
Contract OldClientContracts[MAXPLAYERS+1];
Contract ClientContracts[MAXPLAYERS+1];
ArrayList CompletedContracts[MAXPLAYERS+1];

// ConVars.
ConVar g_UpdatesPerSecond;
ConVar g_DatabaseUpdateTime;
ConVar g_DatabaseRetryTime;
ConVar g_DatabaseMaximumFailures;
ConVar g_DisplayHudMessages;
ConVar g_DisplayProgressHud;
ConVar g_PlaySounds;
ConVar g_BotContracts;

#if defined DEBUG
ConVar g_DebugEvents;
ConVar g_DebugProcessing;
ConVar g_DebugQuery;
ConVar g_DebugProgress;
ConVar g_DebugSessions;
#endif

// Forwards
GlobalForward g_fOnObjectiveCompleted;
GlobalForward g_fOnContractCompleted;
GlobalForward g_fOnContractPreSave;
GlobalForward g_fOnObjectivePreSave;

float g_LastValidProgressTime = -1.0;

// This arraylist contains a list of objectives that we need to update.
ArrayList g_ObjectiveUpdateQueue;

float g_NextHUDUpdate[MAXPLAYERS+1] = { -1.0, ... };

// Major version number, feature number, patch number
#define PLUGIN_VERSION "0.3.1"
// This value should be incremented with every breaking version made to the
// database so saves can be easily converted. For developers who fork this project and
// wish to merge changes, do not increment this number until merge.
#define CONTRACKER_VERSION 1
// How often the HUD will refresh itself.
#define HUD_REFRESH_RATE 0.5

// Subplugins.
#include "zcontracts/contracts_tf2.sp"
#include "zcontracts/contracts_csgo.sp"
// Any custom engine plugins must be included before contracts_schema so
// custom values can be loaded from the schema.
#include "zcontracts/contracts_schema.sp"
#include "zcontracts/contracts_timers.sp"
#include "zcontracts/contracts_database.sp"
#include "zcontracts/contracts_preferences.sp"
#include "zcontracts/contracts_menu.sp"
// TODO: CSGO and TF2 (+ any other game) subplugins. Seperate main logic from game logic.

public Plugin myinfo =
{
	name = "ZContracts - Custom Contract Logic",
	author = "ZoNiCaL",
	description = "Allows server operators to design their own contracts.",
	version = PLUGIN_VERSION,
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
	CreateNative("MarkContractAsCompleted", Native_MarkContractAsCompleted);
	CreateNative("SetSessionDatabase", Native_SetSessionDatabase);

	return APLRes_Success;
}

public void OnPluginStart()
{
	PrintToServer("[ZContracts] Initalizing ZContracts %s - Contracker Version: %d", PLUGIN_VERSION, CONTRACKER_VERSION);

	// ================ CONVARS ================
	g_ConfigSearchPath = CreateConVar("zc_schema_search_path", "configs/zcontracts", "The path, relative to the \"sourcemods/\" directory, to find Contract definition files. Changing this vlue will cause a reload of the Contract schema.");
	g_RequiredFileExt = CreateConVar("zc_schema_required_ext", ".txt", "The file extension that Contract definition files must have in order to be considered valid. Changing this value will cause a reload of the Contract schema.");
	g_DisabledPath = CreateConVar("zc_schema_disabled_path", "configs/zcontracts/disabled", "If a search path has this string in it, any Contract's loaded in or derived from this path will not be loaded. Changing this value will cause a reload of the Contract schema.");
	
	g_DatabaseRetryTime = CreateConVar("zc_database_retry_time", "30", "If a connection attempt to the database fails, reattempt in this amount of time.");
	g_DatabaseUpdateTime = CreateConVar("zc_database_update_time", "30", "How long to wait before sending Contract updates to the database for all players.");
	g_DatabaseMaximumFailures = CreateConVar("zc_database_max_failures", "3", "How many database reconnects to attempt. If the maximum value is reached, the plugin exits.");

	g_UpdatesPerSecond = CreateConVar("zc_updates_per_second", "8", "How many objective updates to process per second.");
	g_DisplayHudMessages = CreateConVar("zc_display_hud_messages", "1", "If enabled, players will see a hint-box in their HUD when they gain progress on their Contract or an Objective.");
	g_PlaySounds = CreateConVar("zc_play_sounds", "1", "If enabled, sounds will play when interacting with the Contracker and when progress is made when a Contract is active.");
	g_DisplayProgressHud = CreateConVar("zc_display_hud_progress", "1", "If enabled, players will see text on the right-side of their screen displaying Contract progress.");
	g_BotContracts = CreateConVar("zc_bot_contracts", "0", "If enabled, bots will be allowed to select Contracts. They will automatically select a new Contract after completion.");

#if defined DEBUG
	g_DebugEvents = CreateConVar("zc_debug_print_events", "0", "Logs every time an event is sent.");
	g_DebugProcessing = CreateConVar("zc_debug_processing", "0", "Logs every time an event is processed.");
	g_DebugQuery = CreateConVar("zc_debug_queries", "0", "Logs every time a query is sent to the database.");
	g_DebugProgress = CreateConVar("zc_debug_progress", "0", "Logs every time player progress is incremented internally.");
	g_DebugSessions = CreateConVar("zc_debug_sessions", "0", "Logs every time a session is restored.");
#endif

	g_DatabaseRetryTime.AddChangeHook(OnDatabaseRetryChange);
	g_DatabaseUpdateTime.AddChangeHook(OnDatabaseUpdateChange);
	g_ConfigSearchPath.AddChangeHook(OnSchemaConVarChange);
	g_RequiredFileExt.AddChangeHook(OnSchemaConVarChange);
	g_DisabledPath.AddChangeHook(OnSchemaConVarChange);

	// ================ ENGINE SETUP ================
	switch (GetEngineVersion())
	{
		case Engine_TF2:
		{
			TF2_CreatePluginConVars();
			TF2_CreateEventHooks();
		}
		// case Engine_CSGO: CSGO_CreatePluginConVars();
	}

	// ================ SOUNDS ================
	PrecacheSound("CYOA.StaticFade");
	PrecacheSound("CYOA.NodeActivate");
	PrecacheSound("Quest.TurnInAccepted");
	PrecacheSound("Quest.Alert");
	PrecacheSound("Quest.Decode");
	PrecacheSound("Quest.StatusTickNovice");

	// ================ CONTRACKER ================
	ProcessContractsSchema();
	CreateContractMenu();

	g_ObjectiveUpdateQueue = new ArrayList(sizeof(ObjectiveUpdate));
	g_DatabaseUpdateTimer = CreateTimer(g_DatabaseUpdateTime.FloatValue, Timer_SaveAllToDB, _, TIMER_REPEAT);
	CreateTimer(1.0, Timer_ProcessEvents, _, TIMER_REPEAT);
	CreateTimer(HUD_REFRESH_RATE, Timer_DrawContrackerHud, _, TIMER_REPEAT);

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
	RegAdminCmd("sm_triggerevent", DebugTriggerEvent, ADMFLAG_BAN);
	RegAdminCmd("sm_savecontract", DebugSaveContract, ADMFLAG_KICK);
	//RegAdminCmd("sm_resetcontract", DebugResetContract, ADMFLAG_BAN);
	RegAdminCmd("sm_debugcontract", DebugContractInfo, ADMFLAG_ROOT);
	RegAdminCmd("zc_reload", ReloadContracts, ADMFLAG_ROOT);
	RegAdminCmd("zc_connect", ReloadDatabase, ADMFLAG_ROOT);

	RegConsoleCmd("sm_contract", OpenContrackerForClientCmd);
	RegConsoleCmd("sm_contracts", OpenContrackerForClientCmd);
	RegConsoleCmd("sm_c", OpenContrackerForClientCmd);
	RegConsoleCmd("sm_zc", OpenContrackerForClientCmd);
	RegConsoleCmd("sm_cpref", OpenPrefPanelCmd);
	RegConsoleCmd("sm_zcpref", OpenPrefPanelCmd);
	RegConsoleCmd("sm_zchelp", OpenHelpPanelCmd);
	RegConsoleCmd("sm_chelp", OpenHelpPanelCmd);

	RegPluginLibrary("zcontracts");
}

// ============ SM FORWARD FUNCTIONS ============

public void OnClientPostAdminCheck(int client)
{
	// Delete the old list of completed contracts if it exists.
	delete CompletedContracts[client];
	CompletedContracts[client] = new ArrayList(MAX_UUID_SIZE);
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;

	// For some reason, having all the database loading functions in this forward
	// caused some to not be called at all. To make sure everything is prepared,
	// we'll call this a frame later.
	if (IsClientValid(client) 
	&& !IsFakeClient(client))
	{
		if (g_DB != null)
		{
			RequestFrame(DelayedLoad, client);
		}
	}
	// If we're a bot, load a random Contract.
	if (IsClientValid(client) && IsFakeClient(client) && g_BotContracts.BoolValue)
	{
		GiveRandomContract(client);
	}
}

public void DelayedLoad(int client)
{
	// Reset variables.
	Contract BlankContract;
	ClientContracts[client] = BlankContract;
	OldClientContracts[client] = BlankContract;

	DB_LoadContractFromLastSession(client);
	DB_LoadAllClientPreferences(client);
	DB_LoadCompletedContracts(client);
}

public void OnClientDisconnect(int client)
{
	if (IsClientValid(client)
	&& !IsFakeClient(client)
	&& g_DB != null)
	{
		SaveClientPreferences(client);

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

	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;
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
	if (!IsClientValid(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;

	if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

	// If we have a Contract already selected, save it's progress to the database.
	Contract OldClientContract;
	GetClientContract(client, OldClientContract);
	OldClientContract.m_bActive = false;
	OldClientContracts[client] = OldClientContract;

	if (OldClientContract.IsContractInitalized() && g_DB != null)
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

	if (!IsFakeClient(client) && g_DB != null)
	{
		// Get the client's SteamID64.
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

		// TODO: Can we make this into one query?
		// TODO: Implement version checking when required! "version" key in SQL
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
	}

	if (!dont_notify)
	{
		// Display the Contract to the client when we can.
		CreateObjectiveDisplay(client, ClientContract, true);
		CreateTimer(1.0, Timer_DisplayContractInfo, client, TIMER_REPEAT);
	}

	// Set this Contract as our current session.
	if (!dont_save && g_DB != null)
	{
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetSessionDatabase(steamid64, ClientContract.m_sUUID);
	}

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
	if (!IsClientValid(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;
	if (NewContract.m_sUUID[0] != '{')
    {
        return ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", NewContract.m_sUUID);
    }

	// If we have a Contract already selected, save it's progress to the database.
	Contract OldClientContract;
	GetClientContract(client, OldClientContract);
	OldClientContract.m_bActive = false;
	OldClientContracts[client] = OldClientContract;

	if (OldClientContract.IsContractInitalized() && g_DB != null)
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
	if (!dont_save && g_DB != null)
	{
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetSessionDatabase(steamid64, NewContract.m_sUUID);
	}

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
 * Gets the last Contract the client selected from their last game session and
 * sets it as the active Contract.
 *
 * @param client    	        Client index.
 * @error                       Client index is invalid. 
 */
void DB_LoadContractFromLastSession(int client)
{
	// Bots cannot grab sessions from the database.
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return;
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

public Action Timer_DrawContrackerHud(Handle hTimer)
{
	if (!g_DisplayProgressHud.BoolValue) return Plugin_Stop;

	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (!IsClientValid(i) || IsFakeClient(i)) continue;
		if (g_NextHUDUpdate[i] > GetGameTime()) continue;
		if (!PlayerHUDEnabled[i]) continue;

		Contract ClientContract;
		GetClientContract(i, ClientContract);
		if (!ClientContract.IsContractInitalized() || !ClientContract.m_bActive) continue;

		// Prepare our text.
		SetHudTextParams(1.0, -1.0, HUD_REFRESH_RATE + 0.1, 255, 255, 255, 255);
		char DisplayText[512] = "\"%s\":\n";
		Format(DisplayText, sizeof(DisplayText), DisplayText, ClientContract.m_sContractName);

		// Add text if we've completed the Contract.
		if (ClientContract.IsContractComplete())
		{
			char CompleteText[] = "COMPLETE - Type /c to\nselect a new Contract.";
			StrCat(DisplayText, sizeof(DisplayText), CompleteText);
		}
		else
		{
			// Display the overall Contract progress.
			if (ClientContract.m_iContractType == Contract_ContractProgress)
			{
				char ProgressText[128] = "Progress: [%d/%d]";
				Format(ProgressText, sizeof(ProgressText), ProgressText,
				ClientContract.m_iProgress, ClientContract.m_iMaxProgress);		

				// Adds +xCP value to the end of the text.
				if (ClientContract.m_bHUD_ContractUpdate)
				{
					SetHudTextParams(1.0, -1.0, 1.0, 52, 235, 70, 255, 1);
					char AddText[16] = " +%dCP";
					Format(AddText, sizeof(AddText), AddText, ClientContract.m_iHUD_UpdateValue);
					StrCat(ProgressText, sizeof(ProgressText), AddText);
					ClientContract.m_bHUD_ContractUpdate = false;
					ClientContract.m_iHUD_UpdateValue = 0;

					g_NextHUDUpdate[i] = GetGameTime() + 1.0;
				}				

				StrCat(ProgressText, sizeof(ProgressText), "\n");
				StrCat(DisplayText, sizeof(DisplayText), ProgressText);
			}

			bool DisplaySavingText = ClientContract.m_bNeedsDBSave;

			// Add our objectives to HUD display.
			int DisplayID = 1;
			for (int j = 0; j < ClientContract.m_hObjectives.Length; j++)
			{
				ContractObjective ClientContractObjective;
				ClientContract.GetObjective(j, ClientContractObjective);
				if (!ClientContractObjective.m_bInitalized) continue;
				if (ClientContractObjective.m_bInfinite) continue;
				if (ClientContractObjective.IsObjectiveComplete()) continue;

				if (ClientContractObjective.m_bNeedsDBSave) DisplaySavingText = true;

				char ObjectiveText[64] = "#%d: [%d/%d]";
				Format(ObjectiveText, sizeof(ObjectiveText), ObjectiveText,
				DisplayID, ClientContractObjective.m_iProgress, ClientContractObjective.m_iMaxProgress);

				// Adds +x value to the end of the text.
				if (ClientContract.m_iHUD_ObjectiveUpdate == ClientContractObjective.m_iInternalID)
				{
					SetHudTextParams(1.0, -1.0, 1.0, 52, 235, 70, 255, 1);
					char AddText[16] = " +%d";
					Format(AddText, sizeof(AddText), AddText, ClientContract.m_iHUD_UpdateValue);
					StrCat(ObjectiveText, sizeof(ObjectiveText), AddText);
					ClientContract.m_bHUD_ContractUpdate = false;
					ClientContract.m_iHUD_ObjectiveUpdate = -1;

					g_NextHUDUpdate[i] = GetGameTime() + 1.0;
				}

				StrCat(DisplayText, sizeof(DisplayText), ObjectiveText);
				
				char TimerText[16] = " [TIME: %ds]";
				// Display a timer if we have one active.
				// NOTE: This will only display the first timer found!
				for (int k = 0; k < ClientContractObjective.m_hEvents.Length; k++)
				{
					ContractObjectiveEvent ObjEvent;
					ClientContractObjective.m_hEvents.GetArray(k, ObjEvent);

					// Do we have a timer going?
					if (ObjEvent.m_hTimer != INVALID_HANDLE)
					{
						int TimeDiff = RoundFloat((GetGameTime() - ObjEvent.m_fStarted));
						Format(TimerText, sizeof(TimerText), TimerText, TimeDiff);
						StrCat(DisplayText, sizeof(DisplayText), TimerText);
					}
				}

				StrCat(DisplayText, sizeof(DisplayText), "\n");
				DisplayID++;
			}

			// Add some text saying that we're saving the Contract to the database.
			if (DisplaySavingText)
			{
				char SavingText[] = "Saving...";
				StrCat(DisplayText, sizeof(DisplayText), SavingText);
			}
		}
		
		// Display text to client.
		ShowHudText(i, -1, DisplayText);

		// Just in case we modified the Contract earlier, resave it.
		ClientContracts[i] = ClientContract;
	}

	return Plugin_Continue;
}

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

		// Is our client still connected?
		if (!IsClientValid(client))
		{
			// Remove any other update from the queue.
			for (int i = 0; i < g_ObjectiveUpdateQueue.Length; i++)
			{
				ObjectiveUpdate OutdatedUpdate;
				g_ObjectiveUpdateQueue.GetArray(i, OutdatedUpdate);
				if (ObjUpdate.m_iClient == client)
				{
					// Remove.
					g_ObjectiveUpdateQueue.Erase(i);
					i--;
				}
			}
			continue;
		}
		
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

	// Restriction checks.
	char Map[256];
	GetCurrentMap(Map, sizeof(Map));
	if (!StrEqual(Map, "") && StrContains(Map, ClientContract.m_sMapRestriction) == -1) return;
	if (!PerformWeaponCheck(ClientContract, client)) return;
	switch (GetEngineVersion())
	{
		case Engine_TF2:
		{
			if (!TF2_IsCorrectClass(client, ClientContract)) return;
			if (!TF2_ValidGameRulesEntityExists(ClientContract.m_sRequiredGameRulesEntity)) return;
		}
		case Engine_CSGO:
		{
			if (!CSGO_IsCorrectGameType(ClientContract.m_iGameTypeRestriction)) return;
			if (!CSGO_IsCorrectGameMode(ClientContract.m_iGameModeRestriction)) return;
			if (!CSGO_IsCorrectSkirmishID(ClientContract.m_iSkirmishIDRestriction)) return;
		}
	}

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

					ObjEvent.m_fStarted = GetGameTime();
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

						// If we have any timers active, cancel them.
						if (m_hEventToReset.m_hTimer != INVALID_HANDLE)
						{
							KillTimer(m_hEventToReset.m_hTimer, true);
							m_hEventToReset.m_hTimer = INVALID_HANDLE;
						}
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
			ClientContract.SaveObjective(objective_id, Objective);
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
		//CPrintToChat(client,
		//"{green}[ZC]{default} Congratulations! You have completed the objective: {lightgreen}\"%s\"{default}",
		//Objective.m_sDescription);
		
		Call_StartForward(g_fOnObjectiveCompleted);
		Call_PushCell(client);
		Call_PushString(ClientContract.m_sUUID);
		Call_PushArray(Objective, sizeof(ContractObjective));
		Call_Finish();

		if (g_DB != null)
		{
			SaveClientObjectiveProgress(client, ClientContract.m_sUUID, Objective);
		}
	}

	// Is our contract now complete?
	if (ClientContract.IsContractComplete())
	{
		if (PlayerSoundsEnabled[client]) EmitGameSoundToClient(client, "Quest.TurnInAccepted");

		if (g_DebugProgress.BoolValue)
		{
			LogMessage("[ZContracts] %N PROGRESS: Contract completed [ID: %s]",
			client, ClientContract.m_sUUID);
		}

		// Print to chat.
		//CPrintToChat(client,
		//"{green}[ZC]{default} Congratulations! You have completed the contract: {lightgreen}\"%s\"{default}",
		//ClientContract.m_sContractName);

		Call_StartForward(g_fOnContractCompleted);
		Call_PushCell(client);
		Call_PushString(ClientContract.m_sUUID);
		Call_PushArray(ClientContract, sizeof(Contract));
		Call_Finish();

		if (g_DB != null)
		{
			SaveClientContractProgress(client, ClientContract);
		}

		CompletedContracts[client].PushString(ClientContract.m_sUUID);

		// If we're a bot, grant a new Contract straight away.
		if (IsFakeClient(client) && g_BotContracts.BoolValue)
		{
			GiveRandomContract(client);
		}
	}
}

void IncrementContractProgress(int client, int value, Contract ClientContract, ContractObjective ClientContractObjective)
{
	if (PlayerSoundsEnabled[client]) EmitGameSoundToClient(client, "Quest.StatusTickNovice");

	int AddValue = 0;

	// Add progress to our Contract.
	if (ClientContract.m_bNoMultiplication) AddValue = ClientContractObjective.m_iAward;
	else if (ClientContractObjective.m_bNoMultiplication) AddValue = ClientContractObjective.m_iAward;
	else AddValue = ClientContractObjective.m_iAward * value;

	// Update HUD.
	ClientContract.m_iProgress += AddValue;
	ClientContract.m_iHUD_UpdateValue = AddValue;
	ClientContract.m_bHUD_ContractUpdate = true;

	// Cap progress.
	ClientContract.m_iProgress = Int_Min(ClientContract.m_iProgress, ClientContract.m_iMaxProgress);

	if (!ClientContractObjective.m_bInfinite)
	{
		ClientContractObjective.m_iProgress++;
		ClientContractObjective.m_iProgress = Int_Min(ClientContractObjective.m_iProgress, ClientContractObjective.m_iMaxProgress);
	}

	// Print HINT text to chat.
	if (g_DisplayHudMessages.BoolValue && PlayerHintEnabled[client])
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

	int AddValue = 0;

	// Add progress to our Objective.
	if (ClientContractObjective.m_bNoMultiplication) AddValue = ClientContractObjective.m_iAward;
	else AddValue = ClientContractObjective.m_iAward * value;
	
	ClientContractObjective.m_iProgress += AddValue;
	ClientContract.m_iHUD_UpdateValue = AddValue;
	ClientContract.m_iHUD_ObjectiveUpdate = ClientContractObjective.m_iInternalID;

	if (!ClientContractObjective.m_bInfinite)
	{
		ClientContractObjective.m_iProgress = Int_Min(ClientContractObjective.m_iProgress, ClientContractObjective.m_iMaxProgress);
	}

	// Display HINT message to the client.
	if (g_DisplayHudMessages.BoolValue && PlayerHintEnabled[client])
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
			// Item definition index check:
			if (!StrEqual("", ClientContract.m_sWeaponItemDefRestriction))
			{
				int DefIndex = GetEntProp(ClientWeapon, Prop_Send, "m_iItemDefinitionIndex");
				if (DefIndex != StringToInt(ClientContract.m_sWeaponItemDefRestriction)) return false;
			}
			// Classname check:
			if (!StrEqual("", ClientContract.m_sWeaponClassnameRestriction))
			{
				char Classname[64];
				GetEntityClassname(ClientWeapon, Classname, sizeof(Classname));
				if (!StrContains(Classname, ClientContract.m_sWeaponClassnameRestriction)) return false;
			}
		}
	}
	return true;
}

// ============ DEBUG FUNCTIONS ============

/**
 * Usage: Sets the activators Contract using a provided UUID.
 * (see contract definition files)
**/
public Action DebugSetContract(int client, int args)
{	
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
		SetClientContract(client, UUID, false, false);
	}
	
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
		... "Objective Event Count: %d\n"
		... "Use No Multiplication %d\n"
		... "Is Objective Complete %d\n"
		... "Needs Database Save %d\n"
		... "[INFO] To debug an objective, type sm_debugcontract [objective_index]\n"
		... "---------------------------------------------",
		ClientContract.m_sContractName, ClientContract.m_sUUID, ClientContract.m_iContractType, ClientContractObjective.m_bInitalized,
		ClientContractObjective.m_iInternalID, ClientContractObjective.m_bInfinite, ClientContractObjective.m_iAward,
		ClientContractObjective.m_iProgress, ClientContractObjective.m_iMaxProgress,
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
		char steamid64[64];
		GetClientAuthId(target_list[i], AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetContractProgressDatabase(steamid64, UUID, GetCmdArgInt(3));
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
		char steamid64[64];
		GetClientAuthId(target_list[i], AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetObjectiveProgressDatabase(steamid64, UUID, GetCmdArgInt(3), GetCmdArgInt(4));
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

bool HasClientCompletedContract(int client, char UUID[MAX_UUID_SIZE])
{
	// Could this be made any faster? I'm not a real programmer.
	// The answer is, yes it can.
	if (!IsClientValid(client)) return false;
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;
	return (CompletedContracts[client].FindString(UUID) != -1);
}

bool CanActivateContract(int client, char UUID[MAX_UUID_SIZE])
{
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;
	if (!IsClientValid(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

	// Grab the Contract from the schema.
	if (g_ContractSchema.JumpToKey(UUID))
	{
		// Construct the required contracts.
		if (g_ContractSchema.JumpToKey("required_contracts", false))
		{
			int Value = 0;
			for (;;)
			{
				char ContractUUID[MAX_UUID_SIZE];
				char ValueStr[4];
				IntToString(Value, ValueStr, sizeof(ValueStr));

				g_ContractSchema.GetString(ValueStr, ContractUUID, sizeof(ContractUUID), "{}");
				// If we reach a blank UUID, we're at the end of the list.
				if (StrEqual("{}", ContractUUID)) break;
				if (CompletedContracts[client].FindString(ContractUUID) != -1)
				{
					g_ContractSchema.Rewind();
					return true;
				}
				Value++;
			}
			g_ContractSchema.GoBack();
		}
		else
		{
			g_ContractSchema.Rewind();
			return true;	
		}
	}
	g_ContractSchema.Rewind();
	return false;
}

// TODO: Can this be made faster?
void GiveRandomContract(int client)
{
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return;
	if (!IsClientValid(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}
	int RandomContractID = GetRandomInt(0, g_ContractsLoaded-1);
	char RandomUUID[MAX_UUID_SIZE];
	int i = 0;

	g_ContractSchema.GotoFirstSubKey();
	do
	{
		if (i == RandomContractID)
		{
			g_ContractSchema.GetSectionName(RandomUUID, sizeof(RandomUUID));
			break;
		}
		i++;
	}
	while(g_ContractSchema.GotoNextKey());
	g_ContractSchema.Rewind();

	// See if we can activate.
	if (!CanActivateContract(client, RandomUUID) || HasClientCompletedContract(client, RandomUUID))
	{
		// Try again.
		GiveRandomContract(client);
		return;
	}

	// Grant Contract.
	if (IsFakeClient(client) && !g_BotContracts.BoolValue)
	{
		SetClientContract(client, RandomUUID, false, false);
	}
	else
	{
		SetClientContract(client, RandomUUID, true, true);
	}
	
}