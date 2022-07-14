#if defined __zcontracts_included
	#endinput
#endif

#define __zcontracts_included

#define MAX_UUID_SIZE 64
#define MAX_CONTRACT_NAME_SIZE 64
#define MAX_CONTRACT_OBJECTIVES 8
#define MAX_OBJECTIVE_DESC_SIZE 128
#define MAX_EVENT_SIZE 64
#define MAX_DIRECTORY_SIZE 128

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

	void StartTimer(int objective_id, int client, const char[] event, int value)
	{
		// Start the timer if it doesn't exist yet.
		if (this.m_hTimer == INVALID_HANDLE && this.m_fTime != 0.0)
		{
			// Create a datapack for our timer so we can pass our objective and event through.
			DataPack m_hTimerdata;
			
			// Create our timer. (see contracts_timers.sp)
			this.m_hTimer = CreateDataTimer(this.m_fTime, EventTimer, m_hTimerdata, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			m_hTimerdata.WriteCell(client); // Pass through our client so we can get our contract.
			m_hTimerdata.WriteCell(objective_id); // Pass through our internal ID so we know which objective to look for.
			m_hTimerdata.WriteCell(this.m_iInternalID); // Pass through the current event index so we know which event we're looking for in our objective.
			// ^^ The reason we do these two things as we can't pass enum structs through into a DataPack.
		}
	}
}

// Contract objectives.
enum struct ContractObjective
{
	int m_iInternalID;
	bool m_bInitalized;
	bool m_bInfinite;	// Objective doesn't have a maximum progress.
	
	char m_sDescription[MAX_OBJECTIVE_DESC_SIZE];
	
	// Award to give when this event is triggered.
	int m_iAward;

	// Progress of this objective.
	int m_iMaxProgress;
	int m_iProgress;
	
	// Restrictions for triggering progress.
	char m_sWeaponRestriction[MAX_UUID_SIZE];
	char m_sMapRestriction[MAX_UUID_SIZE];
	
	// Events for this Contract (see ContractObjectiveEvent).
	ArrayList m_hEvents;
	
	void TryIncrementProgress(int client, ContractObjectiveEvent hEvent)
	{
		if (this.IsObjectiveComplete()) return;
		if (hEvent.m_iCurrentThreshold >= hEvent.m_iThreshold)
		{
			// What type of value are we? Are we incrementing or resetting?
			if (StrEqual(hEvent.m_sEventType, "increment"))
			{
				// Add to our event progress.
				this.m_iProgress += this.m_iAward;
	
				// Clamp.
				if (!this.m_bInfinite) 
					this.m_iProgress = Int_Min(this.m_iProgress, this.m_iMaxProgress);

				// Reset our threshold.
				hEvent.m_iCurrentThreshold = 0;
			}
			else if (StrEqual(hEvent.m_sEventType, "reset"))
			{
				// Reset all of the events' threshold.
				for (int h = 0; h < this.m_hEvents.Length; h++)
				{
					ContractObjectiveEvent m_hEventToReset;
					this.m_hEvents.GetArray(h, m_hEventToReset);
					m_hEventToReset.m_iCurrentThreshold = 0;
					this.m_hEvents.SetArray(h, m_hEventToReset);
				}
			}
			
			// Cancel our timer now that we've reached our threshold.
			if (hEvent.m_hTimer != INVALID_HANDLE)
			{
				CloseHandle(hEvent.m_hTimer);
				hEvent.m_hTimer = INVALID_HANDLE;
			}
		}
	}

	void ResetProgress()
	{ 
		this.m_iProgress = 0;
		return;
	}
	
	bool IsObjectiveComplete()
	{
		if (this.m_bInfinite) return false;
		return this.m_iProgress >= this.m_iMaxProgress;
	}

	void Initalize()
	{
		this.m_hEvents = new ArrayList(sizeof(ContractObjectiveEvent));
		this.m_bInitalized = true;
	}
	
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
	}
}

// Struct representing a Contract.
enum struct Contract
{
	// UUID.
	char m_sUUID[MAX_UUID_SIZE];
	
	// Name of the contract.
	char m_sContractName[MAX_CONTRACT_NAME_SIZE];
	
	// Directory path.
	char m_sDirectoryPath[MAX_DIRECTORY_SIZE]; 

	// Boolean value representing what classes can use this contract.
	bool m_bClass[10];

	// What type of Contract are we handling?
	ContractType m_iContractType;

	// If we're using "contract progress" mode, there is one central
	// progress bar that is updated alongside our objective.
	int m_iProgress;
	int m_iMaxProgress;

	// Contract objectives.
	ArrayList m_hObjectives;
	
	bool IsContractComplete()
	{
		switch (this.m_iContractType)
		{
			case Contract_ObjectiveProgress: // All objectives must be complete.
			{
				for (int i = 0; i < MAX_CONTRACT_OBJECTIVES; i++)
				{
					if (i >= this.m_hObjectives.Length) break;
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
	
	void Initalize()
	{
		this.m_hObjectives = new ArrayList(sizeof(ContractObjective));
		this.m_iProgress = 0;
	}

	void Destroy()
	{
		for (int i = 0; i < MAX_CONTRACT_OBJECTIVES; i++)
		{
			ContractObjective hContractObjective;
			this.m_hObjectives.GetArray(i, hContractObjective);
			if (!hContractObjective.m_bInitalized) continue;
			hContractObjective.Destroy();
			this.m_hObjectives.SetArray(i, hContractObjective);
		}
		this.m_hObjectives.Clear();
	}
}

/**
 * Set a client's contract.
 *
 * @param client    Client index.
 * @param UUID    	The UUID of the contract.
 * @error           Client index is invalid or UUID is invalid.         
 */
native bool SetClientContract(int client, char event[MAX_UUID_SIZE]);

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
 * @return			True if an event is successfully called, false if the client's contract isn't active.
 * @error           Client index is invalid or is a bot.   
 */
native bool CallContrackerEvent(int client, char event[MAX_EVENT_SIZE], int value);