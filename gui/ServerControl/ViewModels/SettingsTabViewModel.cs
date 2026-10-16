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

/// <summary>
/// Settings that hold for every mode go to local.cfg. Bots are the one mode
/// rule the window changes, per mode in local_&lt;mode&gt;.cfg, because a
/// yb_quota in local.cfg would override every mode at once.
/// </summary>
public sealed partial class SettingsTabViewModel : TabViewModel {
    private const int MaxBots = 31;

    public IReadOnlyList<ModeBotSetting> BotsPerMode { get; }

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
    private string _message = "";

    [ObservableProperty]
    private bool _hasError;

    public SettingsTabViewModel(ServerConnection connection) : base("Settings", connection) {
        BotsPerMode = GameModes.All.Select(mode => new ModeBotSetting(mode)).ToList();
        Load();
    }

    /// <summary>
    /// The bot count a mode really runs with: the window's own value, else the
    /// mode config, else base.cfg (which every mode starts from).
    /// </summary>
    private string ReadBotCount(string modeId) {
        foreach (string configFile in new[] { Connection.Paths.ModeLocalConfig(modeId), Connection.Paths.ModeConfig(modeId), Connection.Paths.BaseModeConfig }) {
            string? value = new LocalSettings(configFile).Get("yb_quota");
            if (value != null) {
                return value;
            }
        }
        return "0";
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

        foreach (ModeBotSetting setting in BotsPerMode) {
            setting.BotCount = ReadBotCount(setting.Mode.Id);
        }
    }

    [RelayCommand]
    private async Task Save() {
        if (!TryReadNumber(MaxPlayers, 2, 32, "Max players", out int maxPlayers)
            || !TryReadNumber(FunRoundsEvery, 1, 20, "Fun round every", out int funRoundsEvery)
            || !TryReadNumber(HookSpeed, 100, 3000, "Hook speed", out int hookSpeed)) {
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

        var values = new Dictionary<string, string> {
            ["hostname"] = ServerName.Trim(),
            ["sv_password"] = JoinPassword.Trim(),
            ["fun_rounds_enabled"] = FunRoundsEnabled ? "1" : "0",
            ["fun_rounds_every"] = funRoundsEvery.ToString(CultureInfo.InvariantCulture),
            ["fun_hook_speed"] = hookSpeed.ToString(CultureInfo.InvariantCulture),
            ["fun_hook_admin_only"] = HookAdminOnly ? "1" : "0",
        };

        try {
            var settings = new LocalSettings(Connection.Paths.LocalConfig);
            foreach ((string cvar, string value) in values) {
                settings.Set(cvar, value);
            }
            settings.EnsureRconPassword();
            settings.Save();

            foreach ((string modeId, int botCount) in botCounts) {
                var modeSettings = new LocalSettings(Connection.Paths.ModeLocalConfig(modeId));
                modeSettings.Set("yb_quota", botCount.ToString(CultureInfo.InvariantCulture));
                modeSettings.Save();
            }

            bool maxPlayersChanged = Connection.Settings.MaxPlayers != maxPlayers;
            Connection.Settings.MaxPlayers = maxPlayers;
            Connection.Settings.Save(Connection.Paths.WindowSettingsFile);

            if (Connection.IsRunning) {
                foreach ((string cvar, string value) in values) {
                    await Connection.RunAsync($"{cvar} \"{value}\"");
                }

                // Surf and similar maps switch bots off with their own config,
                // which must keep winning until the next map.
                bool mapHasOwnRules = HasMapTypeConfig(Connection.CurrentMap);
                if (!mapHasOwnRules && botCounts.TryGetValue(Connection.CurrentModeId, out int currentBots)) {
                    await Connection.RunAsync($"yb_quota {currentBots}");
                }
            }

            HasError = false;
            Message = maxPlayersChanged && Connection.IsRunning
                ? "Saved and applied. Max players changes on the next server start."
                : "Saved and applied.";
        } catch (IOException exception) {
            ShowError($"Could not save local.cfg: {exception.Message}");
        }
    }

    /// <summary>Same rule as findMapTypeConfig in fun_modes.sma.</summary>
    private bool HasMapTypeConfig(string mapName) {
        int underscore = mapName.IndexOf('_');
        if (underscore <= 0) {
            return false;
        }
        string prefix = mapName[..underscore].ToLowerInvariant();
        return File.Exists(Path.Combine(Connection.Paths.MapTypeConfigDir, prefix + ".cfg"));
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
