using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed partial class PlayersTabViewModel(ServerConnection connection) : TabViewModel("Players", connection) {
    private const int MaxBots = 20;

    public ObservableCollection<PlayerEntry> Players { get; } = [];

    [ObservableProperty]
    private string _summary = "Server not running";

    [ObservableProperty]
    private int _botQuota;

    public override async Task ActivateAsync() {
        await Refresh();
    }

    [RelayCommand]
    private async Task Refresh() {
        if (!Connection.IsRunning) {
            Players.Clear();
            Summary = "Server not running";
            return;
        }

        string status = await Connection.RunAsync("status", echo: false);
        IReadOnlyList<PlayerEntry> players = StatusParser.ParsePlayers(status);
        Players.Clear();
        foreach (PlayerEntry player in players.OrderBy(entry => entry.IsBot).ThenByDescending(entry => entry.Frags)) {
            Players.Add(player);
        }

        int bots = players.Count(player => player.IsBot);
        Summary = $"{players.Count - bots} humans, {bots} bots";

        string? quota = StatusParser.ParseCvarValue(await Connection.RunAsync("yb_quota", echo: false));
        if (int.TryParse(quota, NumberStyles.Integer, CultureInfo.InvariantCulture, out int quotaValue)) {
            BotQuota = quotaValue;
        }
    }

    // Every action is an existing admin command, targeted by userid so names
    // with spaces or doubles can not hit the wrong player.
    [RelayCommand]
    private Task Glow(PlayerEntry player) => RunOnPlayer($"amx_glow #{player.UserId} green");

    [RelayCommand]
    private Task Unglow(PlayerEntry player) => RunOnPlayer($"amx_glow #{player.UserId} off");

    [RelayCommand]
    private Task Rocket(PlayerEntry player) => RunOnPlayer($"amx_rocket #{player.UserId}");

    [RelayCommand]
    private Task Godmode(PlayerEntry player) => RunOnPlayer($"amx_godmode #{player.UserId} 1");

    [RelayCommand]
    private Task Noclip(PlayerEntry player) => RunOnPlayer($"amx_noclip #{player.UserId} 1");

    [RelayCommand]
    private Task Slay(PlayerEntry player) => RunOnPlayer($"amx_slay #{player.UserId}");

    [RelayCommand]
    private Task Kick(PlayerEntry player) => RunOnPlayer($"amx_kick #{player.UserId}");

    [RelayCommand]
    private Task AddBot() => SetBotQuota(Math.Min(BotQuota + 1, MaxBots));

    [RelayCommand]
    private Task RemoveBot() => SetBotQuota(Math.Max(BotQuota - 1, 0));

    [RelayCommand]
    private Task BotsOff() => SetBotQuota(0);

    private async Task SetBotQuota(int quota) {
        await Connection.RunAsync($"yb_quota {quota}");
        BotQuota = quota;
        await Task.Delay(800);
        await Refresh();
    }

    private async Task RunOnPlayer(string command) {
        await Connection.RunAsync(command);
        await Refresh();
    }
}
