
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

public void CB_ObjectiveProgress(Database db, DBResultSet results, const char[] error, any data)
{
    Contract hContract;
    GetClientContract(data, hContract);

    int id = 0;
    while (results.FetchRow())
    {
        ContractObjective hObj;
        hContract.m_hObjectives.GetArray(id, hObj, sizeof(ContractObjective));
        hObj.m_iProgress = results.FetchInt(0); 
        hContract.m_hObjectives.SetArray(id, hObj, sizeof(ContractObjective));
        PrintToServer("[DEBUG] Progress for objective %d: %d", id, hObj.m_iProgress);
        id++;
    }
}

// NOTE: This assumes that hBuffer has already been assigned the default values and objectives
// it needs. This function inserts the saved progress from the database.
public bool PopulateProgressFromDB(int client, const char[] uuid)
{
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
        "SELECT progress FROM contract_progress WHERE steamid64 = %s AND contract_uuid = %s", steamid64, uuid);
        g_DB.Query(CB_ContractProgress, query, client);
    }

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT progress FROM objective_progress WHERE steamid64 = ? AND contract_uuid = ? AND (objective_id BETWEEN 0 AND ?) ORDER BY objective_id ASC;", 
    steamid64, uuid, hContract.m_hObjectives.Length);
    g_DB.Query(CB_ContractProgress, query, client);

    return true;
}

public Action DebugGetProgress(int client, int args)
{	
    // Grab UUID.
    char sUUID[64];
    GetCmdArg(1, sUUID, sizeof(sUUID));
    PrintToChat(client, "Setting contract: %s", sUUID);

    PopulateProgressFromDB(client, sUUID);
    return Plugin_Handled;
}

public void CB_Obj_OnUpdate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hData = view_as<DataPack>(data);
    int client = hData.ReadCell();
    int objective_id = hData.ReadCell();
    if (results.AffectedRows < 1)
    {
        PrintToServer("[ZContracts] Failed to update player %N progress for objective id %d.", client, objective_id);
        //TODO: failsafe!
    }
}

public void CB_Obj_OnInsert(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hData = view_as<DataPack>(data);
    int client = hData.ReadCell();
    int objective_id = hData.ReadCell();
    if (results.AffectedRows < 1)
    {
        PrintToServer("[ZContracts] Failed to insert player %N progress for objective id %d.", client, objective_id);
        //TODO: failsafe!
    }
}

public void CB_ObjectiveProgressExists(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hData = view_as<DataPack>(data);
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
        g_DB.Format(query, sizeof(query), 
        "UPDATE objective_progress SET progress = ? AND complete = ? WHERE steamid64 = ? AND contract_uuid = ? AND objective_id = ?", 
        progress, is_complete, steamid64, uuid, objective_id);
        g_DB.Query(CB_Obj_OnUpdate, query, hData);
    }
    // Insert.
    else
    {
        char query[256];
        g_DB.Format(query, sizeof(query), 
        "INSERT INTO objective_progress (steamid64, contract_uuid, objective_id, progress, complete) VALUES (?, ?, ?, ?, ?)", 
        steamid64, uuid, objective_id, progress, is_complete);
        g_DB.Query(CB_Obj_OnInsert, query, hData);
    }
}

// Saves the current progress of this objective
public void SaveObjectiveProgressToDB(int client, const char[] uuid, ContractObjective hObjective)
{
    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[256];
    g_DB.Format(query, sizeof(query), 
    "SELECT progress FROM objective_progress WHERE steamid64 = ? AND contract_uuid = ? AND objective_id = ?", 
    steamid64, uuid, hObjective.m_iInternalID);

    DataPack hData = new DataPack();
    hData.WriteCell(client);
    hData.WriteCell(hObjective.m_iInternalID);
    hData.WriteCell(hObjective.m_iProgress);
    hData.WriteCell(hObjective.IsObjectiveComplete());
    hData.WriteString(steamid64);
    hData.WriteString(uuid);
    g_DB.Query(CB_ObjectiveProgressExists, query, hData);
}