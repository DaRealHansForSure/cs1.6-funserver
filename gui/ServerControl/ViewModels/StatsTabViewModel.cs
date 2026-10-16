using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed record LeaderboardRow(int Rank, PlayerStats Stats) {
    public string KillDeathText => Stats.KillDeathRatio.ToString("0.00", CultureInfo.InvariantCulture);
}

public sealed record MapPlayRow(MapPlay Play) {
    public string StartText => Play.StartedAt.ToString("HH:mm", CultureInfo.InvariantCulture);
    public string ModeTitle => Play.ModeId == null ? "" : GameModes.Find(Play.ModeId).Title;

    public string DurationText {
        get {
            if (Play.IsRunning) {
                return ServerConnection.FormatDuration(Play.Duration) + " (now)";
            }
            return Play.Duration == TimeSpan.Zero ? "-" : ServerConnection.FormatDuration(Play.Duration);
        }
    }
}

public sealed record StatsPeriod(string Title, TimeSpan? Length);

public sealed partial class StatsTabViewModel : TabViewModel {
    // A LAN evening rarely lasts longer, and older logs belong to another party.
    private static readonly TimeSpan EveningLength = TimeSpan.FromHours(12);
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromSeconds(10);

    private readonly StatsReader _reader;
    private DateTime _lastRefresh = DateTime.MinValue;

    public bool IsVisible { get; set; }

    public IReadOnlyList<StatsPeriod> Periods { get; } = [
        new("This map", null),
        new("Last 12 hours", EveningLength),
    ];

    public ObservableCollection<LeaderboardRow> Leaderboard { get; } = [];
    public ObservableCollection<MapPlayRow> MapsPlayed { get; } = [];

    [ObservableProperty]
    private StatsPeriod _selectedPeriod;

    [ObservableProperty]
    private bool _hideBots = true;

    [ObservableProperty]
    private string _summary = "";

    /// <summary>0 to 100: how much of the map's time limit is used up.</summary>
    [ObservableProperty]
    private double _mapProgress;

    [ObservableProperty]
    private string _mapProgressText = "";

    public StatsTabViewModel(ServerConnection connection) : base("Stats", connection) {
        _reader = new StatsReader(connection.Paths);
        _selectedPeriod = Periods[1];

        connection.PropertyChanged += (_, args) => {
            if (args.PropertyName is nameof(ServerConnection.Now) or nameof(ServerConnection.TimeLeft)) {
                UpdateMapProgress();
                if (IsVisible && DateTime.Now - _lastRefresh >= RefreshInterval) {
                    Refresh();
                }
            }
        };
    }

    public override Task ActivateAsync() {
        Refresh();
        return Task.CompletedTask;
    }

    partial void OnSelectedPeriodChanged(StatsPeriod value) => Refresh();
    partial void OnHideBotsChanged(bool value) => Refresh();

    [RelayCommand]
    private void Refresh() {
        _lastRefresh = DateTime.Now;
        DateTime now = DateTime.Now;
        DateTime? since = SelectedPeriod.Length == null ? null : now - SelectedPeriod.Length.Value;

        IReadOnlyList<PlayerStats> allPlayers = _reader.ReadLeaderboard(since);
        List<PlayerStats> shown = allPlayers.Where(player => !HideBots || !player.IsBot).ToList();
        Leaderboard.Clear();
        for (int i = 0; i < shown.Count; i++) {
            Leaderboard.Add(new LeaderboardRow(i + 1, shown[i]));
        }

        IReadOnlyList<MapPlay> plays = _reader.ReadMapsPlayed(now - EveningLength, now, Connection.IsRunning);
        MapsPlayed.Clear();
        foreach (MapPlay play in plays.Reverse()) {
            MapsPlayed.Add(new MapPlayRow(play));
        }

        int kills = allPlayers.Sum(player => player.Kills);
        Summary = $"{kills} kills, {allPlayers.Count(player => !player.IsBot)} humans and {allPlayers.Count(player => player.IsBot)} bots in {SelectedPeriod.Title.ToLowerInvariant()}, {plays.Count} maps in the last 12 hours";
        UpdateMapProgress();
    }

    /// <summary>
    /// Elapsed map time against elapsed plus amx_timeleft. Without a time
    /// limit (or before the first answer) the bar stays empty.
    /// </summary>
    private void UpdateMapProgress() {
        if (!Connection.IsRunning || Connection.MapStartedAt == null || !TryParseTimeLeft(Connection.TimeLeft, out TimeSpan left)) {
            MapProgress = 0;
            MapProgressText = Connection.IsRunning ? "No time limit known for this map" : "Server not running";
            return;
        }

        TimeSpan elapsed = Connection.Now - Connection.MapStartedAt.Value;
        double total = elapsed.TotalSeconds + left.TotalSeconds;
        MapProgress = total <= 0 ? 0 : Math.Clamp(elapsed.TotalSeconds / total * 100, 0, 100);
        MapProgressText = $"{Connection.CurrentMap}: {ServerConnection.FormatDuration(elapsed)} played, {Connection.TimeLeft} left, then {Connection.NextMap}";
    }

    /// <summary>amx_timeleft looks like "11:28" (minutes:seconds).</summary>
    internal static bool TryParseTimeLeft(string text, out TimeSpan left) {
        left = TimeSpan.Zero;
        string[] parts = text.Split(':');
        if (parts.Length != 2
            || !int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out int minutes)
            || !int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out int seconds)) {
            return false;
        }
        left = new TimeSpan(0, minutes, seconds);
        return true;
    }
}
