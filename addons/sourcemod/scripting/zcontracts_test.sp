#include <sourcemod>
#include <zcontracts/zcontracts>

public Plugin myinfo =
{
	name = "ZContracts - Testing",
	author = "ZoNiCaL",
	description = "",
	version = "lol what",
	url = ""
};

public void OnClientActivatedContract(int client, char UUID[MAX_UUID_SIZE])
{
    PrintToChat(client, "Activated Contract %s", UUID);

    // Schema testing.
    KeyValues ContractSchema = GetContractSchema(UUID);

    if (ContractSchema != INVALID_HANDLE)
    {
        char ContractName[MAX_CONTRACT_NAME_SIZE];
        ContractSchema.GetString("name", ContractName, sizeof(ContractName));
        PrintToChat(client, "Grabbed Contract \"%s\" schema successfully", ContractName);
    }

    int ObjectiveCount = GetContractObjectiveCount(UUID);
    PrintToChat(client, "Amount of objectives: %d", ObjectiveCount);
    for (int i = 1; i < ObjectiveCount+1; i++)
    {
        KeyValues ObjectiveSchema = GetObjectiveSchema(UUID, i);
        if (ObjectiveSchema != INVALID_HANDLE)
        {
            char ObjectiveDesc[MAX_OBJECTIVE_DESC_SIZE];
            ObjectiveSchema.GetString("description", ObjectiveDesc, sizeof(ObjectiveDesc));
            PrintToChat(client, "Grabbed Objective %d \"%s\" schema successfully", i, ObjectiveDesc);
        }
    }
}

public void OnContractProgressReceived(int client, char UUID[MAX_UUID_SIZE], int progress)
{
    // Progress testing. Yes it's right there but I'm testing the Natives!
    PrintToChat(client, "Main Contract Progress: %d", GetActiveContractProgress(client));
}

public void OnObjectiveProgressReceived(int client, char UUID[MAX_UUID_SIZE], int objective, int progress)
{
    int ObjectiveCount = GetContractObjectiveCount(UUID);
    for (int i = 0; i < ObjectiveCount-1; i++)
    {
        PrintToChat(client, "Objective %d Progress: %d", i, GetActiveObjectiveProgress(client, i+1));
    }
}