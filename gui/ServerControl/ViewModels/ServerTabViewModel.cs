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

    [RelayCommand]
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
