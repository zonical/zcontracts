#include <stocksoup/files>

char LocalSavePath[PLATFORM_MAX_PATH];

public void OnLocalSavePathChange(ConVar convar, char[] oldValue, char[] newValue)
{
    // Save all our old stuff first.
    if (g_DB != null) TransferLocalSavesToDatabase();

    // Construct our new path.
    strcopy(LocalSavePath, sizeof(LocalSavePath), newValue);
    BuildPath(Path_SM, LocalSavePath, sizeof(LocalSavePath), LocalSavePath);

    // Perform a new save.
    if (g_DB != null) TransferLocalSavesToDatabase();
}

/**
 * Creates a local save file for a client.
 * 
 * @param SteamID64     SteamID64 of the client.
 * @return              True if file created, false if failed.
 */
bool CreateLocalSave(char SteamID64[64])
{
    KeyValues SaveFile = new KeyValues("OfflineSave");
    char FileName[PLATFORM_MAX_PATH];
    Format(FileName, sizeof(FileName), "%s/%s.txt", LocalSavePath, SteamID64);
    return SaveFile.ExportToFile(FileName);
}

/**
 * Checks to see if a local save file exists.
 * 
 * @param SteamID64     SteamID64 of the client.
 * @return              True if file exists, false if not.
 */
bool DoesLocalSaveExist(char SteamID64[64])
{
    char FileName[PLATFORM_MAX_PATH];
    Format(FileName, sizeof(FileName), "%s/%s.txt", LocalSavePath, SteamID64);
    return FileExists(FileName);
}

/**
 * Loads a save file into KeyValues.
 * @param SteamID64     SteamID64 of the client.
 * @return A KeyValues handle.
 */
KeyValues LoadLocalSave(char SteamID64[64])
{
    // Create a save if it doesn't exist.
    if (!DoesLocalSaveExist(SteamID64)) CreateLocalSave(SteamID64);

    // Load file.
    KeyValues SaveFile = new KeyValues("OfflineSave");
    char FileName[PLATFORM_MAX_PATH];
    Format(FileName, sizeof(FileName), "%s/%s.txt", LocalSavePath, SteamID64);
    SaveFile.ImportFromFile(FileName);
    return SaveFile;
}

/**
 * Saves a KeyValues handle to disk.
 * @param SteamID64     SteamID64 of the client.
 * @param KV            Keyvalues Handle to save.
 * @return True if file saved, false otherwise.
 */
bool SaveLocalSave(char SteamID64[64], KeyValues KV)
{
    char FileName[PLATFORM_MAX_PATH];
    Format(FileName, sizeof(FileName), "%s/%s.txt", LocalSavePath, SteamID64);
    return KV.ExportToFile(FileName);
}

/**
 * Saves the progress of a Contract to a file on disk.
 * @param client 	Client index.
 * @param ClientContract	Contract struct to save.
 * @error	Client index is invalid.
 */
public any Native_SaveLocalContractProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    Contract ClientContract;
    GetNativeArray(2, ClientContract, sizeof(Contract));

    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
    if (ClientContract.m_sUUID[0] != '{')
    {
        ThrowError("Invalid UUID passed. (%s)", ClientContract.m_sUUID);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE SAVE: Saving client contract progress (%s).", client, ClientContract.m_sUUID);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // Load and save.
    KeyValues LocalSave = new KeyValues("OfflineSave");
    LocalSave.Import(LoadLocalSave(steamid64));
    if (LocalSave.JumpToKey("contracts", true))
    {
        if (LocalSave.JumpToKey(ClientContract.m_sUUID, true))
        {
            LocalSave.SetNum("completed", view_as<int>(ClientContract.IsContractComplete()));
            LocalSave.SetNum("contract_progress", ClientContract.m_iProgress);
            if (LocalSave.JumpToKey("objective_progress", true))
            {
                // Save each objective.
                for (int i = 0; i < ClientContract.m_hObjectives.Length; i++)
                {
                    char StrID[4];
                    IntToString(i, StrID, sizeof(StrID));
                    ContractObjective ClientContractObjective;
                    ClientContract.GetObjective(i, ClientContractObjective);
                    if (!ClientContractObjective.m_bInitalized) continue;

                    LocalSave.SetNum(StrID, ClientContractObjective.m_iProgress);
                }
            }
        }
    }
    LocalSave.Rewind();
    SaveLocalSave(steamid64, LocalSave);
    delete LocalSave;
    return true;
}

