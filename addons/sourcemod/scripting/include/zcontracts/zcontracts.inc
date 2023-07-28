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
enum struct Contract
{
	bool Initalized;
	bool Active;

	KeyValues CachedSchema;
	ArrayList CachedObjSchema;

	// Internal representation of the Contract.
	char UUID[MAX_UUID_SIZE];

	// If we're using "contract progress" mode, there is one central
	// progress bar that is updated alongside our objective.
	int ContractProgress;
	// NOTE: values are never removed from these ArrayLists. The values are only modified.
	ArrayList ObjectiveProgress;
	ArrayList ObjectiveThreshold;
	ArrayList ObjectiveTimers;
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
		
		switch (view_as<ContractType>(this.CachedSchema.GetNum("type")))
		{
			case Contract_ObjectiveProgress: // All objectives must be complete.
			{
				for (int i = 0; i < this.ObjectiveCount; i++)
				{
					KeyValues ObjSchema = this.CachedObjSchema.Get(i);
					return (this.ObjectiveProgress.Get(i) >= ObjSchema.GetNum("maximum_cp"));
				}
				return true;
			}
			case Contract_ContractProgress: // The Contract's progress bar must be complete.
			{
				return this.ContractProgress >= this.CachedSchema.GetNum("maximum_cp");
			}	
		}
		return false;
	}

	bool IsObjectiveComplete(int ObjectiveID)
	{
		KeyValues ObjSchema = this.CachedObjSchema.Get(ObjectiveID);
		return (this.ObjectiveProgress.Get(ObjectiveID) >= ObjSchema.GetNum("maximum_cp"));
	}

	bool IsObjectiveInfinite(int ObjectiveID)
	{
		KeyValues ObjSchema = this.CachedObjSchema.Get(ObjectiveID);
		return (ObjSchema.GetNum("infinite") == 1)
	}

	bool IsTimerRunning(int ObjectiveID)
	{
		return (this.ObjectiveTimers.Get(ObjectiveID) != INVALID_HANDLE);
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

		this.CachedSchema = GetContractSchema(this.UUID);
		this.ObjectiveProgress = new ArrayList();
		this.ObjectiveThreshold = new ArrayList(sizeof(StringMap));
		this.ObjectiveTimers = new ArrayList(sizeof(Handle));

		this.CachedObjSchema = new ArrayList(sizeof(KeyValues));

		// Grab the schema KeyValue objects of our objectives and store them locally.
		if (this.CachedSchema.JumpToKey("objectives"))
		{
			int ObjectiveID = 0;
			this.CachedSchema.GotoFirstSubKey();
			do
			{
				KeyValues ObjSchema = GetObjectiveSchema(this.UUID, ObjectiveID);
				this.CachedObjSchema.Push(ObjSchema);
				this.ObjectiveProgress.Push(0);
				this.ObjectiveThreshold.Push(new StringMap());
				this.ObjectiveTimers.Push(INVALID_HANDLE);
				this.ObjectiveCount++;
				ObjectiveID++;

			} while (this.CachedSchema.GotoNextKey());
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

		this.CachedSchema = null;
		delete this.CachedObjSchema;

		delete this.ObjectiveProgress;
		delete this.ObjectiveThreshold;
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