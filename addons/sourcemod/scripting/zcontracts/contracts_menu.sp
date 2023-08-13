// Menu objects.
static Menu gContractMenu;
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
	Format(MenuTitle, sizeof(MenuTitle), MenuTitle, ZCONTRACTS_PLUGIN_VERSION);
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
			g_ContractSchema.GetString(CONTRACT_DEF_NAME, sContractName, sizeof(sContractName), "undefined");
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
				KeyValues Schema = GetContractSchema(MenuKey);

				char ContractDirectory[MAX_DIRECTORY_SIZE];
				GetContractDirectory(MenuKey, ContractDirectory);
				// Are we in the right directory?
				if (!StrEqual(ContractDirectory, g_Menu_CurrentDirectory[param1])) 
				{
					return ITEMDRAW_IGNORE;
				}

				// Admin check.
				char AdminFlags[64];
				Schema.GetString(CONTRACT_DEF_REQUIRED_FLAG, AdminFlags, sizeof(AdminFlags));
				int RequiredFlags = ReadFlagString(AdminFlags);
				if (!StrEqual(AdminFlags, "") && !(RequiredFlags && GetUserFlagBits(param1) & RequiredFlags)) return ITEMDRAW_IGNORE;

				// Are we currently using this contract?
				if (StrEqual(MenuKey, ActiveContract[param1].UUID)) 
				{
					if (g_RepeatContracts.BoolValue && ActiveContract[param1].IsContractComplete())
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

				// Do not draw a directory if it's listed as an admin-only directory.
				/*char DictAdminString[64];
				g_AdminDictList.GetString(MenuKey, DictAdminString, sizeof(DictAdminString))
				PrintToChat(param1, DictAdminString);
				int RequiredFlags = ReadFlagString(DictAdminString);
				if (!StrEqual(DictAdminString, "") && !(RequiredFlags && GetUserFlagBits(param1) & RequiredFlags)) return ITEMDRAW_IGNORE;*/

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

		// If we're currently doing a Contract, add "(ACTIVE)"
		// If the item is a directory, add ">"
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

				if (StrEqual(ActiveContract[param1].UUID, MenuKey))
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

				Format(MenuDisplay, sizeof(MenuDisplay), "> %s", MenuDisplay);
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
				StrEqual(MenuKey, ActiveContract[param1].UUID) &&
				ActiveContract[param1].IsContractComplete())
				{
					CompletedContractInfo info;
					CompletedContracts[param1].GetArray(ActiveContract[param1].UUID, info, sizeof(CompletedContractInfo));
					if (!info.m_bReset)
					{
						ConstructRepeatContractPanel(param1, ActiveContract[param1].UUID);
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
				else if (!StrEqual(MenuKey, ActiveContract[param1].UUID))
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
	// Are we doing a Contract?
	if (ActiveContract[client].IsContractInitalized())
	{
		// Display our objective display instead.
		CreateObjectiveDisplay(client, false);
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
void CreateObjectiveDisplay(int client, bool unknown)
{
	if (!unknown && PlayerSoundsEnabled[client] == Sounds_Enabled) EmitGameSoundToClient(client, ProgressLoadedSound);

	Menu ContractDisplay = new Menu(ObjectiveDisplayHandler, MENU_ACTIONS_ALL);
	ContractDisplay.OptionFlags = MENUFLAG_NO_SOUND | MENUFLAG_BUTTON_EXIT;

	char ContractName[128];
	ActiveContract[client].GetSchema().GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));
	Format(ContractName, sizeof(ContractName), "\"%s\"", ContractName);
	
	// Add difficulty stars to our title.
	char StrDifficulty[32] = " || Difficulty: ";
	int Difficulty = ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_DIFFICULTY, 0);
	if (Difficulty > 0)
	{
		for (int i = 0; i < Difficulty; i++)
		{
			StrCat(StrDifficulty, sizeof(StrDifficulty), "%s");
			Format(StrDifficulty, sizeof(StrDifficulty), StrDifficulty, "★");
		}
		StrCat(ContractName, sizeof(ContractName), StrDifficulty);
	}

	// Display the amount of times we've completed this Contract.
	if (g_RepeatContracts.BoolValue)
	{
		CompletedContractInfo info;
		CompletedContracts[client].GetArray(ActiveContract[client].UUID, info, sizeof(CompletedContractInfo));
		char text[64] = " || Completions: %d";
		Format(text, sizeof(text), text, info.m_iCompletions);
		StrCat(ContractName, sizeof(ContractName), StrDifficulty);
	}

	ContractDisplay.SetTitle(ContractName);

	switch (view_as<ContractType>(ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_TYPE)))
	{
		case Contract_ContractProgress:
		{
			int MaxProgress = ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS);
			char ContractGoal[128] = "To complete this Contract, get %d CP.";
			Format(ContractGoal, sizeof(ContractGoal), ContractGoal, MaxProgress);
			ContractDisplay.AddItem("#contract_goal", ContractGoal, ITEMDRAW_DISABLED);

			char ContractProgress[256];
			Format(ContractProgress, sizeof(ContractProgress), "Progress: [%d/%d]", ActiveContract[client].ContractProgress, MaxProgress);
			if (unknown)
			{
				Format(ContractProgress, sizeof(ContractProgress), "Progress: [?/%d]", MaxProgress);
			}
			ContractDisplay.AddItem("#contract_progress", ContractProgress, ITEMDRAW_DISABLED);
			ContractDisplay.AddItem("#divider1", "-------------------------------------------------", ITEMDRAW_SPACER);
		}
		case Contract_ObjectiveProgress:
		{
			char ContractGoal[128];
			if (ActiveContract[client].ObjectiveCount == 1)
			{
				ContractGoal = "To complete this Contract, complete %d objective.\n";
			}
			else
			{
				ContractGoal = "To complete this Contract, complete %d objectives.\n";
			}
			
			Format(ContractGoal, sizeof(ContractGoal), ContractGoal, ActiveContract[client].ObjectiveCount);
			ContractDisplay.AddItem("#contract_goal", ContractGoal, ITEMDRAW_DISABLED);
			ContractDisplay.AddItem("#divider2", "-------------------------------------------------", ITEMDRAW_SPACER);
		}
	}

	// TODO: Should we split this up into two pages?
	for (int obj_id = 0; obj_id < ActiveContract[client].ObjectiveCount; obj_id++)
	{
		KeyValues ObjSchema = ActiveContract[client].GetObjectiveSchema(obj_id);
		char line[256];
		char Description[256];
		ObjSchema.GetString(CONTRACT_DEF_OBJ_DESC, Description, sizeof(Description));
		int MaxProgress = ObjSchema.GetNum(CONTRACT_DEF_OBJ_MAX_PROGRESS);
		int Award = ObjSchema.GetNum(CONTRACT_DEF_OBJ_AWARD);

		if (ActiveContract[client].IsObjectiveInfinite(obj_id))
		{
			Format(line, sizeof(line), "Objective #%d: \"%s\" +%dCP", obj_id+1, Description, Award);
		}
		else
		{
			switch (view_as<ContractType>(ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_TYPE)))
			{
				case Contract_ObjectiveProgress:
				{
					Format(line, sizeof(line), "Objective #%d: \"%s\" [%d/%d]", obj_id+1,
					Description, ActiveContract[client].ObjectiveProgress.Get(obj_id), MaxProgress);
					
					if (unknown)
					{
						Format(line, sizeof(line), "Objective #%d: \"%s\" [?/%d]", obj_id+1, Description, MaxProgress);
					}

				}
				case Contract_ContractProgress:
				{
					Format(line, sizeof(line), "Objective #%d: \"%s\" [%d/%d] +%dCP", obj_id+1,
					Description, ActiveContract[client].ObjectiveProgress.Get(obj_id), MaxProgress, Award);
					if (unknown)
					{
						Format(line, sizeof(line), "Objective #%d: \"%s\" [?/%d] +%dCP", obj_id+1,
						Description, MaxProgress, Award);				
					}
				}
			}
		}
		char MenuKey[8];
		Format(MenuKey, sizeof(MenuKey), "obj_%d", obj_id);
		ContractDisplay.AddItem(MenuKey, line);	
	}
	
	ContractDisplay.AddItem("#divider3", "-------------------------------------------------", ITEMDRAW_SPACER);

	// Send this to our client.
	ContractDisplay.AddItem("open", "Open Contracker");
	ContractDisplay.Display(client, 20);
}

