using System.IO;
using System.Text.RegularExpressions;

namespace CsServerControl.Services;

public sealed record NavFileState(string MapName, bool Exists);

/// <summary>
/// Which maps have a zBot navigation mesh (maps\&lt;map&gt;.nav), and what the
/// server console says while zBot builds one. zBot prints its steps there
/// ("  Merging navigation areas...") but never a percentage; that only goes
/// to the HUD of connected players.
/// </summary>
public static partial class NavFileScanner {
    public static IReadOnlyList<NavFileState> Scan(PackagePaths paths) {
        return MapCycleReader.ReadAllCycles(paths.CstrikeDir)
            .Select(map => new NavFileState(map, File.Exists(paths.NavFile(map))))
            .ToList();
    }

    /// <summary>The step zBot is on, for example "Merging navigation areas", or null.</summary>
    public static string? ReadStep(string consoleLine) {
        Match match = StepPattern().Match(consoleLine);
        if (!match.Success) {
            return null;
        }
        return match.Groups["step"].Value;
    }

    /// <summary>True for "Navigation file 'cstrike\maps\x.nav' saved.".</summary>
    public static bool IsDoneLine(string consoleLine) {
        return DonePattern().IsMatch(consoleLine);
    }

    [GeneratedRegex(@"^\s{2}(?<step>[A-Z][a-z]+ [A-Za-z ]+)\.\.\.\s*$")]
    private static partial Regex StepPattern();

    [GeneratedRegex(@"^Navigation file '.*\.nav' saved\.")]
    private static partial Regex DonePattern();
}
