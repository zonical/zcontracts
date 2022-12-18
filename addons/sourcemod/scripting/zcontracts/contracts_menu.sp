// Menu objects.
static Menu gContractMenu;
Panel gContractObjeciveDisplay[MAXPLAYERS+1];
char g_Menu_CurrentDirectory[MAXPLAYERS+1][MAX_DIRECTORY_SIZE];
int g_Menu_DirectoryDeepness[MAXPLAYERS+1] = { 1, ... };


// ============ MENU FUNCTIONS ============
/**
 * Creates the global Contracker menu. This reads through the directories
 * list and Contract schema to insert all of the needed items.
**/
void CreateContractMenu()
{
	// Delete our menu if it exists.
	delete gContractMenu;
	
	gContractMenu = new Menu(ContractMenuHandler, MENU_ACTIONS_ALL);
	gContractMenu.Pagination = true;
	gContractMenu.SetTitle("ZContracts - Contract Selector");
	gContractMenu.ExitButton = true;
	gContractMenu.ExitBackButton = true;
	gContractMenu.OptionFlags = MENUFLAG_NO_SOUND;

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
int ContractMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		// If we're currently doing this Contract, disable the option to select it.
		case MenuAction_DrawItem:
		{
			int style;
			
			char MenuKey[64]; // UUID
			char MenuDisplay[64]; // Display name
			menu.GetItem(param2, MenuKey, sizeof(MenuKey), style, MenuDisplay, sizeof(MenuDisplay));

			// Special directory key:
			if (StrEqual(MenuKey, "#directory"))
			{	
				return ITEMDRAW_DISABLED;
			}

			// Are we a contract?
			else if (MenuKey[0] == '{')
			{
				char ContractDirectory[MAX_DIRECTORY_SIZE];
				GetContractDirectory(MenuKey, ContractDirectory);
				// Are we in the right directory?
				if (!StrEqual(ContractDirectory, g_Menu_CurrentDirectory[param1])) 
				{
					return ITEMDRAW_IGNORE;
				}

				// Are we currently using this contract?
				if (StrEqual(MenuKey, ClientContracts[param1].m_sUUID)) 
				{
					return ITEMDRAW_DISABLED;
				}
			}
			// Are we a directory instead?
			else
			{
				// Should we be listed inside this directory?
				if (StrContains(MenuKey, g_Menu_CurrentDirectory[param1]) == -1 ||
				StrEqual(MenuKey, g_Menu_CurrentDirectory[param1]))
				{
					return ITEMDRAW_IGNORE;
				}

				// Depending on our deepness, see how many times the slash character shows
				// up in this directory choice. If there's more than there should be, don't
				// show this menu option.
				int slashes = 0;
				for (int i = 0; i < strlen(MenuDisplay); i++)
				{
					char check = MenuDisplay[i];
					if (check == '/') slashes++;
				}
				if (g_Menu_DirectoryDeepness[param1] < slashes) return ITEMDRAW_IGNORE;
			}
	
			return style;
		}

		// If we're currently doing a Contract, add "(SELECTED)"
		// If the item is a directory, add ">>"
		case MenuAction_DisplayItem:
		{
			char MenuDisplay[MAX_CONTRACT_NAME_SIZE + 16];
			char MenuKey[64];
			menu.GetItem(param2, MenuKey, sizeof(MenuKey), _, MenuDisplay, sizeof(MenuDisplay));

			// Special directory key:
			if (StrEqual(MenuKey, "#directory"))
			{
				Format(MenuDisplay, sizeof(MenuDisplay), "Current Directory: \"%s\"", g_Menu_CurrentDirectory[param1]);
				return RedrawMenuItem(MenuDisplay);
			}
			// Is this a Contract?
			else if (MenuKey[0] == '{')
			{
				// Are we doing this Contract?
				Contract ClientContract;
				GetClientContract(param1, ClientContract);
				if (StrEqual(ClientContract.m_sUUID, MenuKey))
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "%s [SELECTED]", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);
				}
			}
			// Is this a directory?
			else
			{
				// Remove the current directory from this name.
				int iPosition = StrContains(MenuDisplay, g_Menu_CurrentDirectory[param1]);
				if (iPosition != -1)
				{
					ReplaceString(MenuDisplay, sizeof(MenuDisplay), g_Menu_CurrentDirectory[param1], "");
				}

				Format(MenuDisplay, sizeof(MenuDisplay), ">> %s", MenuDisplay);
				return RedrawMenuItem(MenuDisplay);
			}
			return 0;
		}
		
		// Select a Contract if we're not doing it.
		case MenuAction_Select:
		{
			char MenuKey[64]; // UUID
			menu.GetItem(param2, MenuKey, sizeof(MenuKey));

			// Is this a Contract? Select it.
			if (MenuKey[0] == '{')
			{
				// Are we NOT currently using this contract?
				if (!StrEqual(MenuKey, ClientContracts[param1].m_sUUID))
				{
					SetClientContract(param1, MenuKey);	
				}
			}
			// This is a directory instead.
			// Clear our current menu and populate it with new items.
			else
			{
				g_Menu_CurrentDirectory[param1] = MenuKey;
				g_Menu_DirectoryDeepness[param1]++;
				gContractMenu.Display(param1, MENU_TIME_FOREVER);

				if (PlayerSoundsEnabled[param1]) EmitGameSoundToClient(param1, "CYOA.StaticFade");
			}
		}

		// Reset our current directory on close.
		case MenuAction_Cancel:
		{	
			g_Menu_CurrentDirectory[param1] = "root";
			g_Menu_DirectoryDeepness[param1] = 1;
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
	Contract ClientContract;
	GetClientContract(client, ClientContract);

	// Are we doing a Contract?
	if (ClientContract.IsContractInitalized())
	{
		// Display our objective display instead.
		CreateObjectiveDisplay(client, ClientContract, false);
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
 * @param ClientContract    	Contract struct to grab Objective information from.
 * @param unknown		If true, progress values will be replaced with "?"
**/
void CreateObjectiveDisplay(int client, Contract ClientContract, bool unknown)
{
	// Construct our panel for the client.
	delete gContractObjeciveDisplay[client];
	gContractObjeciveDisplay[client] = new Panel();
	char PanelTitle[128] = "\"%s\"";
	Format(PanelTitle, sizeof(PanelTitle), PanelTitle, ClientContract.m_sContractName);
	gContractObjeciveDisplay[client].SetTitle(PanelTitle);

	if (!unknown && PlayerSoundsEnabled[client]) EmitGameSoundToClient(client, "CYOA.NodeActivate");

	switch (ClientContract.m_iContractType)
	{
		case Contract_ContractProgress:
		{
			char ContractGoal[128] = "To complete this Contract, get %d CP.";
			Format(ContractGoal, sizeof(ContractGoal), ContractGoal, ClientContract.m_iMaxProgress);
			gContractObjeciveDisplay[client].DrawText(ContractGoal);

			char ContractProgress[256];
			Format(ContractProgress, sizeof(ContractProgress), "Progress: [%d/%d]", ClientContract.m_iProgress, ClientContract.m_iMaxProgress);
			if (unknown)
			{
				Format(ContractProgress, sizeof(ContractProgress), "Progress: [?/%d]", ClientContract.m_iMaxProgress);
			}
			gContractObjeciveDisplay[client].DrawText(ContractProgress);
			gContractObjeciveDisplay[client].DrawText(" ");
		}
		case Contract_ObjectiveProgress:
		{
			char ContractGoal[128];
			if (ClientContract.m_hObjectives.Length == 1)
			{
				ContractGoal = "To complete this Contract, complete %d objective.\n";
			}
			else
			{
				ContractGoal = "To complete this Contract, complete %d objectives.\n";
			}
			
			Format(ContractGoal, sizeof(ContractGoal), ContractGoal, ClientContract.m_hObjectives.Length);
			gContractObjeciveDisplay[client].DrawText(ContractGoal);
			gContractObjeciveDisplay[client].DrawText(" ");
		}
	}

	// TODO: Should we split this up into two pages?
	for (int i = 0; i < ClientContract.m_hObjectives.Length; i++)
	{
		ContractObjective Objective;
		ClientContract.GetObjective(i, Objective);

		char line[256];
		if (Objective.m_bInfinite)
		{
			Format(line, sizeof(line), "Objective #%d: \"%s\" +%dCP", i+1,
			Objective.m_sDescription, Objective.m_iAward);
		}
		else
		{
			switch (ClientContract.m_iContractType)
			{
				case Contract_ObjectiveProgress:
				{
					Format(line, sizeof(line), "Objective #%d: \"%s\" [%d/%d]", i+1,
					Objective.m_sDescription, Objective.m_iProgress, Objective.m_iMaxProgress);
					
					if (unknown)
					{
						Format(line, sizeof(line), "Objective #%d: \"%s\" [?/%d]", i+1,
						Objective.m_sDescription, Objective.m_iMaxProgress);
					}

				}
				case Contract_ContractProgress:
				{
					Format(line, sizeof(line), "Objective #%d: \"%s\" [%d/%d] +%dCP", i+1,
					Objective.m_sDescription, Objective.m_iProgress, Objective.m_iMaxProgress, Objective.m_iAward);
					if (unknown)
					{
						Format(line, sizeof(line), "Objective #%d: \"%s\" [?/%d] +%dCP", i+1,
						Objective.m_sDescription, Objective.m_iMaxProgress, Objective.m_iAward);				
					}
				}
			}
		}
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