/**
 * This handles the option to open the global Contracker.
**/
public int ObjectiveDisplayHandler(Menu menu, MenuAction action, int param1, int param2)
{
	int style;
	char MenuKey[MAX_UUID_SIZE];
	char MenuDisplay[MAX_NAME_LENGTH+32]; // Display name (+32 for anything else added after the name)
	menu.GetItem(param2, MenuKey, sizeof(MenuKey), style, MenuDisplay, sizeof(MenuDisplay));
	
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			if (MenuKey[0] == '#') return ITEMDRAW_DISABLED;
			if (StrContains(MenuKey, "#divider") != -1) return ITEMDRAW_DISABLED | ITEMDRAW_SPACER;

			if (StrContains(MenuKey, "obj_") != -1)
			{
				// Format: obj_###
				ReplaceString(MenuDisplay, sizeof(MenuDisplay), "obj_", "");
				int Objective = StringToInt(MenuDisplay);

				KeyValues ObjSchema = ActiveContract[param1].GetObjectiveSchema(Objective);
				char ExtendedDesc[64];
				ObjSchema.GetString(CONTRACT_DEF_OBJ_EXT_DESC, ExtendedDesc, sizeof(ExtendedDesc), "");
				if (StrEqual(ExtendedDesc, ""))
				{
					return ITEMDRAW_DISABLED;
				}
				return ITEMDRAW_DEFAULT;
			}
		
			else return ITEMDRAW_DEFAULT;
		}
		case MenuAction_DisplayItem:
		{
			if (StrContains(MenuKey, "obj_") != -1)
			{
				// Format: obj_###
				ReplaceString(MenuDisplay, sizeof(MenuDisplay), "obj_", "");
				int Objective = StringToInt(MenuDisplay);

				KeyValues ObjSchema = ActiveContract[param1].GetObjectiveSchema(Objective);
				char ExtendedDesc[64];
				ObjSchema.GetString(CONTRACT_DEF_OBJ_EXT_DESC, ExtendedDesc, sizeof(ExtendedDesc));
				if (!StrEqual(ExtendedDesc, ""))
				{
					StrCat(MenuDisplay, sizeof(MenuDisplay), " (...)");
					return RedrawMenuItem(MenuDisplay);
				}
			}
			
		}
		case MenuAction_Select:
		{
			if (StrEqual(MenuKey, "open"))
			{
				gContractMenu.Display(param1, MENU_TIME_FOREVER);
			}
			else if (StrContains(MenuKey, "obj_") != -1)
			{
				// Format: obj_###
				ReplaceString(MenuDisplay, sizeof(MenuDisplay), "obj_", "");
				int Objective = StringToInt(MenuDisplay);

				KeyValues ObjSchema = ActiveContract[param1].GetObjectiveSchema(Objective);
				char ExtendedDesc[64];
				ObjSchema.GetString(CONTRACT_DEF_OBJ_EXT_DESC, ExtendedDesc, sizeof(ExtendedDesc));
				if (!StrEqual(ExtendedDesc, ""))
				{
					ConstructObjectiveInformationMenu(param1, Objective);
				}
			}
		}
	}
	return 0;
}

