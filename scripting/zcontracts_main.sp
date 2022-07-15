// TODO: Save Contract style progress.
// TODO: CSGO testing.
// TODO: Implement more game events.
// TODO: Implement team restrictions for contracts.
	// (e.g red, blu, terrorists, counterterrorists + aliases)
// TODO: Documentation (contracts_db)!!
// TODO: Implement forwards for contract and objective completion


#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <morecolors>

#include <zcontracts/zcontracts>

#pragma semicolon 1

// Global variables.
Database g_DB;
static Menu gContractMenu;
Panel gContractObjeciveDisplay[MAXPLAYERS+1];
char g_Menu_CurrentDirectory[MAXPLAYERS+1][MAX_DIRECTORY_SIZE];

Contract m_hOldContract[MAXPLAYERS+1];
Contract m_hContracts[MAXPLAYERS+1];

ConVar g_PrintQueryInfo;
ConVar g_UpdatesPerSecond;
ConVar g_DatabaseUpdateTime;

// This arraylist contains a list of objectives that we need to update.
ArrayList g_ObjectiveUpdateQueue;

// Subplugins.
#include "zcontracts/contracts_schema.sp"
#include "zcontracts/contracts_timers.sp"
#include "zcontracts/contracts_db.sp"

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
	CreateNative("SetClientContract", Native_SetClientContract);
	CreateNative("GetClientContract", Native_GetClientContract);
	CreateNative("CallContrackerEvent", Native_CallContrackerEvent);
	return APLRes_Success;
}

public void OnPluginStart()
{
	// ================ CONVARS ================
	g_ConfigSearchPath = CreateConVar("zc_contract_search_path", "configs/zcontracts", "The path, relative to the \"sourcemods/\" directory, to find Contract definition files. Changing this Value will cause a reload of the Contract schema.");
	g_RequiredFileExt = CreateConVar("zc_required_file_ext", ".txt", "The file extension that Contract definition files must have in order to be considered valid. Changing this Value will cause a reload of the Contract schema.");
	g_DisabledPath = CreateConVar("zc_disabled_path", "configs/zcontracts/disabled", "If a search path has this string in it, any Contract's loaded in or derived from this path will not be loaded. Changing this Value will cause a reload of the Contract schema.");
	g_UpdatesPerSecond = CreateConVar("zc_updates_per_second", "4", "Process this many objective updates per second.");
	g_DatabaseUpdateTime = CreateConVar("zc_database_update_time", "30", "How long to wait before sending Contract updates to the database.");
	g_PrintQueryInfo = CreateConVar("zc_print_query_info", "1", "If not zero, prints to server console when a query is sent to the datbase. Mainly used for debugging.");
	g_ConfigSearchPath.AddChangeHook(OnSchemaConVarChange);
	g_RequiredFileExt.AddChangeHook(OnSchemaConVarChange);
	g_DisabledPath.AddChangeHook(OnSchemaConVarChange);

	// ================ CONTRACKER ================
	ProcessContractsSchema();
	CreateContractMenu();

	g_ObjectiveUpdateQueue = new ArrayList(sizeof(ObjectiveUpdate));
	CreateTimer(1.0, Timer_ProcessEvents, _, TIMER_REPEAT);
	CreateTimer(g_DatabaseUpdateTime.FloatValue, Timer_SaveAllToDB, _, TIMER_REPEAT);

	// ================ DATABASE ================
	Database.Connect(GotDatabase, "zcontracts");

	// ================ PLAYER INIT ================
	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		OnClientPostAdminCheck(i);
	}
	
	// ================ COMMANDS ================
	RegConsoleCmd("sm_setcontract", DebugSetContract);
	RegConsoleCmd("sm_debugcontract", DebugContractInfo);
	RegConsoleCmd("sm_debug_getprogress", DebugGetProgress);
	RegConsoleCmd("sm_debug_saveprogress", DebugForceSave);

	RegServerCmd("sm_reloadcontracts", ReloadContracts);
	RegConsoleCmd("sm_contract", OpenContrackerForClient);
	RegConsoleCmd("sm_contracts", OpenContrackerForClient);
	RegConsoleCmd("sm_c", OpenContrackerForClient);
}

