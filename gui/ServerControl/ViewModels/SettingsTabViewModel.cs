using System.Globalization;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed partial class ModeBotSetting(GameMode mode) : ObservableObject {
    public GameMode Mode { get; } = mode;

    [ObservableProperty]
    private string _botCount = "0";
}

/// <summary>One choice of a small fixed list, like bot difficulty 0 to 4.</summary>
public sealed record SettingChoice(int Value, string Title);

/// <summary>
/// Where each setting lives, so it overrides exactly what it should:
/// local.cfg for the server (name, password, fun cvars), local_bots.cfg for
/// bot skill and chat in every mode, local_&lt;mode&gt;.cfg for the bot count of
/// one mode. Map configs (surf, the rats maps) still overrule the bot files.
/// </summary>
public sealed partial class SettingsTabViewModel : TabViewModel {
    private const int MaxBots = 31;

    public IReadOnlyList<ModeBotSetting> BotsPerMode { get; }

    // Values as yb_difficulty and yb_radio_mode in YaPB expect them.
    public IReadOnlyList<SettingChoice> DifficultyChoices { get; } = [
        new(0, "Newbie"), new(1, "Easy"), new(2, "Normal"), new(3, "Hard"), new(4, "Expert"),
    ];

    public IReadOnlyList<SettingChoice> RadioChoices { get; } = [
        new(0, "Silent"), new(1, "Radio only"), new(2, "Radio and voice"),
    ];

    [ObservableProperty]
    private string _serverName = "LAN Fun Server";

    [ObservableProperty]
    private string _joinPassword = "";

    [ObservableProperty]
    private string _maxPlayers = "20";

    [ObservableProperty]
    private bool _funRoundsEnabled = true;

    [ObservableProperty]
    private string _funRoundsEvery = "3";

    [ObservableProperty]
    private string _hookSpeed = "750";

    [ObservableProperty]
    private bool _hookAdminOnly;

    [ObservableProperty]
    private SettingChoice _botDifficulty;

    [ObservableProperty]
    private SettingChoice _botRadio;

    [ObservableProperty]
    private bool _botChatEnabled = true;

    [ObservableProperty]
    private string _botChatPercent = "30";

    [ObservableProperty]
    private string _message = "";

    [ObservableProperty]
    private bool _hasError;

    public SettingsTabViewModel(ServerConnection connection) : base("Settings", connection) {
        BotsPerMode = GameModes.All.Select(mode => new ModeBotSetting(mode)).ToList();
        _botDifficulty = DifficultyChoices[2];
        _botRadio = RadioChoices[2];
        Load();
    }

    private void Load() {
        var settings = new LocalSettings(Connection.Paths.LocalConfig);
        ServerName = settings.Get("hostname") ?? ServerName;
        JoinPassword = settings.Get("sv_password") ?? "";
        FunRoundsEnabled = settings.Get("fun_rounds_enabled") != "0";
        FunRoundsEvery = settings.Get("fun_rounds_every") ?? FunRoundsEvery;
        HookSpeed = settings.Get("fun_hook_speed") ?? HookSpeed;
        HookAdminOnly = settings.Get("fun_hook_admin_only") == "1";
        MaxPlayers = Connection.Settings.MaxPlayers.ToString(CultureInfo.InvariantCulture);

        BotDifficulty = FindChoice(DifficultyChoices, ReadBotSetting("yb_difficulty"), BotDifficulty);
        BotRadio = FindChoice(RadioChoices, ReadBotSetting("yb_radio_mode"), BotRadio);
        BotChatEnabled = ReadBotSetting("yb_chat") != "0";
        BotChatPercent = ReadBotSetting("yb_chat_percent") ?? BotChatPercent;

        foreach (ModeBotSetting setting in BotsPerMode) {
            setting.BotCount = ReadFirst("yb_quota", Connection.Paths.ModeLocalConfig(setting.Mode.Id),
                Connection.Paths.ModeConfig(setting.Mode.Id), Connection.Paths.BaseModeConfig) ?? "0";
        }
    }

    /// <summary>The window's own value, else what base.cfg starts every mode with.</summary>
    private string? ReadBotSetting(string cvar) {
        return ReadFirst(cvar, Connection.Paths.BotsLocalConfig, Connection.Paths.BaseModeConfig);
    }

    private static string? ReadFirst(string cvar, params string[] configFiles) {
        foreach (string configFile in configFiles) {
            string? value = new LocalSettings(configFile).Get(cvar);
            if (value != null) {
                return value;
            }
        }
        return null;
    }

    private static SettingChoice FindChoice(IReadOnlyList<SettingChoice> choices, string? value, SettingChoice fallback) {
        return choices.FirstOrDefault(choice => choice.Value.ToString(CultureInfo.InvariantCulture) == value) ?? fallback;
    }

