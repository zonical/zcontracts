

#include <stocksoup/files>
#include <zcontracts/zcontracts_tf2>
#include <zcontracts/zcontracts_csgo>

KeyValues g_ContractSchema;
ArrayList g_Directories;

ConVar g_ConfigSearchPath;
ConVar g_RequiredFileExt;
ConVar g_DisabledPath;

int g_ContractsLoaded;

#define MAXIMUM_TEAMS 4

public KeyValues LoadContractsSchema()
{
	KeyValues contractSchema = new KeyValues("Contracts");
	g_ContractsLoaded = 0;
	
	// We'll ditch the single file legacy format and instead load separate contract files.
	// These will all be loaded and merged together in one single schema.
	char schemaDir[PLATFORM_MAX_PATH];
	char configPath[PLATFORM_MAX_PATH];
	g_ConfigSearchPath.GetString(configPath, sizeof(configPath));
	BuildPath(Path_SM, schemaDir, sizeof(schemaDir), configPath);
	
	// Find files within `configs/creators/contracts/` and import them, too
	ArrayList configFiles = GetFilesInDirectoryRecursive(schemaDir);
	for (int i, n = configFiles.Length; i < n; i++)
	{
		// Grab this file from the directory.
		char contractFilePath[PLATFORM_MAX_PATH];
		configFiles.GetString(i, contractFilePath, sizeof(contractFilePath));
		NormalizePathToPOSIX(contractFilePath);
		
		// Skip files in directories that the g_DisabledPath ConVar disallows
		char disabledPath[PLATFORM_MAX_PATH];
		g_DisabledPath.GetString(disabledPath, sizeof(disabledPath));
		if (StrContains(contractFilePath, disabledPath) != -1) continue;
		
		// Skip files that are NOT what g_RequiredFileExt requires (e.g documentation).
		char requiredExt[16];
		g_RequiredFileExt.GetString(requiredExt, sizeof(requiredExt));
		if (StrContains(contractFilePath, requiredExt) == -1) continue;
		
		// Import in this config file.
		KeyValues importKV = new KeyValues("Contract");
		importKV.ImportFromFile(contractFilePath);
		
		// Try adding it to our overall schema.
		char importUUID[MAX_UUID_SIZE];
		importKV.GotoFirstSubKey(false);
		do 
		{
			// Does this item already exist?
			importKV.GetSectionName(importUUID, sizeof(importUUID));
			if (importKV.GetDataType(NULL_STRING) == KvData_None) 
			{
				if (contractSchema.JumpToKey(importUUID)) 
				{
					LogMessage("[ZContracts] Attempt to import contract %s, failed: %s already exists in schema.", contractFilePath, importUUID);
				} 
				else {
					// Import in.
					contractSchema.JumpToKey(importUUID, true);
					contractSchema.Import(importKV);
				}
				contractSchema.GoBack();
			}
		} while (importKV.GotoNextKey(false));
		
		// Cleanup.
		importKV.GoBack();
		delete importKV;
	}
	delete configFiles;
	return contractSchema;
}

// Creates a contract event.
public void CreateContractObjectiveEvent(KeyValues hEventConf, ContractObjectiveEvent hEvent)
{
	hEvent.Initalize();
	
	hEventConf.GetSectionName(hEvent.m_sEventName, sizeof(hEvent.m_sEventName)); 	// Our event trigger is the section name.
	hEventConf.GetString("type", hEvent.m_sEventType, sizeof(hEvent.m_sEventType), "increment");
	hEvent.m_iThreshold = hEventConf.GetNum("threshold", 1);
	hEvent.m_hTimer = INVALID_HANDLE;
	
	// If this event has a timer...
	if (hEventConf.JumpToKey("timer", false))
	{
		// Populate our variables.
		hEvent.m_fTime = hEventConf.GetFloat("time");
		hEvent.m_iMaxLoops = hEventConf.GetNum("loops");
		
		// Check if any events exist.
		if (hEventConf.JumpToKey("OnTimerEnd", false))
		{
			TimerEvent hTimer;
			
			// Populate our variables.
			//hTimer.m_sEventName = "OnTimerEnd";
			hTimer.m_iVariable = hEventConf.GetNum("variable");
			hEventConf.GetString("event", hTimer.m_sAction, sizeof(hTimer.m_sAction));
			
			// Add to our list.
			hEvent.m_hTimerEvents.PushArray(hTimer, sizeof(TimerEvent));
			
			hEventConf.GoBack();
		}
		hEventConf.GoBack();
	}
}

