#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <morecolors>

#include <zcontracts/zcontracts>

#pragma semicolon 1

Database g_DB;
Panel gContractObjeciveDisplay[MAXPLAYERS+1];
static Menu gContractMenu;

#include "zcontracts/contracts_schema.sp"
#include "zcontracts/contracts_events.sp"
#include "zcontracts/contracts_timers.sp"
#include "zcontracts/contracts_db.sp"

// TODO: Save Contract style progress.
// TODO: Timed interval for database saving. 
	// 	(either end of either round or 60 seconds)
// TODO: CSGO testing.
// TODO: Implement more game events.
// TODO: Move debug functions to their own file.
// TODO: Implement team restrictions for contracts.
	// (e.g red, blu, terrorists, counterterrorists + aliases)
// TODO: Documentation!!.


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
	// Register ConVars
	// These three are defined in contracts_schema.sp
	g_ConfigSearchPath = CreateConVar("zc_contract_search_path", "configs/zcontracts", "The path, relative to the \"sourcemods/\" directory, to find Contract definition files. Changing this Value will cause a reload of the Contract schema.");
	g_RequiredFileExt = CreateConVar("zc_required_file_ext", ".txt", "The file extension that Contract definition files must have in order to be considered valid. Changing this Value will cause a reload of the Contract schema.");
	g_DisabledPath = CreateConVar("zc_disabled_path", "configs/zcontracts/disabled", "If a search path has this string in it, any Contract's loaded in or derived from this path will not be loaded. Changing this Value will cause a reload of the Contract schema.");
	g_ConfigSearchPath.AddChangeHook(OnSchemaConVarChange);
	g_RequiredFileExt.AddChangeHook(OnSchemaConVarChange);
	g_DisabledPath.AddChangeHook(OnSchemaConVarChange);

	// Initalization.
	HookEvents();	
	ProcessContractsSchema();
	CreateContractMenu();

	// Connect to our database.
	Database.Connect(GotDatabase, "zcontracts");

	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		OnClientPostAdminCheck(i);
	}
	
	RegConsoleCmd("sm_setcontract", DebugSetContract);
	RegConsoleCmd("sm_debugcontract", DebugContractInfo);
	RegConsoleCmd("sm_debug_getprogress", DebugGetProgress);

	RegServerCmd("sm_reloadcontracts", ReloadContracts);
	RegConsoleCmd("sm_contract", OpenContrackerForClient);
	RegConsoleCmd("sm_contracts", OpenContrackerForClient);
	RegConsoleCmd("sm_c", OpenContrackerForClient);
}

Contract m_hContracts[MAXPLAYERS+1];
char g_Menu_CurrentDirectory[MAXPLAYERS+1][MAX_DIRECTORY_SIZE];

public void OnClientPostAdminCheck(int client)
{
	// Reset variables.
	Contract hBlankContract;
	m_hContracts[client] = hBlankContract;
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

// Grabs a client's contract.
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

// Calls a contracker event and changes data for the clients contract.
public any Native_CallContrackerEvent(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char event[MAX_EVENT_SIZE];
	GetNativeString(2, event, sizeof(event));
	int value = GetNativeCell(3); 

	// Are we a bot?
	if (!IsClientValid(client) || IsFakeClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

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
		hContract.m_hObjectives.GetArray(i, hContractObjective);

		// Don't touch this objective if it shouldn't be doing anything.
		if (!hContractObjective.m_bInitalized || hContractObjective.IsObjectiveComplete()) 
		{
			continue;
		}
		TryIncrementObjectiveProgress(hContractObjective, client, event, value);
		hContract.m_hObjectives.SetArray(i, hContractObjective);
	}

	return true;
}

// Activates a contract for the player.
public any Native_SetClientContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	char sUUID[MAX_UUID_SIZE];
	GetNativeString(2, sUUID, sizeof(sUUID));

	// Are we a bot?
	if (!IsClientValid(client) || IsFakeClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}

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

public void TryIncrementObjectiveProgress(ContractObjective hObjective, int client, const char[] event, int value)
{
	Contract hContract;
	GetClientContract(client, hContract);

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
			// Increment logic.
			hObjective.TryIncrementProgress(client, hEvent, value);
			hObjective.m_hEvents.SetArray(i, hEvent);

			// Print that this objective is complete.
			if (hObjective.IsObjectiveComplete())
			{
				PrintHintText(client, "Contract Objective Completed: %s (%s)", hObjective.m_sDescription, hContract.m_sContractName);
				// Update in the database to reflect that we've completed this objective.
				SaveObjectiveProgressToDB(client, hContract.m_sUUID, hObjective);
			}
			else
			{
				// Print to HUD that we've triggered this event.
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
		}
	}

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

		// TODO: Save contract!
	}
}