void ConstructObjectiveInformationMenu(int client, int objective)
{
	// Construct our panel for the client.
	Menu ObjectiveInformation = new Menu(ObjectiveInformationHandler, MENU_ACTIONS_ALL);
	ObjectiveInformation.OptionFlags = MENUFLAG_NO_SOUND | MENUFLAG_BUTTON_EXIT;

	char ContractName[128];
	ActiveContract[client].GetSchema().GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));
	Format(ContractName, sizeof(ContractName), "\"%s\"", ContractName);
	
	// Add difficulty stars to our title.
	char StrDifficulty[32] = " || Difficulty: ";
	int Difficulty = ActiveContract[client].GetSchema().GetNum(CONTRACT_DEF_DIFFICULTY, 1);
	for (int i = 0; i < Difficulty; i++)
	{
		StrCat(StrDifficulty, sizeof(StrDifficulty), "%s");
		Format(StrDifficulty, sizeof(StrDifficulty), StrDifficulty, "★");
	}
	StrCat(ContractName, sizeof(ContractName), StrDifficulty);

	// Display the amount of times we've completed this Contract.
	if (g_RepeatContracts.BoolValue)
	{
		CompletedContractInfo info;
		CompletedContracts[client].GetArray(ActiveContract[client].UUID, info, sizeof(CompletedContractInfo));
		char text[64] = " || Completions: %d";
		Format(text, sizeof(text), text, info.m_iCompletions);
		StrCat(ContractName, sizeof(ContractName), StrDifficulty);
	}

	ObjectiveInformation.SetTitle(ContractName);
	KeyValues ObjSchema = ActiveContract[client].GetObjectiveSchema(objective);
	
	char ExtendedDesc[256];
	ObjSchema.GetString(CONTRACT_DEF_OBJ_EXT_DESC, ExtendedDesc, sizeof(ExtendedDesc), "");

	// For some reason, ExplodeString and ReplaceString don't want to deal with
	// newline characters. As a hack, I will split strings with # instead.
	char DescStrings[8][128];
	int StringCount = ExplodeString(ExtendedDesc, "#", DescStrings, sizeof(DescStrings), sizeof(DescStrings[]));
	for (int i = 0; i < StringCount; i++)
	{
		char StringToAdd[128];
		if (i == 0)
		{
			Format(StringToAdd, sizeof(StringToAdd), "Objective Description: \"%s", DescStrings[i]);
		}
		else if (i == StringCount-1)
		{
			Format(StringToAdd, sizeof(StringToAdd), "%s\"", DescStrings[i]);
		}
		else
		{
			StringToAdd = DescStrings[i];
		}
		char Key[16];
		Format(Key, sizeof(Key), "desc_%d", i);
		ObjectiveInformation.AddItem(Key, StringToAdd);
	}

	ObjectiveInformation.AddItem("return", "Return to Contract");
	ObjectiveInformation.AddItem("open", "Open Contracker");
	ObjectiveInformation.Display(client, 20);
}

