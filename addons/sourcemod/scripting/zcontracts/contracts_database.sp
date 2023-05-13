int g_DatabaseFails = 0;

/**
 * This is called when we connect to the database. If we do,
 * load player session data for all of the current clients.
*/
public void GotDatabase(Database db, const char[] error, any data)
{
    if (db == null)
    {
        if (g_DatabaseFails >= g_DatabaseMaximumFailures.IntValue)
        {
            SetFailState("Failed to connect to database.");
        }
        LogError("[ZContracts] Failed to connect to database... reattempting in %f seconds: failure: %s", g_DatabaseRetryTime.FloatValue, error);
        g_DatabaseRetryTimer = CreateTimer(g_DatabaseRetryTime.FloatValue, Timer_RetryDBConnect);
        g_DatabaseFails++;
    } 
    else 
    {
        PrintToServer("[ZContracts] Connected to database.");
        g_DB = db;

        for (int i = 0; i < MAXPLAYERS+1; i++)
	    {
            // Grab the players Contract from the last session.
            if (IsClientValid(i) && !IsFakeClient(i))
            {
                DB_LoadContractFromLastSession(i);
                DB_LoadAllClientPreferences(i);
                DB_LoadCompletedContracts(i);
            }
        }
    }
}

public Action ReloadDatabase(int client, int args)
{
    Database.Connect(GotDatabase, "zcontracts");
    return Plugin_Continue;
}

/**
 * The ConVar "zc_database_update_time" controls how often we update the database
 * with all of the player Contract information.
*/
public void OnDatabaseUpdateChange(ConVar convar, char[] oldValue, char[] newValue)
{
    delete g_DatabaseUpdateTimer;
    g_DatabaseUpdateTimer = CreateTimer(StringToFloat(newValue), Timer_SaveAllToDB, _, TIMER_REPEAT);
}

/**
 * The ConVar "zc_database_retry_time" is used when an attempt to connect to the database
 * fails and we need to reattempt at a later point.
 */
public void OnDatabaseRetryChange(ConVar convar, char[] oldValue, char[] newValue)
{
    delete g_DatabaseRetryTimer;
    g_DatabaseRetryTimer = CreateTimer(StringToFloat(newValue), Timer_RetryDBConnect);
}

public Action Timer_RetryDBConnect(Handle hTimer)
{
    Database.Connect(GotDatabase, "zcontracts");
    return Plugin_Continue;
}

/**
 * The ConVar "zc_database_update_time" controls how often we update the database
 * with all of the player Contract information.
 */

// TODO: Can we make this into a transaction?
public Action Timer_SaveAllToDB(Handle hTimer)
{
    for (int i = 0; i < MAXPLAYERS+1; i++)
    {
        if (!IsClientValid(i) || IsFakeClient(i)) continue;

        // Save this contract to the database.
        if (!ActiveContract[i].IsContractInitalized()) continue;

        if (g_DB != null)
        {
            // Save the Contract.
            if (ActiveContract[i].m_bNeedsDBSave)
            {
                SaveActiveContractToDatabase(i);
                ActiveContract[i].m_bNeedsDBSave = false;
            }
            // Save each of our objectives.
            for (int j = 0; j < ActiveContract[i].m_hObjectives.Length; j++)
            {
                ContractObjective ActiveContractObjective;
                ActiveContract[i].GetObjective(j, ActiveContractObjective);
                if (!ActiveContractObjective.m_bInitalized) continue;

                if (ActiveContractObjective.m_bNeedsDBSave)
                {
                    SaveActiveObjectiveToDatabase(i, j);
                    ActiveContractObjective.m_bNeedsDBSave = false;
                    ActiveContract[i].SaveObjective(j, ActiveContractObjective);
                }
            }
        }
    }
    return Plugin_Continue;
}

/**
 * Sets the progress of a Contract in the database.
 *
 * @param steamid64    Client index.
 * @param UUID	The UUID of the contract to modify.
 * @param value	The value to save to the database.
 * @error           Client index is invalid.         
 */
public any Native_SetContractProgressDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    int progress = GetNativeCell(3);

    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    char query[1024];
    g_DB.Format(query, sizeof(query),
        "INSERT INTO contract_progress (steamid64, contract_uuid, progress, version) VALUES ('%s', '%s', %d, %d)"
    ... " ON DUPLICATE KEY UPDATE progress = %d, version = %d", steamid64, UUID, progress, CONTRACKER_VERSION,
    progress, CONTRACKER_VERSION);

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.WriteCell(progress);
    dp.Reset();

    g_DB.Query(CB_SetContractProgressDatabase, query, dp, DBPrio_High);
    return true;
}

