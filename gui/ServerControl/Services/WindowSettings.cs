using System.IO;
using System.Text.Json;

namespace ServerControl.Services;

/// <summary>
/// Settings that only exist at server start (they are command line options
/// of hlds.exe, not cvars a config could change) plus what the window should
/// remember. Stored as server\server-control.json.
/// </summary>
public sealed class WindowSettings {
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public int MaxPlayers { get; set; } = 20;
    public string LastMode { get; set; } = GameModes.All[0].Id;

    public static WindowSettings Load(string path) {
        try {
            if (File.Exists(path)) {
                return JsonSerializer.Deserialize<WindowSettings>(File.ReadAllText(path)) ?? new WindowSettings();
            }
        } catch (JsonException) {
            // A broken file must not keep the window from starting.
        }
        return new WindowSettings();
    }

    public void Save(string path) {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, JsonOptions));
    }
}
