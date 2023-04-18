// Menu objects.
static Menu gContractMenu;
Panel gContractObjeciveDisplay[MAXPLAYERS+1];
Panel gHelpDisplay[MAXPLAYERS+1];
Panel gRepeatDisplay[MAXPLAYERS+1];
char g_RepeatUUID[MAXPLAYERS+1][MAX_UUID_SIZE];
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
	char MenuTitle[128] = "ZContracts %s - Contract Selector";
	Format(MenuTitle, sizeof(MenuTitle), MenuTitle, PLUGIN_VERSION);
	gContractMenu.SetTitle(MenuTitle);
	gContractMenu.OptionFlags = MENUFLAG_NO_SOUND | MENUFLAG_BUTTON_EXIT;
	
	// This is a display for the current directory for the client. We will manipulate this
	// in menu logic later.
	gContractMenu.AddItem("#directory", "filler");
	gContractMenu.AddItem("$back", "<< Previous Directory");
	
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
			
			char MenuKey[MAX_UUID_SIZE]; // UUID
			char MenuDisplay[MAX_NAME_LENGTH+32]; // Display name (+32 for anything else added after the name)
			menu.GetItem(param2, MenuKey, sizeof(MenuKey), style, MenuDisplay, sizeof(MenuDisplay));

			// Special directory key:
			if (StrEqual(MenuKey, "#directory"))
			{	
				return ITEMDRAW_DISABLED;
			}
			// If we're in the root key, do not draw.
			else if (StrEqual(MenuKey, "$back") && StrEqual(g_Menu_CurrentDirectory[param1], "root"))
			{
				return ITEMDRAW_IGNORE;
			}

			// Are we a contract?
			else if (MenuKey[0] == '{')
			{
				Contract ClientContract;
				GetClientContract(param1, ClientContract);

				char ContractDirectory[MAX_DIRECTORY_SIZE];
				GetContractDirectory(MenuKey, ContractDirectory);
				// Are we in the right directory?
				if (!StrEqual(ContractDirectory, g_Menu_CurrentDirectory[param1])) 
				{
					return ITEMDRAW_IGNORE;
				}

				// Are we currently using this contract?
				if (StrEqual(MenuKey, ClientContract.m_sUUID)) 
				{
					if (g_RepeatContracts.BoolValue && ClientContract.IsContractComplete())
					{
						return ITEMDRAW_DEFAULT;
					}
					else return ITEMDRAW_DISABLED;
				}
			}
			// Any special options.
			else if (MenuKey[0] == '$') return ITEMDRAW_DEFAULT;
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
				char ShorterDirectory[MAX_DIRECTORY_SIZE];
				ShortenDirectoryString(g_Menu_CurrentDirectory[param1], ShorterDirectory, sizeof(ShorterDirectory));
				Format(MenuDisplay, sizeof(MenuDisplay), "Current Directory: \"%s\"", ShorterDirectory);
				return RedrawMenuItem(MenuDisplay);
			}
			// Back button.
			else if (StrEqual(MenuKey, "$back"))
			{
				// Construct previous directory.
				char PreviousDirectory[MAX_DIRECTORY_SIZE];
				GetPreviousDirectory(g_Menu_CurrentDirectory[param1], PreviousDirectory, sizeof(PreviousDirectory));
				char FancyDirectory[MAX_DIRECTORY_SIZE];
				// Shorten previous directory.
				ShortenDirectoryString(PreviousDirectory, FancyDirectory, sizeof(FancyDirectory));
				// Remove the last slash.
				int pos = strlen(FancyDirectory) - 1;
				FancyDirectory[pos] = '\0';

				Format(MenuDisplay, sizeof(MenuDisplay), "<< Previous Directory: \"%s\"", FancyDirectory);
				return RedrawMenuItem(MenuDisplay);
			}
			// Is this a Contract?
			else if (MenuKey[0] == '{')
			{
				Contract ClientContract;
				GetClientContract(param1, ClientContract);

				if (IsContractLockedForClient(param1, MenuKey))
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "[X] %s", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);		
				}

				if (HasClientCompletedContract(param1, MenuKey))
				{
					if (g_RepeatContracts.BoolValue && g_DisplayCompletionsInMenu.BoolValue)
					{
						CompletedContractInfo info;
						CompletedContracts[param1].GetArray(MenuKey, info, sizeof(CompletedContractInfo));
						Format(MenuDisplay, sizeof(MenuDisplay), "[✓/ %d] %s", info.m_iCompletions, MenuDisplay);
					}
					else
					{
						Format(MenuDisplay, sizeof(MenuDisplay), "[✓] %s", MenuDisplay);
					}
					
					return RedrawMenuItem(MenuDisplay);
				}

				if (StrEqual(ClientContract.m_sUUID, MenuKey))
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "%s [ACTIVE]", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);
				}

				// None of the conditions above are valid. Just display nothing.
				Format(MenuDisplay, sizeof(MenuDisplay), "[   ] %s", MenuDisplay);
				return RedrawMenuItem(MenuDisplay);

			}
			// Any special options.
			else if (MenuKey[0] == '$') return 0;
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
		}
		
		// Select a Contract if we're not doing it.
		case MenuAction_Select:
		{
			char MenuKey[MAX_UUID_SIZE]; // UUID
			menu.GetItem(param2, MenuKey, sizeof(MenuKey));

			// Is this a Contract? Select it.
			if (MenuKey[0] == '{')
			{
				// Can we activate this contract?
				if (IsContractLockedForClient(param1, MenuKey))
				{
					CreateLockedContractMenu(param1, MenuKey);
				}

				// If we're allowed to repeat Contracts, allow us to repeat
				// our currently selected contract if it's completed.
				else if (g_RepeatContracts.BoolValue && 
				StrEqual(MenuKey, ClientContracts[param1].m_sUUID) &&
				ClientContracts[param1].IsContractComplete())
				{
					CompletedContractInfo info;
					CompletedContracts[param1].GetArray(ClientContracts[param1].m_sUUID, info, sizeof(CompletedContractInfo));
					if (!info.m_bReset)
					{
						ConstructRepeatContractPanel(param1, ClientContracts[param1].m_sUUID);
					}
					else 
					{
						SetClientContract(param1, MenuKey);	
					}
				}
				else if (g_RepeatContracts.BoolValue &&
				HasClientCompletedContract(param1, MenuKey))
				{
					CompletedContractInfo info;
					CompletedContracts[param1].GetArray(MenuKey, info, sizeof(CompletedContractInfo));
					if (!info.m_bReset)
					{
						ConstructRepeatContractPanel(param1, MenuKey);
					}
					else 
					{
						SetClientContract(param1, MenuKey);	
					}
				}
				// Are we NOT currently using this contract?
				else if (!StrEqual(MenuKey, ClientContracts[param1].m_sUUID))
				{
					SetClientContract(param1, MenuKey);	
				}
			}
			// Head back.
			else if (StrEqual(MenuKey, "$back"))
			{
				// Construct previous directory.
				char PreviousDirectory[MAX_DIRECTORY_SIZE];
				GetPreviousDirectory(g_Menu_CurrentDirectory[param1], PreviousDirectory, sizeof(PreviousDirectory));

				// Remove the last slash.
				int pos = strlen(PreviousDirectory) - 1;
				if (pos > 0) PreviousDirectory[pos] = '\0';

				g_Menu_CurrentDirectory[param1] = PreviousDirectory;
				g_Menu_DirectoryDeepness[param1]--;
				gContractMenu.Display(param1, MENU_TIME_FOREVER);

				if (PlayerSoundsEnabled[param1] == Sounds_Enabled) EmitGameSoundToClient(param1, SelectOptionSound);
			}
			// This is a directory instead.
			// Clear our current menu and populate it with new items.
			else
			{
				g_Menu_CurrentDirectory[param1] = MenuKey;
				g_Menu_DirectoryDeepness[param1]++;
				gContractMenu.Display(param1, MENU_TIME_FOREVER);

				if (PlayerSoundsEnabled[param1] == Sounds_Enabled) EmitGameSoundToClient(param1, SelectOptionSound);
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
public Action OpenContrackerForClientCmd(int client, int args)
{	
	if (PlayerHelpTextEnabled[client])
	{
		ConstructHelpPanel(client);
	}
	else
	{
		OpenContrackerForClient(client);
	}
	return Plugin_Handled;
}

void OpenContrackerForClient(int client)
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
	if (!unknown && PlayerSoundsEnabled[client] == Sounds_Enabled) EmitGameSoundToClient(client, ProgressLoadedSound);

	// Construct our panel for the client.
	delete gContractObjeciveDisplay[client];
	gContractObjeciveDisplay[client] = new Panel();
	char PanelTitle[128] = "\"%s\" || ";
	Format(PanelTitle, sizeof(PanelTitle), PanelTitle, ClientContract.m_sContractName);
	
	// Draw difficulty text.
	char Difficulty[32] = "Difficulty: ";
	for (int i = 0; i < ClientContract.m_iDifficulty; i++)
	{
		StrCat(Difficulty, sizeof(Difficulty), "%s");
		Format(Difficulty, sizeof(Difficulty), Difficulty, "★");
	}
	//gContractObjeciveDisplay[client].DrawText(Difficulty);
	StrCat(PanelTitle, sizeof(PanelTitle), Difficulty);
	gContractObjeciveDisplay[client].SetTitle(PanelTitle);

	// Display the amount of times we've completed this Contract.
	if (g_RepeatContracts.BoolValue)
	{
		CompletedContractInfo info;
		CompletedContracts[client].GetArray(ClientContract.m_sUUID, info, sizeof(CompletedContractInfo));
		char text[64] = "Completions: %d";
		Format(text, sizeof(text), text, info.m_iCompletions);
		gContractObjeciveDisplay[client].DrawText(text);
		gContractObjeciveDisplay[client].DrawText(" ");
	}

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
	
	gContractObjeciveDisplay[client].DrawText(" ");

	// Send this to our client.
	gContractObjeciveDisplay[client].DrawItem("Open Contracker");
	gContractObjeciveDisplay[client].DrawItem("Close");
	gContractObjeciveDisplay[client].Send(client, ObjectiveDisplayHandler, 20);
}

/**
 * This handles the option to open the global Contracker.
**/
public int ObjectiveDisplayHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
    {
		if (param2 == 1)
		{
			gContractMenu.Display(param1, MENU_TIME_FOREVER);
		}
    }
	return 0;
}