// Callback for SetContractProgressDatabase.
void CB_SetContractProgressDatabase(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    char contract_uuid[MAX_UUID_SIZE];
    int progress;
    dp.ReadString(steamid64, sizeof(steamid64));
    dp.ReadString(contract_uuid, sizeof(contract_uuid));
    progress = dp.ReadCell();
    
    // Error handling code.
    if (results == null)
    {
        LogError("[ZContracts] Failed to insert Contract progress: [SQL ERR: %s] [STEAMID64: %s, UUID: %s, PROGRESS: %d]", error, steamid64, contract_uuid, progress);
        
        // Reattempt save.
        SetContractProgressDatabase(steamid64, contract_uuid, progress);
    }
    else
    {
        if (results.AffectedRows < 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: No progress inserted for contract [SQL ERR: %s]", steamid64, error);
        }
        else if (results.AffectedRows == 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: Sucessfully saved progress for contract.", steamid64);
        }
    }

    delete dp;
}

/**
 * Sets the progress of an Objective in the database.
 *
 * @param client    Client index.
 * @param UUID	The UUID of the contract to modify.
 * @param objective_id	The ID of the objective to modify.
 * @param value	The value to save to the database.
 * @error           Client index is invalid.           
 */
public any Native_SetObjectiveProgressDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    int objective_id = GetNativeCell(3);
    int progress = GetNativeCell(4);

    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    // Don't save infinite objectives.
    KeyValues Schema = GetObjectiveSchema(UUID, objective_id+1);
    if (view_as<bool>(Schema.GetNum("infinite", 0)))
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Cannot set progress for an objective that's marked infinite (UUID: %s, OBJ: %d)", UUID, objective_id);
    }

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.WriteCell(progress);
    dp.WriteCell(objective_id);
    dp.Reset();

    char query[1024];
    g_DB.Format(query, sizeof(query),
        "INSERT INTO objective_progress (steamid64, contract_uuid, objective_id, progress, version) VALUES ('%s', '%s', %d, %d, %d)"
    ... " ON DUPLICATE KEY UPDATE progress = %d, version = %d", steamid64, UUID, objective_id, progress, CONTRACKER_VERSION, progress, CONTRACKER_VERSION);

    g_DB.Query(CB_SetObjectiveProgressDatabase, query, dp, DBPrio_High);
    return true;
}

// Callback for SetObjectiveProgressDatabase.
public void CB_SetObjectiveProgressDatabase(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    char contract_uuid[MAX_UUID_SIZE];
    int progress;
    int objective_id;
    dp.ReadString(steamid64, sizeof(steamid64));
    dp.ReadString(contract_uuid, sizeof(contract_uuid));
    progress = dp.ReadCell();
    objective_id = dp.ReadCell();
    
    // Error handling code.
    if (results == null)
    {
        LogError("[ZContracts] Failed to insert Contract progress for Objective %d: [SQL ERR: %s] [STEAMID64: %s, UUID: %s, PROGRESS: %d]",
        objective_id, error, steamid64, contract_uuid, progress);
        
        // Reattempt save.
        SetObjectiveProgressDatabase(steamid64, contract_uuid, objective_id, progress);
    }
    else
    {
        if (results.AffectedRows < 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: No progress inserted for Contract Objective %d [SQL ERR: %s]", steamid64, objective_id, error);
        }
        else if (results.AffectedRows == 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: Sucessfully saved progress for Contract Objective %d.", steamid64, objective_id);
        }
    }

    delete dp;
}

/**
 * Saves a Contract to the database for a client.
 *
 * @param client    Client index.
 * @error           Client index is invalid.      
 */
public any Native_SaveActiveContractToDatabase(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (IsFakeClient(client) && g_BotContracts.BoolValue) return false;
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
	}

    char UUID[MAX_UUID_SIZE];
    if (!GetClientContract(client, UUID, sizeof(UUID)))
    {
        LogMessage("SaveActiveContractToDatabase: Client does not have an active contract to save! (%d)", client);
        return false;
    }

    // Call pre-save forward.
    Call_StartForward(g_fOnContractPreSave);
    Call_PushCell(client);
    Call_PushString(UUID);
    bool ShouldBlock = false;
    Call_Finish(ShouldBlock);

    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // If noone responded or we got a positive response, save to database.
    if (GetForwardFunctionCount(g_fOnContractPreSave) == 0 || !ShouldBlock)
    {
        int ActiveProgress = GetActiveContractProgress(client);
        SetContractProgressDatabase(steamid64, UUID, ActiveProgress);
        
        return true;
    }
    else if (ShouldBlock)
    {
        if (g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %N SAVE: Contract progress save attempt interrupted.", client);
        }       
    }

    return false;
}

