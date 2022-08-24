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
 * Inserts the progression data for the current clients Contract. This assumes that
 * the client has already had a Contract constructed for them (see CreateContractFromUUID).
 *
 * @param client    	        Client index.
 * @param display_to_client		If true, this function will call CreateObjectiveDisplay to display the progress of the client's Contract.
 * @error                       Client index is invalid. 
 */
bool PopulateProgressFromDB(int client, bool display_to_client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

    Contract hContract;
    GetClientContract(client, hContract);

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // If we're tracking Contract progress, get this value from the database first.
    if (hContract.m_iContractType == Contract_ContractProgress)
    {
        char query[256];
        g_DB.Format(query, sizeof(query), 
        "SELECT * FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'", steamid64, hContract.m_sUUID);
        g_DB.Query(CB_ContractProgress, query, client);
    }

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT * FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND (objective_id BETWEEN 0 AND %d) ORDER BY objective_id ASC;", 
    steamid64, hContract.m_sUUID, hContract.m_hObjectives.Length);
    g_DB.Query(CB_ObjectiveProgress, query, client);

    // Create our display.
    if (display_to_client)
    {
        CreateObjectiveDisplay(client, hContract, true);
        CreateTimer(1.0, Timer_DisplayContractInfo, client);
    }

    return true;
}

/**
 * There is a *very small* delay in getting the information from the database
 * and inserting it into the client's Contract.
*/
public Action Timer_DisplayContractInfo(Handle hTimer, int client)
{
    Contract hContract;
    GetClientContract(client, hContract);
    CreateObjectiveDisplay(client, hContract, false);
    return Plugin_Stop;
}

/**
 * Populates the progress for a client's Contract progress.
*/
public void CB_ContractProgress(Database db, DBResultSet results, const char[] error, int client)
{
    Contract hContract;
    GetClientContract(client, hContract);

    while (results.FetchRow())
    {
        hContract.m_iProgress = results.FetchInt(2);
    }

    m_hContracts[client] = hContract;
}

/**
 * Populates the progress a client's Contract objectives.
*/
public void CB_ObjectiveProgress(Database db, DBResultSet results, const char[] error, int client)
{
    Contract hContract;
    GetClientContract(client, hContract);

    int id = 0;
    while (results.FetchRow())
    {
        ContractObjective hObj;
        hContract.GetObjective(id, hObj);
        hObj.m_iProgress = results.FetchInt(3);
        hObj.m_iFires = results.FetchInt(4); 
        hContract.SaveObjective(id, hObj);
        id++;
    }

    m_hContracts[client] = hContract;
}

// ====================================================================================

/**
 * Saves the progression data for Contract-Style progression Contract's. This does NOT
 * save objectives (see SaveObjectiveProgressToDB and SaveContractToDB). 
 *
 * @param client    	        Client index.
 * @param display_to_client		If true, this function will call CreateObjectiveDisplay to display the progress of the client's Contract.
 * @error                       Client index is invalid. 
 */
void SaveContractProgressToDB(int client, const char[] uuid, int progress, bool is_complete)
{
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT * FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'", steamid64, uuid);

    DataPack hData = new DataPack();
    hData.WriteCell(client);
    hData.WriteCell(progress);
    hData.WriteCell(is_complete);
    hData.WriteString(steamid64);
    hData.WriteString(uuid);
    g_DB.Query(CB_ContractProgressExists, query, hData, DBPrio_High);
}

public void CB_ContractProgressExists(Database db, DBResultSet results, const char[] error, DataPack hData)
{
    hData.Reset();
    int client = hData.ReadCell();
    int progress = hData.ReadCell();
    int is_complete = hData.ReadCell();
    char steamid64[64];
    hData.ReadString(steamid64, sizeof(steamid64));
    char uuid[MAX_UUID_SIZE];
    hData.ReadString(uuid, sizeof(uuid));

    // Update.
    if (results.RowCount > 0)
    {
        // Is this data already the same as what we have? Why are we updating?
        while (results.FetchRow())
        {
            if (results.FetchInt(2) == progress)
            {
                // Reset our save status.
                Contract hContract;
                GetClientContract(client, hContract);
                hContract.m_bNeedsDBSave = false;
                m_hContracts[client] = hContract;
            }
            else
            {
                // Update our current progress.
                char query[256];
                db.Format(query, sizeof(query), 
                "UPDATE contract_progress SET progress = %d, complete = %d WHERE steamid64 = '%s' AND contract_uuid = '%s'", 
                progress, is_complete, steamid64, uuid);
                db.Query(CB_Con_OnUpdate, query, client);
            }
        }
    }
    // Insert.
    else
    {
        char query[256];
        db.Format(query, sizeof(query), 
        "INSERT INTO contract_progress (steamid64, contract_uuid, progress, complete) VALUES ('%s', '%s', %d, %d)", 
        steamid64, uuid, progress, is_complete);
        db.Query(CB_Con_OnInsert, query, client);
    }
}

