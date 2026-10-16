using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed partial class MainViewModel : ObservableObject {
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan StopGracePeriod = TimeSpan.FromSeconds(8);

    private readonly DispatcherTimer _refreshTimer;
    private bool _isRefreshing;

    public ServerConnection Connection { get; }
    public ServerTabViewModel ServerTab { get; }
    public MapsTabViewModel MapsTab { get; }
    public PlayersTabViewModel PlayersTab { get; }
    public FunTabViewModel FunTab { get; }
    public SettingsTabViewModel SettingsTab { get; }
    public StatsTabViewModel StatsTab { get; }
    public IReadOnlyList<TabViewModel> Tabs { get; }

    [ObservableProperty]
    private TabViewModel _selectedTab;

    [ObservableProperty]
    private string _consoleInput = "";

    [ObservableProperty]
    private bool _isStopping;

    public MainViewModel() {
        Connection = new ServerConnection(PackagePaths.Find());
        ServerTab = new ServerTabViewModel(Connection, ShowMapsForMode);
        MapsTab = new MapsTabViewModel(Connection, UseAsStartMap);
        PlayersTab = new PlayersTabViewModel(Connection);
        FunTab = new FunTabViewModel(Connection);
        SettingsTab = new SettingsTabViewModel(Connection);
        StatsTab = new StatsTabViewModel(Connection);
        Tabs = [ServerTab, MapsTab, PlayersTab, FunTab, StatsTab, SettingsTab];
        _selectedTab = ServerTab;

        _refreshTimer = new DispatcherTimer { Interval = RefreshInterval };
        _refreshTimer.Tick += async (_, _) => await RefreshAsync();
        _refreshTimer.Start();
        _ = RefreshAsync();
    }

    partial void OnSelectedTabChanged(TabViewModel value) {
        // The stats read log files, so they only refresh while somebody looks.
        StatsTab.IsVisible = value == StatsTab;
        _ = value.ActivateAsync();
    }

    private async Task RefreshAsync() {
        // A slow answer must not stack up timer ticks.
        if (_isRefreshing) {
            return;
        }

        _isRefreshing = true;
        try {
            await Connection.RefreshAsync(CancellationToken.None);
        } finally {
            _isRefreshing = false;
        }
    }

    private void ShowMapsForMode(string modeId) {
        MapsTab.ShowMode(modeId);
        SelectedTab = MapsTab;
    }

    private void UseAsStartMap(string mapName) {
        ServerTab.UseStartMap(mapName);
        SelectedTab = ServerTab;
    }

    [RelayCommand]
    private async Task StartOrStop() {
        if (!Connection.IsRunning) {
            SelectedTab = ServerTab;
            ServerTab.StartOrSwitchCommand.Execute(null);
            return;
        }

        IsStopping = true;
        try {
            Connection.AddConsoleLine("Stopping the server...");
            await Connection.RunAsync("quit", echo: false);
            await Connection.Process.StopAsync(StopGracePeriod);
            Connection.AddConsoleLine("Server stopped.");
            await RefreshAsync();
        } finally {
            IsStopping = false;
        }
    }

    [RelayCommand]
    private Task RestartMap() {
        return Connection.RunAsync("restart");
    }

    [RelayCommand]
    private async Task SendConsole() {
        string command = ConsoleInput.Trim();
        if (command.Length == 0) {
            Connection.AddConsoleLine("! Type a command first.");
            return;
        }
        ConsoleInput = "";
        await Connection.RunAsync(command);
    }
}
