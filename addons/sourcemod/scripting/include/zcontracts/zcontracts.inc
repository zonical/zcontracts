#if defined __zcontracts_included
	#endinput
#endif

#define __zcontracts_included

#define ZCONTRACTS_PLUGIN_VERSION "0.11.0"
// This value should be incremented with every breaking version made to the
// database so saves can be easily converted. For developers who fork this project and
// wish to merge changes, do not increment this number until merge.
// Other plugins should use the GetContrackerVersion() native to get this value, but
// this main plugin and subplugins are free to use the define name in its place.
#define CONTRACKER_VERSION 3
// How often the HUD will refresh itself.
#define HUD_REFRESH_RATE 0.5

#define MAX_UUID_SIZE 64
#define MAX_CONTRACT_NAME_SIZE 64
#define MAX_OBJECTIVE_DESC_SIZE 128
#define MAX_EVENT_SIZE 256
#define MAX_DIRECTORY_SIZE 128

#include <zcontracts/zcontracts_natives>
#include <zcontracts/zcontracts_forwards>

stock int Int_Min(int a, int b) { return a < b ? a : b; }
stock bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}

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

// Struct representing a Contract.
// THERE ARE SEVERAL THINGS LISTED HERE THAT ARE NOT STORED IN THE CONTRACT STRUCT!
// Weapon restriction types:
// "name": Name of the Contract, duh.
// "description": A description on how to complete the Contract or Objective.
// "active_weapon_slot": The slot for the weapon set at m_hActiveWeapon (see items_game.txt)
// "active_weapon_name": The display economy name for the weapon set at m_hActiveWeapon.
// "active_weapon_classname": The classname of the weapon set at m_hActiveWeapon.
// "active_weapon_itemdef": The item definition index for the weapon set at m_hActiveWeapon.
// "inventory_item_name": The display economy name for an item in the players current inventory.
// "inventory_item_classname": The classname for an item in the players current inventory.
// "inventory_item_itemdef": The item definition index for an item in the players current inventory.
// If a player kills another player without using the specified active weapon, the contract is not updated.
// If a player kills another player with a specified active weapon, the contract is updated.
// If a player kills another player without having a specified inventory item equipped, the contract is not updated.
// If a player kills another player while having a specified inventory item equipped, the contract is updated.
//
// Map restriction: "map_restriction". This can be a whole map or part of a map name.
// Examples: "pl_upward", "ctf_2fort", "koth_", "pl_constantlyupdated_v3"
//
// Team restriction: "team_restriction". This can be a team index number or a special name.

// Definitions for things that are used in the base ZContracts plugin:

#define CONTRACT_DEF_NAME "name"
#define CONTRACT_DEF_DIRECTORY "directory"
#define CONTRACT_DEF_TYPE "type"
#define CONTRACT_DEF_MAX_PROGRESS "maximum_cp"
#define CONTRACT_DEF_OBJECTIVES "objectives"
#define CONTRACT_DEF_REQUIRED "required_contracts"
#define CONTRACT_DEF_DIFFICULTY "difficulty"

#define CONTRACT_DEF_OBJ_DESC "description"
#define CONTRACT_DEF_OBJ_EXT_DESC "extended_description"
#define CONTRACT_DEF_OBJ_INFINITE "infinite"
#define CONTRACT_DEF_OBJ_AWARD "award"
#define CONTRACT_DEF_OBJ_EVENTS "events"
#define CONTRACT_DEF_OBJ_MAX_PROGRESS "maximum_cp"
#define CONTRACT_DEF_OBJ_NO_MULTI "no_multiplication"

#define CONTRACT_DEF_EVENT_TYPE "type"
#define CONTRACT_DEF_EVENT_THRESHOLD "threshold"
#define CONTRACT_DEF_EVENT_TIMER "timer"
#define CONTRACT_DEF_TIMER_TIME "time"

#define CONTRACT_DEF_ACTIVE_WEAPON_SLOT	"active_weapon_slot"
#define CONTRACT_DEF_ACTIVE_WEAPON_NAME	"active_weapon_name"
#define CONTRACT_DEF_ACTIVE_WEAPON_CLASSNAME "active_weapon_classname"
#define CONTRACT_DEF_ACTIVE_WEAPON_ITEMDEF "active_weapon_itemdef"

#define CONTRACT_DEF_INV_ITEM_NAME "inventory_item_name"
#define CONTRACT_DEF_INV_ITEM_CLASSNAME "inventory_item_classname"
#define CONTRACT_DEF_INV_ITEM_ITEMDEF "inventory_item_itemdef"

#define CONTRACT_DEF_MAP "map_restriction"
#define CONTRACT_DEF_TEAM "team_restriction"

