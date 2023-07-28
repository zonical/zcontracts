

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
			g_ContractSchema.GetString(CONTRACT_DEF_DIRECTORY, sDirectory, sizeof(sDirectory), "root");
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
	g_ContractSchema.GotoFirstSubKey();

	int ObjectiveCount = 0;
	do
	{
		if (ObjectiveCount == objective)
		{
			char StrObjective[4];
			IntToString(ObjectiveCount, StrObjective, sizeof(StrObjective));

			// Clone this objective and return it.
			KeyValues NewKV = new KeyValues(StrObjective);
			NewKV.Import(g_ContractSchema);
			g_ContractSchema.Rewind();
			Handle Schema = CloneHandle(NewKV, plugin);

			return view_as<KeyValues>(Schema);
		}
		ObjectiveCount++;
	} while (g_ContractSchema.GotoNextKey());

	// Error out once more because we couldn't find the objective!
	g_ContractSchema.Rewind();
	return ThrowNativeError(SP_ERROR_NOT_FOUND, "Could not find objective %d in %s schema", objective, UUID);
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

bool GetContractDirectory(const char[] sUUID, char buffer[MAX_DIRECTORY_SIZE])
{
	if (g_ContractSchema.JumpToKey(sUUID))
	{
		g_ContractSchema.GetString(CONTRACT_DEF_DIRECTORY, buffer, sizeof(buffer), "root");
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