/**
 * Saves an Objective to the database for a client.
 *
 * @param client    Client index.
 * @param objective Objective ID.
 * @error           Client index is invalid.         
 */
public any Native_SaveActiveObjectiveToDatabase(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (IsFakeClient(client) && g_BotContracts.BoolValue) return false;
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
	}

    char UUID[MAX_UUID_SIZE];
    if (!GetClientContract(client, UUID, sizeof(UUID)))
    {
        LogMessage("SaveActiveObjectiveToDatabase: Client %N does not have an active contract to save!", client);
        return false;
    }

    int objective = GetNativeCell(2);
    if (objective > /*zero indexed*/ GetContractObjectiveCount(UUID)-1)
    {
        LogMessage("SaveActiveObjectiveToDatabase: Invalid contract objective ID passed (%N: %d)", client, objective);
        return false;
    }

    // Don't save infinite objectives.
    KeyValues Schema = GetObjectiveSchema(UUID, objective+1);
    if (view_as<bool>(Schema.GetNum("infinite", 0)))
    {
        PrintToChat(client, "Prevented infinite obj save!");
        return false;
    }

    // Call pre-save forward.
    Call_StartForward(g_fOnObjectivePreSave);
    Call_PushCell(client);
    Call_PushString(UUID);
    Call_PushCell(objective);
    bool ShouldBlock = false;
    Call_Finish(ShouldBlock);

    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // If noone responded or we got a positive response, save to database.
    if (GetForwardFunctionCount(g_fOnObjectivePreSave) == 0 || !ShouldBlock)
    {
        int ActiveProgress = GetActiveObjectiveProgress(client, objective);
        SetObjectiveProgressDatabase(steamid64, UUID, objective, ActiveProgress);
        
        return true;
    }

    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N SAVE: Objective progress save attempt interrupted.", client);
    }
    return false;
}

/**
 * Populates the progress for a client's Contract progress.
*/
public void CB_SetClientContract_Contract(Database db, DBResultSet results, const char[] error, int client)
{
    // This may need to change from CONTRACKER_VERSION in the future.
    const int MinimumRequiredVersion = 1;

    if (results == INVALID_HANDLE) return;
    while (results.FetchRow())
    {
        // Version check.
        int VersionField = 0;
        if (!results.FieldNameToNum("version", VersionField))
        {
            ThrowError("Missing required database key: \"version\" while fetching client %d contract data.", client);
        }
        int DataVersion = results.FetchInt(VersionField);
        if (MinimumRequiredVersion > DataVersion)
        {
            ThrowError("Outdated contract data. Minimum version: %d, data version: %d", MinimumRequiredVersion, DataVersion);
        }

        ActiveContract[client].m_iProgress = results.FetchInt(2);

        Call_StartForward(g_fOnContractProgressReceived);
        Call_PushCell(client);
        Call_PushString(ActiveContract[client].m_sUUID);
        Call_PushCell(ActiveContract[client].m_iProgress);
        Call_Finish();

        if (g_DebugQuery.BoolValue && IsClientValid(client))
        {
            LogMessage("[ZContracts] %N LOAD: Successfully grabbed Contract progress from database (%d/%d).",
            client, ActiveContract[client].m_iProgress, ActiveContract[client].m_iMaxProgress);
        }
    }

    ActiveContract[client].m_bLoadedFromDatabase = true;
}

