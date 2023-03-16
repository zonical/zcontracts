#define SOUNDS_DB_NAME "use_sounds"
#define HINT_DB_NAME "use_hint_text"
#define HUD_DB_NAME "use_contract_hud"
#define HELP_DB_NAME "display_help_text"
#define HUD_REPEAT_DB_NAME "display_hud_repeat"

Panel PrefPanel[MAXPLAYERS+1];

// Preferences
bool PlayerHelpTextEnabled[MAXPLAYERS+1] = { true, ... };
bool PlayerHUDEnabled[MAXPLAYERS+1] = { true, ... };
bool PlayerHintEnabled[MAXPLAYERS+1] = { true, ... };
bool PlayerHUDRepeatEnabled[MAXPLAYERS+1] = { true, ... };

enum SoundPrefSettings
{
    Sounds_Disabled = 0,
    Sounds_Enabled = 1,
    Sounds_OnlyCompletion = 2
}

SoundPrefSettings PlayerSoundsEnabled[MAXPLAYERS+1] = { Sounds_Enabled, ... };

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

    char SoundsString[128] = "Use Sounds: %s";
    char HudString[128] = "Display Contract HUD: %s";
    char HintString[128] = "Display progress hint text: %s";
    char HudRepeatString[128] = "Display Contract completions in HUD: %s";
    
    if (g_PlaySounds.BoolValue)
    {
        switch (PlayerSoundsEnabled[client])
        {
            case Sounds_Disabled: Format(SoundsString, sizeof(SoundsString), SoundsString, "No Sounds");
            case Sounds_Enabled: Format(SoundsString, sizeof(SoundsString), SoundsString, "All Sounds");
            case Sounds_OnlyCompletion: Format(SoundsString, sizeof(SoundsString), SoundsString, "Completion Sound Only");
        }
    }
    else
    {
        Format(SoundsString, sizeof(SoundsString), SoundsString, "No Sounds");
    }
    
    Format(HudString, sizeof(HudString), HudString, (PlayerHUDEnabled[client] && g_DisplayProgressHud.BoolValue ? "Enabled" : "Disabled"));
    Format(HintString, sizeof(HintString), HintString, (PlayerHintEnabled[client] && g_DisplayHudMessages.BoolValue ? "Enabled" : "Disabled"));
    Format(HudRepeatString, sizeof(HudRepeatString), HudRepeatString, (PlayerHUDRepeatEnabled[client] && g_DisplayRepeatsInHUD.BoolValue ? "Enabled" : "Disabled"));
    
    PrefPanel[client].DrawItem(SoundsString, (g_PlaySounds.BoolValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
    PrefPanel[client].DrawItem(HudString, (g_DisplayProgressHud.BoolValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
    PrefPanel[client].DrawItem(HintString, (g_DisplayHudMessages.BoolValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
    PrefPanel[client].DrawItem(HudRepeatString, (g_DisplayRepeatsInHUD.BoolValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
    PrefPanel[client].DrawItem("Close");

    PrefPanel[client].Send(client, PrefPanelHandler, MENU_TIME_FOREVER);
}

public int PrefPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        if (param2 == 1)
        {
            PlayerSoundsEnabled[param1]++;
            if (PlayerSoundsEnabled[param1] > Sounds_OnlyCompletion)
            {
                PlayerSoundsEnabled[param1] = Sounds_Disabled;
            }
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
        if (param2 == 4)
        {
            PlayerHUDRepeatEnabled[param1] = !PlayerHUDRepeatEnabled[param1];
            ConstructPreferencePanel(param1);
        }
    }
    if (action == MenuAction_Cancel)
    {
        delete PrefPanel[param1];
    }
    return 0;
}

void DB_LoadAllClientPreferences(int client)
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
        PlayerSoundsEnabled[client] = view_as<SoundPrefSettings>(g_PlaySounds.BoolValue);
        PlayerHUDEnabled[client] = g_DisplayProgressHud.BoolValue;
        PlayerHintEnabled[client] = g_DisplayHudMessages.BoolValue;
        PlayerHUDRepeatEnabled[client] = g_DisplayRepeatsInHUD.BoolValue;
        PlayerHelpTextEnabled[client] = true; // No server default.

        return;
    }
    while (results.FetchRow())
    {
        int HelpIndex = -1;
        int SoundIndex = -1;
        int HUDIndex = -1;
        int HintIndex = -1;
        int HUDRepeatIndex = -1;
        
        // Check to see if this field exists or not. Version checking would be helpful here
        // in the future if there are any breaking changes.
        if (results.FieldNameToNum(HELP_DB_NAME, HelpIndex))
        {
            PlayerHelpTextEnabled[client] = view_as<bool>(results.FetchInt(HelpIndex));
        }
        if (results.FieldNameToNum(SOUNDS_DB_NAME, SoundIndex))
        {
            PlayerSoundsEnabled[client] = view_as<SoundPrefSettings>(results.FetchInt(SoundIndex));
        }
        if (results.FieldNameToNum(HUD_DB_NAME, HUDIndex))
        {
            PlayerHUDEnabled[client] = view_as<bool>(results.FetchInt(HUDIndex));
        }
        if (results.FieldNameToNum(HINT_DB_NAME, HintIndex))
        {
            PlayerHintEnabled[client] = view_as<bool>(results.FetchInt(HintIndex));
        }
        if (results.FieldNameToNum(HUD_REPEAT_DB_NAME, HUDRepeatIndex))
        {
            PlayerHUDRepeatEnabled[client] = view_as<bool>(results.FetchInt(HUDRepeatIndex));
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
        "INSERT INTO preferences (steamid64, version, %s, %s, %s, %s, %s) VALUES ('%s', %d, %d, %d, %d, %d, %d)"
    ... " ON DUPLICATE KEY UPDATE version = %d, %s = %d, %s = %d, %s = %d, %s = %d",
    SOUNDS_DB_NAME, HINT_DB_NAME, HUD_DB_NAME, HELP_DB_NAME, HUD_REPEAT_DB_NAME,
    steamid64, CONTRACKER_VERSION, 
    PlayerSoundsEnabled[client], PlayerHintEnabled[client],
    PlayerHUDEnabled[client], PlayerHelpTextEnabled[client], PlayerHUDRepeatEnabled[client],
    
    CONTRACKER_VERSION,
    SOUNDS_DB_NAME, PlayerSoundsEnabled[client],
    HINT_DB_NAME, PlayerHintEnabled[client],
    HUD_DB_NAME, PlayerHUDEnabled[client],
    HELP_DB_NAME, PlayerHelpTextEnabled[client],
    HUD_REPEAT_DB_NAME, PlayerHUDRepeatEnabled[client]);

    DataPack dp = new DataPack();
    dp.WriteString(steamid64);
    dp.Reset();

    g_DB.Query(CB_SaveClientPreferences, query, dp, DBPrio_High); 
}

public void CB_SaveClientPreferences(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    char steamid64[64];
    dp.ReadString(steamid64, sizeof(steamid64));

    if (results.AffectedRows >= 1 && g_DebugQuery.BoolValue)
    {
        LogMessage("[ZContracts] %s PREFERENCES: Saved client preferences.", steamid64);
    }
    return;
}