#if defined __zcontracts_included
	#endinput
#endif

#define __zcontracts_included

#define ZCONTRACTS_PLUGIN_VERSION "0.9.0"
// This value should be incremented with every breaking version made to the
// database so saves can be easily converted. For developers who fork this project and
// wish to merge changes, do not increment this number until merge.
// Other plugins should use the GetContrackerVersion() native to get this value, but
// this main plugin and subplugins are free to use the define name in its place.
#define CONTRACKER_VERSION 2
// How often the HUD will refresh itself.
#define HUD_REFRESH_RATE 0.5

#define MAX_UUID_SIZE 64
#define MAX_CONTRACT_NAME_SIZE 64
#define MAX_OBJECTIVE_DESC_SIZE 128
#define MAX_EVENT_SIZE 256
#define MAX_DIRECTORY_SIZE 128

#include <zcontracts/zcontracts_natives>
#include <zcontracts/zcontracts_forwards>

/* Okay, quick developer story time.
I originally developed this project with enum structs in mind. I learnt a lot of my SourceMod
practices when developing Creators.TF, and the codebase used a lot of enum structs to store data in
a clean way that is similar to other programming languiages. SourcePawn is notorious for not having
the best OOP capabilities. With this in mind, I wanted to make the project as clean as possible from
a codebase perspective. I started this project before I became aware of the black hole that exists with
enum structs: they ***shouldn't*** be passed through with natives. If they are not handled carefully,
server crashes will happen (see https://github.com/alliedmodders/sourcepawn/issues/547).
This is the biggest coding flaw with ZContracts. In the far future, I would like to rewrite part of
the code to use Methodmaps or some other sane way to transport data between plugins, but for now - this is
my preferred approach. For developers: PLEASE recompile any plugin that deals with ZContracts when you
install a new patch.
*/

stock int Int_Min(int a, int b) { return a < b ? a : b; }

stock bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}

// Methodmap that represents a Contract. This should be passed between plugins
// INSTEAD of using the enum structs below.
/* TODO: Come back to this later. This feels ugly.
methodmap ZContract
{
	public ZContract(int client)
	{
		if (!IsClientValid(client))
		{
			ThrowError("Invalid client index (%d) when constructing methodmap.", client);
		}
		return view_as<ZContract>(client);
	}
	property int Client
	{ 
		public get() { return view_as<int>(this); }
	}
	public bool GetUUID(char[] uuidbuffer, int buffersize)
	{
		return GetClientContract(view_as<int>(this), uuidbuffer, buffersize);
	}

};*/

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

enum DatabaseStatus
{
	DBS_NoInformation,
	DBS_GrabbedInformation
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

	// The starting time for the timer.
	float m_fTime; 
	// The maximum amount of timer loops.
	int m_iMaxLoops; 
	// When this timer was started.
	float m_fStarted;
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

	// Because of the combine-event logic, there is a chance that the value passed
	// to ProcessLogicForContractObjective() may be over the threshold. By default,
	// the award is multiplied by the value to make up for this combination.
	// (e.g 3 kills for 1 CP awards 3CP). Some objectives may wish to not use
	// the multiplication (e.g heal a player for 300HP gives 5CP *only*)
	bool m_bNoMultiplication;

	// Progress of this objective. This includes how many times it should be used.
	int m_iMaxProgress;
	int m_iProgress;

	// If the Objective progress needs to be updated in the database. This is only used
	// with the repeating timer.
	bool m_bNeedsDBSave;
	
	// Events for this Contract (see ContractObjectiveEvent).
	ArrayList m_hEvents;

