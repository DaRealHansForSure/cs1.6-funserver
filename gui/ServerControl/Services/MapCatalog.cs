using System.IO;

namespace ServerControl.Services;

public sealed record MapEntry(string Name, IReadOnlyList<string> Modes, string? PreviewPath);

/// <summary>
/// Lists the installed maps with the modes they belong to and a preview
/// image. Modes come from the mapcycle_*.txt files the installer writes, so
/// the window never repeats the Get-MapModes rules of install.ps1.
/// </summary>
public sealed class MapCatalog(PackagePaths paths) {
    // WPF reads these without extra codecs; the radar .tga files are skipped.
    private static readonly string[] PreviewExtensions = [".jpg", ".jpeg", ".png", ".bmp"];

    // Knife, grenade, deathrun and surf maps are a fun break, not a first map.
    // Same list as Get-StartMapOfMode in start-server.ps1.
    private static readonly string[] SpecialPrefixes = ["35hp", "he_", "ka_", "deathrun_", "surf_"];

    public IReadOnlyList<MapEntry> Load() {
        var modesByMap = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (GameMode mode in GameModes.All) {
            foreach (string mapName in ReadCycle(mode.Id)) {
                if (!modesByMap.TryGetValue(mapName, out List<string>? modes)) {
                    modes = [];
                    modesByMap[mapName] = modes;
                }
                modes.Add(mode.Id);
            }
        }

        var maps = new List<MapEntry>();
        if (!Directory.Exists(paths.MapsDir)) {
            return maps;
        }

        foreach (string bspFile in Directory.EnumerateFiles(paths.MapsDir, "*.bsp")) {
            string mapName = Path.GetFileNameWithoutExtension(bspFile).ToLowerInvariant();
            IReadOnlyList<string> modes = modesByMap.TryGetValue(mapName, out List<string>? found) ? found : [];
            maps.Add(new MapEntry(mapName, modes, FindPreview(mapName)));
        }
        return maps.OrderBy(map => map.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// <summary>
    /// A random installed map of the mode, preferring regular maps, the same
    /// choice start-server.ps1 makes. Null when the mode has no map at all.
    /// </summary>
    public string? PickStartMap(string modeId) {
        var installed = ReadCycle(modeId)
            .Where(map => File.Exists(Path.Combine(paths.MapsDir, map + ".bsp")))
            .ToList();
        if (installed.Count == 0) {
            return null;
        }

        var regular = installed.Where(map => !IsSpecialMap(map)).ToList();
        List<string> candidates = regular.Count > 0 ? regular : installed;
        return candidates[Random.Shared.Next(candidates.Count)];
    }

    public static bool IsSpecialMap(string mapName) {
        return SpecialPrefixes.Any(prefix => mapName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
    }

    private IEnumerable<string> ReadCycle(string modeId) {
        string cycleFile = Path.Combine(paths.CstrikeDir, $"mapcycle_{modeId}.txt");
        if (!File.Exists(cycleFile)) {
            yield break;
        }

        foreach (string line in File.ReadLines(cycleFile)) {
            string mapName = line.Trim();
            bool isCommentOrEmpty = mapName.Length == 0 || mapName.StartsWith("//", StringComparison.Ordinal) || mapName.StartsWith(';');
            if (!isCommentOrEmpty) {
                yield return mapName.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0];
            }
        }
    }

    private string? FindPreview(string mapName) {
        foreach (string folder in new[] { paths.PreviewsDir, paths.OverviewsDir }) {
            foreach (string extension in PreviewExtensions) {
                string candidate = Path.Combine(folder, mapName + extension);
                if (File.Exists(candidate)) {
                    return candidate;
                }
            }
        }
        return null;
    }
}
