float g_TimeChange[MAXPLAYERS+1];
bool g_TimerActive[MAXPLAYERS+1];

// Function for event timers.
public Action EventTimer(Handle hTimer, DataPack hPack)
{
	// Set to the beginning and unpack it.
	hPack.Reset();
	int client = hPack.ReadCell();
	int obj_id = hPack.ReadCell();
	char event[MAX_EVENT_SIZE];
	hPack.ReadString(event, sizeof(event));
	float start = hPack.ReadFloat();

	if (!IsClientValid(client)) return Plugin_Stop;
	
	// This is our actual time remaining for this loop. 
	// This allows us to do stuff like add or subtract
	// from the total time remaining.
	static float TimeRemaining = 0.0;
	if (g_TimerActive[client] == false)
	{
		// Grab the starting time from the Schema.
		KeyValues ObjSchema = GetObjectiveSchema(ActiveContract[client].UUID, obj_id);
		if (!ObjSchema.JumpToKey("events"))
		{
			delete ObjSchema;
			ThrowError("Contract \"%s\" doesn't have any events! Fix this, server developer!", ActiveContract[client].UUID);
		}
		if (!ObjSchema.JumpToKey(event)) 
		{
			delete ObjSchema;
			ThrowError("Contract \"%s\" doesn't have requested event \"%s\"", ActiveContract[client].UUID, event);
		}
		ObjSchema.JumpToKey("timer");
		
		TimeRemaining = ObjSchema.GetFloat("time");
		if (g_DebugTimers.BoolValue)
		{
			LogMessage("[ZContracts] Timer started for %N: [OBJ: %d, EVENT: %s, TIME: %.1f]", client, obj_id, event, TimeRemaining);
		}
		g_TimerActive[client] = true;
		delete ObjSchema;
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

	if (GetGameTime() < start + TimeRemaining) return Plugin_Continue;
	else
	{
		// Call an event for when the timer ends.
		SendEventToTimer(client, obj_id, event, "OnTimerEnd");
		ActiveContract[client].ObjectiveTimers.Set(obj_id, INVALID_HANDLE);
		ActiveContract[client].ObjectiveTimerStarted.Set(obj_id, -1.0);

		StringMap ObjectiveThreshold = ActiveContract[client].ObjectiveThreshold.Get(obj_id);
		ObjectiveThreshold.SetValue(event, 0);
		ActiveContract[client].ObjectiveThreshold.Set(obj_id, ObjectiveThreshold);

		TimeRemaining = 0.0;
		g_TimerActive[client] = false;

		if (g_DebugTimers.BoolValue)
		{
			LogMessage("[ZContracts] Timer finished for %N: [OBJ: %d, EVENT: %s, REASON: Timer reached max loops]", client, obj_id, event);
		}

		// Exit out of the timer.
		return Plugin_Stop;
	}
}

public void SendEventToTimer(int client, int obj_id, char event[MAX_EVENT_SIZE], const char[] timer_event)
{
	// Grab the starting time from the Schema.
	KeyValues ObjSchema = GetObjectiveSchema(ActiveContract[client].UUID, obj_id);
	if (!ObjSchema.JumpToKey(CONTRACT_DEF_OBJ_EVENTS))
	{
		delete ObjSchema;
		ThrowError("Contract \"%s\" doesn't have any events! Fix this, server developer!", ActiveContract[client].UUID);
	}
	if (!ObjSchema.JumpToKey(event))
	{
		delete ObjSchema;
		ThrowError("Contract \"%s\" doesn't have requested event \"%s\"", ActiveContract[client].UUID, event);
	}
	if (!ObjSchema.JumpToKey(CONTRACT_DEF_EVENT_TIMER))
	{
		delete ObjSchema;
		return;
	}
	if (!ObjSchema.JumpToKey(timer_event))
	{
		delete ObjSchema;
		return;
	}

	char EventAction[64];
	ObjSchema.GetString("event", EventAction, sizeof(EventAction));
	if (g_DebugTimers.BoolValue)
	{
		LogMessage("[ZContracts] Timer event fired for %N: [OBJ: %d, OBJ-EVENT: %d, EVENT: %s, ACTION: %s]",
		client, obj_id, event, timer_event, EventAction);
	}
	float Variable = ObjSchema.GetFloat("variable");

	if (StrContains(EventAction, "reward") != -1)
	{
		int Value = view_as<int>(Variable);
		if (StrEqual(EventAction, "subtract_reward")) Value *= -1;
		switch (ActiveContract[client].GetContractType())
		{
			case Contract_ObjectiveProgress: ModifyObjectiveProgress(client, Value, ActiveContract[client], obj_id);
			case Contract_ContractProgress: ModifyContractProgress(client, Value, ActiveContract[client], obj_id);
		}
	}
	/*if (StrContains(EventAction, "threshold") != -1)
	{
		int curr_threshold = ActiveContract[client].ObjectiveThreshold.Get(obj_id);
		int Value = view_as<int>(Variable);
		if (StrContains(EventAction, "subtract") != -1) Value *= -1;
		ActiveContract[client].ObjectiveThreshold.Set(obj_id, curr_threshold + Value);
	}*/

	if (StrEqual(EventAction, "add_time")) g_TimeChange[client] = Variable;
	if (StrEqual(EventAction, "subtract_time")) g_TimeChange[client] = Variable * -1.0;

	delete ObjSchema;
}