#define CONTRACT_DEF_UNIX_START "contract_start_unixtime"
#define CONTRACT_DEF_UNIX_END "contract_end_unixtime"

enum struct Contract
{
	bool Initalized;
	bool Active;

	// Internal representation of the Contract.
	char UUID[MAX_UUID_SIZE];

	// If we're using "contract progress" mode, there is one central
	// progress bar that is updated alongside our objective.
	int ContractProgress;
	// NOTE: values are never removed from these ArrayLists. The values are only modified.
	ArrayList ObjectiveProgress;
	ArrayList ObjectiveThreshold;
	ArrayList ObjectiveTimers;
	ArrayList ObjectiveTimerStarted;
	int ObjectiveCount;

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

	// These three variables trigger visuals on the HUD.
	bool m_bHUD_ContractUpdate;
	int m_iHUD_ObjectiveUpdate;
	int m_iHUD_UpdateValue;
	
	bool IsContractInitalized()
	{
		return this.UUID[0] == '{' && this.Initalized;
	}

	/**
	 * @return		If this Contract is complete.
	**/
	bool IsContractComplete()
	{
		if (!this.Active || !this.Initalized) return false;
		
		switch (view_as<ContractType>(this.GetSchema().GetNum(CONTRACT_DEF_TYPE)))
		{
			case Contract_ObjectiveProgress: // All objectives must be complete.
			{
				for (int i = 0; i < this.ObjectiveCount; i++)
				{
					KeyValues ObjSchema = this.GetObjectiveSchema(i);
					if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_INFINITE) == 1) continue;
					if (!this.IsObjectiveComplete(i)) return false;
				}
				return true;
			}
			case Contract_ContractProgress: // The Contract's progress bar must be complete.
			{
				return this.ContractProgress >= this.GetSchema().GetNum(CONTRACT_DEF_MAX_PROGRESS);
			}	
		}
		return false;
	}

	bool IsObjectiveComplete(int ObjectiveID)
	{
		KeyValues ObjSchema = this.GetObjectiveSchema(ObjectiveID);
		if (ObjSchema.GetNum(CONTRACT_DEF_OBJ_INFINITE) == 1) return false;
		return (this.ObjectiveProgress.Get(ObjectiveID) >= ObjSchema.GetNum(CONTRACT_DEF_OBJ_MAX_PROGRESS));
	}

	bool IsObjectiveInfinite(int ObjectiveID)
	{
		KeyValues ObjSchema = this.GetObjectiveSchema(ObjectiveID);
		return (ObjSchema.GetNum(CONTRACT_DEF_OBJ_INFINITE) == 1)
	}

	bool IsTimerRunning(int ObjectiveID)
	{
		return (this.ObjectiveTimers.Get(ObjectiveID) != INVALID_HANDLE);
	}

	KeyValues GetSchema()
	{
		return GetContractSchema(this.UUID);
	}

	KeyValues GetObjectiveSchema(int ObjectiveID)
	{
		return GetObjectiveSchema(this.UUID, ObjectiveID);
	}

	/**
	 * Creates the ArrayList for objectives.
	**/
	void Initalize(char UUID[MAX_UUID_SIZE])
	{
		this.Initalized = true;
		this.Active = true;
		this.ContractProgress = 0;
		this.UUID = UUID;

		this.ObjectiveProgress = new ArrayList();
		this.ObjectiveThreshold = new ArrayList(sizeof(StringMap));
		this.ObjectiveTimers = new ArrayList(sizeof(Handle));
		this.ObjectiveTimerStarted = new ArrayList();

		KeyValues Schema = this.GetSchema()
		// Grab the schema KeyValue objects of our objectives and store them locally.
		if (Schema.JumpToKey(CONTRACT_DEF_OBJECTIVES))
		{
			int ObjectiveID = 0;
			Schema.GotoFirstSubKey();
			do
			{
				this.ObjectiveProgress.Push(0);
				this.ObjectiveThreshold.Push(new StringMap());
				this.ObjectiveTimers.Push(INVALID_HANDLE);
				this.ObjectiveTimerStarted.Push(-1.0);
				this.ObjectiveCount++;
				ObjectiveID++;

			} while (Schema.GotoNextKey());
		}
		else
		{
			ThrowError("Tried to load Contract with no objectives! UUID: %s", this.UUID);
		}
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
		this.Initalized = false;
		this.Active = false;

		delete this.ObjectiveProgress;
		delete this.ObjectiveThreshold;
		delete this.ObjectiveTimers;
		delete this.ObjectiveTimerStarted;
		this.ObjectiveCount = 0;
		this.ContractProgress = 0;

		this.m_bLoadedFromDatabase = false;
		this.m_bHUD_ContractUpdate = false;
		this.m_iHUD_ObjectiveUpdate = -1;
		this.m_iHUD_UpdateValue = 0;
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