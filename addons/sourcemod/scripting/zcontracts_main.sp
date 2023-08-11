#pragma semicolon 1
#pragma newdecls required

#undef REQUIRE_EXTENSIONS
#undef VERBOSE_DEBUG
#define PREVENT_100_PLAYERS

#include <sourcemod>
#include <sdktools>
#include <float>

#include <zcontracts/zcontracts>
#include <stocksoup/color_literals>

Database g_DB = null;
Handle g_DatabaseRetryTimer;

Handle g_HudSync;

// Player Contracts.
Contract OldContract[MAXPLAYERS+1];
Contract ActiveContract[MAXPLAYERS+1];
StringMap CompletedContracts[MAXPLAYERS+1];
bool PlayerHasSpawned[MAXPLAYERS+1] = { false, ... };

// ConVars.
ConVar g_UpdatesPerSecond;
ConVar g_DatabaseRetryTime;
ConVar g_DatabaseMaximumFailures;
ConVar g_DisplayHudMessages;
ConVar g_DisplayProgressHud;
ConVar g_PlaySounds;
ConVar g_BotContracts;
ConVar g_RepeatContracts;
ConVar g_AutoResetContracts;
ConVar g_DisplayCompletionsInMenu;
ConVar g_DisplayRepeatsInHUD;
ConVar g_ResetThresholdsPerRound;
ConVar g_ResetTimersPerRound;

ConVar g_DebugEvents;
ConVar g_DebugProcessing;
ConVar g_DebugQuery;
ConVar g_DebugProgress;
ConVar g_DebugSessions;
ConVar g_DebugUnlockContracts;
ConVar g_DebugTimers;

// Forwards
GlobalForward g_fOnObjectiveCompleted;
GlobalForward g_fOnContractCompleted;
GlobalForward g_fOnContractPreSave;
GlobalForward g_fOnObjectivePreSave;
GlobalForward g_fOnProcessContractLogic;
GlobalForward g_fOnClientActivatedContract;
GlobalForward g_fOnClientActivatedContractPost;
GlobalForward g_fOnContractProgressReceived;
GlobalForward g_fOnObjectiveProgressReceived;
GlobalForward g_fOnContractCompletableCheck;

// This arraylist contains a list of objectives that we need to update.
ArrayList g_ObjectiveUpdateQueue;

float g_NextHUDUpdate[MAXPLAYERS+1] = { -1.0, ... };

char IncrementProgressSound[64];
char ContractCompletedSound[64];
char ProgressLoadedSound[64];
char SelectOptionSound[64];

#include "zcontracts/contracts_schema.sp"
#include "zcontracts/contracts_utils.sp"
#include "zcontracts/contracts_timers.sp"
#include "zcontracts/contracts_database.sp"
#include "zcontracts/contracts_preferences.sp"
#include "zcontracts/contracts_menu.sp"