// Creates a contract objective.
public void CreateContractObjective(KeyValues hObjectiveConf, ContractObjective hObjective)
{
	hObjective.Initalize();

	hObjectiveConf.GetString("description", hObjective.m_sDescription, sizeof(hObjective.m_sDescription));

	if (hObjectiveConf.GetNum("maximum_cp", -1) != -1) hObjective.m_iMaxProgress = hObjectiveConf.GetNum("maximum_cp");
	if (hObjectiveConf.GetNum("maximum_uses", -1) != -1) hObjective.m_iMaxProgress = hObjectiveConf.GetNum("maximum_uses");

	hObjective.m_iAward = hObjectiveConf.GetNum("award", 1);
	hObjective.m_bInfinite = view_as<bool>(hObjectiveConf.GetNum("infinite", 0));
	hObjective.m_bNoMultiplication = view_as<bool>(hObjectiveConf.GetNum("no_multiply", 0));

	// Create our events.
	if (hObjectiveConf.JumpToKey("events", false))
	{
		if(hObjectiveConf.GotoFirstSubKey())
		{
			int id = 0;
			do 
			{
				// Create an event from our logic.
				ContractObjectiveEvent hEvent;
				CreateContractObjectiveEvent(hObjectiveConf, hEvent);
				hEvent.m_iInternalID = id;
				id++;
				hObjective.m_hEvents.PushArray(hEvent);
				
			} while (hObjectiveConf.GotoNextKey());
			hObjectiveConf.GoBack();
		}
		hObjectiveConf.GoBack();
	}
}