/**
 * Saves the session of a client to a file on disk.
 * @param client	Client index.
 * @param UUID	UUID to save as the session.
 * @error	Client index is invalid.
 */
public any Native_SaveLocalClientSession(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));

    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE SAVE: Saving client session.", client);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // Load and save.
    KeyValues LocalSave = LoadLocalSave(steamid64);
    LocalSave.SetString("session", UUID);
    LocalSave.Rewind();
    SaveLocalSave(steamid64, LocalSave);
    delete LocalSave;

    return true;
}

/**
 * Saves the preferences of a client to a file on disk.
 * @param client	Client index.
 * @error	Client index is invalid.
 */
public any Native_SaveLocalClientPreferences(Handle plugin, int numParams)
{
    int client = GetNativeCell(1)

    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE SAVE: Saving client preferences.", client);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64)); 

    // Load and save.
    KeyValues LocalSave = LoadLocalSave(steamid64);
    char name[64];
    LocalSave.GetSectionName(name, sizeof(name));
    if (LocalSave.JumpToKey("preferences", true))
    {
        LocalSave.SetNum(HELP_DB_NAME, view_as<int>(PlayerHelpTextEnabled[client]));
        LocalSave.SetNum(HINT_DB_NAME, view_as<int>(PlayerHintEnabled[client]));
        LocalSave.SetNum(HUD_DB_NAME, view_as<int>(PlayerHUDEnabled[client]));
        LocalSave.SetNum(SOUNDS_DB_NAME, view_as<int>(PlayerSoundsEnabled[client]));
    }
    LocalSave.Rewind();
    SaveLocalSave(steamid64, LocalSave);
    delete LocalSave;

    return true;
}

// Loads the Contract UUID from the last session.
void Local_LoadContractFromLastSession(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE SESSION: Loading client session.", client);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64)); 

    // Load and save.
    KeyValues LocalSave = LoadLocalSave(steamid64);

    char SessionUUID[MAX_UUID_SIZE] = "{}";
    LocalSave.GetString("session", SessionUUID, sizeof(SessionUUID), "{}")
    if (StrEqual(SessionUUID, "{}"))
    {
#if defined DEBUG
        if (g_DebugOffline.BoolValue)
        {
            LogMessage("[ZContracts] %N OFFLINE SESSION: No previous session found.", client);
        }
#endif
        return;
    }

    // Load information from the Contract.
    Contract NewContract;
    CreateContractFromUUID(SessionUUID, NewContract); // Load inital Contract data.
    Local_LoadContractProgress(client, SessionUUID, NewContract); // Load from save.
    SetClientContractStruct(client, NewContract, true, false);

    delete LocalSave;
}

void Local_LoadContractProgress(int client, char UUID[MAX_UUID_SIZE], Contract ContractBuffer)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE LOAD: Loading contract progress (%s).", client, UUID);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64)); 

    // Load and save.
    KeyValues LocalSave = LoadLocalSave(steamid64);
    if (LocalSave.JumpToKey("contracts"))
    {
        if (LocalSave.JumpToKey(UUID))
        {
            ContractBuffer.m_iProgress = LocalSave.GetNum("contract_progress", -1);
#if defined DEBUG
            if (g_DebugOffline.BoolValue)
            {
                LogMessage("[ZContracts] %N OFFLINE LOAD: Loaded contract progress (%d).", client, ContractBuffer.m_iProgress);
            }
#endif
            if (LocalSave.JumpToKey("objective_progress"))
            {
                // Save each objective.
                for (int i = 0; i < ContractBuffer.m_hObjectives.Length; i++)
                {
                    char StrID[4];
                    IntToString(i, StrID, sizeof(StrID));
                    ContractObjective ClientContractObjective;
                    ContractBuffer.GetObjective(i, ClientContractObjective);
                    if (!ClientContractObjective.m_bInitalized) continue;

                    ClientContractObjective.m_iProgress = LocalSave.GetNum(StrID, 0);
                    ContractBuffer.SaveObjective(i, ClientContractObjective);
#if defined DEBUG
                    if (g_DebugOffline.BoolValue)
                    {
                        LogMessage("[ZContracts] %N OFFLINE LOAD: Loaded contract objective %d progress (%d).",
                        client, i, ClientContractObjective.m_iProgress);
                    }
#endif
                }
            }
        }
    }
    delete LocalSave;
}


