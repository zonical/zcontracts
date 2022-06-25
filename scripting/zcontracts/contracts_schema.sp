

#include <stocksoup/files>
#include <zcontracts/zcontracts>

ArrayList g_Contracts;
ArrayList g_Directories;

public KeyValues LoadContractsSchema()
{
	KeyValues contractSchema = new KeyValues("Items");
	
	// We'll ditch the single file legacy format and instead load separate contract files.
	// These will all be loaded and merged together in one single schema.
	char schemaDir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, schemaDir, sizeof(schemaDir), "configs/%s", SCHEMA_FOLDER);
	
	// Find files within `configs/creators/contracts/` and import them, too
	ArrayList configFiles = GetFilesInDirectoryRecursive(schemaDir);
	for (int i, n = configFiles.Length; i < n; i++)
	{
		// Grab this file from the directory.
		char contractFilePath[PLATFORM_MAX_PATH];
		configFiles.GetString(i, contractFilePath, sizeof(contractFilePath));
		NormalizePathToPOSIX(contractFilePath);
		
		// Skip files in directories named "disabled".
		if (StrContains(contractFilePath, "/disabled/") != -1) continue;
		
		// Skip files that are NOT text files (e.g documentation).
		if (StrContains(contractFilePath, REQUIRED_FILE_EXTENSION) == -1) continue;
		
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
	hEventConf.GetString("exclusive_description", hEvent.m_sExclusiveDescription, sizeof(hEvent.m_sExclusiveDescription));
	hEventConf.GetString("type", hEvent.m_sEventType, sizeof(hEvent.m_sEventType), "increment");
	hEvent.m_iThreshold = hEventConf.GetNum("threshold", 1);
	hEvent.m_iAward = hEventConf.GetNum("award", 1);
	
	// If this event has a timer...
	if (hEventConf.JumpToKey("timer", false))
	{
		// Populate our variables.
		hEvent.m_fTime = hEventConf.GetFloat("time");
		hEvent.m_iMaxLoops = hEventConf.GetNum("loop");
		
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
	hObjectiveConf.GetString("weapon_restriction", hObjective.m_sWeaponRestriction, sizeof(hObjective.m_sWeaponRestriction));
	hObjective.m_iMaxProgress = hObjectiveConf.GetNum("required_progress", 1);
	hObjective.m_bInfinite = view_as<bool>(hObjectiveConf.GetNum("infinite", 0));
	if (hObjective.m_bInfinite)
	{
		hObjective.m_iMaxProgress = 0;
	}

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
	hContract.Initalize();

	// Grab our UUID from the section name.
	hContractConf.GetSectionName(hContract.m_sUUID, sizeof(hContract.m_sUUID));
	hContractConf.GetString("name", hContract.m_sContractName, sizeof(hContract.m_sContractName));
	hContractConf.GetString("directory", hContract.m_sDirectoryPath, sizeof(hContract.m_sDirectoryPath), "root");
	hContract.m_iContractType = hContractConf.GetNum("type", view_as<int>(Contract_ObjectiveProgress));
	hContract.m_iMaxProgress = hContractConf.GetNum("required_progress", -1);

	// Grab the classes that can do this contract.
#if defined ZC_TF2
	if (hContractConf.JumpToKey("classes", false))
	{
		hContract.m_bClass[TFClass_Scout] 		= view_as<bool>(hContractConf.GetNum("scout", 0));
		hContract.m_bClass[TFClass_Soldier] 	= view_as<bool>(hContractConf.GetNum("soldier", 0));
		hContract.m_bClass[TFClass_Pyro] 		= view_as<bool>(hContractConf.GetNum("pyro", 0));
		hContract.m_bClass[TFClass_DemoMan] 	= view_as<bool>(hContractConf.GetNum("demoman", 0));
		hContract.m_bClass[TFClass_Heavy]		= view_as<bool>(hContractConf.GetNum("heavy", 0));
		hContract.m_bClass[TFClass_Engineer] 	= view_as<bool>(hContractConf.GetNum("engineer", 0));
		hContract.m_bClass[TFClass_Sniper] 		= view_as<bool>(hContractConf.GetNum("sniper", 0));
		hContract.m_bClass[TFClass_Medic] 		= view_as<bool>(hContractConf.GetNum("medic", 0));
		hContract.m_bClass[TFClass_Spy] 		= view_as<bool>(hContractConf.GetNum("spy", 0));
		
		// Return.
		hContractConf.GoBack();
	}	
#endif
	
	// Create our objectives.
	if (hContractConf.JumpToKey("objectives", false))
	{
		if(hContractConf.GotoFirstSubKey())
		{
			int obj = 0;
			do 
			{
				if (hContract.m_hObjectives.Length > MAX_CONTRACT_OBJECTIVES)
				{
					LogMessage("[ZContracts] Warning: Contract %s has too many objectives (max: %d), skipping extra objectives...", 
					hContract.m_sUUID, MAX_CONTRACT_OBJECTIVES);
					break;
				}

				ContractObjective m_hObjective;
				CreateContractObjective(hContractConf, m_hObjective);
				m_hObjective.m_iInternalID = obj;
				hContract.m_hObjectives.PushArray(m_hObjective);
				obj++;
			} while (hContractConf.GotoNextKey());
		}
		hContractConf.GoBack();
	}

	// Add our new directory into the directory register.
	if (g_Directories.FindString(hContract.m_sDirectoryPath) == -1)
	{
		g_Directories.PushString(hContract.m_sDirectoryPath);
	}
	// Add our contract to the global list.
	g_Contracts.PushArray(hContract, sizeof(Contract));

	LogMessage("[ZContracts] Created Contract %s in directory: %s", hContract.m_sUUID, hContract.m_sDirectoryPath);
	hContractConf.GoBack();
}

public void ProcessContractsSchema()
{
	KeyValues contractSchema = LoadContractsSchema();

	delete g_Directories;
	delete g_Contracts;
	g_Directories = new ArrayList(ByteCountToCells(MAX_DIRECTORY_SIZE));
	g_Contracts = new ArrayList(sizeof(Contract));
	
	// Parse our items.
	if (contractSchema.GotoFirstSubKey()) 
	{
		do 
		{
			// Create our Contract.
			Contract hContract;
			CreateContract(contractSchema, hContract);
		} while (contractSchema.GotoNextKey());
		contractSchema.GoBack();
		
	} 
	delete contractSchema;
	
	PrintToServer("[ZContracts] Initalized contracts.");
}

// Attempt to find a contract by searching through all directories
// and matching the UUID's together.
bool GetContractDefinition(const char[] UUID, Contract buffer) 
{
	if (g_Contracts)
	{
		for (int i = 0; i < g_Contracts.Length; i++)
		{
			Contract hContract;
			g_Contracts.GetArray(i, hContract, sizeof(Contract));
			if (StrEqual(hContract.m_sUUID, UUID))
			{
				buffer = hContract;
				return true;
			}
		}
	}
	return false;
}