public Plugin myinfo =
{
	name = "ZContracts - Custom Contract Logic",
	author = "ZoNiCaL",
	description = "Allows server operators to design their own contracts.",
	version = ZCONTRACTS_PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("zcontracts");
	
	// ================ FORWARDS ================
	g_fOnObjectiveCompleted = new GlobalForward("OnContractObjectiveCompleted", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	g_fOnContractCompleted = new GlobalForward("OnContractCompleted", ET_Ignore, Param_Cell, Param_String);
	g_fOnContractPreSave = new GlobalForward("OnContractPreSave", ET_Event, Param_Cell, Param_String);
	g_fOnObjectivePreSave = new GlobalForward("OnObjectivePreSave", ET_Event, Param_Cell, Param_String, Param_Cell);
	g_fOnProcessContractLogic = new GlobalForward("OnProcessContractLogic", ET_Event, Param_Cell, Param_String, Param_Cell, Param_String, Param_Cell);
	g_fOnClientActivatedContract = new GlobalForward("OnClientActivatedContract", ET_Ignore, Param_Cell, Param_String);
	g_fOnClientActivatedContractPost = new GlobalForward("OnClientActivatedContractPost", ET_Ignore, Param_Cell, Param_String);
	g_fOnContractProgressReceived = new GlobalForward("OnContractProgressReceived", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	g_fOnObjectiveProgressReceived = new GlobalForward("OnObjectiveProgressReceived", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Cell);
	g_fOnContractCompletableCheck = new GlobalForward("OnContractCompletableCheck", ET_Event, Param_Cell, Param_String);

	// ================ NATIVES ================
	CreateNative("GetContrackerVersion", Native_GetContrackerVersion);

	CreateNative("SetClientContract", Native_SetClientContract);
	CreateNative("SetClientContractEx", Native_SetClientContractEx);
	CreateNative("GetClientContract", Native_GetClientContract);
	CreateNative("GetClientContractStruct", Native_GetClientContractStruct);
	CreateNative("CallContrackerEvent", Native_CallContrackerEvent);

	CreateNative("GetContractSchema", Native_GetContractSchema);
	CreateNative("GetObjectiveSchema", Native_GetObjectiveSchema);
	CreateNative("GetContractObjectiveCount", Native_GetContractObjectiveCount);

	CreateNative("GetActiveContractProgress", Native_GetActiveContractProgress);
	CreateNative("GetActiveObjectiveProgress", Native_GetActiveObjectiveProgress);
	CreateNative("SetActiveContractProgress", Native_SetActiveContractProgress);
	CreateNative("SetActiveObjectiveProgress", Native_SetActiveObjectiveProgress);

	CreateNative("GetClientCompletedContracts", Native_GetClientCompletedContracts);
	CreateNative("CanClientActivateContract", Native_CanClientActivateContract);
	CreateNative("CanClientCompleteContract", Native_CanClientCompleteContract);
	CreateNative("IsActiveContractComplete", Native_IsActiveContractComplete);
	CreateNative("HasClientCompletedContract", Native_HasClientCompletedContract);

	CreateNative("SaveActiveContractToDatabase", Native_SaveActiveContractToDatabase);
	CreateNative("SaveActiveObjectiveToDatabase", Native_SaveActiveObjectiveToDatabase);
	CreateNative("SetContractProgressDatabase", Native_SetContractProgressDatabase);
	CreateNative("SetObjectiveProgressDatabase", Native_SetObjectiveProgressDatabase);
	CreateNative("DeleteContractProgressDatabase", Native_DeleteContractProgressDatabase);
	CreateNative("DeleteObjectiveProgressDatabase", Native_DeleteObjectiveProgressDatabase);
	CreateNative("DeleteAllObjectiveProgressDatabase", Native_DeleteAllObjectiveProgressDatabase);
	CreateNative("SetCompletedContractInfoDatabase", Native_SetContractCompletionInfoDatabase);
	CreateNative("SetSessionDatabase", Native_SetSessionDatabase);

	return APLRes_Success;
}

public void OnPluginStart()
{
#if defined PREVENT_100_PLAYERS
	// TF2 recently added the ability for servers to have up to 100 max players with this
	// command line parameter. For now (29/07), I'm not going to support the feature and
	// I'm leaving the max players at 64. You would have to be crazy to undefine this. I
	// will also not support bugs related to having 100 players trying to all complete
	// contracts at the same time.
	char CommandLine[512];
	GetCommandLine(CommandLine, sizeof(CommandLine));
	if (StrContains(CommandLine, "-unrestricted_maxplayers") != -1)
	{
		SetFailState("ZContracts is not ready for 100 players yet. Calm down.");
	}
#endif

	PrintToServer("[ZContracts] Initalizing ZContracts %s - Contracker Version: %d", ZCONTRACTS_PLUGIN_VERSION, CONTRACKER_VERSION);

	// Create our Hud Sync object.
	g_HudSync = CreateHudSynchronizer();

	// ================ CONVARS ================
	g_ConfigSearchPath = CreateConVar("zc_schema_search_path", "configs/zcontracts", "The path, relative to the \"sourcemods/\" directory, to find Contract definition files. Changing this value will cause a reload of the Contract schema.");
	g_RequiredFileExt = CreateConVar("zc_schema_required_ext", ".txt", "The file extension that Contract definition files must have in order to be considered valid. Changing this value will cause a reload of the Contract schema.");
	g_DisabledPath = CreateConVar("zc_schema_disabled_path", "configs/zcontracts/disabled", "If a search path has this string in it, any Contract's loaded in or derived from this path will not be loaded. Changing this value will cause a reload of the Contract schema.");
	g_DatabaseRetryTime = CreateConVar("zc_database_retry_time", "30", "If a connection attempt to the database fails, reattempt in this amount of time.");
	g_DatabaseMaximumFailures = CreateConVar("zc_database_max_failures", "3", "How many database reconnects to attempt. If the maximum value is reached, the plugin exits.");
	g_UpdatesPerSecond = CreateConVar("zc_updates_per_second", "8", "How many objective updates to process per second.");
	g_DisplayHudMessages = CreateConVar("zc_display_hud_messages", "1", "If enabled, players will see a hint-box in their HUD when they gain progress on their Contract or an Objective.");
	g_PlaySounds = CreateConVar("zc_play_sounds", "1", "If enabled, sounds will play when interacting with the Contracker and when progress is made when a Contract is active.");
	g_DisplayProgressHud = CreateConVar("zc_display_hud_progress", "1", "If enabled, players will see text on the right side of their screen displaying Contract progress.");
	g_BotContracts = CreateConVar("zc_bot_contracts", "0", "If enabled, bots will be allowed to select Contracts. They will automatically select a new Contract after completion.");
	g_RepeatContracts = CreateConVar("zc_repeatable_contracts", "0", "If enabled, a player can choose to select a completed Contract and reset its progress to complete it again.");
	g_AutoResetContracts = CreateConVar("zc_repeatable_autoreset", "0", "If enabled, when a Contract is completed, its progress will automatically be reset so the player can complete it again.");
	g_DisplayCompletionsInMenu = CreateConVar("zc_repeatable_displaycount", "1", "If enabled with zc_repeatable_contracts, a value displaying how many times a contract was completed will be shown in the Contracker.");
	g_DisplayRepeatsInHUD = CreateConVar("zc_display_repeats_hud", "0", "If enabled, the progress HUD on the right side of the screen will display the amount of times that Contract has been completed.");
	g_ResetThresholdsPerRound = CreateConVar("zc_reset_thresholds_per_round", "1", "If enabled, the threshold for client objective will be reset.");
	g_ResetTimersPerRound = CreateConVar("zc_reset_timers_per_round", "1", "If enabled, all timers for client objectives will be reset.");

	g_DebugEvents = CreateConVar("zc_debug_print_events", "0", "Logs every time an event is sent.");
	g_DebugProcessing = CreateConVar("zc_debug_processing", "0", "Logs every time an event is processed.");
	g_DebugQuery = CreateConVar("zc_debug_queries", "0", "Logs every time a query is sent to the database.");
	g_DebugProgress = CreateConVar("zc_debug_progress", "0", "Logs every time player progress is incremented internally.");
	g_DebugSessions = CreateConVar("zc_debug_sessions", "0", "Logs every time a session is restored.");
	g_DebugUnlockContracts = CreateConVar("zc_debug_unlock_contracts", "0", "Allows any contract to be selected.");
	g_DebugTimers = CreateConVar("zc_debug_timers", "0", "Logs timer events.");

	g_DatabaseRetryTime.AddChangeHook(OnDatabaseRetryChange);
	g_DisplayProgressHud.AddChangeHook(OnDisplayHudChange);
	g_ConfigSearchPath.AddChangeHook(OnSchemaConVarChange);
	g_RequiredFileExt.AddChangeHook(OnSchemaConVarChange);
	g_DisabledPath.AddChangeHook(OnSchemaConVarChange);

	HookEvent("teamplay_round_start", OnRoundStart);
	HookEvent("player_spawn", OnPlayerSpawn);

	// ================ ENGINE SETUP ================
	switch (GetEngineVersion())
	{
		case Engine_TF2:
		{
			IncrementProgressSound = "Quest.StatusTickNovice";
			ContractCompletedSound = "Quest.TurnInAccepted";
			ProgressLoadedSound = "CYOA.NodeActivate";
			SelectOptionSound = "CYOA.StaticFade";
		}
	}

	PrecacheSound(IncrementProgressSound);
	PrecacheSound(ContractCompletedSound);
	PrecacheSound(ProgressLoadedSound);
	PrecacheSound(SelectOptionSound);
	
	// ================ CONTRACKER ================
	ProcessContractsSchema();
	CreateContractMenu();

	g_ObjectiveUpdateQueue = new ArrayList(sizeof(ObjectiveUpdate));
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
	//RegAdminCmd("sm_debugcontract", DebugContractInfo, ADMFLAG_ROOT);
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
}

public void OnMapEnd()
{
	// Save everything just to be safe.
	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (!IsClientValid(i) || IsFakeClient(i)) continue;
		SaveClientPreferences(i);

		SaveActiveContractToDatabase(i);
		for (int j = 0; j < ActiveContract[i].ObjectiveCount; j++)
		{
			SaveActiveObjectiveToDatabase(i, j);
		}
	}
}

// ============ SM FORWARD FUNCTIONS ============

public void OnClientPostAdminCheck(int client)
{
	// Delete the old list of completed contracts if it exists.
	delete CompletedContracts[client];
	CompletedContracts[client] = new StringMap();
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

	g_NextHUDUpdate[client] = -1.0;
}

public void DelayedLoad(int client)
{
#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD DelayedLoad(%N)] Loading ZContracts information...", client);
#endif

	// Reset variables.
	Contract BlankContract;
	ActiveContract[client] = BlankContract;
	OldContract[client] = BlankContract;
	PlayerHasSpawned[client] = false;

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
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD OnClientDisconnect(%N)] Saving ZContracts information...", client);
#endif
		SaveClientPreferences(client);
		SaveActiveContractToDatabase(client);
		for (int i = 0; i < ActiveContract[client].ObjectiveCount; i++)
		{
			SaveActiveObjectiveToDatabase(client, i);
		}
	}

	Contract Blank;
	ActiveContract[client] = Blank;
	OldContract[client] = Blank;
	PlayerHasSpawned[client] = false;

	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;
	g_NextHUDUpdate[client] = -1.0;
}

public void OnDisplayHudChange(ConVar convar, char[] oldValue, char[] newValue)
{
	// If the value is ever set to zero, the timer automatically kills itself
	// (see Timer_DrawContrackerHud)
	if (StringToInt(newValue) >= 1)
	{
		CreateTimer(HUD_REFRESH_RATE, Timer_DrawContrackerHud, _, TIMER_REPEAT);
	}
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
 * The Contracker version is used to determine the minimum Contract that should be
 * loaded from the database. This is intended to be used when a change is made to the
 * database structure or there is a breaking change in ZContracts.
 * @return The value of CONTRACKER_VERSION from zcontracts_main.sp
 */
public any Native_GetContrackerVersion(Handle plugin, int numParams)
{
	return CONTRACKER_VERSION;
}

/**
 * Obtain a client's active Contract UUID.
 * 
 * @param client	Client index.
 * @param uuidbuffer	Buffer to store the UUID.
 * @param uuidsize	Size of UUID buffer.
 * @return	A valid UUID will be stored in the buffer and structured with two brackets (e.g {ea20dcca-81c3-41f2-8f3d-a757b2b85765}).
 * 			An empty string will be stored in the buffer and false will be returned if the client has no active contract.
 * @error	Client index is invalid.
 */
public any Native_GetClientContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client)) 
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	if (ActiveContract[client].IsContractInitalized())
	{
		SetNativeString(2, ActiveContract[client].UUID, GetNativeCell(3));
		return true;
	}
	else
	{
		SetNativeString(2, "", GetNativeCell(3));
		return false;
	}
}

/**
 * Obtains a client's active Contract enum struct.
 *
 * @param client    Client index.
 * @param buffer    Buffer to store the client's contract.
 * @error           Client index is invalid.
 * @note			Please make sure your plugins are updated before using this function to prevent crashes.
 */
public any Native_GetClientContractStruct(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client)) 
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	SetNativeArray(2, ActiveContract[client], sizeof(Contract));
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
	
