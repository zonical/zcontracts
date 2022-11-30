#if defined __zcontracts_included
	#endinput
#endif

#define __zcontracts_included

#define MAX_UUID_SIZE 64
#define MAX_CONTRACT_NAME_SIZE 64
#define MAX_OBJECTIVE_DESC_SIZE 128
#define MAX_EVENT_SIZE 128
#define MAX_DIRECTORY_SIZE 128

stock int Int_Min(int a, int b) { return a < b ? a : b; }

enum ContractType
{
	// Each objective has it's own progress bar. All objectives must be completed
	// to complete the contract.
	Contract_ObjectiveProgress = 1,
	// The contract has it's own progress bar as well as objectives. The progress bar must
	// reach the maximum points (e.g 100CP) to complete the contract. All objectives
	// are optional to complete.
	Contract_ContractProgress = 2
}

// Timer events for ContractObjectiveEvent timers.
enum struct TimerEvent
{
	char m_sEventName[MAX_EVENT_SIZE];
	char m_sAction[MAX_EVENT_SIZE];
	int m_iVariable;
}

// Contract objective events.
enum struct ContractObjectiveEvent
{
	int m_iInternalID;
	char m_sEventName[MAX_EVENT_SIZE];
	
	// If this event gets triggered and is apart of a special condition, trigger some different text.
	char m_sExclusiveDescription[MAX_OBJECTIVE_DESC_SIZE];

	// Threshold for how many times this event should called before giving an award.
	int m_iThreshold;
	int m_iCurrentThreshold;

	char m_sEventType[16];
	
	// Timer logic.
	Handle m_hTimer;
	float m_fTime; // The starting time for the timer.
	int m_iMaxLoops; // The maximum amount of timer loops.
	int m_iCurrentLoops;
	// The events that get triggered on certain timer events.
	ArrayList m_hTimerEvents; // See TimerEvent
	
	bool m_bInitalized;
	
	void Initalize()
	{
		this.m_hTimerEvents = new ArrayList(sizeof(TimerEvent));
		this.m_bInitalized = true;
	}
	
	void Destroy()
	{
		if (!this.m_bInitalized || !this.m_hTimerEvents) return;
		delete this.m_hTimerEvents;
		this.m_bInitalized = false;
	}
}

// Contract objectives.
enum struct ContractObjective
{
	// Store the original type of Contract.
	ContractType m_iContractType;

	int m_iInternalID;
	bool m_bInitalized;
	bool m_bInfinite;	// Objective doesn't have a maximum progress.
	
	char m_sDescription[MAX_OBJECTIVE_DESC_SIZE];
	
	// Award to give when this event is triggered.
	int m_iAward;

	// For an Objective-Progress type of Contract, store the progress
	// of this objective.
	int m_iMaxProgress;
	int m_iProgress;

	// For an Contract-Progress type of Contract, we can limit how many times
	// this objective can be used to gain Contract progress.
	int m_iFires;
	int m_iMaxFires;
	
	// Events for this Contract (see ContractObjectiveEvent).
	ArrayList m_hEvents;

	// If this objective needs to be updated in the database.
	bool m_bNeedsDBSave;

	/**
	 * @return		If this Contract is complete.
	**/
	bool IsObjectiveComplete()
	{
		if (this.m_bInfinite) return false;
		switch (this.m_iContractType)
		{
			case Contract_ObjectiveProgress: return this.m_iProgress >= this.m_iMaxProgress;
			case Contract_ContractProgress: return this.m_iFires >= this.m_iMaxFires;
		}
		return false;
		
	}
	/**
	 * Creates the ArrayList for Objective Events.
	**/
	void Initalize()
	{
		this.m_hEvents = new ArrayList(sizeof(ContractObjectiveEvent));
		this.m_bInitalized = true;
		this.m_bNeedsDBSave = false;
	}
	
	/**
	 * Destory the ArrayList for Objective Events.
	**/
	void Destroy()
	{
		if (!this.m_bInitalized || !this.m_hEvents) return;
		
		// Destroy all of our events.
		for (int i = 0; i < this.m_hEvents.Length; i++)
		{
			ContractObjectiveEvent hEvent;
			this.m_hEvents.GetArray(i, hEvent, sizeof(ContractObjectiveEvent));
			hEvent.Destroy();
		}
		
		delete this.m_hEvents;
		this.m_bInitalized = false;
		this.m_bNeedsDBSave = false;
	}
}

// Struct representing a Contract.
enum struct Contract
{
	bool m_bInitalized;