public void CB_Con_OnUpdate(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_PrintQueryInfo.BoolValue)
        {
            PrintToServer("[ZContracts] Failed to update player %N contract progress. [%s]", client, error);
        }
        return;
    }
    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Updated player %N progress for contract.", client);
    }

    // Reset our save status.
    Contract hContract;
    GetClientContract(client, hContract);
    hContract.m_bNeedsDBSave = false;
    m_hContracts[client] = hContract;
}

public void CB_Con_OnInsert(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_PrintQueryInfo.BoolValue)
        {
            PrintToServer("[ZContracts] Failed to insert player %N progress for contract. [%s]", client, error);
        }
        return;
    }

    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Inserted player %N progress for contract.", client);
    }

    // Reset our save status.
    Contract hContract;
    GetClientContract(client, hContract);
    hContract.m_bNeedsDBSave = false;
    m_hContracts[client] = hContract;
}

// ====================================================================================

/**
 * Saves the progression data for a Contract objective..
 *
 * @param client    	        Client index.
 * @param uuid                  The UUID of the original Contract
 * @param hObjective		    Objective to save to the Database.
 * @error                       Client index is invalid. 
 */
void SaveObjectiveProgressToDB(int client, const char[] uuid, ContractObjective hObjective)
{
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Attempting to save progress for %N (%s) for objective id %d. Progress: %d",
        client, steamid64, hObjective.m_iInternalID, hObjective.m_iProgress);
    }

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT * FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND objective_id = %d", 
    steamid64, uuid, hObjective.m_iInternalID);

    DataPack hData = new DataPack();
    hData.WriteCell(client);
    hData.WriteCell(hObjective.m_iInternalID);
    hData.WriteCell(hObjective.m_iProgress);
    hData.WriteCell(hObjective.m_iFires);
    hData.WriteCell(hObjective.IsObjectiveComplete());
    hData.WriteString(steamid64);
    hData.WriteString(uuid);
    g_DB.Query(CB_ObjectiveProgressExists, query, hData, DBPrio_High);
}

public void CB_ObjectiveProgressExists(Database db, DBResultSet results, const char[] error, DataPack hData)
{
    hData.Reset();
    int client = hData.ReadCell();
    int objective_id = hData.ReadCell();
    int progress = hData.ReadCell();
    int fires = hData.ReadCell();
    int is_complete = hData.ReadCell();
    char steamid64[64];
    hData.ReadString(steamid64, sizeof(steamid64));
    char uuid[MAX_UUID_SIZE];
    hData.ReadString(uuid, sizeof(uuid));

    // Update.
    if (results.RowCount > 0)
    {
        while (results.FetchRow())
        {
            // Is this data already the same as what we have? Why are we updating?
            if (results.FetchInt(3) == progress)
            {
                // Reset our save status.
                Contract hContract;
                GetClientContract(client, hContract);
                ContractObjective hObjective;
                hContract.GetObjective(objective_id, hObjective);
                hObjective.m_bNeedsDBSave = false;
                hContract.SaveObjective(objective_id, hObjective);
                m_hContracts[client] = hContract;
            }
            else
            {
                char query[256];
                db.Format(query, sizeof(query), 
                "UPDATE objective_progress SET progress = %d, fires = %d, complete = %d WHERE steamid64 = '%s' AND contract_uuid = '%s' AND objective_id = %d", 
                progress, fires, is_complete, steamid64, uuid, objective_id);
                db.Query(CB_Obj_OnUpdate, query, hData);   
            }
        }

    }
    // Insert.
    else
    {
        char query[256];
        db.Format(query, sizeof(query), 
        "INSERT INTO objective_progress (steamid64, contract_uuid, objective_id, progress, fires, complete) VALUES ('%s', '%s', %d, %d, %d, %d)", 
        steamid64, uuid, objective_id, progress, fires, is_complete);
        db.Query(CB_Obj_OnInsert, query, hData);
    }
}