public int ObjectiveInformationHandler(Menu menu, MenuAction action, int param1, int param2)
{
	int style;
	char MenuKey[MAX_UUID_SIZE];
	char MenuDisplay[MAX_NAME_LENGTH+32]; // Display name (+32 for anything else added after the name)
	menu.GetItem(param2, MenuKey, sizeof(MenuKey), style, MenuDisplay, sizeof(MenuDisplay));
	
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			if (StrContains(MenuKey, "desc_") != -1)
			{
				return ITEMDRAW_DISABLED;
			}
			else return ITEMDRAW_DEFAULT;
		}
		case MenuAction_Select:
		{
			if (StrEqual(MenuKey, "open"))
			{
				gContractMenu.Display(param1, MENU_TIME_FOREVER);
			}
			else if (StrEqual(MenuKey, "return"))
			{
				CreateObjectiveDisplay(param1, false);
			}
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
	gHelpDisplay[client].DrawText("Directories are notated with \">\". They contain more Contracts inside.");
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
	KeyValues LockedContract = GetContractSchema(UUID);

	Menu ClientMenu = new Menu(LockedContractMenuHandler, MENU_ACTIONS_ALL);
	char ContractNameText[MAX_CONTRACT_NAME_SIZE + 32] = "\"%s\" cannot be activated.";
	char ContractName[MAX_CONTRACT_NAME_SIZE];
	LockedContract.GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));
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
			g_ContractSchema.GetString(CONTRACT_DEF_NAME, DisplayName, sizeof(DisplayName));
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
				// Are we currently using this contract?
				if (StrEqual(MenuKey, ActiveContract[param1].UUID)) 
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
				// Are we doing this Contract?
				if (StrEqual(ActiveContract[param1].UUID, MenuKey))
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
				else if (!StrEqual(MenuKey, ActiveContract[param1].UUID))
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

void ConstructRepeatContractPanel(int client, char UUID[MAX_UUID_SIZE])
{
	gRepeatDisplay[client] = new Panel();
	gRepeatDisplay[client].SetTitle("ZContracts - Repeat Contract");

	// Grab the Contract from the schema.
	KeyValues LockedContract = GetContractSchema(UUID);

	char ContractName[MAX_CONTRACT_NAME_SIZE];
	LockedContract.GetString(CONTRACT_DEF_NAME, ContractName, sizeof(ContractName));

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