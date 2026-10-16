using System.IO;
using System.Text.RegularExpressions;

namespace ServerControl.Services;

/// <summary>
/// Finds the running mode. fun_modes.amxx logs "Active mode: x" on every map
/// start, and the newest such line is the truth, also after a /mode vote.
/// </summary>
public sealed partial class ModeLog(string amxLogsDir) {
    public string? ReadActiveMode() {
        if (!Directory.Exists(amxLogsDir)) {
            return null;
        }

        FileInfo? newestLog = new DirectoryInfo(amxLogsDir)
            .GetFiles("L*.log")
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .FirstOrDefault();
        if (newestLog == null) {
            return null;
        }

        try {
            // HLDS keeps the log open, so it has to be shared for reading.
            using var stream = new FileStream(newestLog.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            string? activeMode = null;
            string? line;
            while ((line = reader.ReadLine()) != null) {
                Match match = ActiveModeLine().Match(line);
                if (match.Success) {
                    activeMode = match.Groups["mode"].Value;
                }
            }
            return activeMode;
        } catch (IOException) {
            return null;
        }
    }

    [GeneratedRegex(@"\[fun_modes\.amxx\] Active mode: (?<mode>\w+)")]
    private static partial Regex ActiveModeLine();
}
