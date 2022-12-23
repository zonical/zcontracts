// Function for event timers.
public Action EventTimer(Handle hTimer, DataPack hPack)
{
	// Set to the beginning and unpack it.
	hPack.Reset();
	// Grab our client.
	int client = hPack.ReadCell();
	int iObjectiveID = hPack.ReadCell();
	int iEventID = hPack.ReadCell();

	// If our client disconnects, stop the timer.
	if (!IsClientValid(client)) return Plugin_Stop;
	
	// Get our contracts.
	Contract hContract;
	GetClientContract(client, hContract);
	
	// Grab our objective.
	ContractObjective hObjective;
	hContract.m_hObjectives.GetArray(iObjectiveID, hObjective);
	
	// Grab our event.
	ContractObjectiveEvent hEvent;
	hObjective.m_hEvents.GetArray(iEventID, hEvent, sizeof(ContractObjectiveEvent));
	
	// Add to our loops.
	hEvent.m_iCurrentLoops++;
	
	// Call an event for when this loop of the timer ends.
	TriggerTimeEvent(hObjective, hEvent, "OnLoopEnd");
	
	// Are we at the maximum of our loops?
	if (hEvent.m_iCurrentLoops >= hEvent.m_iMaxLoops)
	{
		// Call an event for when the timer ends.
		TriggerTimeEvent(hObjective, hEvent, "OnTimerEnd");

		// Reset our variables.
		hEvent.m_fStarted = 0.0;
		hEvent.m_iCurrentLoops = 0;
		hEvent.m_iCurrentThreshold = 0;
		hEvent.m_hTimer = INVALID_HANDLE;
		hObjective.m_hEvents.SetArray(iEventID, hEvent, sizeof(ContractObjectiveEvent));
		// Exit out of the timer.
		return Plugin_Stop;
	}

	hObjective.m_hEvents.SetArray(iEventID, hEvent, sizeof(ContractObjectiveEvent));
	hContract.m_hObjectives.SetArray(iObjectiveID, hObjective);
	return Plugin_Continue;
}

// Processes events for an events timer. This can do things such as add or subtract another loop to the timer
// or add or subtract progress from the objective (hObjective).
public void TriggerTimeEvent(ContractObjective hObjective, ContractObjectiveEvent hEvent, const char[] m_sEventName)
{
	// Loop over our events and do an action accordingly.
	for (int i = 0; i < hEvent.m_hTimerEvents.Length; i++)
	{
		// Grab our event.
		TimerEvent hTimerEvent;
		hEvent.m_hTimerEvents.GetArray(i, hTimerEvent, sizeof(TimerEvent));
		
		// Is this the event we're looking for?
		if (StrEqual(hTimerEvent.m_sEventName, m_sEventName))
		{
			// What should we do here?
			if (StrEqual(hTimerEvent.m_sAction, "add_reward")) hObjective.m_iProgress += hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "subtract_reward")) hObjective.m_iProgress -= hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "add_loop")) hEvent.m_iMaxLoops += hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "subtract_loop")) hEvent.m_iMaxLoops -= hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "subtract_threshold")) hEvent.m_iCurrentThreshold -= hTimerEvent.m_iVariable;
		}
	}
}