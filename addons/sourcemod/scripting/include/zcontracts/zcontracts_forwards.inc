// =========================== FORWARDS ===========================

/**
 * Sent on client completion of a Contract objective.
 *
 * @param client    	Client index.
 * @param uuid    		The UUID of the original Contract.
 * @param objective     Objective index.
 */
forward void OnContractObjectiveCompleted(int client, char UUID[MAX_UUID_SIZE], int objective);
/**
 * Sent on client completion of a Contract.
 *
 * @param client    	Client index.
 * @param uuid    		The UUID of the original Contract.
 */
forward void OnContractCompleted(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Called before a contract is saved to the database. This is not called for any
 * low-level value setting functions (e.g SetContractProgressDatabase).
 *
 * @param client    	Client index.
 * @param uuid    		The UUID of the original Contract.
 */
forward bool OnContractPreSave(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Called before an objective is saved to the database. This is not called for any
 * low-level value setting functions (e.g SetObjectiveProgressDatabase).
 *
 * @param client    	Client index.
 * @param uuid    		The UUID of the original Contract.
 * @param objective	    Objective index.
 */
forward bool OnObjectivePreSave(int client, char UUID[MAX_UUID_SIZE], int objective);

/**
 * Called when an event is about to potentially add progress to a Contract.
 * 
 * @param client	Client index.
 * @param UUID		UUID of the Contract.
 * @param objective Objective index.
 * @param event		Name of the event being processed.
 * @param value		Value passed by the event.
 * @return A value higher than Plugin_Continue will prevent potential progress being added to the Contract.
 */
forward Action OnProcessContractLogic(int client, char UUID[MAX_UUID_SIZE], int objective, char event[MAX_EVENT_SIZE],
int value);

/**
 * Called whenever CanClientCompleteContract() is called to see if a client can complete
 * a selected Contract.
 * 
 * @param client	Client index.
 * @param UUID		UUID of the Contract.
 * @return A value higher than Plugin_Continue will mark the contract as incompletable.
 */
forward Action OnContractCompletableCheck(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Called when a client selects a Contract.
 * 
 * @param client	Client index.
 * @param UUID		UUID of the Contract.
 */
forward void OnClientActivatedContract(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Called when a client selects a Contract and data from the database has been retrieved.
 * 
 * @param client	Client index.
 * @param UUID		UUID of the Contract.
 */
forward void OnClientActivatedContractPost(int client, char UUID[MAX_UUID_SIZE]);

/**
 * Called when the database returns progress data about a Contract.
 * 
 * @param client	Client index.
 * @param UUID		UUID of the Contract.
 * @param progress  Progress value from the database.
 */
forward void OnContractProgressReceived(int client, char UUID[MAX_UUID_SIZE], int progress);

/**
 * Called when the database returns progress data about a Contract Objective.
 * 
 * @param client	Client index.
 * @param UUID		UUID of the Contract.
 * @param objective ID of the Objective.
 * @param progress  Progress value from the database.
 */
forward void OnObjectiveProgressReceived(int client, char UUID[MAX_UUID_SIZE], int objective, int progress);