void ConstructHelpPanel(int client)
{
	gHelpDisplay[client] = new Panel();
	gHelpDisplay[client].SetTitle("ZContracts - Help Page");
	gHelpDisplay[client].DrawText("Welcome to ZContracts - a custom Contracker implementation."); 
	gHelpDisplay[client].DrawText("To select a Contract, press the corresponding menu option.");
	gHelpDisplay[client].DrawText("Completed Contracts are marked with [✓], locked Contracts are maked with [X]")
	gHelpDisplay[client].DrawText("Directories are notated with \">>\". They contain more Contracts inside.");
	gHelpDisplay[client].DrawText("If you wish to disable the HUD or sounds, type \"/zcpref\" in chat.");
	gHelpDisplay[client].DrawText(" ");
	gHelpDisplay[client].DrawItem("Take me to the Contracker and never show this again!");
	gHelpDisplay[client].DrawItem("Take me to the Contracker, but show this when I open it again.");
	gHelpDisplay[client].DrawItem("Close this display.");

	gHelpDisplay[client].Send(client, HelpPanelHandler, MENU_TIME_FOREVER);
}

public int HelpPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		if (param2 == 1)
		{
			PlayerHelpTextEnabled[param1] = !PlayerHelpTextEnabled[param1];
			if (g_DB != null) SaveClientPreferences(param1);
			OpenContrackerForClient(param1);
		}
		if (param2 == 2)
		{
			OpenContrackerForClient(param1);
		} 
	}
	return 0;
}