// Creates a contract.
public void CreateContract(KeyValues hContractConf, Contract hContract)
{	
	// THERE ARE SEVERAL THINGS LISTED HERE THAT ARE NOT STORED IN THE CONTRACT STRUCT!
	// Weapon restriction types:
	// "active_weapon_slot": The slot for the weapon set at m_hActiveWeapon (see items_game.txt)
	// "active_weapon_name": The display economy name for the weapon set at m_hActiveWeapon.
	// "active_weapon_classname": The classname of the weapon set at m_hActiveWeapon.
	// "active_weapon_itemdef": The item definition index for the weapon set at m_hActiveWeapon.
	// "inventory_item_name": The display economy name for an item in the players current inventory.
	// "inventory_item_classname": The classname for an item in the players current inventory.
	// "inventory_item_itemdef": The item definition index for an item in the players current inventory.
	// If a player kills another player without using the specified active weapon, the contract is not updated.
	// If a player kills another player with a specified active weapon, the contract is updated.
	// If a player kills another player without having a specified inventory item equipped, the contract is not updated.
	// If a player kills another player while having a specified inventory item equipped, the contract is updated.
	//
	// Map restriction: "map_restriction". This can be a whole map or part of a map name.
	// Examples: "pl_upward", "ctf_2fort", "koth_", "pl_constantlyupdated_v3"
	//
	// Team restriction: "team_restriction". This can be a team index number or a special name.


	hContract.Initalize();

	// Grab our UUID from the section name.
	hContractConf.GetSectionName(hContract.m_sUUID, sizeof(hContract.m_sUUID));
	// Display name of the Contract in the Contracker.
	hContractConf.GetString("name", hContract.m_sContractName, sizeof(hContract.m_sContractName));
	// Directory of the Contract. This MUST include "root" and not end in a slash.
	hContractConf.GetString("directory", hContract.m_sDirectoryPath, sizeof(hContract.m_sDirectoryPath), "root");

	hContract.m_bNoMultiplication = view_as<bool>(hContractConf.GetNum("no_multiply", 0));
	hContract.m_iContractType = view_as<ContractType>(hContractConf.GetNum("type", view_as<int>(Contract_ObjectiveProgress))); // stops a warning
	hContract.m_iMaxProgress = hContractConf.GetNum("maximum_cp", -1);
	hContract.m_iDifficulty = hContractConf.GetNum("difficulty", 1);
	
	// Create our objectives.
	if (hContractConf.JumpToKey("objectives", false))
	{
		if(hContractConf.GotoFirstSubKey())
		{
			int obj = 0;
			do 
			{
				ContractObjective m_hObjective;
				CreateContractObjective(hContractConf, m_hObjective);
				m_hObjective.m_iInternalID = obj;
				m_hObjective.m_iContractType = hContract.m_iContractType;
				m_hObjective.m_bInitalized = true;
				hContract.m_hObjectives.PushArray(m_hObjective);
				obj++;
			} while (hContractConf.GotoNextKey());
		}
		hContractConf.GoBack();
	}

	// Get a list of contracts that are required to be completed before
	// this one can be activated.
	if (hContractConf.JumpToKey("required_contracts", false))
	{
		int Value = 0;
		for (;;)
		{
			char ContractUUID[MAX_UUID_SIZE];
			char ValueStr[4];
			IntToString(Value, ValueStr, sizeof(ValueStr));

			hContractConf.GetString(ValueStr, ContractUUID, sizeof(ContractUUID), "{}");
			
			// If we reach a blank UUID, we're at the end of the list.
			if (StrEqual("{}", ContractUUID)) break;

			hContract.m_hRequiredContracts.PushString(ContractUUID);
			Value++;
		}
	
		hContractConf.GoBack();
	}

	LogMessage("[ZContracts] Created Contract %s (%s) in directory: %s", hContract.m_sUUID, hContract.m_sContractName, hContract.m_sDirectoryPath);
	hContractConf.GoBack();
}

public void ProcessContractsSchema()
{
	delete g_ContractSchema;
	g_ContractSchema = LoadContractsSchema();
	
	delete g_Directories;
	g_Directories = new ArrayList(ByteCountToCells(MAX_DIRECTORY_SIZE));
	int iContractCount = 0;
	
	if (g_ContractSchema.GotoFirstSubKey())
	{
		do
		{
			char sDirectory[MAX_DIRECTORY_SIZE];
			g_ContractSchema.GetString("directory", sDirectory, sizeof(sDirectory), "root");
			// Add our new directory into the directory register.
			if (g_Directories.FindString(sDirectory) == -1)
			{
				g_Directories.PushString(sDirectory);
			} 
			iContractCount++;
		}
		while(g_ContractSchema.GotoNextKey());
	}
	g_ContractSchema.Rewind();
	g_ContractsLoaded = iContractCount;
	PrintToServer("[ZContracts] Loaded %d contracts.", iContractCount);
}

/**
 * Grabs the Keyvalues schema for a Contract.
 *
 * @param UUID  Contract UUID.
 * @return		KeyValues object of a Contract.
 * @error       Contract could not be found in the schema.
*/
public any Native_GetContractSchema(Handle plugin, int numParams)
{
	char UUID[MAX_UUID_SIZE];
	GetNativeString(1, UUID, sizeof(UUID));
	if (!g_ContractSchema.JumpToKey(UUID))
	{
		// Error out!
		ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find Contract in schema - invalid UUID %s", UUID);
	}

	// Clone our handle and return it.
	KeyValues NewKV = new KeyValues(UUID);
	NewKV.Import(g_ContractSchema);
	g_ContractSchema.Rewind();
	Handle Schema = CloneHandle(NewKV, plugin);
	return view_as<KeyValues>(Schema);
}

/**
 * Grabs the Keyvalues schema for an Objective.
 *
 * @param UUID  Contract UUID.
 * @param objective Objective ID.
 * @return		KeyValues object of an Objective.
 * @error       Contract or Objective could not be found in the schema.
 */
