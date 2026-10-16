using System.Collections.ObjectModel;
using System.Net;
using CommunityToolkit.Mvvm.ComponentModel;
using ServerControl.Services;

namespace ServerControl.ViewModels;

/// <summary>
/// The one place that knows the server: its process, address, live status and
/// the RCON line. The status bar and every tab read from here, and every
/// command goes through RunAsync so it shows up in the console panel.
/// </summary>
public sealed partial class ServerConnection : ObservableObject {
    private const int ConsoleLineLimit = 300;

    private readonly ServerQuery _query = new();
    private readonly ModeLog _modeLog;

    public PackagePaths Paths { get; }
    public ServerProcess Process { get; }
    public RconClient Rcon { get; } = new();
    public MapCatalog Maps { get; }
    public WindowSettings Settings { get; }
    public ObservableCollection<string> ConsoleLines { get; } = [];

    [ObservableProperty]
    private bool _isRunning;

    [ObservableProperty]
    private bool _isAnswering;

    [ObservableProperty]
    private bool _isTvRunning;

    [ObservableProperty]
    private string _serverName = "LAN Fun Server";

    [ObservableProperty]
    private string _currentMap = "";

    [ObservableProperty]
    private string _currentModeId = GameModes.All[0].Id;

    [ObservableProperty]
    private int _playerCount;

    [ObservableProperty]
    private int _maxPlayers;

    [ObservableProperty]
    private IPAddress _lanAddress;

    public string Address => $"{LanAddress}:{ServerProcess.GamePort}";
    public string TvAddress => $"{LanAddress}:{ServerProcess.TvPort}";
    public string CurrentModeTitle => GameModes.Find(CurrentModeId).Title;

    public string StatusText {
        get {
            if (!Paths.IsServerInstalled) {
                return "Not installed, run 1_INSTALL.bat";
            }
            if (!IsRunning) {
                return "Stopped";
            }
            if (!IsAnswering) {
                return "Starting...";
            }
            return $"{CurrentMap} \u00B7 {CurrentModeTitle} \u00B7 {PlayerCount}/{MaxPlayers} players";
        }
    }

    public ServerConnection(PackagePaths paths) {
        Paths = paths;
        Process = new ServerProcess(paths);
        Maps = new MapCatalog(paths);
        Settings = WindowSettings.Load(paths.WindowSettingsFile);
        _modeLog = new ModeLog(paths.AmxLogsDir);
        _lanAddress = ServerProcess.FindLanAddress();
        _maxPlayers = Settings.MaxPlayers;

        Rcon.Server = new IPEndPoint(_lanAddress, ServerProcess.GamePort);
        Rcon.Password = new LocalSettings(paths.LocalConfig).Get("rcon_password") ?? "";
    }

    partial void OnIsRunningChanged(bool value) => OnPropertyChanged(nameof(StatusText));
    partial void OnIsAnsweringChanged(bool value) => OnPropertyChanged(nameof(StatusText));
    partial void OnCurrentMapChanged(string value) => OnPropertyChanged(nameof(StatusText));
    partial void OnPlayerCountChanged(int value) => OnPropertyChanged(nameof(StatusText));
    partial void OnMaxPlayersChanged(int value) => OnPropertyChanged(nameof(StatusText));

    partial void OnCurrentModeIdChanged(string value) {
        OnPropertyChanged(nameof(CurrentModeTitle));
        OnPropertyChanged(nameof(StatusText));
    }

    partial void OnLanAddressChanged(IPAddress value) {
        OnPropertyChanged(nameof(Address));
        OnPropertyChanged(nameof(TvAddress));
        Rcon.Server = new IPEndPoint(value, ServerProcess.GamePort);
    }

    /// <summary>Polls process, query and mode log. Called by a timer.</summary>
    public async Task RefreshAsync(CancellationToken cancellation) {
        IsRunning = Process.IsRunning;
        IsTvRunning = Process.IsTvRunning;
        if (!IsRunning) {
            IsAnswering = false;
            PlayerCount = 0;
            return;
        }

        ServerInfo? info = await _query.QueryAsync(new IPEndPoint(LanAddress, ServerProcess.GamePort), cancellation);
        IsAnswering = info != null;
        if (info == null) {
            return;
        }

        ServerName = info.Name;
        CurrentMap = info.Map;
        PlayerCount = info.Players;
        MaxPlayers = info.MaxPlayers;
        CurrentModeId = _modeLog.ReadActiveMode() ?? CurrentModeId;
    }

    /// <summary>
    /// Sends a console command, echoes it and the answer into the console panel
    /// and returns the answer (empty when it failed, the panel shows why).
    /// </summary>
    public async Task<string> RunAsync(string command, bool echo = true) {
        if (echo) {
            AddConsoleLine("> " + command);
        }

        try {
            string answer = await Rcon.SendAsync(command);
            if (echo && answer.Length > 0) {
                foreach (string line in answer.Split('\n')) {
                    AddConsoleLine(line.TrimEnd('\r'));
                }
            }
            return answer;
        } catch (RconException exception) {
            AddConsoleLine("! " + exception.Message);
            return "";
        }
    }

    public void ReloadRconPassword() {
        Rcon.Password = new LocalSettings(Paths.LocalConfig).Get("rcon_password") ?? "";
        Rcon.Reset();
    }

    public void AddConsoleLine(string line) {
        ConsoleLines.Add(line);
        while (ConsoleLines.Count > ConsoleLineLimit) {
            ConsoleLines.RemoveAt(0);
        }
    }
}
