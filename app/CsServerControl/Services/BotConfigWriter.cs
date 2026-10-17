using System.IO;

namespace CsServerControl.Services;

/// <summary>
/// Writes the bot cvars into a managed block of modes\base.cfg. Everything
/// outside the two marker lines stays exactly as it was.
/// </summary>
public static class BotConfigWriter {
    public const string StartMarker = "// --- Bots (Server Control) ---";
    public const string EndMarker = "// --- End Bots ---";

    public static void WriteBlock(string configFile, IReadOnlyList<KeyValuePair<string, string>> cvars) {
        List<string> lines = File.Exists(configFile) ? File.ReadAllLines(configFile).ToList() : [];
        IReadOnlyList<string> updated = ReplaceBlock(lines, cvars);
        Directory.CreateDirectory(Path.GetDirectoryName(configFile)!);
        // ASCII on purpose: the engine and the installer read configs byte by byte.
        File.WriteAllLines(configFile, updated, System.Text.Encoding.ASCII);
    }

    internal static IReadOnlyList<string> ReplaceBlock(IReadOnlyList<string> lines, IReadOnlyList<KeyValuePair<string, string>> cvars) {
        List<string> block = [StartMarker, .. cvars.Select(cvar => $"{cvar.Key} \"{cvar.Value}\""), EndMarker];

        int start = IndexOfMarker(lines, StartMarker, 0);
        int end = start >= 0 ? IndexOfMarker(lines, EndMarker, start + 1) : -1;

        if (start < 0 || end < 0) {
            var appended = lines.ToList();
            while (appended.Count > 0 && appended[^1].Trim().Length == 0) {
                appended.RemoveAt(appended.Count - 1);
            }
            if (appended.Count > 0) {
                appended.Add("");
            }
            appended.AddRange(block);
            return appended;
        }

        var replaced = lines.Take(start).ToList();
        replaced.AddRange(block);
        replaced.AddRange(lines.Skip(end + 1));
        return replaced;
    }

    /// <summary>Reads the cvars inside the managed block, empty when there is none.</summary>
    public static IReadOnlyDictionary<string, string> ReadBlock(string configFile) {
        if (!File.Exists(configFile)) {
            return new Dictionary<string, string>();
        }
        return ParseBlock(File.ReadAllLines(configFile));
    }

    internal static IReadOnlyDictionary<string, string> ParseBlock(IReadOnlyList<string> lines) {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        int start = IndexOfMarker(lines, StartMarker, 0);
        if (start < 0) {
            return values;
        }

        for (int index = start + 1; index < lines.Count; index++) {
            string line = lines[index].Trim();
            if (line == EndMarker) {
                break;
            }
            int space = line.IndexOf(' ');
            if (space <= 0 || line.StartsWith("//", StringComparison.Ordinal)) {
                continue;
            }
            values[line[..space]] = line[(space + 1)..].Trim().Trim('"');
        }
        return values;
    }

    private static int IndexOfMarker(IReadOnlyList<string> lines, string marker, int from) {
        for (int index = from; index < lines.Count; index++) {
            if (lines[index].Trim() == marker) {
                return index;
            }
        }
        return -1;
    }
}
