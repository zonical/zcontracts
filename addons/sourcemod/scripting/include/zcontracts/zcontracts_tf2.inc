#if defined __zcontracts_tf2_included
	#endinput
#endif

#define __zcontracts_tf2_included

#include <tf2>
#include <tf2_stocks>

#define CONTRACT_DEF_TF2_CLASSES "classes"

// ============================= SCHEMA FUNCTIONS =============================

stock int TF2_GetTeamIndexFromString(const char[] team)
{
    if (StrEqual(team, "red")) return view_as<int>(TFTeam_Red);
    if (StrEqual(team, "blue") || StrEqual(team, "blu")) 
    {
        return view_as<int>(TFTeam_Blue);
    }

    return -1;
}

// ============================= GAMEMODE EXTENSIONS =============================

// Some gamemodes which have variations might not be detectable
// with the existance of a gamerules entity. Attack/Defend CP maps
// are an example of this.
enum TF2GameMode_Extensions
{
    TGE_NoExtension = 0,
    TGE_RedAttacksBlu = 1, // Standard A/D
    TGE_BluAttacksRed = 2, // Standard Payload
    TGE_Symmetrical = 3 // 3CP like Powerhouse or 5CP like Badlands
}

// Checks to see if a GameRules entity exists on the current map.
stock bool TF2_ValidGameRulesEntityExists(const char[] classname)
{
	// Ignore if string is empty.
	if (StrEqual(classname, "")) return true;

	// Validate that we're actually checking for
	// a gamerules entity with a classname check.
	if (StrContains(classname, "tf_logic_") == -1) return false;

	// Try and find this entity.
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		return true;
	}
	return false;
}

// ============================= NATIVES AND FORWARDS =============================

/**
 * Overrides the value of the gamemode extension for TF2 logic. See contracts_tf2.sp
 * @param value    The new value of the the gamemode extension.
*/
native bool SetTF2GameModeExt(int value);

/**
 * Gets the gamemode extension that is used for TF2 logic. See contracts_tf2.sp
 * @return	Value of the gamemode extension.
*/
native int GetTF2GameModeExt();

/**
 * Called at the start of every map when ZContracts checks to see what type of
 * map is being played (e.g Control Points but it's A/D or Symmetrical). This
 * Forward is best used alongside SetTF2GameModeExt to alter the gamemode extension.
 * A value of Plugin_Changed or higher must be returned otherwise ZContracts will
 * override any value set by SetTF2GameModeExt.
 */
forward Action OnTF2GameModeExtCheck();