public any Native_GetObjectiveSchema(Handle plugin, int numParams)
{
	char UUID[MAX_UUID_SIZE];
	GetNativeString(1, UUID, sizeof(UUID));
	int objective = GetNativeCell(2);
	if (!g_ContractSchema.JumpToKey(UUID))
	{
		// Error out!
		ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find Contract in schema - invalid UUID %s", UUID);
	}
	if (!g_ContractSchema.JumpToKey("objectives"))
	{
		// Error out again!
		ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find objectives in %s schema - invalid structure", UUID);
	}
	char StrObjective[4];
	IntToString(objective, StrObjective, sizeof(StrObjective));
	if (!g_ContractSchema.JumpToKey(StrObjective))
	{
		// Error out once more!
		ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find objective %d in %s schema", objective, UUID);
	}

	// Clone our handle and return it.
	KeyValues NewKV = new KeyValues(StrObjective);
	NewKV.Import(g_ContractSchema);
	g_ContractSchema.Rewind();
	Handle Schema = CloneHandle(NewKV, plugin);
	return view_as<KeyValues>(Schema);
}

/**
 * Grabs the amount of objectives in a Contract.
 *
 * @param UUID  Contract UUID.
 * @return		Amount of objectives in a Contract.
 * @error       Contract could not be found in the schema.
 */
public any Native_GetContractObjectiveCount(Handle plugin, int numParams)
{
	char UUID[MAX_UUID_SIZE];
	GetNativeString(1, UUID, sizeof(UUID));
	if (!g_ContractSchema.JumpToKey(UUID))
	{
		// Error out!
		ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find Contract in schema - invalid UUID %s", UUID);
	}
	if (!g_ContractSchema.JumpToKey("objectives"))
	{
		// Error out again!
		ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find objectives in %s schema - invalid structure", UUID);
	}

	int count = 0;
	if(g_ContractSchema.GotoFirstSubKey())
	{
		do 
		{
			count++;
		} while (g_ContractSchema.GotoNextKey());
	}
	g_ContractSchema.Rewind();
	return count;
}

bool CreateContractFromUUID(const char[] sUUID, Contract hBuffer)
{
	hBuffer.m_bInitalized = false;
	if (g_ContractSchema.JumpToKey(sUUID))
	{
		CreateContract(g_ContractSchema, hBuffer);
		g_ContractSchema.GoBack();
		hBuffer.m_bInitalized = true;
		return true;
	}
	return false;
}

bool GetContractDirectory(const char[] sUUID, char buffer[MAX_DIRECTORY_SIZE])
{
	if (g_ContractSchema.JumpToKey(sUUID))
	{
		g_ContractSchema.GetString("directory", buffer, sizeof(buffer), "root");
		g_ContractSchema.GoBack();
		return true;
	}
	return false;
}

int GetTeamFromSchema(const char[] sTeamBuffer)
{
	// Is this an int? We can easily grab the team index and set it from there.
	int iTeamIndex = StringToInt(sTeamBuffer);
	// CS:GO and TF2 team indexes don't go any higher than three. If this plugin
	// is ported to another Engine with more teams, you will need to change the
	// value of MAXIMUM_TEAMS to be max+1.
	if (iTeamIndex != 0 && iTeamIndex < MAXIMUM_TEAMS)
	{
		return iTeamIndex;
	}
	else if (StrEqual(sTeamBuffer, "0")) return -1;
	else
	{
		// Set the  incoming restriction string to be all lowercase.
		for (int i = 0; i < strlen(sTeamBuffer); i++)
		{
			CharToLower(sTeamBuffer[i]);
		}

		// Depending on the engine version, we can specify aliases
		// to use instead of intergers. 
		switch (GetEngineVersion())
		{
			case Engine_TF2: return TF2_GetTeamIndexFromString(sTeamBuffer);
			case Engine_CSGO: return CSGO_GetTeamIndexFromString(sTeamBuffer);
		}
	}

	// Could not determine team.
	return -1;
}