	/**
	 * @return		If this Contract is complete.
	**/
	bool IsObjectiveComplete()
	{
		if (this.m_bInfinite) return false;
		return this.m_iProgress >= this.m_iMaxProgress;
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
	bool m_bActive;

	// Internal representation of the Contract.
	char m_sUUID[MAX_UUID_SIZE];

	// Display name of the Contract.
	char m_sContractName[MAX_CONTRACT_NAME_SIZE];
	
	// Path of where this Contract should be stored in the global Contracker.
	char m_sDirectoryPath[MAX_DIRECTORY_SIZE]; 

	// Difficulty of the Contract.
	int m_iDifficulty;

	// Boolean value representing what classes can use this contract. (TF2 only!)
	bool m_bClass[10];
	
	// The contracts the client must have completed before
	// being allowed to activate this Contract.
	ArrayList m_hRequiredContracts;

	// Restrictions.
	char m_sWeaponNameRestriction[64];
	char m_sWeaponItemDefRestriction[64];
	char m_sWeaponClassnameRestriction[64];
	char m_sMapRestriction[64];
	int m_iTeamRestriction;

	char m_sRequiredGameRulesEntity[64]; // TF2
	int m_iGameModeRestriction; // CSGO
	int m_iGameTypeRestriction; 
	int m_iSkirmishIDRestriction; // CSGO

	// Other plugins can mark this Contract as uncompletable on player switch.
	bool m_bIsCompletableOverride;

	// What type of Contract are we handling? (see ContractType)
	ContractType m_iContractType;

	// If we're using "contract progress" mode, there is one central
	// progress bar that is updated alongside our objective.
	int m_iProgress;
	int m_iMaxProgress;

	// Because of the combine-event logic, there is a chance that the value passed
	// to ProcessLogicForContractObjective() may be over the threshold. By default,
	// the award is multiplied by the value to make up for this combination.
	// (e.g 3 kills for 1 CP awards 3CP). Some objectives may wish to not use
	// the multiplication (e.g heal a player for 300HP gives 5CP *only*)
	bool m_bNoMultiplication;

	// If the Contract progress needs to be updated in the database. This is only used
	// with the repeating timer 
	bool m_bNeedsDBSave;

	// Has this enum struct had information set from the database?
	bool m_bLoadedFromDatabase;

	// The objectives for this Contract.
	ArrayList m_hObjectives;

	// These three variables trigger visuals on the HUD.
	bool m_bHUD_ContractUpdate;
	int m_iHUD_ObjectiveUpdate;
	int m_iHUD_UpdateValue;
	
	bool IsContractInitalized()
	{
		return this.m_sUUID[0] == '{';
	}

	/**
	 * @return		If this Contract is complete.
	**/
	bool IsContractComplete()
	{
		if (!this.m_bActive || !this.m_bInitalized) return false;
		
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

	bool IsContractCompletableForClient(int client)
	{
		if (!this.m_bActive || !this.m_bInitalized) return false;

		// Map check.
		char Map[256];
		GetCurrentMap(Map, sizeof(Map));
		if (!StrEqual(Map, "") && StrContains(Map, this.m_sMapRestriction) == -1) return false;

		// Team check.
		if (this.m_iTeamRestriction != -1 && GetClientTeam(client) != this.m_iTeamRestriction) return false;

		// Weapon check.
		if (!StrEqual("", this.m_sWeaponItemDefRestriction)
		|| !StrEqual("", this.m_sWeaponClassnameRestriction))
		{
			int ClientWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if (IsValidEntity(ClientWeapon))
			{
				// Item definition index check:
				if (!StrEqual("", this.m_sWeaponItemDefRestriction))
				{
					int DefIndex = GetEntProp(ClientWeapon, Prop_Send, "m_iItemDefinitionIndex");
					if (DefIndex != StringToInt(this.m_sWeaponItemDefRestriction)) return false;
				}
				// Classname check:
				if (!StrEqual("", this.m_sWeaponClassnameRestriction))
				{
					char Classname[64];
					GetEntityClassname(ClientWeapon, Classname, sizeof(Classname));
					if (!StrContains(Classname, this.m_sWeaponClassnameRestriction)) return false;
				}
			}
		}

		// Specific game check.
		// TODO: Remove me!
		/*
		switch (GetEngineVersion())
		{
			case Engine_TF2:
			{
				
			}
			case Engine_CSGO:
			{
				if (this.m_iGameTypeRestriction != -1 && !CSGO_IsCorrectGameType(this.m_iGameTypeRestriction)) return false;
				if (this.m_iGameModeRestriction != -1 && !CSGO_IsCorrectGameMode(this.m_iGameModeRestriction)) return false;
				if (this.m_iSkirmishIDRestriction != -1 && !CSGO_IsCorrectSkirmishID(this.m_iSkirmishIDRestriction)) return false;
			}
		}*/

		// All checks passed, we're good to go!
		return true;
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
		this.m_hRequiredContracts = new ArrayList();
		this.m_hObjectives = new ArrayList(sizeof(ContractObjective));
		this.m_iProgress = 0;
		this.m_bInitalized = true;
		this.m_bActive = true;
		this.m_bLoadedFromDatabase = false;
		this.m_bHUD_ContractUpdate = false;
		this.m_iHUD_ObjectiveUpdate = -1;
		this.m_iHUD_UpdateValue = 0;
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
		this.m_bActive = false;
		this.m_bLoadedFromDatabase = false;
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

enum struct CompletedContractInfo
{
	int m_iCompletions;
	bool m_bReset;
}