/**
 * Populates the progress a client's Contract objectives.
*/
public void CB_SetClientContract_Objective(Database db, DBResultSet results, const char[] error, int client)
{
    // This may need to change from CONTRACKER_VERSION in the future.
    const int MinimumRequiredVersion = 1;

    if (results == INVALID_HANDLE) return;
    while (results.FetchRow())
    {
        // Version check.
        int VersionField = 0;
        if (!results.FieldNameToNum("version", VersionField))
        {
            ThrowError("Missing required database key: \"version\" while fetching client %d contract data.", client);
        }
        int DataVersion = results.FetchInt(VersionField);
        if (MinimumRequiredVersion > DataVersion)
        {
            ThrowError("Outdated contract objective data. Minimum version: %d, data version: %d", MinimumRequiredVersion, DataVersion);
        }

        ContractObjective hObj;
        int db_id = results.FetchInt(2);
        ActiveContract[client].GetObjective(db_id, hObj);
        hObj.m_iProgress = results.FetchInt(3);
        ActiveContract[client].SaveObjective(db_id, hObj);

        Call_StartForward(g_fOnObjectiveProgressReceived);
        Call_PushCell(client);
        Call_PushString(ActiveContract[client].m_sUUID);
        Call_PushCell(db_id);
        Call_PushCell(hObj.m_iProgress);
        Call_Finish();

        if (g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %N LOAD: Successfully grabbed ContractObjective %d progress from database CP: (%d/%d)",
            client, db_id, hObj.m_iProgress, hObj.m_iMaxProgress);
        }
    }

    ActiveContract[client].m_bLoadedFromDatabase = true;
}

/**
 * Marks the contract as complete in the database.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
 * @param data		Contract competion data.
*/
public any Native_SetContractCompletionInfoDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    CompletedContractInfo info;
    GetNativeArray(3, info, sizeof(CompletedContractInfo));

    if (UUID[0] != '{')
    {
        ThrowError("Invalid UUID passed. (%s)", UUID);
    }

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.WriteCell(info.m_iCompletions);
    dp.WriteCell(info.m_bReset);
    dp.Reset();

    char query[1024];
    g_DB.Format(query, sizeof(query), "INSERT INTO completed_contracts (steamid64, contract_uuid, completions, reset) VALUES ('%s', '%s', %d, %d)"
    ... " ON DUPLICATE KEY UPDATE completions = %d, reset = %d",
    steamid64, UUID, info.m_iCompletions, info.m_bReset, info.m_iCompletions, info.m_bReset);

    g_DB.Query(CB_SaveCompletedContract, query, dp, DBPrio_High);
    return true; 
}

public void CB_SaveCompletedContract(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    char contract_uuid[MAX_UUID_SIZE];
    int completions;
    bool reset;
    dp.ReadString(steamid64, sizeof(steamid64));
    dp.ReadString(contract_uuid, sizeof(contract_uuid));
    completions = dp.ReadCell();
    reset = dp.ReadCell();
    
    // Error handling code.
    if (results == null)
    {
        LogError("[ZContracts] Failed to insert Contract completion progress: [SQL ERR: %s] [STEAMID64: %s, UUID: %s, COMPLETIONS: %d, RESET: %d]",
        error, steamid64, contract_uuid, completions, reset);
        
        // Reattempt save.
        CompletedContractInfo info;
        info.m_iCompletions = completions;
        info.m_bReset = reset;
        SetCompletedContractInfoDatabase(steamid64, contract_uuid, info);
    }
    else
    {
        if (results.AffectedRows < 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: No completed data was updated for Contract [SQL ERR: %s]", steamid64, error);
        }
        else if (results.AffectedRows == 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: Sucessfully saved progress Contract completion data", steamid64);
        }
    }

    delete dp;
}

void DB_LoadCompletedContracts(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowError("Invalid client index. (%d)", client);
    }

    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N COMPLETE: Attempting to load completion status of all attempted Contracts.", client);
    }

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[1024];
    g_DB.Format(query, sizeof(query), "SELECT * FROM completed_contracts WHERE steamid64 = '%s'", steamid64);
    g_DB.Query(CB_LoadCompletedContracts, query, client, DBPrio_High);
    return;
}

public void CB_LoadCompletedContracts(Database db, DBResultSet results, const char[] error, int client)
{
    // Error handling.
    if (results == null)
    {
        LogError("[ZContracts] Failed to load Contract completion data: [SQL ERR: %s] [CLIENT: %N]", client);
        DB_LoadCompletedContracts(client);
        return;
    }

    while (results.FetchRow())
    {
        char UUID[MAX_UUID_SIZE];
        results.FetchString(1, UUID, sizeof(UUID));
        CompletedContractInfo info;
        info.m_iCompletions = results.FetchInt(2);
        info.m_bReset = view_as<bool>(results.FetchInt(3));
        CompletedContracts[client].SetArray(UUID, info, sizeof(CompletedContractInfo));
    }

    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N COMPLETE: Loaded %d attempted Contracts.", client, results.RowCount);
    }
}

