float g_TimeChange[MAXPLAYERS+1];
bool g_TimerActive[MAXPLAYERS+1];

// Function for event timers.
public Action EventTimer(Handle hTimer, DataPack hPack)
{
	// Set to the beginning and unpack it.
	hPack.Reset();
	// Grab our client.
	int client = hPack.ReadCell();
	int iObjectiveID = hPack.ReadCell();
	int iEventID = hPack.ReadCell();

	if (!IsClientValid(client)) return Plugin_Stop;
	
	Contract ClientContract;
	GetClientContractStruct(client, ClientContract);
	ContractObjective ActiveObjective;
	ClientContract.m_hObjectives.GetArray(iObjectiveID, ActiveObjective);
	ContractObjectiveEvent ObjectiveEvent;
	ActiveObjective.m_hEvents.GetArray(iEventID, ObjectiveEvent, sizeof(ObjectiveEvent));
	
	// This is our actual time remaining for this loop. 
	// Treat ObjectiveEvent.m_fTime like the inital starting time.
	// This allows us to do stuff like add or subtract
	// from the total time remaining.
	static float TimeRemaining = 0.0;
	if (g_TimerActive[client] == false)
	{
		TimeRemaining = ObjectiveEvent.m_fTime;
		if (g_DebugTimers.BoolValue)
		{
			LogMessage("[ZContracts] Timer started for %N: [OBJ: %d, EVENT: %d, TIME: %.1f]", client, iObjectiveID, iEventID, TimeRemaining);
		}
		g_TimerActive[client] = true;
	}

	if (g_TimeChange[client] != 0.0)
	{
		TimeRemaining += g_TimeChange[client];
		if (g_DebugTimers.BoolValue)
		{
			LogMessage("[ZContracts] Time change for %N: [change: %.1f, new: %.1f]", client, g_TimeChange[client], TimeRemaining);
		}
		g_TimeChange[client] = 0.0;
	}

	// Only progress forward if this loop is done!
	if (GetGameTime() < ObjectiveEvent.m_fStarted + TimeRemaining) return Plugin_Continue;

	ObjectiveEvent.m_iCurrentLoops++;
	if (g_DebugTimers.BoolValue)
	{
		LogMessage("[ZContracts] Loop %d finished for timer started for %N: [OBJ: %d, EVENT: %d, MAX: %d]",
		ObjectiveEvent.m_iCurrentLoops, client, iObjectiveID, iEventID, ObjectiveEvent.m_iMaxLoops);
	}
	
	// Call an event for when this loop of the timer ends.
	SendEventToTimer(client, iObjectiveID, iEventID, "OnLoopEnd");
	
	// Are we at the maximum of our loops?
	if (ObjectiveEvent.m_iCurrentLoops >= ObjectiveEvent.m_iMaxLoops)
	{
		// Call an event for when the timer ends.
		SendEventToTimer(client, iObjectiveID, iEventID, "OnTimerEnd");

		// Reset our variables.
		ObjectiveEvent.m_fStarted = 0.0;
		ObjectiveEvent.m_iCurrentLoops = 0;
		ObjectiveEvent.m_iCurrentThreshold = 0;
		ObjectiveEvent.m_hTimer = INVALID_HANDLE;
		ActiveObjective.m_hEvents.SetArray(iEventID, ObjectiveEvent, sizeof(ContractObjectiveEvent));

		if (g_DebugTimers.BoolValue)
		{
			LogMessage("[ZContracts] Timer finished for %N: [OBJ: %d, EVENT: %d, REASON: Timer reached max loops]",
			client, iObjectiveID, iEventID);
		}

		TimeRemaining = 0.0;
		g_TimerActive[client] = false;

		// Exit out of the timer.
		return Plugin_Stop;
	}

	// Restart this loop.
	ObjectiveEvent.m_fStarted = GetGameTime();
	TimeRemaining = ObjectiveEvent.m_fTime;

	ActiveObjective.m_hEvents.SetArray(iEventID, ObjectiveEvent, sizeof(ContractObjectiveEvent));
	ClientContract.m_hObjectives.SetArray(iObjectiveID, ActiveObjective);
	return Plugin_Continue;
}

public void SendEventToTimer(int client, int objective, int event, const char[] timer_event)
{
	ContractObjective ActiveObjective;
	ActiveContract[client].GetObjective(objective, ActiveObjective);
	if (!ActiveObjective.m_bInitalized) return;
	ContractObjectiveEvent ObjectiveEvent;
	ActiveObjective.m_hEvents.GetArray(event, ObjectiveEvent, sizeof(ContractObjectiveEvent));
	if (ObjectiveEvent.m_hTimer == INVALID_HANDLE) return;
	KeyValues ObjSchema = GetObjectiveSchema(ActiveContract[client].m_sUUID, objective);
	
	// Jump down a bit.
	ObjSchema.JumpToKey("events");
	ObjSchema.JumpToKey(ObjectiveEvent.m_sEventName);
	if (!ObjSchema.JumpToKey("timer")) return;
	if (!ObjSchema.JumpToKey(timer_event)) return;

	char EventAction[64];
	ObjSchema.GetString("event", EventAction, sizeof(EventAction));
	if (g_DebugTimers.BoolValue)
	{
		LogMessage("[ZContracts] Timer event fired for %N: [OBJ: %d, OBJ-EVENT: %d, EVENT: %s, ACTION: %s]",
		client, objective, event, timer_event, EventAction);
	}
	float Variable = ObjSchema.GetFloat("variable");

	// What should we do here?
	if (StrEqual(EventAction, "add_reward") || StrEqual(EventAction, "subtract_reward"))
	{
		int Value = view_as<int>(Variable);
		if (StrEqual(EventAction, "subtract_reward")) Value *= -1;
		switch (ActiveContract[client].m_iContractType)
		{
			case Contract_ObjectiveProgress: ModifyObjectiveProgress(client, Value, ActiveContract[client], objective);
			case Contract_ContractProgress: ModifyContractProgress(client, Value, ActiveContract[client], objective);
		}
	}

	if (StrEqual(EventAction, "add_loop")) ObjectiveEvent.m_iMaxLoops += view_as<int>(Variable);
	if (StrEqual(EventAction, "subtract_loop")) ObjectiveEvent.m_iMaxLoops -= view_as<int>(Variable);

	if (StrEqual(EventAction, "add_threshold")) ObjectiveEvent.m_iCurrentThreshold += view_as<int>(Variable);
	if (StrEqual(EventAction, "subtract_threshold")) ObjectiveEvent.m_iCurrentThreshold -= view_as<int>(Variable);

	if (StrEqual(EventAction, "add_time")) g_TimeChange[client] = Variable;
	if (StrEqual(EventAction, "subtract_time")) g_TimeChange[client] = Variable * -1.0;
	
	ActiveObjective.m_hEvents.SetArray(event, ObjectiveEvent, sizeof(ContractObjectiveEvent));
	ActiveContract[client].SaveObjective(objective, ActiveObjective);
}