// ============ MENU FUNCTIONS ============
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

// Our menu handler.
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
				Format(sDisplay, sizeof(sDisplay), "Current Directory: %s", g_Menu_CurrentDirectory[param1]);
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

public Action OpenContrackerForClient(int client, int args)
{	
	gContractMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

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

	// Print our objectives.
	// TODO: Should we split this up into two pages?
	for (int i = 0; i < hContract.m_hObjectives.Length; i++)
	{
		ContractObjective hObjective;
		hContract.m_hObjectives.GetArray(i, hObjective);

		char line[256];
		Format(line, sizeof(line), "Objective #%d: \"%s\" [%d/%d] +%dCP", i+1,
		hObjective.m_sDescription, hObjective.m_iProgress, hObjective.m_iMaxProgress, hObjective.m_iAward);
		gContractObjeciveDisplay[client].DrawText(line);
	}

	gContractObjeciveDisplay[client].DrawItem("Return to Contracker");
	gContractObjeciveDisplay[client].DrawItem("Close");
	gContractObjeciveDisplay[client].Send(client, ObjectiveDisplayHandler, 20);
}

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

public Action DebugSetContract(int client, int args)
{	
	// Grab UUID.
	char sUUID[64];
	GetCmdArg(1, sUUID, sizeof(sUUID));
	PrintToChat(client, "Setting contract: %s", sUUID);
	
	SetClientContract(client, sUUID);
	return Plugin_Handled;
}

public Action DebugContractInfo(int client, int args)
{	
	// Grab UUID.
	char sUUID[64];
	GetCmdArg(1, sUUID, sizeof(sUUID));
	Contract hContract;
	CreateContractFromUUID(sUUID, hContract);
	PrintToConsole(client, "See server console for output.");

	if (args == 1)
	{
		PrintToServer(
			"---------------------------------------------"
		... "Contract Name: %s\n"
		... "Contract UUID: %s\n"
		... "Contract Directory: %s\n"
		... "Contract Progress Type: %d\n"
		... "Contract Progress: %d/%d\n"
		... "Contract Objective Count: %d\n"
		... "Is Contract Complete: %d\n"
		... "[INFO] To debug an objective, type sm_debugcontract [UUID] [objective_index]"
		... "---------------------------------------------",
		hContract.m_sContractName, hContract.m_sUUID, hContract.m_sDirectoryPath, hContract.m_iContractType,
		hContract.m_iProgress, hContract.m_iMaxProgress, hContract.m_hObjectives.Length, hContract.IsContractComplete());
	}
	if (args == 2)
	{
		char sArg[4];
		GetCmdArg(2, sArg, sizeof(sArg));
		int iID = StringToInt(sArg);
		PrintToServer("%d", iID);

		ContractObjective hContractObjective;
		hContract.m_hObjectives.GetArray(iID, hContractObjective);

		PrintToServer(
			"---------------------------------------------"
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
		... "[INFO] To debug an objective, type sm_debugcontract [UUID] [objective_index]"
		... "---------------------------------------------",
		hContract.m_sContractName, hContract.m_sUUID, hContract.m_iContractType, hContractObjective.m_bInitalized,
		hContractObjective.m_iInternalID, hContractObjective.m_bInfinite, hContractObjective.m_iAward,
		hContractObjective.m_iProgress, hContractObjective.m_iMaxProgress, hContractObjective.m_hEvents.Length,
		hContractObjective.IsObjectiveComplete());
	}
	
	return Plugin_Handled;
}

// ============ UTILITY FUNCTIONS ============

stock int Int_Min(int a, int b) { return a < b ? a : b; }