#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CallContrackerEvent(%N, %s, %d, %d)] Native called", client, event, value, can_combine);
#endif

	// Do we have a contract currently active?
	if (!ActiveContract[client].IsContractInitalized() || ActiveContract[client].IsContractComplete()) return false;

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CallContrackerEvent(%N, %s, %d, %d)] Contract is valid", client, event, value, can_combine);
#endif

	if (g_DebugEvents.BoolValue)
	{
		LogMessage("[ZContracts] Event triggered by %N: %s, VALUE: %d", client, event, value);
	}

	// Try to add our objectives to the increment queue.
	for (int i = 0; i < ActiveContract[client].ObjectiveCount; i++)
	{	
		if (ActiveContract[client].IsObjectiveComplete(i)) continue;
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_CallContrackerEvent(%N, %s, %d, %d)] Objective %d not complete",
		client, event, value, can_combine, i);
#endif

		// Check to see if we have this event in the queue already. 
		// If "can_combine" is set to true when this native is called,
		// we add the value from this incoming event to the pre-existing event in the queue.
		if (can_combine && g_ObjectiveUpdateQueue.Length > 0)
		{
#if defined VERBOSE_DEBUG
			PrintToServer("[ZCD Native_CallContrackerEvent(%N, %s, %d, %d)] can_combine check", client, event, value, can_combine);
#endif
			bool ObjectiveUpdated = false;
			ObjectiveUpdate ObjUpdate;
			for (int k = 0; k < g_ObjectiveUpdateQueue.Length; k++)
			{
				g_ObjectiveUpdateQueue.GetArray(k, ObjUpdate);
				if (ObjUpdate.m_iClient != client) continue;
				if (ObjUpdate.m_iObjectiveID != i) continue;
				if (!StrEqual(ObjUpdate.m_sUUID, ActiveContract[client].UUID)) continue;
				if (!StrEqual(ObjUpdate.m_sEvent, event)) continue;

				ObjUpdate.m_iValue += value;
				g_ObjectiveUpdateQueue.SetArray(k, ObjUpdate);
				ObjectiveUpdated = true;
#if defined VERBOSE_DEBUG
				PrintToServer("[ZCD Native_CallContrackerEvent(%N, %s, %d, %d)] %d ObjectiveUpdated = true",
				client, event, value, can_combine, ObjUpdate.m_iObjectiveID);
#endif
				break;
			}

			// Move to the next objective to be added to the queue.
			if (ObjectiveUpdated) continue;
		}
		
		// We reach this point if we can't combine anything.
		ObjectiveUpdate ObjUpdate;
		ObjUpdate.m_iClient = client;
		ObjUpdate.m_iValue = value;
		ObjUpdate.m_iObjectiveID = i;
		ObjUpdate.m_sUUID = ActiveContract[client].UUID;
		ObjUpdate.m_sEvent = event;
		g_ObjectiveUpdateQueue.PushArray(ObjUpdate, sizeof(ObjectiveUpdate));

#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_CallContrackerEvent(%N, %s, %d, %d)] Pushed event to process queue, obj: %d",
		client, event, value, can_combine, i);
#endif

		if (g_DebugEvents.BoolValue)
		{
			LogMessage("[ZContracts] Event added to process queue by %N: %s, VALUE: %d", client, event, value);
		}
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
	ActiveContract[client].Active = false;
	OldContract[client] = ActiveContract[client];

	if (OldContract[client].IsContractInitalized() && 
	!OldContract[client].IsContractComplete() &&
	!StrEqual(OldContract[client].UUID, UUID) && 
	g_DB != null)
	{
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_SetClientContract(%N, %s)] Saving old Contract to DB", client, UUID);
#endif
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetContractProgressDatabase(steamid64, OldContract[client].UUID, OldContract[client].ContractProgress);
		for (int i = 0; i < OldContract[client].ObjectiveCount; i++)
		{
			KeyValues ObjSchema = OldContract[client].GetObjectiveSchema(i);
			if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_INFINITE) == 1) continue;
			SetObjectiveProgressDatabase(steamid64, OldContract[client].UUID, i, OldContract[client].ObjectiveProgress.Get(i));
		}
	}

	// Get our Contract definition.
	Contract NewContract;
	NewContract.Initalize(UUID);
	ActiveContract[client] = NewContract;

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_SetClientContract(%N, %s)] Init Contract struct", client, UUID);
#endif

	if (!IsFakeClient(client))
	{
		// Get the client's SteamID64.
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_SetClientContract(%N, %s)] Grabbing existing progress", client, UUID);
#endif

		// TODO: Can we make this into one query?
		// TODO: Implement version checking when required! "version" key in SQL
		char contract_query[1024];
		if (view_as<ContractType>(ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_TYPE)) == Contract_ContractProgress)
		{
			g_DB.Format(contract_query, sizeof(contract_query),
			"SELECT * FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'", steamid64, UUID);
			g_DB.Query(CB_SetClientContract_Contract, contract_query, client);
		}
		char objective_query[1024];
		g_DB.Format(objective_query, sizeof(objective_query), 
		"SELECT * FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND (objective_id BETWEEN 0 AND %d) ORDER BY objective_id ASC;", 
		steamid64, UUID, ActiveContract[client].ObjectiveCount);
		g_DB.Query(CB_SetClientContract_Objective, objective_query, client);
	}

	// Display the Contract to the client when we can.
	CreateObjectiveDisplay(client, true);
	CreateTimer(1.0, Timer_DisplayContractInfo, client, TIMER_REPEAT);

	// Set this Contract as our current session.
	char steamid64[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	SetSessionDatabase(steamid64, ActiveContract[client].UUID);

	Call_StartForward(g_fOnClientActivatedContract);
	Call_PushCell(client);
	Call_PushString(ActiveContract[client].UUID);
	Call_Finish();

	LogMessage("[ZContracts] %N CONTRACT: Set Contract to: %s", client, ActiveContract[client].UUID);

	// Reset our current directory in the Contracker.
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;

	return true;
}

/**
 * Set a client's contract (with extended functionality)
 *
 * @param client    Client index.
 * @param UUID    	The UUID of the contract.
 * @param dont_save	Optional argument: doesn't save this as the active Contract in the database.
 * @param dont_notify Optional argument: don't notify the player that we've set their contract.
 * @error           Client index is invalid or UUID is invalid.         
 */
public any Native_SetClientContractEx(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char UUID[MAX_UUID_SIZE];
	GetNativeString(2, UUID, sizeof(UUID));

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
	ActiveContract[client].Active = false;
	OldContract[client] = ActiveContract[client];

	if (OldContract[client].IsContractInitalized() && 
	!OldContract[client].IsContractComplete() &&
	!StrEqual(OldContract[client].UUID, UUID) && 
	g_DB != null)
	{
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_SetClientContract(%N, %s)] Saving old Contract to DB", client, UUID);
#endif
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetContractProgressDatabase(steamid64, OldContract[client].UUID, OldContract[client].ContractProgress);
		for (int i = 0; i < OldContract[client].ObjectiveCount; i++)
		{
			KeyValues ObjSchema = OldContract[client].GetObjectiveSchema(i);
			if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_INFINITE) == 1) continue;
			SetObjectiveProgressDatabase(steamid64, OldContract[client].UUID, i, OldContract[client].ObjectiveProgress.Get(i));
		}
	}

	// Get our Contract definition.
	Contract NewContract;
	NewContract.Initalize(UUID);
	ActiveContract[client] = NewContract;

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_SetClientContract(%N, %s)] Init Contract struct", client, UUID);
#endif

	if (!IsFakeClient(client))
	{
		// Get the client's SteamID64.
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_SetClientContract(%N, %s)] Grabbing existing progress", client, UUID);
#endif

		// TODO: Can we make this into one query?
		// TODO: Implement version checking when required! "version" key in SQL
		char contract_query[1024];
		if (view_as<ContractType>(ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_TYPE)) == Contract_ContractProgress)
		{
			g_DB.Format(contract_query, sizeof(contract_query),
			"SELECT * FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'", steamid64, UUID);
			g_DB.Query(CB_SetClientContract_Contract, contract_query, client);
		}
		char objective_query[1024];
		g_DB.Format(objective_query, sizeof(objective_query), 
		"SELECT * FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND (objective_id BETWEEN 0 AND %d) ORDER BY objective_id ASC;", 
		steamid64, UUID, ActiveContract[client].ObjectiveCount);
		g_DB.Query(CB_SetClientContract_Objective, objective_query, client);
	}

	// Display the Contract to the client when we can.
	bool dont_notify = GetNativeCell(4);
	if (!dont_notify)
	{
		CreateObjectiveDisplay(client, true);
		CreateTimer(1.0, Timer_DisplayContractInfo, client, TIMER_REPEAT);
	}
	// Set this Contract as our current session.
	bool dont_save = GetNativeCell(3);
	if (!dont_save)
	{
		char steamid64[64];
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
		SetSessionDatabase(steamid64, ActiveContract[client].UUID);
	}


	Call_StartForward(g_fOnClientActivatedContract);
	Call_PushCell(client);
	Call_PushString(ActiveContract[client].UUID);
	Call_Finish();

	LogMessage("[ZContracts] %N CONTRACT: Set Contract to: %s", client, ActiveContract[client].UUID);

	// Reset our current directory in the Contracker.
	g_Menu_CurrentDirectory[client] = "root";
	g_Menu_DirectoryDeepness[client] = 1;

	return true;
}

