bool HasClientCompletedContract(int client, char UUID[MAX_UUID_SIZE])
{
	// Could this be made any faster? I'm not a real programmer.
	// The answer is, yes it can.
	if (!IsClientValid(client)) return false;
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;
	return CompletedContracts[client].ContainsKey(UUID);
}

bool IsContractLockedForClient(int client, char UUID[MAX_UUID_SIZE])
{
	if (g_DebugUnlockContracts.BoolValue) return false;

	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return false;
	if (!IsClientValid(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}

	// Grab the Contract from the schema.
	if (g_ContractSchema.JumpToKey(UUID))
	{
		// Construct the required contracts.
		if (g_ContractSchema.JumpToKey("required_contracts", false))
		{
			int Value = 0;
			for (;;)
			{
				char ContractUUID[MAX_UUID_SIZE];
				char ValueStr[4];
				IntToString(Value, ValueStr, sizeof(ValueStr));

				g_ContractSchema.GetString(ValueStr, ContractUUID, sizeof(ContractUUID), "{}");
				// If we reach a blank UUID, we're at the end of the list.
				if (StrEqual("{}", ContractUUID)) break;
				if (CompletedContracts[client].ContainsKey(ContractUUID))
				{
					g_ContractSchema.Rewind();
					return false;
				}
				Value++;
			}
			g_ContractSchema.GoBack();
		}
		else
		{
			g_ContractSchema.Rewind();
			return false;	
		}
	}
	g_ContractSchema.Rewind();
	return true;
}

// TODO: Can this be made faster?
void GiveRandomContract(int client)
{
	if (IsFakeClient(client) && !g_BotContracts.BoolValue) return;
	if (!IsClientValid(client))
	{
		ThrowError("Invalid client index. (%d)", client);
	}
	int RandomContractID = GetRandomInt(0, g_ContractsLoaded-1);
	char RandomUUID[MAX_UUID_SIZE];
	int i = 0;

	g_ContractSchema.GotoFirstSubKey();
	do
	{
		if (i == RandomContractID)
		{
			g_ContractSchema.GetSectionName(RandomUUID, sizeof(RandomUUID));
			break;
		}
		i++;
	}
	while(g_ContractSchema.GotoNextKey());
	g_ContractSchema.Rewind();

	// See if we can activate.
	if (!IsContractLockedForClient(client, RandomUUID) || HasClientCompletedContract(client, RandomUUID))
	{
		// Try again.
		GiveRandomContract(client);
		return;
	}

	// Grant Contract.
	if (IsFakeClient(client) && !g_BotContracts.BoolValue)
	{
		SetClientContractEx(client, RandomUUID, false, false);
	}
	else
	{
		SetClientContractEx(client, RandomUUID, true, true);
	}	
}

/*
bool ContractIsCompletableOnMap(char UUID[MAX_UUID_SIZE])
{
	// Grab the Contract from the schema.
	if (g_ContractSchema.JumpToKey(UUID))
	{
		char CurrentMap[64];
		char MapRestriction[64];
		g_ContractSchema.GetString("map_restriction", MapRestriction, sizeof(MapRestriction));
		if (StrEqual(MapRestriction, ""))
		{
			g_ContractSchema.Rewind();
			return true;
		}
		GetCurrentMap(CurrentMap, sizeof(CurrentMap));
		if (StrContains(MapRestriction, CurrentMap) == -1)
		{
			g_ContractSchema.Rewind();
			return false;
		}
	}
	g_ContractSchema.Rewind();
	return false;
}

bool ContractIsCompletableWithWeapons(int client, char UUID[MAX_UUID_SIZE])
{
	// Grab the Contract from the schema.
	if (g_ContractSchema.JumpToKey(UUID))
	{
		// Classname restriction.
		char ClassnameRestriction[64];
		g_ContractSchema.GetString("weapon_classname_restriction", ClassnameRestriction, sizeof(ClassnameRestriction));
		if (StrEqual(ClassnameRestriction, ""))
		{
			g_ContractSchema.Rewind();
			return true;
		}

		// Loop over player weapons to see are the required weapon to
		// complete the Contract.
		bool WeaponFound = false;

		for (int i = 0; i < GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons"); i++)
		{
			// If we reach an invalid entity, we're probably at the end of
			// this array and we shouldn't bother checking the rest of it.
			if (!IsValidEntity(i)) break;

			char EntityClassname[64];
			GetEntityClassname(i, EntityClassname, sizeof(EntityClassname));
			if (StrContains(EntityClassname, ClassnameRestriction) != -1)
			{
				WeaponFound = true;
				break;
			}
		}

		if (WeaponFound)
		{
			g_ContractSchema.Rewind();
			return false;
		}
	}
	g_ContractSchema.Rewind();
	return false;
}

bool ContractIsCompletableWithTF2Class(int client, char UUID[MAX_UUID_SIZE])
{
    // Grab the Contract from the schema.
	if (g_ContractSchema.JumpToKey(UUID))
	{
        if (g_ContractSchema.JumpToKey("classes", false))
        {
            TFClassType PlayerClass = TF2_GetPlayerClass(client);
            if (PlayerClass == TFClass_Unknown) return false;
            bool ValidClass = false;

            switch (PlayerClass)
            {
                case TFClass_Scout: ValidClass = view_as<bool>(g_ContractSchema.GetNum("scout", 0));
                case TFClass_Soldier: ValidClass = view_as<bool>(g_ContractSchema.GetNum("soldier", 0));
                case TFClass_Pyro: ValidClass = view_as<bool>(g_ContractSchema.GetNum("pyro", 0));
                case TFClass_DemoMan: ValidClass = view_as<bool>(g_ContractSchema.GetNum("demoman", 0));
                case TFClass_Heavy: ValidClass = view_as<bool>(g_ContractSchema.GetNum("heavy", 0));
                case TFClass_Engineer: ValidClass = view_as<bool>(g_ContractSchema.GetNum("engineer", 0));
                case TFClass_Sniper: ValidClass = view_as<bool>(g_ContractSchema.GetNum("sniper", 0));
                case TFClass_Medic: ValidClass = view_as<bool>(g_ContractSchema.GetNum("medic", 0));
                case TFClass_Spy: ValidClass = view_as<bool>(g_ContractSchema.GetNum("spy", 0));
            }

			g_ContractSchema.GoBack();
			PrintToChat(client, "%s %d", UUID, ValidClass);
			return ValidClass;
        }
	}
	g_ContractSchema.Rewind();
	return false;
}
*/