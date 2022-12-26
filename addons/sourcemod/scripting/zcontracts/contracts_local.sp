#include <stocksoup/files>

char LocalSavePath[PLATFORM_MAX_PATH];

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