public Action OpenHelpPanelCmd(int client, int args)
{
	ConstructHelpPanel(client);
	return Plugin_Handled;
}

void CreateLockedContractMenu(int client, char UUID[MAX_UUID_SIZE])
{
	// Grab the Contract from the schema.
	KeyValues LockedContract = new KeyValues("Contract");
	if (!g_ContractSchema.JumpToKey(UUID))
	{
		// How the hell did we get here?
		ThrowError("%N somehow selected an invalid, locked Contract!? UUID: %s", client, UUID);
	}
	KvCopySubkeys(g_ContractSchema, LockedContract);
	g_ContractSchema.Rewind();

	Menu ClientMenu = new Menu(LockedContractMenuHandler, MENU_ACTIONS_ALL);
	char ContractNameText[MAX_CONTRACT_NAME_SIZE + 32] = "\"%s\" cannot be activated.";
	char ContractName[MAX_CONTRACT_NAME_SIZE];
	LockedContract.GetString("name", ContractName, sizeof(ContractName));
	Format(ContractNameText, sizeof(ContractNameText), ContractNameText, ContractName);

	ClientMenu.SetTitle("ZContracts - Locked Contract");
	ClientMenu.AddItem("#message1", ContractNameText);
	ClientMenu.AddItem("#message2", "You have not completed the prerequisite Contracts.");
	ClientMenu.AddItem("#message3", "You can select a Contract directly from this list.");

	// Get a list of contracts that are required to be completed before
	// this one can be activated.
	if (LockedContract.JumpToKey("required_contracts", false))
	{
		int Value = 0;
		for (;;)
		{
			char ValueStr[4];
			char ContractUUID[MAX_UUID_SIZE];
			IntToString(Value, ValueStr, sizeof(ValueStr));
			LockedContract.GetString(ValueStr, ContractUUID, sizeof(ContractUUID), "{}");

			// If we reach a blank UUID, we're at the end of the list.
			if (StrEqual("{}", ContractUUID)) break;

			// Grab the name of this Contract.
			if (!g_ContractSchema.JumpToKey(ContractUUID)) continue;
			char DisplayName[MAX_CONTRACT_NAME_SIZE];
			g_ContractSchema.GetString("name", DisplayName, sizeof(DisplayName));
			g_ContractSchema.Rewind();

			ClientMenu.AddItem(ContractUUID, DisplayName);
			Value++;
		}
	}
	ClientMenu.Display(client, MENU_TIME_FOREVER);
	delete LockedContract;
}

int LockedContractMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		// If we're currently doing this Contract, disable the option to select it.
		case MenuAction_DrawItem:
		{
			int style;
			
			char MenuKey[MAX_UUID_SIZE]; // UUID
			char MenuDisplay[MAX_NAME_LENGTH+32]; // Display name (+32 for anything else added after the name)
			menu.GetItem(param2, MenuKey, sizeof(MenuKey), style, MenuDisplay, sizeof(MenuDisplay));

			// Are we a contract?
			if (MenuKey[0] == '{')
			{
				Contract ClientContract;
				GetClientContract(param1, ClientContract);

				// Are we currently using this contract?
				if (StrEqual(MenuKey, ClientContract.m_sUUID)) 
				{
					return ITEMDRAW_DISABLED;
				}
			}
			// Are we display text?
			if (MenuKey[0] == '#') return ITEMDRAW_DISABLED;

			return style;
		}

		// If we're currently doing a Contract, add "(ACTIVE)"
		// If the item is a directory, add ">>"
		case MenuAction_DisplayItem:
		{
			char MenuDisplay[MAX_CONTRACT_NAME_SIZE + 16];
			char MenuKey[64];
			menu.GetItem(param2, MenuKey, sizeof(MenuKey), _, MenuDisplay, sizeof(MenuDisplay));

			// Is this a Contract?
			if (MenuKey[0] == '{')
			{
				Contract ClientContract;
				GetClientContract(param1, ClientContract);

				// Are we doing this Contract?
				if (StrEqual(ClientContract.m_sUUID, MenuKey))
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "%s [ACTIVE]", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);
				}
				if (IsContractLockedForClient(param1, MenuKey))
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "[X] %s", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);		
				}
				if (HasClientCompletedContract(param1, MenuKey))
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "[✓] %s", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);
				}
				else
				{
					Format(MenuDisplay, sizeof(MenuDisplay), "[   ] %s", MenuDisplay);
					return RedrawMenuItem(MenuDisplay);
				}
			}
		}
		
		// Select a Contract if we're not doing it.
		case MenuAction_Select:
		{
			char MenuKey[64]; // UUID
			menu.GetItem(param2, MenuKey, sizeof(MenuKey));

			// Is this a Contract? Select it.
			if (MenuKey[0] == '{')
			{
				// Can we activate this contract?
				if (IsContractLockedForClient(param1, MenuKey))
				{
					CreateLockedContractMenu(param1, MenuKey);
					delete menu;
				}
				// Are we NOT currently using this contract?
				else if (!StrEqual(MenuKey, ClientContracts[param1].m_sUUID))
				{
					SetClientContract(param1, MenuKey);	
				}
				
			}
		}

		// Reset our current directory on close.
		case MenuAction_Cancel:
		{	
			g_Menu_CurrentDirectory[param1] = "root";
			g_Menu_DirectoryDeepness[param1] = 1;
			gContractMenu.Display(param1, MENU_TIME_FOREVER);
		}
	}
	return 0;
}

