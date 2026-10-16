namespace ServerControl.Services;

public sealed record GameMode(string Id, string Title, string Description);

/// <summary>
/// The five modes, same ids as fun_modes.sma and start-server.ps1.
/// </summary>
public static class GameModes {
    public static readonly IReadOnlyList<GameMode> All = [
        new("classic", "Classic fun", "Hook, grab, parachute, bunnyhop, fun rounds"),
        new("gungame", "GunGame", "Every kill gives the next weapon"),
        new("zombie", "Zombie", "Zombies infect the humans"),
        new("deathmatch", "Deathmatch", "Free for all, instant respawn"),
        new("deathrun", "Deathrun", "One trapper, everybody runs, no bots"),
    ];

    public static GameMode Find(string? id) {
        return All.FirstOrDefault(mode => mode.Id.Equals(id, StringComparison.OrdinalIgnoreCase)) ?? All[0];
    }
}
