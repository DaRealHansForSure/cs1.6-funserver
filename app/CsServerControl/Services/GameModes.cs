namespace CsServerControl.Services;

public sealed record GameMode(string Id, string Title, string Description);

public static class GameModes {
    public static readonly IReadOnlyList<GameMode> All = [
        new("classic", "Classic Fun", "Hook, grab, parachute, bunny hop"),
        new("gungame", "GunGame", "24 weapon levels, free for all"),
        new("zombie", "Zombie", "Humans against zombies, infection"),
        new("deathmatch", "Deathmatch", "Instant respawn, random weapons"),
    ];

    public static string TitleOf(string? modeId) {
        GameMode? mode = All.FirstOrDefault(candidate => candidate.Id == modeId);
        if (mode != null) {
            return mode.Title;
        }
        if (string.IsNullOrEmpty(modeId)) {
            return "-";
        }
        // Modes the window has no tile for (deathrun) still get a readable name.
        return char.ToUpperInvariant(modeId[0]) + modeId[1..];
    }
}
