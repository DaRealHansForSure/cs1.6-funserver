using System.Diagnostics;
using System.IO;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed partial class ModeOption(GameMode mode) : ObservableObject {
    public GameMode Mode { get; } = mode;

    [ObservableProperty]
    private bool _isSelected;

    /// <summary>True for the mode the running server plays right now.</summary>
    [ObservableProperty]
    private bool _isRunning;
}

public sealed partial class ServerTabViewModel : TabViewModel {
    private readonly Action<string> _showMapsForMode;

    public IReadOnlyList<ModeOption> Modes { get; }

    /// <summary>Null means a random map of the selected mode.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StartMapText))]
    private string? _chosenStartMap;

    public ModeOption SelectedMode => Modes.First(option => option.IsSelected);

    public string StartMapText => ChosenStartMap ?? $"Random {SelectedMode.Mode.Title} map";

    public ServerTabViewModel(ServerConnection connection, Action<string> showMapsForMode)
        : base("Server", connection) {
        _showMapsForMode = showMapsForMode;
        Modes = GameModes.All.Select(mode => new ModeOption(mode)).ToList();
        SelectMode(Modes.First(option => option.Mode.Id == GameModes.Find(connection.Settings.LastMode).Id));

        connection.PropertyChanged += (_, args) => {
            if (args.PropertyName is nameof(ServerConnection.CurrentModeId) or nameof(ServerConnection.IsRunning)) {
                MarkRunningMode();
            }
        };
        MarkRunningMode();
    }

    private void MarkRunningMode() {
        foreach (ModeOption option in Modes) {
            option.IsRunning = Connection.IsRunning && option.Mode.Id == Connection.CurrentModeId;
        }
    }

    /// <summary>One button for both: start the server, or switch the running one.</summary>
    [RelayCommand]
    private async Task StartOrSwitch() {
        if (Connection.IsRunning) {
            await SwitchNow();
            return;
        }
        StartServer();
    }

    /// <summary>
    /// Switches the running server to the selected mode and map in one go.
    /// fun_modes reads the mode from localinfo on the next map start, the same
    /// way amx_funmode does it, but this way the chosen map is kept.
    /// </summary>
    private async Task SwitchNow() {
        string modeId = SelectedMode.Mode.Id;
        string? map = ChosenStartMap ?? Connection.Maps.PickStartMap(modeId);
        if (map == null) {
            Connection.AddConsoleLine($"! No map installed for {SelectedMode.Mode.Title}. Run 3_UPDATE_MAPS.bat.");
            return;
        }

        await Connection.RunAsync($"localinfo fun_mode {modeId}");
        await Connection.RunAsync($"mapcyclefile mapcycle_{modeId}.txt");
        await Connection.RunAsync($"amx_say \"Switching to {SelectedMode.Mode.Title} on {map}\"");
        await Connection.RunAsync($"changelevel {map}");

        Connection.Settings.LastMode = modeId;
        Connection.Settings.Save(Connection.Paths.WindowSettingsFile);
        ChosenStartMap = null;
    }

    [RelayCommand]
    private void SelectMode(ModeOption option) {
        foreach (ModeOption other in Modes) {
            other.IsSelected = other == option;
        }

        // A map chosen for another mode might not exist in this one.
        ChosenStartMap = null;
        OnPropertyChanged(nameof(SelectedMode));
        OnPropertyChanged(nameof(StartMapText));
    }

    public void UseStartMap(string mapName) {
        ChosenStartMap = mapName;
    }

    [RelayCommand]
    private void ChooseMap() {
        _showMapsForMode(SelectedMode.Mode.Id);
    }

    private void StartServer() {
        string modeId = SelectedMode.Mode.Id;
        string? map = ChosenStartMap ?? Connection.Maps.PickStartMap(modeId);
        if (map == null) {
            Connection.AddConsoleLine($"! No map installed for {SelectedMode.Mode.Title}. Run 3_UPDATE_MAPS.bat.");
            return;
        }

        try {
            // Same file and rules as start-server.ps1, so both ways share one password.
            var localSettings = new LocalSettings(Connection.Paths.LocalConfig);
            localSettings.EnsureRconPassword();
            Connection.ReloadRconPassword();

            Connection.Settings.LastMode = modeId;
            Connection.Settings.Save(Connection.Paths.WindowSettingsFile);

            Connection.Process.Start(modeId, map, Connection.Settings.MaxPlayers, Connection.LanAddress);
            Connection.AddConsoleLine($"Server starting: {SelectedMode.Mode.Title} on {map}");
        } catch (Exception exception) when (exception is InvalidOperationException or IOException or System.ComponentModel.Win32Exception) {
            Connection.AddConsoleLine("! " + exception.Message);
        }
    }

    [RelayCommand]
    private void ToggleTv() {
        if (Connection.Process.IsTvRunning) {
            Connection.Process.StopTv();
            Connection.IsTvRunning = false;
            Connection.AddConsoleLine("TV stopped.");
            return;
        }
        if (!Connection.IsRunning) {
            Connection.AddConsoleLine("! Start the server first, the TV joins it as a spectator.");
            return;
        }

        try {
            Connection.Process.StartTv(Connection.LanAddress);
            Connection.IsTvRunning = true;
            Connection.AddConsoleLine($"TV started. On the TV PC type in the game console: connect {Connection.TvAddress}");
        } catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception) {
            Connection.AddConsoleLine("! " + exception.Message);
        }
    }

    [RelayCommand]
    private void RunInstaller() {
        OpenFile(Connection.Paths.InstallBat);
    }

    [RelayCommand]
    private void UpdateMaps() {
        OpenFile(Connection.Paths.UpdateMapsBat);
    }

    [RelayCommand]
    private void OpenLogs() {
        OpenFile(Connection.Paths.AmxLogsDir);
    }

    [RelayCommand]
    private void CopyConnectCommand() {
        Clipboard.SetText($"connect {Connection.Address}");
        Connection.AddConsoleLine($"Copied: connect {Connection.Address}");
    }

    private void OpenFile(string path) {
        if (!File.Exists(path) && !Directory.Exists(path)) {
            Connection.AddConsoleLine($"! Not found: {path}");
            return;
        }
        Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true, WorkingDirectory = Connection.Paths.Root });
    }
}