/**
 * Grabs the progress of the clients active Contract.
 *
 * @param client    Client index.
 * @return		Progress value. If the client does not have an active Contract, -1 is returned.
 * @error       Invalid client index.
 */
public any Native_GetActiveContractProgress(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	// Return progress.
	if (ActiveContract[client].IsContractInitalized())
	{
		return ActiveContract[client].ContractProgress;
	}
	else
	{
		return -1;
	}
}

/**
 * Grabs the progress of an Objective from the clients active Contract.
 *
 * @param client    Client index.
 * @param objective     Objective ID.
 * @return		Progress value. If the client does not have an active Contract, -1 is returned.
 * @error       Invalid client or objective index.
 */
public any Native_GetActiveObjectiveProgress(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	if (ActiveContract[client].IsContractInitalized())
	{
		int ObjectiveID = GetNativeCell(2);
		if (ObjectiveID > ActiveContract[client].ObjectiveCount)
		{
			ThrowNativeError(SP_ERROR_NATIVE, "Invalid objective index (UUID: %s, ID: %d).",
			ActiveContract[client].UUID, ObjectiveID);
		}

		return ActiveContract[client].ObjectiveProgress.Get(ObjectiveID);
	}
	else
	{
		return -1;
	}
}

/**
 * Sets the progress of a clients active Contract. This does not automatically
 * save the progress to the database (see SaveActiveContractToDatabase).
 *
 * @param client    Client index.
 * @param value     New progress value.
 * @error       Invalid client index.
 */
public any Native_SetActiveContractProgress(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	// Set progress.
	if (ActiveContract[client].IsContractInitalized())
	{
		ActiveContract[client].ContractProgress = GetNativeCell(2);
	}
	
	return 0;
}

/**
 * Sets the progress of an objective in a clients active Contract. This does not automatically
 * save the progress to the database (see SaveActiveObjectiveToDatabase).
 *
 * @param client    Client index.
 * @param objective     Objective ID.
 * @param value     New progress value.
 * @error       Invalid client or objective index.
 */
public any Native_SetActiveObjectiveProgress(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	if (ActiveContract[client].IsContractInitalized())
	{
		int ObjectiveID = GetNativeCell(2);
		if (ObjectiveID > ActiveContract[client].ObjectiveCount)
		{
			ThrowNativeError(SP_ERROR_NATIVE, "Invalid objective index (UUID: %s, ID: %d).",
			ActiveContract[client].UUID, ObjectiveID);
		}

		ActiveContract[client].ObjectiveProgress.Set(ObjectiveID, GetNativeCell(3));
	}

	return false;
}

/**
 * Returns a list of all completed contracts.
 *
 * @param client    Client index.
 * @return      StringMap sorted by UUID as key and completion data as the info.
 * @note        This function is partially unsafe as enum structs are still used inside.
 * @error       Invalid client index.
 */
public any Native_GetClientCompletedContracts(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	return CompletedContracts[client].Clone();
}

/**
 * Checks to see if the client can activate a Contract.
 *
 * @param client    Client index.
 * @param UUID      UUID of Contract to check.
 * @return      True if the client can activate a contract, false otherwise.
 * @error       Invalid client index or invalid UUID.
 */
public any Native_CanClientActivateContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	char UUID[MAX_UUID_SIZE];
	GetNativeString(2, UUID, sizeof(UUID));
	
	if (g_DebugUnlockContracts.BoolValue) return true;

	KeyValues Schema = GetContractSchema(UUID);

	// Time restriction check.
	int BeginTimestampRestriction = Schema.GetNum(CONTRACT_DEF_UNIX_START, -1);
	if (BeginTimestampRestriction != -1 && BeginTimestampRestriction > GetTime()) return false;
	int EndTimestampRestriction = Schema.GetNum(CONTRACT_DEF_UNIX_END, -1);
	if (EndTimestampRestriction != -1 && EndTimestampRestriction < GetTime()) return false;
	
	// Required contracts check.
	if (Schema.JumpToKey(CONTRACT_DEF_REQUIRED, false))
	{
		int Value = 0;
		for (;;)
		{
			char ContractUUID[MAX_UUID_SIZE];
			char ValueStr[4];
			IntToString(Value, ValueStr, sizeof(ValueStr));

			Schema.GetString(ValueStr, ContractUUID, sizeof(ContractUUID), "{}");
			// If we reach a blank UUID, we're at the end of the list.
			if (StrEqual("{}", ContractUUID)) break;
			if (CompletedContracts[client].ContainsKey(ContractUUID))
			{
				return true;
			}
			Value++;
		}
	}
	else
	{
		return true;	
	}
	
	return false;
}

/**
 * Checks to see if the client can complete a Contract at the current time.
 *
 * @param client    Client index.
 * @param UUID      UUID of Contract to check.
 * @return      True if the client can complete the contract, false otherwise.
 * @error       Invalid client index or invalid UUID.
 */
public any Native_CanClientCompleteContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	char UUID[MAX_UUID_SIZE];
	GetNativeString(2, UUID, sizeof(UUID));
	if (UUID[0] != '{')
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID structure (%s).", UUID);
	}

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Called.", client, UUID);
#endif
	
	// Call forward to see if any plugins want to block this function.
	Call_StartForward(g_fOnContractCompletableCheck);
	Call_PushCell(client);
	Call_PushString(UUID);
	bool ShouldBlock = false;
	Call_Finish(ShouldBlock);

	if (ShouldBlock) return false;

	KeyValues Schema = GetContractSchema(UUID);

	// Map check.
	char Map[256];
	GetCurrentMap(Map, sizeof(Map));
	char MapRestriction[256];
	Schema.GetString(CONTRACT_DEF_MAP, MapRestriction, sizeof(MapRestriction));
	if (!StrEqual(Map, "") && StrContains(Map, MapRestriction) == -1)
	{
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Map check failed. Schema: %s, curr: %s",
		client, UUID, MapRestriction, Map);
#endif
		return false;
	}

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Map check passed.", client, UUID);
#endif

	// Team check.
	char TeamString[64];
	Schema.GetString(CONTRACT_DEF_TEAM, TeamString, sizeof(TeamString));
	int TeamRestriction = GetTeamFromSchema(TeamString);
	if (TeamRestriction != -1 && GetClientTeam(client) != TeamRestriction)
	{
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Team check failed. Schema: %d, curr: %d",
		client, UUID, TeamRestriction, GetClientTeam(client));
