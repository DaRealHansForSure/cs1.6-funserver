using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;

namespace ServerControl.Services;

public sealed record AmxLogState(string? ActiveMode, DateTime? MapStartedAt);

/// <summary>
/// Reads what the AMX Mod X log knows about the running map: fun_modes.amxx
/// logs "Active mode: x" on every map start, and AMXX itself logs every map
/// change with its time. The newest lines are the truth, also after a vote.
/// </summary>
public sealed partial class ModeLog(string amxLogsDir) {
    public string? ReadActiveMode() {
        return ReadState().ActiveMode;
    }

    public AmxLogState ReadState() {
        if (!Directory.Exists(amxLogsDir)) {
            return new AmxLogState(null, null);
        }

        FileInfo? newestLog = new DirectoryInfo(amxLogsDir)
            .GetFiles("L*.log")
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .FirstOrDefault();
        if (newestLog == null) {
            return new AmxLogState(null, null);
        }

        try {
            // HLDS keeps the log open, so it has to be shared for reading.
            using var stream = new FileStream(newestLog.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            return Parse(reader);
        } catch (IOException) {
            return new AmxLogState(null, null);
        }
    }

    internal static AmxLogState Parse(TextReader reader) {
        string? activeMode = null;
        DateTime? mapStartedAt = null;

        string? line;
        while ((line = reader.ReadLine()) != null) {
            Match modeMatch = ActiveModeLine().Match(line);
            if (modeMatch.Success) {
                activeMode = modeMatch.Groups["mode"].Value;
                continue;
            }

            Match mapMatch = MapChangeLine().Match(line);
            if (mapMatch.Success && TryParseLogTime(mapMatch.Groups["time"].Value, out DateTime time)) {
                mapStartedAt = time;
            }
        }
        return new AmxLogState(activeMode, mapStartedAt);
    }

    // AMXX writes local time as "10/17/2026 - 00:27:57".
    private static bool TryParseLogTime(string text, out DateTime time) {
        return DateTime.TryParseExact(text, "MM/dd/yyyy - HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out time);
    }

    [GeneratedRegex(@"\[fun_modes\.amxx\] Active mode: (?<mode>\w+)")]
    private static partial Regex ActiveModeLine();

    [GeneratedRegex(@"^L (?<time>\d{2}/\d{2}/\d{4} - \d{2}:\d{2}:\d{2}): -------- Mapchange to ")]
    private static partial Regex MapChangeLine();
}