void Local_LoadAllClientPreferences(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE LOAD: Loading client preferences.", client);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64)); 

    // Load.
    KeyValues LocalSave = LoadLocalSave(steamid64);
    if (LocalSave.JumpToKey("preferences"))
    {
    #if defined DEBUG
        if (g_DebugOffline.BoolValue)
        {
            LogMessage("[ZContracts] %N OFFLINE LOAD: Loaded client preferences.", client);
        }
#endif
        PlayerHelpTextEnabled[client] = view_as<bool>(LocalSave.GetNum(HELP_DB_NAME, 1));
        PlayerHintEnabled[client] = view_as<bool>(LocalSave.GetNum(HINT_DB_NAME, g_DisplayHudMessages.BoolValue));
        PlayerSoundsEnabled[client] = view_as<bool>(LocalSave.GetNum(SOUNDS_DB_NAME, g_PlaySounds.BoolValue));
        PlayerHUDEnabled[client] = view_as<bool>(LocalSave.GetNum(HUD_DB_NAME, g_DisplayProgressHud.BoolValue));
    }
    else
    {
#if defined DEBUG
        if (g_DebugOffline.BoolValue)
        {
            LogMessage("[ZContracts] %N OFFLINE LOAD: No client preferences found.", client);
            PlayerHelpTextEnabled[client] = true;
            PlayerHintEnabled[client] = g_DisplayHudMessages.BoolValue;
            PlayerSoundsEnabled[client] = g_PlaySounds.BoolValue;
            PlayerHUDEnabled[client] = g_DisplayProgressHud.BoolValue;
        }
#endif
    }
    delete LocalSave;
}

void Local_LoadCompletedContracts(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE LOAD: Loading completed contracts.", client);
    }
#endif

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64)); 

    // Load.
    KeyValues LocalSave = LoadLocalSave(steamid64);
    if (LocalSave.JumpToKey("contracts"))
    {
        // Loop over all of our contracts to see if we've completed this.
        LocalSave.GotoFirstSubKey();
        char ContractUUID[MAX_UUID_SIZE];
        do
        {
            LocalSave.GetSectionName(ContractUUID, sizeof(ContractUUID));
            if (view_as<bool>(LocalSave.GetNum("completed")))
            {
                // Save internally.
                CompletedContracts[client].PushString(ContractUUID);
            }
        }
        while (LocalSave.GotoNextKey());
    }
#if defined DEBUG
    if (g_DebugOffline.BoolValue)
    {
        LogMessage("[ZContracts] %N OFFLINE LOAD: Loaded %d completed contracts.", client, CompletedContracts[client].Length);
    }
#endif
    delete LocalSave;
}

