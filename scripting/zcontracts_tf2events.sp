#include <sourcemod>
#include <sdkhooks>
#include <zcontracts/zcontracts>

public Plugin myinfo =
{
	name = "ZContracts - TF2 Event Logic",
	author = "ZoNiCaL",
	description = "Hooks game events into the ZContract system.",
	version = "alpha-1",
	url = ""
};

// Hook all of our game events.
public void OnPluginStart()
{
	// Hook player events.
	HookEvent("escort_progress", OnEscortProgress);
	HookEvent("teamplay_point_capture", OnPointCaptured);
}

public Action OnEscortProgress(Event event, const char[] name, bool dontBroadcast)
{
	static float last_award = 0.0;
	const float ESCORT_THRESHOLD = 0.1;
	float divided_progress = event.GetFloat("progress") / ESCORT_THRESHOLD;
	// Are we a whole number?
	if (divided_progress % 1 != 0)
	{
		// Don't double dip.
		if (event.GetFloat("progress") <= last_award) return;

		last_award = event.GetFloat("progress");
		for (int i = 0; i < MAXPLAYERS+1; i++)
		{
			if (!IsClientValid(i) || IsFakeClient(i)) continue;
			if (GetClientTeam(i) != event.GetInt("team")) continue;
			CallContrackerEvent(i, "CONTRACTS_TF2_PL_ESCORT", 1);
		}
	}
	return Plugin_Continue;
}

public Action OnPointCaptured(Event event, const char[] name, bool dontBroadcast)
{

}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
