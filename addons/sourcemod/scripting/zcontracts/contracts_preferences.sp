#define SOUNDS_DB_NAME "use_sounds"
#define HINT_DB_NAME "use_hint_text"
#define HUD_DB_NAME "use_contract_hud"
#define HELP_DB_NAME "display_help_text"

Panel PrefPanel[MAXPLAYERS+1];

// Preferences
bool PlayerHelpTextEnabled[MAXPLAYERS+1] = { true, ... };
bool PlayerSoundsEnabled[MAXPLAYERS+1] = { true, ... };
bool PlayerHUDEnabled[MAXPLAYERS+1] = { true, ... };
bool PlayerHintEnabled[MAXPLAYERS+1] = { true, ... };

public Action OpenPrefPanelCmd(int client, int args)
{
    if (!IsClientValid(client) || IsFakeClient(client)) return Plugin_Continue;
    ConstructPreferencePanel(client);
    return Plugin_Continue;
}

void ConstructPreferencePanel(int client)
{
    PrefPanel[client] = new Panel();
    PrefPanel[client].SetTitle("ZContracts - Client Preferences");
    PrefPanel[client].DrawText("Select an option to toggle its value."); 
    PrefPanel[client].DrawText("Your settings will be saved on disconnect.");
    PrefPanel[client].DrawText(" ");

    char SoundsString[64] = "Enable Sounds: %s";
    char HudString[64] = "Enable Contract HUD: %s";
    char HintString[64] = "Enable Progress hint text: %s";
    Format(SoundsString, sizeof(SoundsString), SoundsString, (PlayerSoundsEnabled[client] ? "true" : "false"));
    Format(HudString, sizeof(HudString), HudString, (PlayerHUDEnabled[client] ? "true" : "false"));
    Format(HintString, sizeof(HintString), HintString, (PlayerHintEnabled[client] ? "true" : "false"));
    PrefPanel[client].DrawItem(SoundsString);
    PrefPanel[client].DrawItem(HudString);
    PrefPanel[client].DrawItem(HintString);
    PrefPanel[client].DrawItem("Close");

    PrefPanel[client].Send(client, PrefPanelHandler, MENU_TIME_FOREVER);
}

public int PrefPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        if (param2 == 1)
        {
            // TODO: This doesn't change for some reason. Check me!
            PlayerSoundsEnabled[param1] = !PlayerSoundsEnabled[param1];
            ConstructPreferencePanel(param1);
        }
        if (param2 == 2)
        {
            PlayerHUDEnabled[param1] = !PlayerHUDEnabled[param1];
            ConstructPreferencePanel(param1);
        } 
        if (param2 == 3)
        {
            PlayerHintEnabled[param1] = !PlayerHintEnabled[param1];
            ConstructPreferencePanel(param1);
        } 
        if (param2 == 1)
        {
            PlayerSoundsEnabled[param1] = !PlayerSoundsEnabled[param1];
            ConstructPreferencePanel(param1);
        } 
    }
    return 0;
}

void LoadAllClientPreferences(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
    }

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    if (g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %N PREFERENCES: Attempting to load preferences.", client);
    }

    char query[1024];
    g_DB.Format(query, sizeof(query),
    "SELECT * FROM preferences WHERE steamid64 = '%s'", steamid64);
    g_DB.Query(CB_LoadAllClientPreferences, query, client);
}

public void CB_LoadAllClientPreferences(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.RowCount == 0)
    {
        // We have no preferences returned. Set them to the server default.
        PlayerSoundsEnabled[client] = g_PlaySounds.BoolValue;
        PlayerHUDEnabled[client] = g_DisplayProgressHud.BoolValue;
        PlayerHintEnabled[client] = g_DisplayHudMessages.BoolValue;
        PlayerHelpTextEnabled[client] = true; // No server default.

        return;
    }
    while (results.FetchRow())
    {
        int HelpIndex = -1;
        int SoundIndex = -1;
        int HUDIndex = -1;
        int HintIndex = -1;
        
        // Check to see if this field exists or not. Version checking would be helpful here
        // in the future if there are any breaking changes.
        if (results.FieldNameToNum(HELP_DB_NAME, HelpIndex))
        {
            PlayerHelpTextEnabled[client] = view_as<bool>(results.FetchInt(HelpIndex));
        }
        if (results.FieldNameToNum(SOUNDS_DB_NAME, SoundIndex))
        {
            PlayerSoundsEnabled[client] = view_as<bool>(results.FetchInt(SoundIndex));
        }
        if (results.FieldNameToNum(HUD_DB_NAME, HUDIndex))
        {
            PlayerHUDEnabled[client] = view_as<bool>(results.FetchInt(HUDIndex));
        }
        if (results.FieldNameToNum(HINT_DB_NAME, HintIndex))
        {
            PlayerHintEnabled[client] = view_as<bool>(results.FetchInt(HintIndex));
        }

        if (g_DebugQuery.BoolValue)
        {
            LogMessage("[ZContracts] %N PREFERENCES: Loaded client preferences.", client);
        }
    }

    return;
}

void SaveClientPreferences(int client)
{
    if (!IsClientValid(client) || IsFakeClient(client))
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index. (%d)", client);
    }

    // Get the client's SteamID64.
    char steamid64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));

    char query[1024];
    g_DB.Format(query, sizeof(query),
        "INSERT INTO preferences (steamid64, version, %s, %s, %s, %s) VALUES ('%s', %d, %d, %d, %d, %d)"
    ... " ON DUPLICATE KEY UPDATE version = %d, %s = %d, %s = %d, %s = %d, %s = %d",
    SOUNDS_DB_NAME, HINT_DB_NAME, HUD_DB_NAME, HELP_DB_NAME, 
    steamid64, CONTRACKER_VERSION, PlayerSoundsEnabled[client], PlayerHintEnabled[client], PlayerHUDEnabled[client], PlayerHelpTextEnabled[client],
    CONTRACKER_VERSION,
    SOUNDS_DB_NAME, PlayerSoundsEnabled[client],
    HINT_DB_NAME, PlayerHintEnabled[client],
    HUD_DB_NAME, PlayerHUDEnabled[client],
    HELP_DB_NAME, PlayerHelpTextEnabled[client]);

    g_DB.Query(CB_SaveClientPreferences, query, client, DBPrio_High); 
}

public void CB_SaveClientPreferences(Database db, DBResultSet results, const char[] error, int client)
{
    if (results.AffectedRows >= 1 && g_DebugQuery.BoolValue && IsClientValid(client))
    {
        LogMessage("[ZContracts] %N PREFERENCES: Saved client preferences.", client);
    }
    return;
}

