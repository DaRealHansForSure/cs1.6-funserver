using System.IO;
using CsServerControl.Services;
using Xunit;

namespace CsServerControl.Tests;

public class BotConfigWriterTests {
    private static readonly IReadOnlyList<KeyValuePair<string, string>> Cvars = [
        new("bot_difficulty", "3"),
        new("bot_quota", "10"),
        new("bot_join_team", "CT"),
    ];

    [Fact]
    public void AppendsBlockWhenThereIsNone() {
        string[] lines = ["mp_timelimit 25", "sv_gravity 800", ""];

        IReadOnlyList<string> result = BotConfigWriter.ReplaceBlock(lines, Cvars);

        Assert.Equal([
            "mp_timelimit 25",
            "sv_gravity 800",
            "",
            BotConfigWriter.StartMarker,
            "bot_difficulty \"3\"",
            "bot_quota \"10\"",
            "bot_join_team \"CT\"",
            BotConfigWriter.EndMarker,
        ], result);
    }

    [Fact]
    public void ReplacesExistingBlockAndKeepsOtherLines() {
        string[] lines = [
            "// Runs before every mode",
            "mp_timelimit 25",
            BotConfigWriter.StartMarker,
            "bot_difficulty \"1\"",
            "bot_quota \"8\"",
            "bot_allow_shield \"1\"",
            BotConfigWriter.EndMarker,
            "fun_hook_enabled 1",
        ];

        IReadOnlyList<string> result = BotConfigWriter.ReplaceBlock(lines, Cvars);

        Assert.Equal([
            "// Runs before every mode",
            "mp_timelimit 25",
            BotConfigWriter.StartMarker,
            "bot_difficulty \"3\"",
            "bot_quota \"10\"",
            "bot_join_team \"CT\"",
            BotConfigWriter.EndMarker,
            "fun_hook_enabled 1",
        ], result);
    }

    [Fact]
    public void StartMarkerWithoutEndAppendsANewBlock() {
        string[] lines = ["mp_timelimit 25", BotConfigWriter.StartMarker, "bot_quota \"8\""];

        IReadOnlyList<string> result = BotConfigWriter.ReplaceBlock(lines, Cvars);

        Assert.Equal("mp_timelimit 25", result[0]);
        Assert.Equal(BotConfigWriter.EndMarker, result[^1]);
        Assert.Contains("bot_quota \"10\"", result);
    }

    [Fact]
    public void ReadsBlockBack() {
        IReadOnlyList<string> written = BotConfigWriter.ReplaceBlock(["mp_timelimit 25"], Cvars);

        IReadOnlyDictionary<string, string> values = BotConfigWriter.ParseBlock(written);

        Assert.Equal(3, values.Count);
        Assert.Equal("CT", values["bot_join_team"]);
        Assert.Equal("10", values["bot_quota"]);
    }

    [Fact]
    public void WritesAsciiFileThatTheInstallerCanRead() {
        string file = Path.Combine(Path.GetTempPath(), $"base_{Guid.NewGuid():N}.cfg");
        try {
            File.WriteAllLines(file, ["mp_timelimit 25"]);

            BotConfigWriter.WriteBlock(file, Cvars);

            byte[] bytes = File.ReadAllBytes(file);
            Assert.All(bytes, value => Assert.True(value < 128));
            Assert.Equal("10", BotConfigWriter.ReadBlock(file)["bot_quota"]);
        } finally {
            File.Delete(file);
        }
    }
}
