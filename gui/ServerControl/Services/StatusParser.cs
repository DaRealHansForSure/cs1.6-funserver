using System.Globalization;
using System.Text.RegularExpressions;

namespace ServerControl.Services;

public sealed record PlayerEntry(int UserId, string Name, bool IsBot, int Frags, string Time, int Ping);

/// <summary>
/// Reads the player table of the "status" console command. The query protocol
/// would give names and scores too, but only "status" has the userid that the
/// admin commands need (#12) and the BOT marker.
/// </summary>
internal static partial class StatusParser {
    public static IReadOnlyList<PlayerEntry> ParsePlayers(string statusOutput) {
        var players = new List<PlayerEntry>();
        foreach (string rawLine in statusOutput.Split('\n')) {
            Match match = PlayerLine().Match(rawLine.TrimEnd('\r'));
            if (!match.Success) {
                continue;
            }

            players.Add(new PlayerEntry(
                UserId: int.Parse(match.Groups["userid"].Value, CultureInfo.InvariantCulture),
                Name: match.Groups["name"].Value,
                IsBot: match.Groups["uniqueid"].Value.Equals("BOT", StringComparison.OrdinalIgnoreCase),
                Frags: int.Parse(match.Groups["frags"].Value, CultureInfo.InvariantCulture),
                Time: match.Groups["time"].Value,
                Ping: int.Parse(match.Groups["ping"].Value, CultureInfo.InvariantCulture)));
        }
        return players;
    }

    /// <summary>Reads the value from an answer like: "yb_quota" is "8"</summary>
    public static string? ParseCvarValue(string answer) {
        Match match = CvarAnswer().Match(answer);
        return match.Success ? match.Groups["value"].Value : null;
    }

    // #      name userid uniqueid frag time ping loss adr
    // # 1 "ICSharp" 1 STEAM_ID_LAN   14 23:10   12    0 192.168.89.63:27005
    // # 2 "bjaren" 2 BOT    7  9:30    0    0
    [GeneratedRegex(@"^#\s*\d+\s+""(?<name>.*)""\s+(?<userid>\d+)\s+(?<uniqueid>\S+)\s+(?<frags>-?\d+)\s+(?<time>[\d:]+)\s+(?<ping>\d+)")]
    private static partial Regex PlayerLine();

    [GeneratedRegex(@"""[^""]+""\s+is\s+""(?<value>[^""]*)""")]
    private static partial Regex CvarAnswer();
}
