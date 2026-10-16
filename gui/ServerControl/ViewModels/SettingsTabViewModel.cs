using System.Globalization;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

/// <summary>
/// The few settings that hold for every mode. Mode rules (round time, bots
/// per mode ...) stay in the mode configs on purpose: a value in local.cfg
/// would override them in every mode.
/// </summary>
public sealed partial class SettingsTabViewModel : TabViewModel {
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

            bool maxPlayersChanged = Connection.Settings.MaxPlayers != maxPlayers;
            Connection.Settings.MaxPlayers = maxPlayers;
            Connection.Settings.Save(Connection.Paths.WindowSettingsFile);

            if (Connection.IsRunning) {
                foreach ((string cvar, string value) in values) {
                    await Connection.RunAsync($"{cvar} \"{value}\"");
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