public any Native_TransferLocalSavesToDatabase(Handle plugin, int numParams)
{
    ArrayList SaveFiles = GetFilesInDirectoryRecursive(LocalSavePath);
    for (int i = 0; i < SaveFiles.Length; i++)
    {
        // Grab this file from the directory.
        char LocalSaveFilePath[PLATFORM_MAX_PATH];
        SaveFiles.GetString(i, LocalSaveFilePath, sizeof(LocalSaveFilePath));
        NormalizePathToPOSIX(LocalSaveFilePath);

        char SteamID64[64];
        // Load save.
        char SplitPathStr[16][72];
        ExplodeString(LocalSaveFilePath, "/", SplitPathStr, sizeof(SplitPathStr), sizeof(SplitPathStr[]));
        for (int j = 0; j < sizeof(SplitPathStr); j++)
        {
            // Check to see if this string is our SteamID.
            if (StrContains(SplitPathStr[j], ".txt") >= 0)
            {
                SplitString(SplitPathStr[j], ".", SteamID64, sizeof(SteamID64));
                break;
            }
        }

        // Open the save file.
        KeyValues LocalSave = LoadLocalSave(SteamID64);
        LogMessage("[ZContracts] Saving %s local file to database.", SteamID64);

        // Save all Contract and Objective data.
        if (LocalSave.JumpToKey("contracts"))
        {
            LocalSave.GotoFirstSubKey();
            char ContractUUID[MAX_UUID_SIZE];
            do
            {
                LocalSave.GetSectionName(ContractUUID, sizeof(ContractUUID));
                
                // Progress.
                SetContractProgressDatabase(SteamID64, ContractUUID, LocalSave.GetNum("contract_progress"));
                if (LocalSave.JumpToKey("objective_progress"))
                {
                    int id = 0;
                    LocalSave.GotoFirstSubKey();
                    do
                    {
                        char IDStr[4];
                        int Value = LocalSave.GetNum(IDStr);
                        if (Value != 0)
                        {
                            IntToString(id, IDStr, sizeof(IDStr));
                            SetObjectiveProgressDatabase(SteamID64, ContractUUID, id, LocalSave.GetNum(IDStr));
                        }

                        id++;
                    }
                    while (LocalSave.GotoNextKey());
                    LocalSave.GoBack();
                }

                // Completion status.
                if (view_as<bool>(LocalSave.GetNum("completed")))
                {
                    MarkContractAsCompleted(SteamID64, ContractUUID);
                }
            }
            while (LocalSave.GotoNextKey());
            LocalSave.GoBack();
        }
        LocalSave.Rewind();
        
        // Save the last session.
        char SessionUUID[MAX_UUID_SIZE];
        LocalSave.GetString("session", SessionUUID, sizeof(SessionUUID), "{}");
        if (!StrEqual(SessionUUID, "{}"))
        {
            SetSessionDatabase(SteamID64, SessionUUID);
        }

        // Save contract preferences.
        if (LocalSave.JumpToKey("preferences"))
        {
            bool Sounds, Hint, HUD, Help;
            Sounds = view_as<bool>(LocalSave.GetNum(SOUNDS_DB_NAME));
            Hint = view_as<bool>(LocalSave.GetNum(HINT_DB_NAME));
            HUD = view_as<bool>(LocalSave.GetNum(HUD_DB_NAME));
            Help = view_as<bool>(LocalSave.GetNum(HELP_DB_NAME));

            char query[1024];
            g_DB.Format(query, sizeof(query),
                "INSERT INTO preferences (steamid64, version, %s, %s, %s, %s) VALUES ('%s', %d, %d, %d, %d, %d)"
            ... " ON DUPLICATE KEY UPDATE version = %d, %s = %d, %s = %d, %s = %d, %s = %d",
            SOUNDS_DB_NAME, HINT_DB_NAME, HUD_DB_NAME, HELP_DB_NAME, SteamID64, CONTRACKER_VERSION, Sounds, Hint, HUD, Help,
            CONTRACKER_VERSION, SOUNDS_DB_NAME, Sounds,
            HINT_DB_NAME, Hint,
            HUD_DB_NAME, HUD,
            HELP_DB_NAME, Help);

            DataPack dp = new DataPack();
            dp.WriteString(SteamID64);
            dp.Reset();

            g_DB.Query(CB_SaveClientPreferences, query, dp, DBPrio_High); 
        }
        LocalSave.Rewind();
        
        // TODO: If any of these saves fail for *any* reason, we need to not delete the file from
        // disk so we can reattempt a save later.
        DeleteFile(LocalSaveFilePath);
        delete LocalSave;
    }

    return true;
}



public Action DebugSaveLocalPlayer(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[ZC] Usage: sm_savelocalplayer <target>");
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
        Contract ClientContract;
        GetClientContract(i, ClientContract);
        SaveLocalContractProgress(i, ClientContract);
        SaveLocalClientSession(i, ClientContract.m_sUUID);
        SaveLocalClientPreferences(i);
    }

    return Plugin_Continue;
}