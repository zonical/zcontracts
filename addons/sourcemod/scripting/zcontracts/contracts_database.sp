/**
 * This is called when we connect to the database. If we do,
 * load player session data for all of the current clients.
*/
public void GotDatabase(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("Database failure: %s", error);
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
                GrabContractFromLastSession(i);
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
        Contract ClientContract;
        GetClientContract(i, ClientContract);
        if (!ClientContract.IsContractInitalized()) continue;

        if (ClientContract.m_bNeedsDBSave)
        {
            SaveClientContractProgress(i, ClientContract);
            ClientContract.m_bNeedsDBSave = false;
        }

        for (int j = 0; j < ClientContract.m_hObjectives.Length; j++)
        {
            ContractObjective ClientContractObjective;
            ClientContract.GetObjective(j, ClientContractObjective);
            if (!ClientContractObjective.m_bInitalized) continue;

            if (ClientContractObjective.m_bNeedsDBSave)
            {
                SaveClientObjectiveProgress(i, ClientContract.m_sUUID, ClientContractObjective);
                ClientContractObjective.m_bNeedsDBSave = false;
                ClientContract.SaveObjective(j, ClientContractObjective);
            }
        }

        ClientContracts[i] = ClientContract;
    }
    return Plugin_Continue;
}

/**
 * Sets the progress of a Contract in the database.
 *
 * @param client    Client index.
 * @param UUID	The UUID of the contract to modify.
 * @param value	The value to save to the database.
 * @error           Client index is invalid.         
 */
public any Native_SetContractProgressDatabase(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    int progress = GetNativeCell(3);

    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
	}
    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[1024];
    g_DB.Format(query, sizeof(query),
        "INSERT INTO contract_progress (steamid64, contract_uuid, progress, version) VALUES ('%s', '%s', %d, %d)"
    ... " ON DUPLICATE KEY UPDATE progress = %d, version = %d", steamid64, UUID, progress, CONTRACKER_VERSION, progress, CONTRACKER_VERSION);

    g_DB.Query(CB_SetContractProgressDatabase, query, client, DBPrio_High);
    return true;
}

// Callback for SetContractProgressDatabase.
public void CB_SetContractProgressDatabase(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_DebugQuery.BoolValue && !StrEqual(error, ""))
        {
            LogMessage("[ZContracts] %N SAVE: Failed to save progress for contract [SQL ERR: %s]", client, error);
        }
        return;
    }
    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N SAVE: Sucessfully saved progress for contract.", client);
    }
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
    int client = GetNativeCell(1);
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    int objective_id = GetNativeCell(3);
    int progress = GetNativeCell(4);

    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
	}
    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[1024];
    g_DB.Format(query, sizeof(query),
        "INSERT INTO objective_progress (steamid64, contract_uuid, objective_id, progress, version) VALUES ('%s', '%s', %d, %d, %d)"
    ... " ON DUPLICATE KEY UPDATE progress = %d, version = %d", steamid64, UUID, objective_id, progress, CONTRACKER_VERSION, progress, CONTRACKER_VERSION);
    g_DB.Query(CB_SetObjectiveProgressDatabase, query, client, DBPrio_High);
    return true;
}

// Callback for SetObjectiveProgressDatabase.
public void CB_SetObjectiveProgressDatabase(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_DebugQuery.BoolValue && !StrEqual(error, ""))
        {
            LogMessage("[ZContracts] %N SAVE: Failed to save progress for objective [SQL ERR: %s]", client, error);
        }
        return;
    }
    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N SAVE: Sucessfully saved progress for objective.", client);
    }
}

/**
 * Saves a Contract to the database for a client.
 *
 * @param client    Client index.
 * @param ClientContract The enum struct of the contract to save.
 * @error           Client index is invalid or the Contract is invalid.         
 */
public any Native_SaveClientContractProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    Contract ClientContract;
    GetNativeArray(2, ClientContract, sizeof(Contract));

    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
	}
    if (ClientContract.m_sUUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", ClientContract.m_sUUID);
    }

    // Call pre-save forward.
    Call_StartForward(g_fOnContractPreSave);
    Call_PushCell(client);
    Call_PushString(ClientContract.m_sUUID);
    Call_PushArray(ClientContract, sizeof(Contract));
    bool ShouldBlock = false;
    Call_Finish(ShouldBlock);

    // If noone responded or we got a positive response, save to database.
    if (GetForwardFunctionCount(g_fOnContractPreSave) == 0 || !ShouldBlock)
    {
        if (ClientContract.m_iProgress > 0)
        {
            SetContractProgressDatabase(client, ClientContract.m_sUUID, ClientContract.m_iProgress);
        }
        return true;
    }

    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N SAVE: Contract progress save attempt interrupted.", client);
    }
    return false;
}

/**
 * Saves an Objective to the database for a client.
 *
 * @param client    Client index.
 * @param UUID	UUID of the Contract that contains this objective.
 * @param ClientObjective The enum struct of the objective to save.
 * @error           Client index is invalid or the ClientObjective is invalid.         
 */
public any Native_SaveClientObjectiveProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char UUID[MAX_UUID_SIZE];
    GetNativeString(2, UUID, sizeof(UUID));
    ContractObjective ClientContractObjective;
    GetNativeArray(3, ClientContractObjective, sizeof(ContractObjective));

    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
	}
    if (UUID[0] != '{')
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid UUID passed. (%s)", UUID);
    }

    // Call pre-save forward.
    Call_StartForward(g_fOnObjectivePreSave);
    Call_PushCell(client);
    Call_PushString(UUID);
    Call_PushArray(ClientContractObjective, sizeof(ContractObjective));
    bool ShouldBlock = false;
    Call_Finish(ShouldBlock);

    // If noone responded or we got a positive response, save to database.
    if (GetForwardFunctionCount(g_fOnObjectivePreSave) == 0 || !ShouldBlock)
    {
        if (ClientContractObjective.m_iProgress > 0)
        {
            SetObjectiveProgressDatabase(client, UUID, ClientContractObjective.m_iInternalID, ClientContractObjective.m_iProgress);
        }
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
    Contract ClientContract;
    GetClientContract(client, ClientContract);

    while (results.FetchRow())
    {
        ClientContract.m_iProgress = results.FetchInt(2);
        if (g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %N LOAD: Successfully grabbed Contract progress from database (%d/%d).", client, ClientContract.m_iProgress, ClientContract.m_iMaxProgress);
        }
    }

    ClientContract.m_bLoadedFromDatabase = true;
    ClientContracts[client] = ClientContract;
}

/**
 * Populates the progress a client's Contract objectives.
*/
public void CB_SetClientContract_Objective(Database db, DBResultSet results, const char[] error, int client)
{
    Contract ClientContract;
    GetClientContract(client, ClientContract);

    while (results.FetchRow())
    {
        ContractObjective hObj;
        int db_id = results.FetchInt(2);
        ClientContract.GetObjective(db_id, hObj);
        hObj.m_iProgress = results.FetchInt(3);
        ClientContract.SaveObjective(db_id, hObj);

        if (g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %N LOAD: Successfully grabbed ContractObjective %d progress from database CP: (%d/%d)",
            client, db_id, hObj.m_iProgress, hObj.m_iMaxProgress);
        }
    }

    ClientContract.m_bLoadedFromDatabase = true;
    ClientContracts[client] = ClientContract;
}