#endif
		return false;
	}

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Team check passed.", client, UUID);
#endif

	// Weapon check.
	char WeaponClassnameRestriction[64];
	Schema.GetString(CONTRACT_DEF_ACTIVE_WEAPON_CLASSNAME, WeaponClassnameRestriction, sizeof(WeaponClassnameRestriction));
	if (/*!StrEqual("", this.m_sWeaponItemDefRestriction)
	|| */!StrEqual("", WeaponClassnameRestriction))
	{
		int ClientWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(ClientWeapon))
		{
			char Classname[64];
			GetEntityClassname(ClientWeapon, Classname, sizeof(Classname));
			if (StrContains(Classname, WeaponClassnameRestriction) == -1)
			{
#if defined VERBOSE_DEBUG
				PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Weapon classname check failed. Schema: %s, curr: %s",
				client, UUID, WeaponClassnameRestriction, Classname);
#endif
				return false;
			}
		}
	}

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Weapon classname check passed.", client, UUID);
#endif

	// Timestamp check.
	int BeginTimestampRestriction = Schema.GetNum(CONTRACT_DEF_UNIX_START, -1);
	if (BeginTimestampRestriction != -1 && BeginTimestampRestriction > GetTime())
	{
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Time begin check failed. Schema: %d, curr: %d",
		client, UUID, BeginTimestampRestriction, GetTime());
#endif
		return false;
	}
	int EndTimestampRestriction = Schema.GetNum(CONTRACT_DEF_UNIX_END, -1);
	if (EndTimestampRestriction != -1 && EndTimestampRestriction < GetTime())
	{
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Time begin check failed. Schema: %d, curr: %d",
		client, UUID, EndTimestampRestriction, GetTime());
#endif
		return false;
	}

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] Time check passed.", client, UUID);
#endif

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD Native_CanClientCompleteContract(%N, %s)] All checks passed, client can complete contract.", client, UUID);
#endif

	return true;
}

/**
 * Checks to see if a client has already completed a Contract.
 *
 * @param client    Client index.
 * @param UUID      UUID of Contract to check.
 * @return      True if the client has completed the contract, false otherwise.
 * @error       Invalid client index or invalid UUID.
 */
public any Native_HasClientCompletedContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	char UUID[MAX_UUID_SIZE];
	GetNativeString(2, UUID, sizeof(UUID));
	if (UUID[0] != '{')
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID structure (%s).", UUID);
	}
	return CompletedContracts[client].ContainsKey(UUID);
}

/**
 * Checks to see if the client has completed their active Contract.
 *
 * @param client    Client index.
 * @return      True if a client has completed their active Contract.
 *              False if the client has not finished their contract or has no contract active.
 * @error       Invalid client index.
 */
public any Native_IsActiveContractComplete(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d).", client);
	}

	return ActiveContract[client].IsContractComplete();
}

// Function for event timers.
public Action Timer_DisplayContractInfo(Handle hTimer, int client)
{
	static int Attempts = 0;
	
	if (ActiveContract[client].m_bLoadedFromDatabase || Attempts >= 3)
	{
		Call_StartForward(g_fOnClientActivatedContractPost);
		Call_PushCell(client);
		Call_PushString(ActiveContract[client].UUID);
		Call_Finish();

		CreateObjectiveDisplay(client, false);
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
        SetClientContractEx(client, UUID, true, true);
    }
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (PlayerHasSpawned[client]) return Plugin_Continue;
	OpenContrackerForClient(client);
	PlayerHasSpawned[client] = true;
	return Plugin_Continue;
}

// ============ MAIN LOGIC FUNCTIONS ============

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (!IsClientValid(i)) continue;
		if (!ActiveContract[i].IsContractInitalized()) continue;
		for (int j = 0; j < ActiveContract[i].ObjectiveCount; j++)
		{
			if (g_ResetThresholdsPerRound.BoolValue)
			{
				StringMap ObjectiveThreshold = ActiveContract[i].ObjectiveThreshold.Get(j);
				StringMapSnapshot Snapshot = ObjectiveThreshold.Snapshot();
				for (int k = 0; k < Snapshot.Length; k++)
				{
					char event_name[MAX_EVENT_SIZE];
					Snapshot.GetKey(k, event_name, sizeof(event_name));
					ObjectiveThreshold.SetValue(event_name, 0);
				}
				ActiveContract[i].ObjectiveThreshold.Set(j, ObjectiveThreshold);
			}
			if (g_ResetTimersPerRound.BoolValue)
			{
				CloseHandle(ActiveContract[i].ObjectiveTimers.Get(j));
				ActiveContract[i].ObjectiveTimers.Set(j, INVALID_HANDLE);
				ActiveContract[i].ObjectiveTimerStarted.Set(j, -1.0);

				g_TimeChange[i] = 0.0;
				g_TimerActive[i] = false;
			}
		}
	}
	return Plugin_Continue;
}