void ConstructRepeatContractPanel(int client, const char[] UUID)
{
	gRepeatDisplay[client] = new Panel();
	gRepeatDisplay[client].SetTitle("ZContracts - Repeat Contract");

	// Grab the Contract name with a little bit of schema tomfoolery.
	if (!g_ContractSchema.JumpToKey(UUID))
	{
		ThrowError("How the fuck did we get here?");
	}
	char ContractName[MAX_CONTRACT_NAME_SIZE];
	g_ContractSchema.GetString("name", ContractName, sizeof(ContractName));
	g_ContractSchema.Rewind();

	char PromptText[128] = "Do you wish to reset your progress for \"%s\"";
	Format(PromptText, sizeof(PromptText), PromptText, ContractName);
	gRepeatDisplay[client].DrawText(PromptText); 
	gRepeatDisplay[client].DrawText("and activate the Contract?");
	gRepeatDisplay[client].DrawText(" ");
	gRepeatDisplay[client].DrawText("NOTE: The Contract will still be marked as completed");
	gRepeatDisplay[client].DrawText("when you reopen the Contracker.");
	gRepeatDisplay[client].DrawText(" ");
	gRepeatDisplay[client].DrawItem("Yes.");
	gRepeatDisplay[client].DrawItem("No.");

	strcopy(g_RepeatUUID[client], sizeof(g_RepeatUUID[]), UUID);
	gRepeatDisplay[client].Send(client, RepeatContractPanelHandler, MENU_TIME_FOREVER);
}

public int RepeatContractPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		if (param2 == 1)
		{
			// Grab the SteamID64 of the client so we can delete data from the database.
			char steamid64[64];
			GetClientAuthId(param1, AuthId_SteamID64, steamid64, sizeof(steamid64));
			DeleteContractProgressDatabase(steamid64, g_RepeatUUID[param1]);
			DeleteAllObjectiveProgressDatabase(steamid64, g_RepeatUUID[param1]);

			CompletedContractInfo info;
			CompletedContracts[param1].GetArray(g_RepeatUUID[param1], info, sizeof(CompletedContractInfo));
			info.m_bReset = true;
			CompletedContracts[param1].SetArray(g_RepeatUUID[param1], info, sizeof(CompletedContractInfo));

			SetCompletedContractInfoDatabase(steamid64, g_RepeatUUID[param1], info);
			SetClientContract(param1, g_RepeatUUID[param1]);

			g_RepeatUUID[param1] = "";
		}
		if (param2 == 2)
		{
			OpenContrackerForClient(param1);
			g_RepeatUUID[param1] = "";
		} 
	}
	return 0;
}


void ShortenDirectoryString(const char[] Directory, char[] buffer, int size)
{
	// Construct a shorter directory.
	char ShorterDirectory[MAX_DIRECTORY_SIZE];
	char Folders[16][64];
	int Splits = ExplodeString(Directory, "/", Folders, sizeof(Folders), sizeof(Folders[]));

	if (Splits > 2)
	{
		for (int i = 0; i < Splits - 2; i++) Folders[i] = "..";
	}

	for (int i = 0; i < Splits; i++)
	{
		char FolderWithSlash[64];
		Format(FolderWithSlash, sizeof(FolderWithSlash), "%s/", Folders[i]);
		StrCat(ShorterDirectory, sizeof(ShorterDirectory), FolderWithSlash);
	}

	strcopy(buffer, size, ShorterDirectory);
}

void GetPreviousDirectory(const char[] Directory, char[] buffer, int size)
{
	char PreviousDirectory[MAX_DIRECTORY_SIZE];
	char Folders[16][64];
	ExplodeString(Directory, "/", Folders, sizeof(Folders), sizeof(Folders[]));
	for (int i = 0; i < sizeof(Folders); i++)
	{
		if (StrEqual(Folders[i+1], "")) break;
		char FolderWithSlash[64];
		Format(FolderWithSlash, sizeof(FolderWithSlash), "%s/", Folders[i]);
		StrCat(PreviousDirectory, sizeof(PreviousDirectory), FolderWithSlash);
	}

	strcopy(buffer, size, PreviousDirectory);
}