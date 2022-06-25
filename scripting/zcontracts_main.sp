#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <morecolors>

#include <zcontracts/zcontracts>

#pragma semicolon 1

#include "zcontracts/contracts_schema.sp"
#include "zcontracts/contracts_events.sp"
#include "zcontracts/contracts_timers.sp"

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
	// Initalization.
	HookEvents();	
	ProcessContractsSchema();
	CreateContractMenu();
	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		OnClientPostAdminCheck(i);
	}
	
	RegServerCmd("sm_reloadcontracts", ReloadContracts);
	RegConsoleCmd("sm_setcontract", DebugSetContract);

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

public Action DebugSetContract(int client, int args)
{	
	// Grab UUID.
	char sUUID[64];
	GetCmdArg(1, sUUID, sizeof(sUUID));
	PrintToChat(client, "Setting contract: %s", sUUID);
	
	SetClientContract(client, sUUID);
	return Plugin_Handled;
}

public Action ReloadContracts(int args)
{
	ProcessContractsSchema();
	CreateContractMenu();
}

// Grabs a client's contract.
public any Native_GetClientContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsClientValid(client)) return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
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
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	Contract hContract;
	GetClientContract(client, hContract);
	
	// Do we have a contract currently active?
	if (hContract.m_sUUID[0] != '{') return false;
	if (hContract.IsContractComplete()) return false;

	// Try to increment all of our objectives.
	for (int i = 0; i < MAX_CONTRACT_OBJECTIVES; i++)
	{
		ContractObjective hContractObjective;
		hContract.m_hObjectives.GetArray(i, hContractObjective);
		if (!hContractObjective.m_bInitalized) continue;
		if (hContractObjective.IsObjectiveComplete()) continue;

		TryIncrementObjectiveProgress(hContractObjective, client, event, value);
		hContract.m_hObjectives.SetArray(i, hContractObjective);
	}

	return true;
}

// Activates a contract for the player.
public any Native_SetClientContract(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char sUUID[MAX_EVENT_SIZE];
	GetNativeString(2, sUUID, sizeof(sUUID));

	// Are we a bot?
	if (!IsClientValid(client) || IsFakeClient(client)) 
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	if (GetContractDefinition(sUUID, m_hContracts[client]))
	{
		MC_PrintToChat(client,
		"{green}[ZC]{default} You have selected the contract: {lightgreen}\"%s\"{default}. To complete it, finish all the objectives.",
		m_hContracts[client].m_sContractName);
		
		// Print our objectives to chat.
		for (int i = 0; i < MAX_CONTRACT_OBJECTIVES; i++)
		{
			ContractObjective hContractObjective;
			m_hContracts[client].m_hObjectives.GetArray(i, hContractObjective);
			if (!hContractObjective.m_bInitalized) continue;
			PrintContractObjective(client, hContractObjective);
		}

		// Reset our current directory in the Contracker.
		g_Menu_CurrentDirectory[client] = "root";
		return true;
	}
	else
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID for client (%s): (%d)", sUUID, client);
	}
}

// Prints a Contract Objective to the player in chat.
public void PrintContractObjective(int client, ContractObjective hObjective)
{
	// Print our objective.
	if (hObjective.m_bInitalized)
	{
		char objectiveString[128] = "{green}[ZC]{default} Objective: {lightgreen}\"%s\"{default}";
		Format(objectiveString, sizeof(objectiveString), objectiveString, hObjective.m_sDescription);
		if (!hObjective.m_bInfinite)
		{
			StrCat(objectiveString, sizeof(objectiveString), " [%d/%d]");
			Format(objectiveString, sizeof(objectiveString), objectiveString, 
			hObjective.m_iProgress, hObjective.m_iMaxProgress);
		}
		
		MC_PrintToChat(client, objectiveString);
	}
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
			// Add to our event threshold.
			hEvent.m_iCurrentThreshold += value;
			
			// Do we have a timer going?
			if (hEvent.m_hTimer != INVALID_HANDLE) 
				TriggerTimeEvent(hObjective, hEvent, "OnThreshold");
			else 
				hEvent.StartTimer(i, client, event, value);
			
			// Increment logic.
			hObjective.TryIncrementProgress(client, hEvent);
			hObjective.m_hEvents.SetArray(i, hEvent);

			// Print that this objective is complete.
			if (hObjective.IsObjectiveComplete())
			{
				// Print to HUD that we've completed this objective.
				switch (hContract.m_iContractType)
				{
					case Contract_ObjectiveProgress:
						PrintHintText(client, "Objective Completed: %s (%s)", hObjective.m_sDescription, hContract.m_sContractName);
					
					case Contract_ContractProgress:
						PrintHintText(client, "Objective Completed: %s (%s) [%d/%d]", 
						hObjective.m_sDescription, hContract.m_sContractName,
						hContract.m_iProgress, hContract.m_iMaxProgress);
				}
			}
			else
			{
				// If we have any exclusive text for this event that we've triggered, then display it.
				char sDescriptionText[128];
				if (!StrEqual(hEvent.m_sExclusiveDescription, "")) 
					sDescriptionText = hEvent.m_sExclusiveDescription;
				else 
					sDescriptionText = hObjective.m_sDescription;
				
				// Print to HUD that we've triggered this event.
				if (hObjective.m_bInfinite)
				{
					switch (hContract.m_iContractType)
					{
						case Contract_ObjectiveProgress:
							PrintHintText(client, "%s (%s) +%dCP",
							sDescriptionText, hContract.m_sContractName, hEvent.m_iAward);
						
						case Contract_ContractProgress:
							PrintHintText(client, "[%d/%d] %s (%s) +%dCP",
							hContract.m_iProgress, hContract.m_iMaxProgress,
							sDescriptionText, hContract.m_sContractName, hEvent.m_iAward);
					}
				}
				else
				{
					PrintHintText(client, "[%d/%d] %s (%s) +%dCP", 
					hObjective.m_iProgress, hObjective.m_iMaxProgress, sDescriptionText,
					hContract.m_sContractName, hEvent.m_iAward);
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
	}
}

// ============ MENU FUNCTIONS ============
static Menu gContractMenu;
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
	if (g_Contracts)
	{
		for (int i = 0; i < g_Contracts.Length; i++)
		{
			Contract hContract;
			g_Contracts.GetArray(i, hContract, sizeof(Contract));
			gContractMenu.AddItem(hContract.m_sUUID, hContract.m_sContractName);
		}
	}
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
				Contract hContract;
				GetContractDefinition(sKey, hContract);
				// Are we in the right directory?
				if (!StrEqual(hContract.m_sDirectoryPath, g_Menu_CurrentDirectory[param1])) 
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

// ============ UTILITY FUNCTIONS ============

stock int Int_Min(int a, int b) { return a < b ? a : b; }