public Action Timer_DrawContrackerHud(Handle hTimer)
{
	if (!g_DisplayProgressHud.BoolValue) return Plugin_Stop;

	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (!IsClientValid(i) || IsFakeClient(i)) continue;
		if (!ActiveContract[i].IsContractInitalized() || !ActiveContract[i].Active) continue;
		if (!PlayerHUDEnabled[i]) continue;

		// TF2 specific check.
		if (GetEngineVersion() == Engine_TF2 &&
		(TF2_GetClientTeam(i) == TFTeam_Spectator || TF2_GetClientTeam(i) == TFTeam_Unassigned)) continue;

		// Prepare our text.
		SetHudTextParams(1.0, -1.0, HUD_REFRESH_RATE + 0.1, 255, 255, 255, 255);
		char DisplayText[512] = "\"%s\":\n";
		char ContractName[MAX_CONTRACT_NAME_SIZE];
		ActiveContract[i].GetSchema().GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));
		Format(DisplayText, sizeof(DisplayText), DisplayText, ContractName);

		// Add the amount of completions.
		CompletedContractInfo info;
		CompletedContracts[i].GetArray(ActiveContract[i].UUID, info, sizeof(CompletedContractInfo));

		if (PlayerHUDRepeatEnabled[i] && g_DisplayRepeatsInHUD.BoolValue && info.m_iCompletions > 0)
		{
			char CompletionsText[64] = "Completions: %d\n";
			Format(CompletionsText, sizeof(CompletionsText), CompletionsText, info.m_iCompletions);
			StrCat(DisplayText, sizeof(DisplayText), CompletionsText);
		}

		// TODO: UNDO ME
		// Add text if we've completed the Contract.
		if (ActiveContract[i].IsContractComplete())
		{
			char CompleteText[] = "CONTRACT COMPLETE - Type /c to\nselect a new Contract.";
			StrCat(DisplayText, sizeof(DisplayText), CompleteText);
		}
		else if (!CanClientCompleteContract(i, ActiveContract[i].UUID))
		{
			char WarningText[] = "This Contract cannot be completed.\nType /c to select a new Contract.";
			StrCat(DisplayText, sizeof(DisplayText), WarningText);
		}
		else
		{
			// Display the overall Contract progress.
			if (view_as<ContractType>(ActiveContract[i].GetSchema().GetNum(CONTRACT_DEF_TYPE)) == Contract_ContractProgress)
			{
				if (g_NextHUDUpdate[i] > GetGameTime()) continue;

				char ProgressText[128] = "Progress: [%d/%d]";
				Format(ProgressText, sizeof(ProgressText), ProgressText,
				ActiveContract[i].ContractProgress, ActiveContract[i].GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS));		

				// Adds +xCP value to the end of the text.
				if (ActiveContract[i].m_bHUD_ContractUpdate)
				{
					char AddText[16];
					if (ActiveContract[i].m_iHUD_UpdateValue > 0)
					{
						AddText = " +%dCP";
						SetHudTextParams(1.0, -1.0, 1.0, 52, 235, 70, 255, 1);
					}
					else // subtract
					{
						AddText = " -%dCP";
						SetHudTextParams(1.0, -1.0, 1.0, 209, 33, 21, 255, 1);
					}
					
					Format(AddText, sizeof(AddText), AddText, ActiveContract[i].m_iHUD_UpdateValue);
					StrCat(ProgressText, sizeof(ProgressText), AddText);
					ActiveContract[i].m_bHUD_ContractUpdate = false;
					ActiveContract[i].m_iHUD_UpdateValue = 0;

					g_NextHUDUpdate[i] = GetGameTime() + 1.0;
				}				

				StrCat(ProgressText, sizeof(ProgressText), "\n");
				StrCat(DisplayText, sizeof(DisplayText), ProgressText);
			}

			bool DisplaySavingText = ActiveContract[i].m_bNeedsDBSave;

			// Add our objectives to HUD display.
			for (int j = 0; j < ActiveContract[i].ObjectiveCount; j++)
			{
				if (ActiveContract[i].IsObjectiveComplete(j)) continue;
				KeyValues ObjSchema = ActiveContract[i].GetObjectiveSchema(j);

				char ObjectiveText[64] = "#%d:";
				Format(ObjectiveText, sizeof(ObjectiveText), ObjectiveText, j+1);
				// Display the progress of this objective if we're not infinite.
				if (!ActiveContract[i].IsObjectiveInfinite(j))
				{
					if (g_NextHUDUpdate[i] > GetGameTime()) continue;

					char ProgressText[64] = " [%d/%d]";
					Format(ProgressText, sizeof(ProgressText), ProgressText,
					ActiveContract[i].ObjectiveProgress.Get(j), 
					ObjSchema.GetNum(CONTRACT_DEF_OBJ_MAX_PROGRESS));
					StrCat(ObjectiveText, sizeof(ObjectiveText), ProgressText);

					// Adds +x value to the end of the text.
					if (ActiveContract[i].m_iHUD_ObjectiveUpdate == j)
					{
						char AddText[16];
						if (ActiveContract[i].m_iHUD_UpdateValue > 0)
						{
							AddText = " +%dCP";
							SetHudTextParams(1.0, -1.0, 1.0, 52, 235, 70, 255, 1);
						}
						else // subtract
						{
							AddText = " -%dCP";
							SetHudTextParams(1.0, -1.0, 1.0, 209, 33, 21, 255, 1);
						}
					
						Format(AddText, sizeof(AddText), AddText, ActiveContract[i].m_iHUD_UpdateValue);
						StrCat(ObjectiveText, sizeof(ObjectiveText), AddText);
						ActiveContract[i].m_bHUD_ContractUpdate = false;
						ActiveContract[i].m_iHUD_ObjectiveUpdate = -1;

						g_NextHUDUpdate[i] = GetGameTime() + 1.0;
					}
				}
				// Infinite contract objectives may have timers attached to them, so we
				// add them here.
				char TimerText[64] = " [TIME: %ds]";
				// Display a timer if we have one active.
				for (int k = 0; k < ActiveContract[i].ObjectiveCount; k++)
				{
					// Do we have a timer going?
					if (ActiveContract[i].IsTimerRunning(k))
					{
						int TimeDiff = (RoundToFloor(GetGameTime()) - RoundToFloor(ActiveContract[i].ObjectiveTimerStarted.Get(k)));
						Format(TimerText, sizeof(TimerText), TimerText, TimeDiff);

						if (g_TimeChange[i] != 0.0)
						{
							SetHudTextParams(1.0, -1.0, 1.0, 255, 242, 0, 255, 1);
							char TimeDiffText[16] = " %s%.1fs max";
							if (g_TimeChange[i] > 0.0)
							{
								Format(TimeDiffText, sizeof(TimeDiffText), TimeDiffText, "+", g_TimeChange[i]);
							}
							if (g_TimeChange[i] < 0.0)
							{
								Format(TimeDiffText, sizeof(TimeDiffText), TimeDiffText, "-", g_TimeChange[i]);
							}
							StrCat(TimerText, sizeof(TimerText), TimeDiffText);
							g_NextHUDUpdate[i] = GetGameTime() + 1.0;
						}
						StrCat(ObjectiveText, sizeof(ObjectiveText), TimerText);
					}
				}

				if (strlen(ObjectiveText) > 4)
				{
					StrCat(DisplayText, sizeof(DisplayText), ObjectiveText);
					StrCat(DisplayText, sizeof(DisplayText), "\n");
				}
			}

			// Add some text saying that we're saving the Contract to the database.
			if (DisplaySavingText)
			{
				char SavingText[] = "Saving...";
				StrCat(DisplayText, sizeof(DisplayText), SavingText);
			}
		}
		// Display text to client.
		ShowSyncHudText(i, g_HudSync, DisplayText);
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

		// You never know (debugging) - just process the active contract.
		if (StrEqual(OldContract[client].UUID, ActiveContract[client].UUID))
		{
			ProcessContrackerEvent(client, event, value, false);
#if defined VERBOSE_DEBUG
			PrintToServer("[ZCD Timer_ProcessEvents(%N)] Calling ProcessContrackerEvent for active Contract %s", client, uuid);
#endif
			iProcessed++;
			continue;
		}
		// Do our UUID's match?
		if (OldContract[client].IsContractInitalized() && StrEqual(uuid, OldContract[client].UUID))
		{
#if defined VERBOSE_DEBUG
			PrintToServer("[ZCD Timer_ProcessEvents(%N)] Calling ProcessContrackerEvent for old Contract %s", client, uuid);
#endif
			ProcessContrackerEvent(client, event, value, true);
		}
		if (StrEqual(uuid, ActiveContract[client].UUID))
		{
#if defined VERBOSE_DEBUG
			PrintToServer("[ZCD Timer_ProcessEvents(%N)] Calling ProcessContrackerEvent for active Contract %s", client, uuid);
#endif
			ProcessContrackerEvent(client, event, value, false);
		}

		iProcessed++;
	}

	return Plugin_Continue;
}