public void CB_Obj_OnUpdate(Database db, DBResultSet results, const char[] error, DataPack hData)
{
    hData.Reset();
    int client = hData.ReadCell();
    int objective_id = hData.ReadCell();
    if (results.AffectedRows < 1)
    {
        if (g_PrintQueryInfo.BoolValue)
        {
            PrintToServer("[ZContracts] Failed to update player %N progress for objective id %d. [%s]", client, objective_id, error);
        }
        return;
    }
    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Updated player %N progress for objective id %d.", client, objective_id);
    }

    // Reset our save status.
    Contract hContract;
    GetClientContract(client, hContract);
    ContractObjective hObjective;
    hContract.GetObjective(objective_id, hObjective);
    hObjective.m_bNeedsDBSave = false;
    hContract.SaveObjective(objective_id, hObjective);
    m_hContracts[client] = hContract;
}

public void CB_Obj_OnInsert(Database db, DBResultSet results, const char[] error, DataPack hData)
{
    hData.Reset();
    int client = hData.ReadCell();
    int objective_id = hData.ReadCell();
    if (results.AffectedRows < 1)
    {
        if (g_PrintQueryInfo.BoolValue)
        {
            PrintToServer("[ZContracts] Failed to insert player %N progress for objective id %d. [%s]", client, objective_id, error);
        }
        return;
    }

    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Inserted player %N progress for objective id %d.", client, objective_id);
    }

    // Reset our save status.
    Contract hContract;
    GetClientContract(client, hContract);
    ContractObjective hObjective;
    hContract.GetObjective(objective_id, hObjective);
    hObjective.m_bNeedsDBSave = false;
    hContract.SaveObjective(objective_id, hObjective);
    m_hContracts[client] = hContract;
}

// ====================================================================================

/**
 * Saves the progression data for a Contract to the database. This is a handy wrapper
 * that calls SaveContractProgressToDB and SaveObjectiveProgressToDB for you.
 *
 * @param client    	        Client index.
 * @param hContract		        The Contract to save to the database.
 * @error                       Client index is invalid. 
 */
void SaveContractToDB(int client, Contract hContract)
{
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

    // Save the overall progress of this Contract.
    if (hContract.m_iContractType == Contract_ContractProgress)
    {
        SaveContractProgressToDB(client, hContract.m_sUUID, 
        hContract.m_iProgress, hContract.IsContractComplete());
    }

    // Save the contract objectives.
    for (int i = 0; i < hContract.m_hObjectives.Length; i++)
    {
        ContractObjective hObjective;
        hContract.GetObjective(i, hObjective);

        // Only update if we've actually gained some progress.
        if (hObjective.m_bNeedsDBSave == false) continue;
        if (hObjective.IsObjectiveComplete()) continue;

        SaveObjectiveProgressToDB(client, hContract.m_sUUID, hObjective);
    }
}

/**
 * The ConVar "zc_database_update_time" controls how often we update the database
 * with all of the player Contract information.
 */
public Action Timer_SaveAllToDB(Handle hTimer)
{
    for (int i = 0; i < MAXPLAYERS+1; i++)
    {
        if (!IsClientValid(i) || IsFakeClient(i)) continue;
        // Save this contract to the database.
        Contract hContract;
        GetClientContract(i, hContract);
        SaveContractToDB(i, hContract);
    }
    return Plugin_Continue;
}

// ====================================================================================

/**
 * Gets the last Contract the client selected from their last game session and
 * sets it as the active Contract.
 *
 * @param client    	        Client index.
 * @error                       Client index is invalid. 
 */
void GrabContractFromLastSession(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT contract_uuid FROM selected_contract WHERE steamid64 = '%s'", steamid64);
    g_DB.Query(CB_GetContractFromLastSession, query, client, DBPrio_High);
}

