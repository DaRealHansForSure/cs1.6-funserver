using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed record FunRound(string Id, string Title);

public sealed partial class FunTabViewModel(ServerConnection connection) : TabViewModel("Fun", connection) {
    // Ids match amx_funround in fun_rounds.sma.
    public IReadOnlyList<FunRound> FunRounds { get; } = [
        new("knives", "Knives only"),
        new("awp", "AWP only"),
        new("lowgrav", "Low gravity"),
        new("speed", "Speed"),
        new("headshot", "Headshots only"),
        new("deagle", "One bullet Deagle"),
        new("hewar", "HE war"),
        new("ghost", "Ghosts"),
    ];

    public IReadOnlyList<GameMode> Modes { get; } = GameModes.All;

    [ObservableProperty]
    private string _chatMessage = "";

    [RelayCommand]
    private Task ForceFunRound(FunRound round) => Connection.RunAsync($"amx_funround {round.Id}");

    [RelayCommand]
    private Task SwitchMode(GameMode mode) => Connection.RunAsync($"amx_funmode {mode.Id}");

    [RelayCommand]
    private Task RestartRound() => Connection.RunAsync("sv_restart 1");

    [RelayCommand]
    private Task HookOn() => Connection.RunAsync("fun_hook_enabled 1");

    [RelayCommand]
    private Task HookOff() => Connection.RunAsync("fun_hook_enabled 0");

    [RelayCommand]
    private async Task SendChat() {
        string message = ChatMessage.Trim().Replace("\"", "'");
        if (message.Length == 0) {
            Connection.AddConsoleLine("! Type a chat message first.");
            return;
        }
        await Connection.RunAsync($"amx_say \"{message}\"");
        ChatMessage = "";
    }
}