void ProcessEventTimerLogic(int client, Contract Buffer, int obj_id, char event[MAX_EVENT_SIZE])
{
#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD ProcessEventTimerLogic(%N, %s, %d, %s)] Called.", client, Buffer.UUID, obj_id, event);
#endif
	// Do we have a timer going?
	if (Buffer.ObjectiveTimers.Get(obj_id) != INVALID_HANDLE)
	{
		SendEventToTimer(client, obj_id, event, "OnEventFired");
	}
	else 
	{
		KeyValues Schema = Buffer.GetObjectiveSchema(obj_id);
		if (!Schema.JumpToKey(CONTRACT_DEF_OBJ_EVENTS)) ThrowError("Contract \"%s\" doesn't have any events! Fix this, server developer!", Buffer.UUID);
		if (!Schema.JumpToKey(event)) ThrowError("Contract \"%s\" doesn't have requested event \"%s\"", Buffer.UUID, event);
		if (!Schema.JumpToKey(CONTRACT_DEF_EVENT_TIMER)) return;

		// Start a timer if we should have one.
		if (Buffer.ObjectiveTimers.Get(obj_id) == INVALID_HANDLE && Schema.GetFloat(CONTRACT_DEF_TIMER_TIME) != 0.0)
		{
			// Create a datapack for our timer so we can pass our objective and event through.
			DataPack TimerData;
			
			// Create our timer. (see contracts_timers.sp)
			Handle TimerHandle = CreateDataTimer(0.5, EventTimer, TimerData, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			TimerData.WriteCell(client);
			TimerData.WriteCell(obj_id);
			TimerData.WriteString(event);
			TimerData.WriteFloat(GetGameTime());
			Buffer.ObjectiveTimers.Set(obj_id, TimerHandle);
			Buffer.ObjectiveTimerStarted.Set(obj_id, GetGameTime());
		}
	}
}

void PerformThresholdCheck(int client, Contract Buffer, int objective_id, char event[MAX_EVENT_SIZE], int value)
{
#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD PerformThresholdCheck(%N, %s, %d, %s, %d)] Called.", client, Buffer.UUID, objective_id, event, value);
#endif

	KeyValues Schema = Buffer.GetObjectiveSchema(objective_id);
	if (!Schema.JumpToKey(CONTRACT_DEF_OBJ_EVENTS)) ThrowError("Contract \"%s\" doesn't have any events! Fix this, server developer!", Buffer.UUID);
	if (!Schema.JumpToKey(event)) ThrowError("Contract \"%s\" doesn't have requested event \"%s\"", Buffer.UUID, event);

	StringMap ObjectiveThreshold = Buffer.ObjectiveThreshold.Get(objective_id);
	int CurrentThreshold = 0;
	ObjectiveThreshold.GetValue(event, CurrentThreshold);

	// We've reached the threshold for this Objective!
	if (CurrentThreshold >= Schema.GetNum(CONTRACT_DEF_EVENT_THRESHOLD))
	{
		char EventType[64];
		Schema.GetString(CONTRACT_DEF_EVENT_TYPE, EventType, sizeof(EventType));
		// Give us a special reward!
		if (StrEqual(EventType, "increment") || StrEqual(EventType, "subtract"))
		{
			if (StrEqual(EventType, "subtract"))
			{
				value *= -1;
			}

			switch (view_as<ContractType>(Buffer.GetSchema().GetNum(CONTRACT_DEF_TYPE)))
			{
				case Contract_ObjectiveProgress: ModifyObjectiveProgress(client, value, Buffer, objective_id);
				case Contract_ContractProgress: ModifyContractProgress(client, value, Buffer, objective_id);
			}

			// Reset our threshold.
			ObjectiveThreshold.SetValue(event, 0);
		}
		else if (StrEqual(EventType, "reset"))
		{
			StringMapSnapshot Snapshot = ObjectiveThreshold.Snapshot();
			for (int i = 0; i < Snapshot.Length; i++)
			{
				char event_name[MAX_EVENT_SIZE];
				Snapshot.GetKey(i, event_name, sizeof(event_name));
				ObjectiveThreshold.SetValue(event_name, 0);
			}
		}
		
		// Cancel our timer now that we've reached our threshold.
		if (Buffer.ObjectiveTimers.Get(objective_id) != INVALID_HANDLE)
		{
			if (g_DebugTimers.BoolValue)
			{
				LogMessage("[ZContracts] Timer finished for %N: [OBJ: %d, EVENT: %s, REASON: Event reached threshold]",
				client, objective_id, event);
			}

			CloseHandle(Buffer.ObjectiveTimers.Get(objective_id));
			Buffer.ObjectiveTimers.Set(objective_id, INVALID_HANDLE);

			g_TimeChange[client] = 0.0;
			g_TimerActive[client] = false;
		}
	}
	Buffer.ObjectiveThreshold.Set(objective_id, ObjectiveThreshold);
}

void ProcessContrackerEvent(int client, char event[MAX_EVENT_SIZE], int value, bool use_old=false)
{
#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD ProcessContrackerEvent(%N, %s, %d, %d)] Called.", client, event, value, use_old);
#endif
	Contract Buffer;
	if (!use_old) Buffer = ActiveContract[client];
	else Buffer = OldContract[client];

	// Is this contract completed or able to be completed right now?
	if (!Buffer.IsContractInitalized()) return;
	if (Buffer.IsContractComplete()) return;
	if (!CanClientCompleteContract(client, Buffer.UUID)) return;

#if defined VERBOSE_DEBUG
	PrintToServer("[ZCD ProcessContrackerEvent(%N, %s, %d, %d)] Contract %s passed all completion checks", client, event, value, use_old, Buffer.UUID);
#endif

	char steamid64[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

	// Loop through our objectives.
	for (int obj_id = 0; obj_id < Buffer.ObjectiveCount; obj_id++)
	{
		if (Buffer.IsObjectiveComplete(obj_id)) continue;
#if defined VERBOSE_DEBUG
		PrintToServer("[ZCD ProcessContrackerEvent(%N, %s, %d, %d)] Contract: %s, obj %d passed completion check", client, event, value, use_old, Buffer.UUID, obj_id);
#endif
		KeyValues Schema = Buffer.GetObjectiveSchema(obj_id);
		// Loop through events:
		if (!Schema.JumpToKey(CONTRACT_DEF_OBJ_EVENTS)) ThrowError("Contract \"%s\" doesn't have any events! Fix this, server developer!", Buffer.UUID);
		if (!Schema.GotoFirstSubKey()) ThrowError("Contract \"%s\" doesn't have any events! Fix this, server developer!", Buffer.UUID);
		do
		{
			// The name of the section is the event we compare, e.g "CONTRACTS_PLAYER_KILL"
			char EventName[MAX_EVENT_SIZE];
			Schema.GetSectionName(EventName, sizeof(EventName));

			if (!StrEqual(EventName, event)) continue;
#if defined VERBOSE_DEBUG
			PrintToServer("[ZCD ProcessContrackerEvent(%N, %s, %d, %d)] Contract: %s, obj %d passed event name check", client, event, value, use_old, Buffer.UUID, obj_id);
#endif
			// Call OnProcessContractLogic. If any plugins want to block a certain event
			// from being processed, now is the time!
			Call_StartForward(g_fOnProcessContractLogic);
			Call_PushCell(client);
			Call_PushString(Buffer.UUID);
			Call_PushCell(obj_id);
			Call_PushString(event);
			Call_PushCell(value);
			bool ShouldBlock = false;
			Call_Finish(ShouldBlock);

			// Debug logging.
			if (ShouldBlock)
			{
				if (g_DebugProcessing.BoolValue)
				{
					LogMessage("[ZContracts] Event [%s, %d] for %N was blocked.", event, value, client);
				}
				return;
			}

			if (g_DebugProcessing.BoolValue)
			{
				LogMessage("[ZContracts] Processing event [%s, %d] for %N", event, value, client);
			}

			ProcessEventTimerLogic(client, Buffer, obj_id, event);
			StringMap ObjectiveThreshold = Buffer.ObjectiveThreshold.Get(obj_id);
			int CurrentThreshold = 0;
			ObjectiveThreshold.GetValue(event, CurrentThreshold);
			ObjectiveThreshold.SetValue(event, CurrentThreshold + value);
			Buffer.ObjectiveThreshold.Set(obj_id, ObjectiveThreshold);
			
			// Store the old progress so we can check to see if we need to save.
			int OldProgress = 0;
			switch (view_as<ContractType>(Buffer.GetSchema().GetNum(CONTRACT_DEF_TYPE)))
			{
				case Contract_ContractProgress: OldProgress = Buffer.ContractProgress;
				case Contract_ObjectiveProgress: OldProgress = Buffer.ObjectiveProgress.Get(obj_id);
			}

			// This is where progress values get updated!
			PerformThresholdCheck(client, Buffer, obj_id, event, value);

			// Update HUD now.
			g_NextHUDUpdate[client] = -1.0;
			
			// Print some awesome text saying our objective is now complete!
			if (Buffer.IsObjectiveComplete(obj_id))
			{
				if (g_DebugProgress.BoolValue)
				{
					LogMessage("[ZContracts] %N PROGRESS: Objective completed [ID: %s, OBJ: %d]",
					client, Buffer.UUID, obj_id);
				}

				Call_StartForward(g_fOnObjectiveCompleted);
				Call_PushCell(client);
				Call_PushString(Buffer.UUID);
				Call_PushCell(obj_id);
				Call_Finish();
			}

			// Do a progress check now to see if we should save.
			bool ShouldSave = false;
			switch (view_as<ContractType>(Buffer.GetSchema().GetNum(CONTRACT_DEF_TYPE)))
			{
				case Contract_ContractProgress: ShouldSave = (OldProgress < Buffer.ContractProgress);
				case Contract_ObjectiveProgress: ShouldSave = (OldProgress < Buffer.ObjectiveProgress.Get(obj_id));
			}

			if (ShouldSave) SetContractProgressDatabase(steamid64, Buffer.UUID, Buffer.ContractProgress);

		} while (Schema.GotoNextKey());
	}

	// Is our contract now complete?
	if (Buffer.IsContractComplete())
	{
		if (PlayerSoundsEnabled[client] >= Sounds_Enabled) EmitGameSoundToClient(client, ContractCompletedSound);
		if (g_DebugProgress.BoolValue)
		{
			LogMessage("[ZContracts] %N PROGRESS: Contract completed [ID: %s]",
			client, Buffer.UUID);
		}

		Call_StartForward(g_fOnContractCompleted);
		Call_PushCell(client);
		Call_PushString(Buffer.UUID);
		Call_Finish();

		// Save completion status to database.
		CompletedContractInfo info;
		if (CompletedContracts[client].ContainsKey(Buffer.UUID))
		{
			CompletedContracts[client].GetArray(Buffer.UUID, info, sizeof(CompletedContractInfo));
		}
		info.m_iCompletions++;
		info.m_bReset = g_AutoResetContracts.BoolValue;
		CompletedContracts[client].SetArray(Buffer.UUID, info, sizeof(CompletedContractInfo));
		SetCompletedContractInfoDatabase(steamid64, Buffer.UUID, info);

		if (!g_AutoResetContracts.BoolValue)
		{
			char ContractName[MAX_CONTRACT_NAME_SIZE];
			Buffer.GetSchema().GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));

			PrintColoredChatAll("%s[ZC]%s %N has completed the contract: %s\"%s\"%s, congratulations!",
			COLOR_LIGHTSEAGREEN, COLOR_DEFAULT, client, COLOR_YELLOW, ContractName, COLOR_DEFAULT);
			SetContractProgressDatabase(steamid64, Buffer.UUID, Buffer.ContractProgress);
		}
		else // Delete all progress from database and reset the Contract.
		{
			DeleteContractProgressDatabase(steamid64, Buffer.UUID);
			DeleteAllObjectiveProgressDatabase(steamid64, Buffer.UUID);

			if (!use_old)
			{
				// Reset everything.
				Buffer.ContractProgress = 0;
				for (int j = 0; j < Buffer.ObjectiveCount; j++)
				{
					Buffer.ObjectiveProgress.Set(j, 0);
					StringMap ObjectiveThreshold = Buffer.ObjectiveThreshold.Get(j);
					StringMapSnapshot Snapshot = ObjectiveThreshold.Snapshot();
					for (int k = 0; k < Snapshot.Length; k++)
					{
						char event_name[MAX_EVENT_SIZE];
						Snapshot.GetKey(k, event_name, sizeof(event_name));
						ObjectiveThreshold.SetValue(event_name, 0);
					}
					Buffer.ObjectiveThreshold.Set(j, ObjectiveThreshold);

					CloseHandle(Buffer.ObjectiveTimers.Get(j));
					Buffer.ObjectiveTimers.Set(j, INVALID_HANDLE);
					Buffer.ObjectiveTimerStarted.Set(j, -1.0);

					g_TimeChange[client] = 0.0;
					g_TimerActive[client] = false;
				}
			}
		}

		// If we're a bot, grant a new Contract straight away.
		if (IsFakeClient(client) && g_BotContracts.BoolValue)
		{
			GiveRandomContract(client);
		}
	}
	if (!use_old) ActiveContract[client] = Buffer;
	else OldContract[client] = Buffer;
}

