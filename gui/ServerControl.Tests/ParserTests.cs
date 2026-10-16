using System.IO;
using System.Text;
using ServerControl.Services;
using Xunit;

namespace ServerControl.Tests;

public class QueryParserTests {
    [Fact]
    public void ReadsSourceStyleInfo() {
        byte[] packet = Packet(
            [(byte)'I', 48],
            "LAN Fun Server", "surf_ski_2", "cstrike", "Counter-Strike",
            new byte[] { 10, 0, 6, 20, 3 });

        ServerInfo? info = QueryParser.ParseInfo(packet);

        Assert.NotNull(info);
        Assert.Equal("LAN Fun Server", info.Name);
        Assert.Equal("surf_ski_2", info.Map);
        Assert.Equal(6, info.Players);
        Assert.Equal(20, info.MaxPlayers);
        Assert.Equal(3, info.Bots);
    }

    [Fact]
    public void ReadsGoldSrcStyleInfo() {
        byte[] packet = Packet(
            [(byte)'m'],
            "192.168.89.63:27015", "LAN Fun Server", "de_rats", "cstrike", "Counter-Strike",
            new byte[] { 4, 20, 47 });

        ServerInfo? info = QueryParser.ParseInfo(packet);

        Assert.NotNull(info);
        Assert.Equal("de_rats", info.Map);
        Assert.Equal(4, info.Players);
        Assert.Equal(20, info.MaxPlayers);
    }

    [Fact]
    public void RecognizesChallenge() {
        byte[] packet = [0xFF, 0xFF, 0xFF, 0xFF, (byte)'A', 1, 2, 3, 4];

        Assert.True(QueryParser.TryReadChallenge(packet, out byte[] challenge));
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, challenge);
        Assert.Null(QueryParser.ParseInfo(packet));
    }

    [Fact]
    public void RejectsGarbage() {
        Assert.Null(QueryParser.ParseInfo([1, 2, 3]));
        Assert.False(QueryParser.TryReadChallenge([0xFF, 0xFF, 0xFF, 0xFF, (byte)'I'], out _));
    }

    private static byte[] Packet(byte[] head, params object[] parts) {
        var bytes = new List<byte> { 0xFF, 0xFF, 0xFF, 0xFF };
        bytes.AddRange(head);
        foreach (object part in parts) {
            if (part is string text) {
                bytes.AddRange(Encoding.UTF8.GetBytes(text));
                bytes.Add(0);
            } else if (part is byte[] raw) {
                bytes.AddRange(raw);
            }
        }
        return bytes.ToArray();
    }
}

public class StatusParserTests {
    private const string StatusOutput =
        "hostname:  LAN Fun Server\n" +
        "version :  48/1.1.2.7/Stdio 4419 secure  (10)\n" +
        "tcp/ip  :  192.168.89.63:27015\n" +
        "map     :  surf_ski_2 at: 0 x, 0 y, 0 z\n" +
        "players :  3 active (20 max)\n" +
        "\n" +
        "#      name userid uniqueid frag time ping loss adr\n" +
        "# 1 \"ICSharp\"  1 STEAM_ID_LAN   14 23:10   12    0 192.168.89.63:27005\n" +
        "# 2 \"[SMUT]DarkDruid\"  7 BOT    7  9:30    0    0\n" +
        "# 3 \"Player with spaces\" 12 STEAM_ID_LAN   -2 1:02:03   35    1 192.168.89.70:27005\n" +
        "3 users\n";

    [Fact]
    public void ReadsHumansAndBots() {
        IReadOnlyList<PlayerEntry> players = StatusParser.ParsePlayers(StatusOutput);

        Assert.Equal(3, players.Count);
        Assert.Equal(new PlayerEntry(1, "ICSharp", false, 14, "23:10", 12), players[0]);
        Assert.True(players[1].IsBot);
        Assert.Equal(7, players[1].UserId);
        Assert.Equal("Player with spaces", players[2].Name);
        Assert.Equal(-2, players[2].Frags);
        Assert.Equal("1:02:03", players[2].Time);
    }

    [Fact]
    public void ReadsCrlfLines() {
        IReadOnlyList<PlayerEntry> players = StatusParser.ParsePlayers(StatusOutput.Replace("\n", "\r\n"));
        Assert.Equal(3, players.Count);
    }

    [Theory]
    [InlineData("\"yb_quota\" is \"8\"\n", "8")]
    [InlineData("\"hostname\" is \"LAN Fun Server\"", "LAN Fun Server")]
    [InlineData("Unknown command: yb_quota", null)]
    public void ReadsCvarAnswer(string answer, string? expected) {
        Assert.Equal(expected, StatusParser.ParseCvarValue(answer));
    }
}

public class RconPacketTests {
    [Fact]
    public void StripsHeaderAndPrintMarker() {
        byte[] packet = [0xFF, 0xFF, 0xFF, 0xFF, (byte)'l', .. Encoding.ASCII.GetBytes("Bad rcon_password.\n"), 0, 0];
        Assert.Equal("Bad rcon_password.\n", RconPacket.ReadText(packet));
    }

    [Fact]
    public void ReadsChallengeReply() {
        byte[] packet = [0xFF, 0xFF, 0xFF, 0xFF, .. Encoding.ASCII.GetBytes("challenge rcon 123456789\n"), 0];
        Assert.Equal("challenge rcon 123456789\n", RconPacket.ReadText(packet));
    }
}

public class LocalSettingsTests : IDisposable {
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"local-{Guid.NewGuid():N}.cfg");

    public void Dispose() {
        File.Delete(_path);
        GC.SuppressFinalize(this);
    }

    [Fact]
    public void KeepsUnknownLinesAndReplacesValues() {
        File.WriteAllText(_path, "// my notes\r\nrcon_password \"secret\"\r\nmp_friendlyfire \"1\"\r\n");

        var settings = new LocalSettings(_path);
        settings.Set("hostname", "Peter's LAN");
        settings.Set("rcon_password", "other");
        settings.Save();

        string[] lines = File.ReadAllLines(_path);
        Assert.Equal("// my notes", lines[0]);
        Assert.Contains("rcon_password \"other\"", lines);
        Assert.Contains("mp_friendlyfire \"1\"", lines);
        Assert.Contains("hostname \"Peter's LAN\"", lines);
        Assert.Single(lines, line => line.StartsWith("rcon_password", StringComparison.Ordinal));
    }

    [Fact]
    public void CreatesPasswordOnlyOnce() {
        var settings = new LocalSettings(_path);
        string first = settings.EnsureRconPassword();
        string second = new LocalSettings(_path).EnsureRconPassword();

        Assert.Equal(16, first.Length);
        Assert.Equal(first, second);
        Assert.StartsWith("//", File.ReadAllLines(_path)[0]);
    }

    [Fact]
    public void ReadsUnquotedValuesOfTheModeConfigs() {
        File.WriteAllText(_path, "// GunGame\r\nmapcyclefile \"mapcycle_gungame.txt\"\r\nyb_quota 6\r\nmp_forcerespawn 1.5 // seconds\r\n");

        var settings = new LocalSettings(_path);

        Assert.Equal("6", settings.Get("yb_quota"));
        Assert.Equal("1.5", settings.Get("mp_forcerespawn"));
        Assert.Equal("mapcycle_gungame.txt", settings.Get("mapcyclefile"));
        Assert.Null(settings.Get("hostname"));
    }

    [Fact]
    public void DropsQuotesThatWouldBreakTheConfig() {
        var settings = new LocalSettings(_path);
        settings.Set("hostname", "Bad \"name\"");
        Assert.Equal("Bad name", settings.Get("hostname"));
    }
}