public void OnClientPostAdminCheck(int client)
{
	// Reset variables.
	Contract hBlankContract;
	m_hContracts[client] = hBlankContract;
	m_hOldContract[client] = hBlankContract;

	// Grab the players Contract from the last session.
	if (IsClientValid(client)
	&& !IsFakeClient(client)
	&& g_DB != null)
	{
		GrabContractFromLastSession(client);
	}
	
	g_Menu_CurrentDirectory[client] = "root";
}

public void OnSchemaConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	ProcessContractsSchema();
	CreateContractMenu();
}

public Action ReloadContracts(int args)
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
	SetNativeArray(2, m_hContracts[client], sizeof(Contract));
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

	if (!IsClientValid(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	// If we're a bot, fail silently.
	if (IsFakeClient(client)) return false;

	Contract hContract;
	GetClientContract(client, hContract);
	
	// Do we have a contract currently active?
	if (hContract.m_sUUID[0] != '{' || hContract.IsContractComplete())
	{
		return false;
	}

	// Try to increment all of our objectives.
	for (int i = 0; i < hContract.m_hObjectives.Length; i++)
	{	
		ContractObjective hContractObjective;
		hContract.GetObjective(i, hContractObjective);

		// Don't touch this objective if it shouldn't be doing anything.
		if (!hContractObjective.m_bInitalized || hContractObjective.IsObjectiveComplete()) 
		{
			continue;
		}

		// Add to the global queue.
		ObjectiveUpdate hUpdate;
		hUpdate.m_iClient = client;
		hUpdate.m_iValue = value;
		hUpdate.m_iObjectiveID = hContractObjective.m_iInternalID;
		hUpdate.m_sEvent = event;
		hUpdate.m_sUUID = hContract.m_sUUID;
		g_ObjectiveUpdateQueue.PushArray(hUpdate, sizeof(ObjectiveUpdate));
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
	// Are we a bot?
	if (!IsClientValid(client) || IsFakeClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

	// If we have a Contract already selected, save it's progress to the database.
	Contract hOldContract;
	GetClientContract(client, hOldContract);
	if (hOldContract.m_hObjectives != null)
	{
		SaveContractToDB(client, hOldContract);
		m_hOldContract[client] = hOldContract;
	}
	
	char sUUID[MAX_UUID_SIZE];
	GetNativeString(2, sUUID, sizeof(sUUID));

	// Get our Contract definition.
	Contract hContract;
	if (!CreateContractFromUUID(sUUID, hContract))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID (%s) for client %d", sUUID, client);
	}

	// Set our client contract here so we can populate it's progress
	// values in the threaded callback functions.
	m_hContracts[client] = hContract;
	PopulateProgressFromDB(client, sUUID, true);

	// Set this Contract as our current session.
	SaveContractSession(client);
	
	// Print a specific type of message depending on what type of Contract we're doing.
	char sMessage[128] = "{green}[ZC]{default} You have selected the contract: {lightgreen}\"%s\"{default}. To complete it, ";
	switch (hContract.m_iContractType)
	{
		case Contract_ObjectiveProgress:
		{
			char sAppendText[] = "finish all the objectives.";
			StrCat(sMessage, sizeof(sMessage), sAppendText);
		}
		case Contract_ContractProgress:
		{
			char sAppendText[] = "get %dCP.";
			Format(sAppendText, sizeof(sAppendText), sAppendText, m_hContracts[client].m_iMaxProgress);
			StrCat(sMessage, sizeof(sMessage), sAppendText);
		}
	}
	MC_PrintToChat(client, sMessage, hContract.m_sContractName);

	// Reset our current directory in the Contracker.
	g_Menu_CurrentDirectory[client] = "root";
	return true;
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
		ObjectiveUpdate hUpdate;
		g_ObjectiveUpdateQueue.GetArray(0, hUpdate); // Get the first element of this array.
		g_ObjectiveUpdateQueue.Erase(0); // Erase the first element.

		int client = hUpdate.m_iClient;
		int value = hUpdate.m_iValue;
		int objective_id = hUpdate.m_iObjectiveID;
		char event[MAX_EVENT_SIZE];
		event = hUpdate.m_sEvent;
		char uuid[MAX_UUID_SIZE];
		uuid = hUpdate.m_sUUID;
		
		// Grab the objective from our client's contract.
		Contract hContract;
		GetClientContract(client, hContract);

		// Do our UUID's match?
		// TODO: Event's can trigger late and we might've switched Contracts. Add a failsafe!
		if (!StrEqual(uuid, hContract.m_sUUID) && StrEqual(uuid, m_hOldContract[client].m_sUUID))
		{
			PrintToServer("[ZContracts] Processing late update for %N for contract %s and objective id %d", client, uuid, objective_id);
			ProcessLogicForContractObjective(m_hOldContract[client], objective_id, client, event, value);

			// Get the new progress and completion status for the old contract.
			ContractObjective hOldObjective;
			m_hOldContract[client].GetObjective(objective_id, hOldObjective);
			SaveObjectiveProgressToDB(client, m_hOldContract[client].m_sUUID, objective_id,
			hOldObjective.m_iProgress, hOldObjective.IsObjectiveComplete());
		}
		else
		{
			// Update progress.
			ProcessLogicForContractObjective(hContract, objective_id, client, event, value);
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
 * @param hContract 	Contract struct to grab the objective from.
 * @param objective_id 	ID of the objective to be processed.
 * @param client    	Client index.
 * @param event    		Event to process.
 * @param value			Value to send alongside this event.
 */
public void ProcessLogicForContractObjective(Contract hContract, int objective_id, int client, const char[] event, int value)
{
	// Get our objective.
	ContractObjective hObjective;
	hContract.GetObjective(objective_id, hObjective);

	// TODO: Class check
	// TODO: Weapon check
	// TODO: Map check
	
	// Loop over all of our objectives and see if this event matches.
	for (int i = 0; i < hObjective.m_hEvents.Length; i++)
	{
		ContractObjectiveEvent hEvent;
		hObjective.m_hEvents.GetArray(i, hEvent);
		
		// Does this event match?
		if (StrEqual(hEvent.m_sEventName, event))
		{
			// Do we have a timer going?
			if (hEvent.m_hTimer != INVALID_HANDLE)
			{
				TriggerTimeEvent(hObjective, hEvent, "OnThreshold");
			}
			// Start the timer if it doesn't exist yet.
			else 
			{
				if (hEvent.m_hTimer == INVALID_HANDLE && hEvent.m_fTime != 0.0)
				{
					// Create a datapack for our timer so we can pass our objective and event through.
					DataPack m_hTimerdata;
					
					// Create our timer. (see contracts_timers.sp)
					hEvent.m_hTimer = CreateDataTimer(hEvent.m_fTime, EventTimer, m_hTimerdata, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					m_hTimerdata.WriteCell(client); // Pass through our client so we can get our contract.
					m_hTimerdata.WriteCell(hObjective.m_iInternalID); // Pass through our internal ID so we know which objective to look for.
					m_hTimerdata.WriteCell(hEvent.m_iInternalID); // Pass through the current event index so we know which event we're looking for in our objective.
					// ^^ The reason we do these two things as we can't pass enum structs through into a DataPack.
				}
			}

			// Increment logic.
			int iOldProgress = hObjective.m_iProgress;
			hObjective.TryIncrementProgress(client, hEvent, value);
			hObjective.m_hEvents.SetArray(i, hEvent);
			hContract.SaveObjective(objective_id, hObjective);
		
			// Is our contract now complete?
			if (hContract.IsContractComplete())
			{
				// Print to chat.
				MC_PrintToChat(client,
				"{green}[ZC]{default} Congratulations! You have completed the contract: {lightgreen}\"%s\"{default}.",
				hContract.m_sContractName);

				// Set the client's contract to nothing.
				Contract hBlankContract;
				m_hContracts[client] = hBlankContract;

				// TODO: Save full contract!
			}


			// Print to HUD that we've triggered this event and gained progress.
			if (hObjective.m_iProgress > iOldProgress)
			{
				if (hObjective.m_bInfinite)
				{
					switch (hContract.m_iContractType)
					{
						case Contract_ObjectiveProgress:
						{
							PrintHintText(client, "%s (%s) +%dCP",
							hObjective.m_sDescription, hContract.m_sContractName, hObjective.m_iAward);
						}
						case Contract_ContractProgress:
						{
							PrintHintText(client, "%s (%s [%d/%dCP]) +%dCP",
							hObjective.m_sDescription, hContract.m_sContractName,
							hContract.m_iProgress, hContract.m_iMaxProgress, hObjective.m_iAward);
						}
					}
				}
				else
				{
					PrintHintText(client, "[%d/%dCP] %s (%s) +%dCP", 
					hObjective.m_iProgress, hObjective.m_iMaxProgress, hObjective.m_sDescription,
					hContract.m_sContractName, hObjective.m_iAward);
				}
			}

			// Print that this objective is complete.
			if (hObjective.IsObjectiveComplete())
			{
				// Print to chat.
				MC_PrintToChat(client,
				"{green}[ZC]{default} Congratulations! You have completed the contract objective: {lightgreen}\"%s\"{default}.",
				hObjective.m_sDescription);

				// Update in the database to reflect that we've completed this objective.
				SaveObjectiveProgressToDB(client, hContract.m_sUUID, hObjective.m_iInternalID,
				hObjective.m_iProgress, hObjective.IsObjectiveComplete());
			}
		}
	}
}

// ============ MENU FUNCTIONS ============
/**
 * Creates the global Contracker menu. This reads through the directories
 * list and Contract schema to insert all of the needed items.
**/
public void CreateContractMenu()
{
	// Delete our menu if it exists.
	delete gContractMenu;
	
	gContractMenu = new Menu(ContractMenuHandler, MENU_ACTIONS_ALL);
	gContractMenu.SetTitle("ZContracts - Contract Selector");
	gContractMenu.ExitButton = true;

	// This is a display for the current directory for the client. We will manipulate this
	// in menu logic later.
	gContractMenu.AddItem("#directory", "filler");
	
	// Add our directories to the menu. We'll hide options depending on what
	// we should be able to see.
	if (g_Directories)
	{
		for (int i = 0; i < g_Directories.Length; i++)
		{
			char directory[MAX_DIRECTORY_SIZE];
			g_Directories.GetString(i, directory, sizeof(directory));
			gContractMenu.AddItem(directory, directory);
		}
	}

	// Add all of our contracts to the menu. We'll hide options depending on what
	// we should be able to see.
	if (g_ContractSchema.GotoFirstSubKey())
	{
		do
		{
			char sUUID[MAX_UUID_SIZE];
			g_ContractSchema.GetSectionName(sUUID, sizeof(sUUID));
			char sContractName[MAX_CONTRACT_NAME_SIZE];
			g_ContractSchema.GetString("name", sContractName, sizeof(sContractName), "undefined");
			gContractMenu.AddItem(sUUID, sContractName);
		}
		while(g_ContractSchema.GotoNextKey());
	}
	g_ContractSchema.Rewind();
}

/**
 * By default, all items in the global Contracker will be invisible to the client.
 * The client's current directory will decide which items in the menu should be
 * shown and how to display them.
**/
public int ContractMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		// If we're currently doing this Contract, disable the option to select it.
		case MenuAction_DrawItem:
		{
			int style;
			
			// Grab the item name.
			char sKey[64];
			menu.GetItem(param2, sKey, sizeof(sKey), style);

			// Special directory key:
			if (StrEqual(sKey, "#directory"))
			{	
				return ITEMDRAW_DISABLED;
			}

			// Are we a contract?
			else if (sKey[0] == '{')
			{
				char sDirectory[MAX_DIRECTORY_SIZE];
				GetContractDirectory(sKey, sDirectory);
				// Are we in the right directory?
				if (!StrEqual(sDirectory, g_Menu_CurrentDirectory[param1])) 
				{
					return ITEMDRAW_IGNORE;
				}

				// Are we currently using this contract?
				if (StrEqual(sKey, m_hContracts[param1].m_sUUID)) 
				{
					return ITEMDRAW_DISABLED;
				}
			}
			// Are we a directory instead?
			else
			{
				// Should we be listed inside this directory?
				if (StrContains(sKey, g_Menu_CurrentDirectory[param1]) == -1 ||
				StrEqual(sKey, g_Menu_CurrentDirectory[param1]))
				{
					return ITEMDRAW_IGNORE;
				}
			}
	
			return style;
		}

		// If we're currently doing a Contract, add "(SELECTED)"
		// If the item is a directory, add ">>"
		case MenuAction_DisplayItem:
		{
			char sDisplay[MAX_CONTRACT_NAME_SIZE + 16];
			char sKey[64];
			menu.GetItem(param2, sKey, sizeof(sKey), _, sDisplay, sizeof(sDisplay));

			// Special directory key:
			if (StrEqual(sKey, "#directory"))
			{
				Format(sDisplay, sizeof(sDisplay), "Current Directory: \"%s\"", g_Menu_CurrentDirectory[param1]);
				return RedrawMenuItem(sDisplay);
			}
			// Is this a Contract?
			else if (sKey[0] == '{')
			{
				// Are we doing this Contract?
				Contract hContract;
				GetClientContract(param1, hContract);
				if (StrEqual(hContract.m_sUUID, sKey))
				{
					Format(sDisplay, sizeof(sDisplay), "%s [SELECTED]", sDisplay);
					return RedrawMenuItem(sDisplay);
				}
			}
			// Is this a directory?
			else
			{
				// Remove the current directory from this name.
				int iPosition = StrContains(sDisplay, g_Menu_CurrentDirectory[param1]);
				if (iPosition != -1)
				{
					ReplaceString(sDisplay, sizeof(sDisplay), g_Menu_CurrentDirectory[param1], "");
				}

				Format(sDisplay, sizeof(sDisplay), ">> %s", sDisplay);
				return RedrawMenuItem(sDisplay);
			}
			return 0;
		}
		
		// Select a Contract if we're not doing it.
		case MenuAction_Select:
		{
			char sKey[64];
			menu.GetItem(param2, sKey, sizeof(sKey));

			// Is this a Contract? Select it.
			if (sKey[0] == '{')
			{
				// Are we NOT currently using this contract?
				if (!StrEqual(sKey, m_hContracts[param1].m_sUUID))
				{
					SetClientContract(param1, sKey);	
				}
			}
			// This is a directory instead.
			// Clear our current menu and populate it with new items.
			else
			{
				g_Menu_CurrentDirectory[param1] = sKey;
				gContractMenu.Display(param1, MENU_TIME_FOREVER);
			}
		}

		// Reset our current directory on close.
		case MenuAction_Cancel:
		{	
			g_Menu_CurrentDirectory[param1] = "root";
		}
	}
	return 0;
}

/**
 * Console command that opens up the global Contracker for the client.
 * If a contract is already selected, this will open up the Objective
 * display instead. The Objective display contains an option to
 * open the global Contracker.
**/
public Action OpenContrackerForClient(int client, int args)
{	
	Contract hContract;
	GetClientContract(client, hContract);

	// Are we doing a Contract?
	if (hContract.m_sUUID[0] == '{')
	{
		// Display our objective display instead.
		CreateObjectiveDisplay(client, hContract);
	}
	else
	{
		gContractMenu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}


/**
 * Creates the Objective display for the client. This menu displays
 * all of the objective progress for the selected Contract, as well
 * as providing an option to open the global Contracker.
 * 
 * @param client 		Client index.
 * @param hContract    	Contract struct to grab Objective information from.
**/
public void CreateObjectiveDisplay(int client, Contract hContract)
{
	// Construct our panel for the client.
	delete gContractObjeciveDisplay[client];
	gContractObjeciveDisplay[client] = new Panel();
	gContractObjeciveDisplay[client].SetTitle(hContract.m_sContractName);

	if (hContract.m_iContractType == Contract_ContractProgress)
	{
		char line[256];
		Format(line, sizeof(line), "Progress: [%d/%d]", hContract.m_iProgress, hContract.m_iMaxProgress);
	}

	// TODO: Should we split this up into two pages?
	for (int i = 0; i < hContract.m_hObjectives.Length; i++)
	{
		ContractObjective hObjective;
		hContract.GetObjective(i, hObjective);

		char line[256];
		Format(line, sizeof(line), "Objective #%d: \"%s\" [%d/%d] +%dCP", i+1,
		hObjective.m_sDescription, hObjective.m_iProgress, hObjective.m_iMaxProgress, hObjective.m_iAward);
		gContractObjeciveDisplay[client].DrawText(line);
	}

	// Send this to our client.
	gContractObjeciveDisplay[client].DrawItem("Return to Contracker");
	gContractObjeciveDisplay[client].DrawItem("Close");
	gContractObjeciveDisplay[client].Send(client, ObjectiveDisplayHandler, 20);
}

/**
 * This handles the option to open the global Contracker.
**/
public int ObjectiveDisplayHandler(Menu menu, MenuAction action, int param1, int param2)
{
	// We don't need to do anything here...
	if (action == MenuAction_Select)
    {
		if (param2 == 1)
		{
			gContractMenu.Display(param1, MENU_TIME_FOREVER);
		}
    }
	return 0;
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
	Contract hContract;
	GetClientContract(client, hContract);

	if (args == 0)
	{
		PrintToConsole(client,
			"---------------------------------------------\n"
		... "Contract Name: %s\n"
		... "Contract UUID: %s\n"
		... "Contract Directory: %s\n"
		... "Contract Progress Type: %d\n"
		... "Contract Progress: %d/%d\n"
		... "Contract Objective Count: %d\n"
		... "Is Contract Complete: %d\n"
		... "[INFO] To debug an objective, type sm_debugcontract [objective_index]"
		... "---------------------------------------------",
		hContract.m_sContractName, hContract.m_sUUID, hContract.m_sDirectoryPath, hContract.m_iContractType,
		hContract.m_iProgress, hContract.m_iMaxProgress, hContract.m_hObjectives.Length, hContract.IsContractComplete());
	}
	if (args == 1)
	{
		char sArg[4];
		GetCmdArg(1, sArg, sizeof(sArg));
		int iID = StringToInt(sArg);
		PrintToServer("%d", iID);

		ContractObjective hContractObjective;
		hContract.GetObjective(iID, hContractObjective);

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
		... "Is Objective Complete %d\n"
		... "[INFO] To debug an objective, type sm_debugcontract [objective_index]"
		... "---------------------------------------------",
		hContract.m_sContractName, hContract.m_sUUID, hContract.m_iContractType, hContractObjective.m_bInitalized,
		hContractObjective.m_iInternalID, hContractObjective.m_bInfinite, hContractObjective.m_iAward,
		hContractObjective.m_iProgress, hContractObjective.m_iMaxProgress, hContractObjective.m_hEvents.Length,
		hContractObjective.IsObjectiveComplete());
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