public any Native_SetSessionDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));

    if (UUID[0] != '{')
    {
        ThrowError("Invalid UUID passed. (%s)", UUID);
    }

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.Reset();

    char query[1024];
    g_DB.Format(query, sizeof(query),
        "INSERT INTO selected_contract (steamid64, contract_uuid) VALUES ('%s', '%s')"
    ... " ON DUPLICATE KEY UPDATE contract_uuid = '%s'", steamid64, UUID, UUID);

    g_DB.Query(CB_SetSession, query, dp, DBPrio_High);
    return true;
}

public void CB_SetSession(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    char contract_uuid[MAX_UUID_SIZE];
    dp.ReadString(steamid64, sizeof(steamid64));
    dp.ReadString(contract_uuid, sizeof(contract_uuid));

    // Error handling code.
    if (results == null)
    {
        LogError("[ZContracts] Failed to set client session: [SQL ERR: %s] [STEAMID64: %s, SESSION UUID: %s]",
        error, steamid64, contract_uuid);
        
        SetSessionDatabase(steamid64, contract_uuid);
    }
    else
    {
        if (results.AffectedRows < 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: No update to client session. [SQL ERR: %s]", steamid64, error);
        }
        else if (results.AffectedRows == 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s SAVE: Sucessfully updated client session.", steamid64);
        }
    }

    delete dp;
}

/**
 * Deletes all client progress for a contract.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
*/
public any Native_DeleteContractProgressDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));

    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.Reset();

    char query[1024];
    g_DB.Format(query, sizeof(query), "DELETE FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'",
    steamid64, UUID);

    g_DB.Query(CB_DeleteContractProgress, query, dp, DBPrio_High);
    return true;
}

/**
 * Deletes all client progress for a contract.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
*/
public any Native_DeleteObjectiveProgressDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    int objective_id = GetNativeCell(3);

    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.WriteCell(objective_id);
    dp.Reset();

    char query[1024];
    g_DB.Format(query, sizeof(query), "DELETE FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND objective_id = %d",
    steamid64, UUID, objective_id);

    g_DB.Query(CB_DeleteObjectiveProgress, query, dp, DBPrio_High);
    return true;
}

public any Native_DeleteAllObjectiveProgressDatabase(Handle plugin, int numParams)
{
    char steamid64[64];
    GetNativeString(1, steamid64, sizeof(steamid64));
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));

    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.WriteString(UUID);
    dp.WriteCell(-1);
    dp.Reset();

    char query[1024];
    g_DB.Format(query, sizeof(query), "DELETE FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'",
    steamid64, UUID);

    g_DB.Query(CB_DeleteObjectiveProgress, query, dp, DBPrio_High);
    return true;
}

public void CB_DeleteContractProgress(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    char contract_uuid[MAX_UUID_SIZE];
    dp.ReadString(steamid64, sizeof(steamid64));
    dp.ReadString(contract_uuid, sizeof(contract_uuid));

    // Error handling code.
    if (results == null)
    {
        LogError("[ZContracts] Failed to delete Contract progress: [SQL ERR: %s] [STEAMID64: %s, UUID: %s]",
        error, steamid64, contract_uuid);
        
        DeleteContractProgressDatabase(steamid64, contract_uuid);
    }
    else
    {
        if (results.AffectedRows < 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s DELETE: No deletion required for Contract progress. [SQL ERR: %s]", steamid64, error);
        }
        else if (results.AffectedRows == 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s DELETE: Sucessfully deleted Contract progress.", steamid64);
        }
    }

    delete dp;
}

public void CB_DeleteObjectiveProgress(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    char contract_uuid[MAX_UUID_SIZE];
    int objective_id;
    dp.ReadString(steamid64, sizeof(steamid64));
    dp.ReadString(contract_uuid, sizeof(contract_uuid));
    objective_id = dp.ReadCell();

    // Error handling code.
    if (results == null)
    {
        LogError("[ZContracts] Failed to delete Contract Objective %d progress: [SQL ERR: %s] [STEAMID64: %s, UUID: %s]",
        error, objective_id, steamid64, contract_uuid);
        
        if (objective_id == -1) DeleteAllObjectiveProgressDatabase(steamid64, contract_uuid);
        else DeleteObjectiveProgressDatabase(steamid64, contract_uuid, objective_id);
    }
    else
    {
        if (results.AffectedRows < 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s DELETE: No deletion required for Contract Objective progress. [SQL ERR: %s]", steamid64, error);
        }
        else if (results.AffectedRows == 1 && g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %s DELETE: Sucessfully deleted Contract Objective progress.", steamid64);
        }
    }
}