void ModifyContractProgress(int client, int value, Contract Buffer, int obj_id)
{
	int AddValue = 0;
	KeyValues ObjSchema = Buffer.GetObjectiveSchema(obj_id);

	// This award value will not be multiplied by the value argument. This may be useful for some Contracts.
	if (Buffer.m_bNoMultiplication) AddValue = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD);
	else if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_NO_MULTI) == 1) AddValue = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD);
	else AddValue = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD) * value;

	Buffer.ContractProgress += AddValue;
	Buffer.ContractProgress = Int_Min(Buffer.ContractProgress, Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS));
	if (Buffer.ContractProgress < 0)
	{
		Buffer.ContractProgress = 0;
		return;
	}

	// Update HUD.
	Buffer.m_iHUD_UpdateValue = AddValue;
	Buffer.m_bHUD_ContractUpdate = true;
	
	if (PlayerSoundsEnabled[client] == Sounds_Enabled) EmitGameSoundToClient(client, IncrementProgressSound);

	// In Contract-Style progression, Objectives are only triggered
	// once at a time if they are not infinite.
	if (!Buffer.IsObjectiveInfinite(obj_id))
	{
		int ObjectiveProgress = Buffer.ObjectiveProgress.Get(obj_id);
		ObjectiveProgress++;

		ObjectiveProgress = Int_Min(ObjectiveProgress, Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS));
		Buffer.ObjectiveProgress.Set(obj_id, ObjectiveProgress);
	}

	// Print HINT text to chat.
	if (g_DisplayHudMessages.BoolValue && PlayerHintEnabled[client])
	{							
		char MessageText[256];
		char AwardStr[8];
		if (AddValue > 0) AwardStr = "+%dCP";
		else AwardStr = "%dCP";

		char ContractName[MAX_CONTRACT_NAME_SIZE];
		char ContractDescription[256];
		Buffer.GetSchema().GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));
		Buffer.GetObjectiveSchema(obj_id).GetString(CONTRACT_DEF_OBJ_DESC, ContractDescription, sizeof(ContractDescription));

		if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_NO_MULTI) == 1)
		{
			Format(AwardStr, sizeof(AwardStr), AwardStr, ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD));

			MessageText = "\"%s\" (%s [%d/%dCP]) %s";
			PrintHintText(client, MessageText, ContractDescription,
			ContractName, Buffer.ContractProgress,
			Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS), AwardStr);
		}
		else
		{
			Format(AwardStr, sizeof(AwardStr), AwardStr, ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD) * value);

			MessageText = "\"%s\" %dx (%s [%d/%dCP]) %s";
			PrintHintText(client, MessageText, ContractDescription,
			value, ContractName, Buffer.ContractProgress,
			Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS), AwardStr);
		}
	}
	if (g_DebugProgress.BoolValue)
	{
		LogMessage("[ZContracts] %N PROGRESS: Increment event triggered [ID: %s, CP: %d]",
		client, Buffer.UUID, Buffer.ObjectiveProgress.Get(obj_id));
	}
}

void ModifyObjectiveProgress(int client, int value, Contract Buffer, int obj_id)
{
	int AddValue = 0;
	KeyValues ObjSchema = Buffer.GetObjectiveSchema(obj_id);

	// This award value will not be multiplied by the value argument. This may be useful for some Contracts.
	if (Buffer.m_bNoMultiplication) AddValue = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD);
	else if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_NO_MULTI) == 1) AddValue = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD);
	else AddValue = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD) * value;

	int ObjectiveProgress = Buffer.ObjectiveProgress.Get(obj_id) + AddValue;
	ObjectiveProgress = Int_Min(ObjectiveProgress, Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS));
	if (ObjectiveProgress < 0) ObjectiveProgress = 0;
	Buffer.ObjectiveProgress.Set(obj_id, ObjectiveProgress);

	// Update HUD.
	Buffer.m_iHUD_UpdateValue = AddValue;
	Buffer.m_bHUD_ContractUpdate = true;
	Buffer.m_iHUD_ObjectiveUpdate = obj_id;

	if (PlayerSoundsEnabled[client] == Sounds_Enabled) EmitGameSoundToClient(client, IncrementProgressSound);

	// Display HINT message to the client.
	if (g_DisplayHudMessages.BoolValue && PlayerHintEnabled[client])
	{
		char MessageText[256];
		char AwardStr[8];
		if (AddValue > 0) AwardStr = "+%dCP";
		else AwardStr = "%dCP";

		char ContractName[MAX_CONTRACT_NAME_SIZE];
		char ContractDescription[256];
		Buffer.GetSchema().GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));
		Buffer.GetSchema().GetString(CONTRACT_DEF_OBJ_DESC, ContractDescription, sizeof(ContractDescription));
		
		if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_NO_MULTI) == 1)
		{
			Format(AwardStr, sizeof(AwardStr), AwardStr, ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD));

			MessageText = "\"%s\" (%s [%d/%d]) %s";
			PrintHintText(client, MessageText, ContractDescription,
			ContractName, Buffer.ObjectiveProgress.Get(obj_id),
			Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS), AwardStr);
		}
		else
		{
			Format(AwardStr, sizeof(AwardStr), AwardStr, ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD) * value);

			MessageText = "\"%s\" %dx (%s [%d/%d]) %s";
			PrintHintText(client, MessageText, ContractDescription,
			value, ContractName, Buffer.ObjectiveProgress.Get(obj_id),
			Buffer.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS), AwardStr);
		}
	}
	if (g_DebugProgress.BoolValue)
	{
		LogMessage("[ZContracts] %N PROGRESS: Increment event triggered [ID: %s, OBJ: %d, CP: %d]",
		client, Buffer.UUID, obj_id, Buffer.ObjectiveProgress.Get(obj_id));
	}
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
		SetClientContract(client, UUID);
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
		int user = target_list[i];
		if (!ActiveContract[user].IsContractInitalized()) continue;

		SaveActiveContractToDatabase(user);
		for (int j = 0; j < ActiveContract[user].ObjectiveCount; j++)
		{
			SaveActiveObjectiveToDatabase(user, j);
		}
	}

	return Plugin_Handled;
}
