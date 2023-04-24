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

public void OnClientActivatedContractPost(int client, char UUID[MAX_UUID_SIZE])
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
    PrintToChat(client, "Is active contract complete: %d", IsActiveContractComplete(client));
    PrintToChat(client, "Main Contract Progress: %d", GetActiveContractProgress(client));

    for (int i = 0; i < ObjectiveCount-1; i++)
    {
        PrintToChat(client, "Objective %d Progress: %d", i, GetActiveObjectiveProgress(client, i+1));
    }

    StringMap CompletedContracts = GetClientCompletedContracts(client);
    PrintToChat(client, "Completed Contracts: %d", CompletedContracts.Size);
    PrintToChat(client, "Can activate this contract: %d", CanClientActivateContract(client, UUID));
    PrintToChat(client, "Can complete contract: %d", CanClientCompleteContract(client, UUID));
    PrintToChat(client, "Has client completed contract: %d", HasClientCompletedContract(client, UUID));
}