	char m_sUUID[MAX_UUID_SIZE];
	char m_sContractName[MAX_CONTRACT_NAME_SIZE];
	
	// Path of where this Contract should be stored in the global Contracker.
	char m_sDirectoryPath[MAX_DIRECTORY_SIZE]; 

	// Boolean value representing what classes can use this contract. (TF2 only!)
	bool m_bClass[10];

	// Restrictions.
	char m_sWeaponNameRestriction[64];
	char m_sWeaponItemDefRestriction[64];
	char m_sWeaponClassnameRestriction[64];

	char m_sMapRestriction[MAX_UUID_SIZE];
	int m_iTeamRestriction;

	// What type of Contract are we handling? (see ContractType)
	ContractType m_iContractType;

	// If we're using "contract progress" mode, there is one central
	// progress bar that is updated alongside our objective.
	int m_iProgress;
	int m_iMaxProgress;

	// If the Contract progress needs to be updated in the database.
	bool m_bNeedsDBSave;

	ArrayList m_hObjectives;
	
	bool IsContractInitalized()
	{
		return this.m_sUUID[0] == '{';
	}

	/**
	 * @return		If this Contract is complete.
	**/
	bool IsContractComplete()
	{
		switch (this.m_iContractType)
		{
			case Contract_ObjectiveProgress: // All objectives must be complete.
			{
				for (int i = 0; i < this.m_hObjectives.Length; i++)
				{
					ContractObjective hContractObjective;
					this.m_hObjectives.GetArray(i, hContractObjective);
					if (!hContractObjective.m_bInitalized) continue;
					if (hContractObjective.m_bInfinite) continue;
					if (!hContractObjective.IsObjectiveComplete()) return false;
				}
				return true;
			}
			case Contract_ContractProgress: // The Contract's progress bar must be complete.
			{
				return this.m_iProgress >= this.m_iMaxProgress;
			}
				
		}
		
		return false;
	}
	/**
	 * Wrapper to easily get a Contract objective.
	**/
	void GetObjective(int index, ContractObjective hBuffer)
	{
		this.m_hObjectives.GetArray(index, hBuffer, sizeof(ContractObjective));
	}

	/**
	 * Wrapper to easily save a Contract objective.
	**/
	void SaveObjective(int index, ContractObjective hBuffer)
	{
		this.m_hObjectives.SetArray(index, hBuffer, sizeof(ContractObjective));
	}

	/**
	 * Creates the ArrayList for objectives.
	**/
	void Initalize()
	{
		this.m_hObjectives = new ArrayList(sizeof(ContractObjective));
		this.m_iProgress = 0;
		this.m_bInitalized = true;
	}
	/**
	 * Destroy the ArrayList for objectives.
	**/
	void Destroy()
	{
		for (int i = 0; i < this.m_hObjectives.Length; i++)
		{
			ContractObjective hContractObjective;
			this.m_hObjectives.GetArray(i, hContractObjective);
			if (!hContractObjective.m_bInitalized) continue;
			hContractObjective.Destroy();
			this.m_hObjectives.SetArray(i, hContractObjective);
		}
		this.m_hObjectives.Clear();
		this.m_bInitalized = false;
	}
}

enum struct ObjectiveUpdate
{
	int m_iClient;
	int m_iValue;
	int m_iObjectiveID;
	char m_sEvent[MAX_EVENT_SIZE];
	char m_sUUID[MAX_UUID_SIZE];
}

/**
 * Set a client's contract.
 *
 * @param client    Client index.
 * @param UUID    	The UUID of the contract.
 * @param dont_save	Optional argument: doesn't save this as the active Contract in the database.
 * @error           Client index is invalid or UUID is invalid.         
 */
native bool SetClientContract(int client, char event[MAX_UUID_SIZE], bool dont_save = false);

/**
 * Obtains a client's active Contract.
 *
 * @param client    Client index.
 * @param buffer    Buffer to store the client's contract.
 * @error           Client index is invalid.          
 */
native bool GetClientContract(int client, any buffer[sizeof(Contract)]);

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

/**
 * Sent on client completion of a Contract objective.
 *
 * @param client    	Client index.
 * @param uuid    		The UUID of the original Contract.
 * @param hObjective	Handle to the completed objective.
 */
forward void OnContractObjectiveCompleted(int client, const char[] uuid, ContractObjective hObjective);
/**
 * Sent on client completion of a Contract.
 *
 * @param client    	Client index.
 * @param uuid    		The UUID of the original Contract.
 * @param hObjective	Handle to the completed Contract.
 */
forward void OnContractCompleted(int client, const char[] uuid, Contract hContract);