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
    }
}

// Callback for getting ContractProgress progress.
public void CB_ContractProgress(Database db, DBResultSet results, const char[] error, any data)
{
    while (results.FetchRow())
    {
        Contract hContract;
        GetClientContract(data, hContract);
        hContract.m_iProgress = results.FetchInt(0);
    }
}

public void CB_ObjectiveProgress(Database db, DBResultSet results, const char[] error, DataPack hData)
{
    hData.Reset();
    int client = hData.ReadCell();
    bool display_to_client = hData.ReadCell();

    Contract hContract;
    GetClientContract(client, hContract);

    int id = 0;
    while (results.FetchRow())
    {
        ContractObjective hObj;
        hContract.GetObjective(id, hObj);
        hObj.m_iProgress = results.FetchInt(0); 
        hContract.SaveObjective(id, hObj);
        id++;
    }

    // Should we display to the client?
    if (display_to_client)
    {
        CreateObjectiveDisplay(client, hContract);
    }
}

// NOTE: This assumes that hBuffer has already been assigned the default values and objectives
// it needs. This function inserts the saved progress from the database.
public bool PopulateProgressFromDB(int client, const char[] uuid, bool display_to_client)
{
    Contract hContract;
    GetClientContract(client, hContract);

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    DataPack hData = new DataPack();
    hData.WriteCell(client);
    hData.WriteCell(display_to_client);

    // If we're tracking Contract progress, get this value from the database first.
    if (hContract.m_iContractType == Contract_ContractProgress)
    {
        char query[256];
        g_DB.Format(query, sizeof(query), 
        "SELECT progress FROM contract_progress WHERE steamid64 = '%s' AND contract_uuid = '%s'", steamid64, uuid);
        g_DB.Query(CB_ContractProgress, query, hData);
    }

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT progress FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND (objective_id BETWEEN 0 AND %d) ORDER BY objective_id ASC;", 
    steamid64, uuid, hContract.m_hObjectives.Length);
    g_DB.Query(CB_ObjectiveProgress, query, hData);

    return true;
}

public Action DebugGetProgress(int client, int args)
{	
    // Grab UUID.
    char sUUID[64];
    GetCmdArg(1, sUUID, sizeof(sUUID));

    PrintToChat(client, "[DEBUG] Getting progress data for contract: %s", sUUID);
    PopulateProgressFromDB(client, sUUID, false);

    return Plugin_Handled;
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
        //TODO: failsafe!
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
        //TODO: failsafe!
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
}

public void CB_ObjectiveProgressExists(Database db, DBResultSet results, const char[] error, DataPack hData)
{
    hData.Reset();
    hData.ReadCell();
    int objective_id = hData.ReadCell();
    int progress = hData.ReadCell();
    int is_complete = hData.ReadCell();
    char steamid64[64];
    hData.ReadString(steamid64, sizeof(steamid64));
    char uuid[MAX_UUID_SIZE];
    hData.ReadString(uuid, sizeof(uuid));

    // Update.
    if (results.RowCount > 0)
    {
        char query[256];
        db.Format(query, sizeof(query), 
        "UPDATE objective_progress SET progress = %d WHERE steamid64 = '%s' AND contract_uuid = '%s' AND objective_id = %d AND complete = %d", 
        progress, steamid64, uuid, objective_id, is_complete);
        db.Query(CB_Obj_OnUpdate, query, hData);
    }
    // Insert.
    else
    {
        char query[256];
        db.Format(query, sizeof(query), 
        "INSERT INTO objective_progress (steamid64, contract_uuid, objective_id, progress, complete) VALUES ('%s', '%s', %d, %d, %d)", 
        steamid64, uuid, objective_id, progress, is_complete);
        db.Query(CB_Obj_OnInsert, query, hData);
    }
}

// Saves the current progress of this objective.
public void SaveObjectiveProgressToDB(int client, const char[] uuid, int objective_id, int progress, bool is_complete)
{
    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    if (g_PrintQueryInfo.BoolValue)
    {
        PrintToServer("[ZContracts] Attempting to save progress for %N (%s) for objective id %d. Progress: %d",
        client, steamid64, objective_id, progress);
    }

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT progress FROM objective_progress WHERE steamid64 = '%s' AND contract_uuid = '%s' AND objective_id = %d", 
    steamid64, uuid, objective_id);

    DataPack hData = new DataPack();
    hData.WriteCell(client);
    hData.WriteCell(objective_id);
    hData.WriteCell(progress);
    hData.WriteCell(is_complete);
    hData.WriteString(steamid64);
    hData.WriteString(uuid);
    g_DB.Query(CB_ObjectiveProgressExists, query, hData, DBPrio_High);
}

public void SaveContractToDB(int client, Contract hContract)
{
    // TODO: ContractProgress saving
    for (int i = 0; i < hContract.m_hObjectives.Length; i++)
    {
        ContractObjective hObjective;
        hContract.GetObjective(i, hObjective);

        // Only update if we've actually gained some progress.
        if (hObjective.m_bNeedsDBSave == false) continue;
        if (hObjective.IsObjectiveComplete()) continue;

        SaveObjectiveProgressToDB(client, hContract.m_sUUID, hObjective.m_iInternalID,
        hObjective.m_iProgress, hObjective.IsObjectiveComplete());
    }
}

public Action DebugForceSave(int client, int args)
{	
    // Grab UUID.
    Contract hContract;
    GetClientContract(client, hContract);

    PrintToChat(client, "[DEBUG] Saving progress data for contract: %s", hContract.m_sUUID);
    SaveContractToDB(client, hContract);

    return Plugin_Handled;
}

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