    [RelayCommand]
    private async Task Save() {
        if (!TryReadNumber(MaxPlayers, 2, 32, "Max players", out int maxPlayers)
            || !TryReadNumber(FunRoundsEvery, 1, 20, "Fun round every", out int funRoundsEvery)
            || !TryReadNumber(HookSpeed, 100, 3000, "Hook speed", out int hookSpeed)
            || !TryReadNumber(BotChatPercent, 0, 100, "Bot chat chance", out int botChatPercent)) {
            return;
        }
        if (ServerName.Trim().Length == 0) {
            ShowError("Enter a server name.");
            return;
        }

        var botCounts = new Dictionary<string, int>();
        foreach (ModeBotSetting setting in BotsPerMode) {
            if (!TryReadNumber(setting.BotCount, 0, MaxBots, $"Bots in {setting.Mode.Title}", out int botCount)) {
                return;
            }
            botCounts[setting.Mode.Id] = botCount;
        }

        var serverValues = new Dictionary<string, string> {
            ["hostname"] = ServerName.Trim(),
            ["sv_password"] = JoinPassword.Trim(),
            ["fun_rounds_enabled"] = FunRoundsEnabled ? "1" : "0",
            ["fun_rounds_every"] = Number(funRoundsEvery),
            ["fun_hook_speed"] = Number(hookSpeed),
            ["fun_hook_admin_only"] = HookAdminOnly ? "1" : "0",
        };
        var botValues = new Dictionary<string, string> {
            ["yb_difficulty"] = Number(BotDifficulty.Value),
            ["yb_chat"] = BotChatEnabled ? "1" : "0",
            ["yb_chat_percent"] = Number(botChatPercent),
            ["yb_radio_mode"] = Number(BotRadio.Value),
        };

        try {
            var settings = new LocalSettings(Connection.Paths.LocalConfig);
            SetAll(settings, serverValues);
            settings.EnsureRconPassword();
            settings.Save();

            var botSettings = new LocalSettings(Connection.Paths.BotsLocalConfig);
            SetAll(botSettings, botValues);
            botSettings.Save();

            foreach ((string modeId, int botCount) in botCounts) {
                var modeSettings = new LocalSettings(Connection.Paths.ModeLocalConfig(modeId));
                modeSettings.Set("yb_quota", Number(botCount));
                modeSettings.Save();
            }

            bool maxPlayersChanged = Connection.Settings.MaxPlayers != maxPlayers;
            Connection.Settings.MaxPlayers = maxPlayers;
            Connection.Settings.Save(Connection.Paths.WindowSettingsFile);

            bool mapHasOwnRules = false;
            if (Connection.IsRunning) {
                await ApplyLive(serverValues);

                // Surf and the rats maps set their own bot rules, which must keep
                // winning until the next map. Their file says what they change.
                mapHasOwnRules = HasMapConfig(Connection.CurrentMap);
                if (!mapHasOwnRules) {
                    await ApplyLive(botValues);
                    if (botCounts.TryGetValue(Connection.CurrentModeId, out int currentBots)) {
                        await Connection.RunAsync($"yb_quota {currentBots}");
                    }
                }
            }

            HasError = false;
            Message = DescribeResult(maxPlayersChanged, mapHasOwnRules);
        } catch (IOException exception) {
            ShowError($"Could not save the settings: {exception.Message}");
        }
    }

    private string DescribeResult(bool maxPlayersChanged, bool mapHasOwnRules) {
        if (!Connection.IsRunning) {
            return "Saved. Used on the next server start.";
        }

        var notes = new List<string>();
        if (maxPlayersChanged) {
            notes.Add("max players on the next server start");
        }
        if (mapHasOwnRules) {
            notes.Add("bot settings on the next map, this map has its own");
        }
        return notes.Count == 0 ? "Saved and applied." : $"Saved and applied, {string.Join(", ", notes)}.";
    }

    private async Task ApplyLive(Dictionary<string, string> values) {
        foreach ((string cvar, string value) in values) {
            await Connection.RunAsync($"{cvar} \"{value}\"");
        }
    }

    private static void SetAll(LocalSettings settings, Dictionary<string, string> values) {
        foreach ((string cvar, string value) in values) {
            settings.Set(cvar, value);
        }
    }

    private static string Number(int value) => value.ToString(CultureInfo.InvariantCulture);

    /// <summary>
    /// Same rules as fun_modes.sma: modes/maps/&lt;prefix&gt;.cfg for a map type,
    /// modes/maps/&lt;mapname&gt;.cfg for a single map.
    /// </summary>
    private bool HasMapConfig(string mapName) {
        string lowerName = mapName.ToLowerInvariant();
        if (File.Exists(Path.Combine(Connection.Paths.MapTypeConfigDir, lowerName + ".cfg"))) {
            return true;
        }

        int underscore = lowerName.IndexOf('_');
        if (underscore <= 0) {
            return false;
        }
        return File.Exists(Path.Combine(Connection.Paths.MapTypeConfigDir, lowerName[..underscore] + ".cfg"));
    }

    private bool TryReadNumber(string text, int min, int max, string label, out int value) {
        bool isValid = int.TryParse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value)
            && value >= min && value <= max;
        if (!isValid) {
            ShowError($"{label} must be a number from {min} to {max}.");
        }
        return isValid;
    }

    private void ShowError(string text) {
        HasError = true;
        Message = text;
    }
}
