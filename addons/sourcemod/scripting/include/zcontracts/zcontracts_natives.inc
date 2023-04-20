#if defined __zcontracts_natives_included
	#endinput
#endif

#define __zcontracts_natives_included


/**
 * The Contracker version is used to determine the minimum Contract that should be
 * loaded from the database. This is intended to be used when a change is made to the
 * database structure or there is a breaking change in ZContracts.
 * @return The value of CONTRACKER_VERSION from zcontracts_main.sp
 */
native int GetContrackerVersion();

/**
 * Set a client's contract.
 *
 * @param client    Client index.
 * @param UUID    	The UUID of the contract.
 * @error           Client index is invalid or UUID is invalid.         
 */
native bool SetClientContract(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Set a client's contract (with extended functionality)
 *
 * @param client    Client index.
 * @param UUID    	The UUID of the contract.
 * @param dont_save	Optional argument: doesn't save this as the active Contract in the database.
 * @param dont_notify Optional argument: don't notify the player that we've set their contract.
 * @error           Client index is invalid or UUID is invalid.         
 */
native bool SetClientContractEx(int client, char UUID[MAX_UUID_SIZE], bool dont_save = false, bool dont_notify = false);

/**
 * Obtain a client's active Contract UUID.
 * 
 * @param client	Client index.
 * @param uuidbuffer	Buffer to store the UUID.
 * @param uuidsize	Size of UUID buffer.
 * @return	A valid UUID will be stored in the buffer and structured with two brackets (e.g {ea20dcca-81c3-41f2-8f3d-a757b2b85765}).
 * 			An empty string will be stored in the buffer and false will be returned if the client has no active contract.
 * @error	Client index is invalid.
 */
native bool GetClientContract(int client, char[] uuidbuffer, int uuidsize);

/**
 * Obtains a client's active Contract enum struct.
 *
 * @param client    Client index.
 * @param buffer    Buffer to store the client's contract.
 * @error           Client index is invalid.
 * @note			Please make sure your plugins are updated before using this function to prevent crashes.
 */
native bool GetClientContractStruct(int client, any buffer[sizeof(Contract)]);

/**
 * Processes an event for the client's active Contract.
 *
 * @param client    Client index.
 * @param event    	Event to process.
 * @param value		Value to send alongside this event.
 * @param can_combine 	If true, if this event was recently sent to the event queue, the value from this function will be added to the first event.
 * @return			True if an event is successfully called, false if the client's contract isn't active.
 * @error           Client index is invalid or is a bot.   
 */
native bool CallContrackerEvent(int client, char event[MAX_EVENT_SIZE], int value, bool can_combine = false);

// =========================== SCHEMA ===========================

/**
 * Grabs the Keyvalues schema for a Contract.
 *
 * @param UUID  Contract UUID.
 * @return		KeyValues object of a Contract.
 * @error       Contract could not be found in the schema.
 */
native KeyValues GetContractSchema(char UUID[MAX_UUID_SIZE]);

/**
 * Grabs the Keyvalues schema for an Objective.
 *
 * @param UUID  Contract UUID.
 * @param objective Objective ID.
 * @return		KeyValues object of an Objective.
 * @error       Contract or Objective could not be found in the schema.
 */
native KeyValues GetObjectiveSchema(char UUID[MAX_UUID_SIZE], int objective);

/**
 * Grabs the amount of objectives in a Contract.
 *
 * @param UUID  Contract UUID.
 * @return		Amount of objectives in a Contract.
 * @error       Contract could not be found in the schema.
 */
native int GetContractObjectiveCount(char UUID[MAX_UUID_SIZE]);

// =========================== PROGRESS ===========================

/**
 * Grabs the progress of the clients active Contract.
 *
 * @param client    Client index.
 * @return		Progress value. If the client does not have an active Contract, -1 is returned.
 * @error       Invalid client index.
 */
native int GetActiveContractProgress(int client);

/**
 * Grabs the progress of an Objective from the clients active Contract.
 *
 * @param client    Client index.
 * @param objective     Objective ID.
 * @return		Progress value. If the client does not have an active Contract, -1 is returned.
 * @error       Invalid client or objective index.
 */
native int GetActiveObjectiveProgress(int client, int objective);

/**
 * Sets the progress of a clients active Contract. This does not automatically
 * save the progress to the database (see SaveActiveContractToDatabase).
 *
 * @param client    Client index.
 * @param value     New progress value.
 * @error       Invalid client index.
 */
native void SetActiveContractProgress(int client, int value);

/**
 * Sets the progress of an objective in a clients active Contract. This does not automatically
 * save the progress to the database (see SaveActiveObjectiveToDatabase).
 *
 * @param client    Client index.
 * @param objective     Objective ID.
 * @param value     New progress value.
 * @error       Invalid client or objective index.
 */
native void SetActiveObjectiveProgress(int client, int objective, int value);

// =========================== CONTRACT COMPLETION ===========================

/**
 * Returns a list of all completed contracts.
 *
 * @param client    Client index.
 * @return      StringMap sorted by UUID as key and completion data as the info.
 * @note        This function is partially unsafe as enum structs are still used inside.
 * @error       Invalid client index.
 */
native StringMap GetClientCompletedContracts(int client);

/**
 * Checks to see if the client can activate a Contract.
 *
 * @param client    Client index.
 * @param UUID      UUID of Contract to check.
 * @return      True if the client can activate a contract, false otherwise.
 * @error       Invalid client index or invalid UUID.
 */
native bool CanClientActivateContract(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Checks to see if the client can complete a Contract at the current time.
 *
 * @param client    Client index.
 * @param UUID      UUID of Contract to check.
 * @return      True if the client can complete the contract, false otherwise.
 * @error       Invalid client index or invalid UUID.
 */
native bool CanClientCompleteContract(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Checks to see if the client has completed their active Contract.
 *
 * @param client    Client index.
 * @return      True if a client has completed their active Contract.
 *              False if the client has not finished their contract or has no contract active.
 * @error       Invalid client index.
 */
native bool IsActiveContractComplete(int client);

/**
 * Checks to see if a client has already completed a Contract.
 *
 * @param client    Client index.
 * @param UUID      UUID of Contract to check.
 * @return      True if the client has completed the contract, false otherwise.
 * @error       Invalid client index or invalid UUID.
 */
native bool HasClientCompletedContract(int client, char UUID[MAX_UUID_SIZE]);

// =========================== DATABASE SAVING ===========================

/**
 * Sets the active session for a user in the database.
 * @param steamid64 	SteamID64 of the user.
 * @param UUID	Contract UUID to save.
 * @error	Invalid UUID.
 */
native bool SetSessionDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE]);

/**
 * Saves a Contract to the database for a client.
 *
 * @param client    Client index.
 * @param ClientContract The enum struct of the contract to save.
 * @error           Client index is invalid or the Contract is invalid.         
 */
native bool SaveClientContractProgress(int client, any ClientContract[sizeof(Contract)]);

/**
 * Saves an Objective to the database for a client.
 *
 * @param client    Client index.
 * @param UUID	UUID of the Contract that contains this objective.
 * @param ClientObjective The enum struct of the objective to save.
 * @error           Client index is invalid or the ClientObjective is invalid.         
 */
native bool SaveClientObjectiveProgress(int client, char UUID[MAX_UUID_SIZE], any ClientObjective[sizeof(ContractObjective)]);

/**
 * Sets the progress of a Contract in the database.
 *
 * @param steamid64    SteamID64 of the user.
 * @param UUID	The UUID of the contract to modify.
 * @param value	The value to save to the database.         
 */
native bool SetContractProgressDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE], int value);

/**
 * Sets the progress of an Objective in the database.
 *
 * @param steamid64    SteamID64 of the user.
 * @param UUID	The UUID of the contract to modify.
 * @param objective_id	The ID of the objective to modify.
 * @param value	The value to save to the database.         
 */
native bool SetObjectiveProgressDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE], int objective_id, int value);

/**
 * Marks the contract as complete in the database.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
 * @param data		Contract competion data.
*/
native bool SetCompletedContractInfoDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE], any data[sizeof(CompletedContractInfo)]);

/**
 * Deletes all client progress for a contract.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
*/
native bool DeleteContractProgressDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE]);

/**
 * Deletes all client progress for an objective.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
 * @param objective_id	The objective ID.
*/
native bool DeleteObjectiveProgressDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE], int objective_id);

/**
 * Deletes all client progress for all objectives.
 * @param steamid64    SteamID64 of the user.
 * @param UUID		The UUID of the contract.
*/
native bool DeleteAllObjectiveProgressDatabase(char steamid64[64], char UUID[MAX_UUID_SIZE]);