public void CB_GetContractFromLastSession(Database db, DBResultSet results, const char[] error, int client)
{
    char uuid[MAX_UUID_SIZE];
    if (results.RowCount < 1) return;

    while (results.FetchRow())
    {
        results.FetchString(0, uuid, sizeof(uuid));
        SetClientContract(client, uuid);
    }
}

/**
 * Saves the client's Contract UUID to the database. If the client disconnects,
 * this value will be used to grab the Contract again on reconnect.
 *
 * @param client    	        Client index.
 * @error                       Client index is invalid. 
 */
void SaveContractSession(int client)
{
    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT * FROM selected_contract WHERE steamid64 = '%s'", steamid64);
    g_DB.Query(CB_DoesSessionExist, query, client);
}

public void CB_DoesSessionExist(Database db, DBResultSet results, const char[] error, int client)
{
    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // Get our client's current contract.
    Contract hContract;
    GetClientContract(client, hContract);

    if (results.RowCount < 1)
    {
        // Insert our new row into the database.
        char query[256];
        db.Format(query, sizeof(query), 
        "INSERT INTO selected_contract (steamid64, contract_uuid) VALUES ('%s', '%s')", steamid64, hContract.m_sUUID);
        db.Query(CB_Session_OnInsert, query, client);
    }
    else
    {
        while (results.FetchRow())
        {
            // Is our UUID the same?
            char stored_uuid[MAX_UUID_SIZE];
            results.FetchString(1, stored_uuid, sizeof(stored_uuid));

            if (!StrEqual(stored_uuid, hContract.m_sUUID))
            {
                // Update our row in the database.
                char query[256];
                db.Format(query, sizeof(query), 
                "UPDATE selected_contract SET contract_uuid = '%s' WHERE steamid64 = '%s'", hContract.m_sUUID, steamid64);
                db.Query(CB_Session_OnUpdate, query, client);
            }
        }
    }
}

public void CB_Session_OnUpdate(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_PrintQueryInfo.BoolValue)
        {
            PrintToServer("[ZContracts] Failed to update player %N session. [%s]", client, error);
        }
        return;
    }
    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Updated player %N session.", client);
    }
}

public void CB_Session_OnInsert(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows < 1)
    {
        if (g_PrintQueryInfo.BoolValue)
        {
            PrintToServer("[ZContracts] Failed to insert player %N session. [%s]", client, error);
        }
        return;
    }

    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Inserted player %N session.", client);
    }
}

// ====================================================================================

/**
 * Resets Contract's for a group of clients. If a UUID isn't provided, ALL contract
 * progress will be removed for clients.
 *
 * @param client    	        Client index.
 * @error                       Client index is invalid. 
 */

/*
void ResetMultipleClientsContract(int clients[MAXPLAYERS], const char[] uuid = "")
{
    // Loop over all clients and grab their SteamID64's.
    char steamid64[MAXPLAYERS][64];
    for (int i = 1; i < MAXPLAYERS+1; i++)
    {
        if (!IsClientValid(i) && IsFakeClient(i)) continue;
        GetClientAuthId(i, AuthId_SteamID64, steamid64[i], sizeof(steamid64[]));
    }

    // Remove Contract-style progress:

    // Prepare a query.
    char query[2048]; // 2048 - just in case we have a ton of clients.
    query = "DELETE FROM contract_progress WHERE ";
    for (int i = 0; i < MAXPLAYERS+1; i++)
    {
        if (!IsClientValid(i) && IsFakeClient(i)) continue;
        char str_to_add[128];
        Format(str_to_add, sizeof(str_to_add), "steamid64 = '%s'", steamid64);
        StrCat(query, sizeof(query), str_to_add);
        PrintToChatAll(query);

        if (clients[i+1] != 0)
        {
            StrCat(query, sizeof(query), " AND ");
        }
        else break;
    }
    

    // Are we removing by UUID?
    if (uuid[0] != '{')
    {
        StrCat(query, sizeof(query), " AND contract_uuid = '%s'");
        Format(query, sizeof(query), query, uuid);
    }

    
    //g_DB.Query(CB_ResetMultipleClients, query, clients);
}*/