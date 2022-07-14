
// NOTE: This assumes that hBuffer has already been assigned the default values and objectives
// it needs. This function inserts the saved progress from the database.
public bool PopulateProgressFromDB(int client, const char[] uuid, Contract hBuffer)
{
    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    // If we're tracking Contract progress, get this value from the database first.
    if (hBuffer.m_iContractType == Contract_ContractProgress)
    {
        // Start our query.
        char error[256];
        DBStatement hStatement = null;
        
        hStatement = SQL_PrepareQuery(g_DB, 
        "SELECT progress FROM contract_progress WHERE steamid64 = ? AND contract_uuid = ?", error, sizeof(error));
        if (hStatement == null)
        {
            PrintToServer("[ZC] Error setting up hStatement: %s", error);
            return false;
        }
        SQL_BindParamString(hStatement, 0, steamid64, false);
        SQL_BindParamString(hStatement, 1, uuid, false);
        
        // Get our stuff and put into the main Contract body first.
        if (!SQL_Execute(hStatement)) return false;
        while (SQL_FetchRow(hStatement))
        {
            hBuffer.m_iProgress = SQL_FetchInt(hStatement, 0);
            PrintToServer("[DEBUG] Progress: %d", hBuffer.m_iProgress);
        }
        delete hStatement;
    }

    // Start our query.
    char error[256];
    DBStatement hStatement = null;
    
    hStatement = SQL_PrepareQuery(g_DB, 
    "SELECT progress FROM objective_progress WHERE steamid64 = ? AND contract_uuid = ? AND (objective_id BETWEEN 0 AND ?) ORDER BY objective_id ASC;",
    error, sizeof(error));

    if (hStatement == null)
    {
        PrintToServer("[ZC] Error setting up hStatement: %s", error);
        return false;
    }
    SQL_BindParamString(hStatement, 0, steamid64, false);
    SQL_BindParamString(hStatement, 1, uuid, false);
    SQL_BindParamInt(hStatement, 2, hBuffer.m_hObjectives.Length);
    
    // Populate each objective with progress.
    if (!SQL_Execute(hStatement)) return false;

    int id = 0;
    while (SQL_FetchRow(hStatement))
    {
        ContractObjective hObj;
        hBuffer.m_hObjectives.GetArray(id, hObj, sizeof(ContractObjective));
        hObj.m_iProgress = SQL_FetchInt(hStatement, 0); 
        hBuffer.m_hObjectives.SetArray(id, hObj, sizeof(ContractObjective));
        PrintToServer("[DEBUG] Progress for objective %d: %d", id, hObj.m_iProgress);
        id++;
    }
    delete hStatement;

    PrintToServer("penis");
    return true;
}

public Action DebugGetProgress(int client, int args)
{	
    // Grab UUID.
    char sUUID[64];
    GetCmdArg(1, sUUID, sizeof(sUUID));
    PrintToChat(client, "Setting contract: %s", sUUID);

    Contract hContract;
    CreateContractFromUUID(sUUID, hContract);
    PopulateProgressFromDB(client, sUUID, hContract);

    return Plugin_Handled;
}
