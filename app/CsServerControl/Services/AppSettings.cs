using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

namespace CsServerControl.Services;

/// <summary>
/// Per user settings in %APPDATA%\CsServerControl\settings.json. A missing
/// or broken file gives the defaults, it never stops the app from starting.
/// </summary>
public sealed class AppSettings {
    private const string PasswordAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public string RconPassword { get; set; } = "";
    public double? WindowLeft { get; set; }
    public double? WindowTop { get; set; }
    public double WindowWidth { get; set; } = 1440;
    public double WindowHeight { get; set; } = 900;
    public bool WindowMaximized { get; set; }
    public string LastScreen { get; set; } = "LiveMap";
    public bool ShowNames { get; set; } = true;
    public bool ShowTrails { get; set; } = true;
    public bool ShowNavMesh { get; set; }
    public bool FirewallAsked { get; set; }

    public static string SettingsFile => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CsServerControl", "settings.json");

    public static AppSettings Load() {
        AppSettings settings = ReadFile() ?? new AppSettings();
        if (string.IsNullOrEmpty(settings.RconPassword)) {
            settings.RconPassword = CreatePassword();
            settings.Save();
        }
        return settings;
    }

    public void Save() {
        try {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsFile)!);
            File.WriteAllText(SettingsFile, JsonSerializer.Serialize(this, JsonOptions));
        } catch (Exception exception) when (exception is IOException or UnauthorizedAccessException) {
            // Losing the window position is not worth an error dialog.
        }
    }

    internal static string CreatePassword() {
        return RandomNumberGenerator.GetString(PasswordAlphabet, 24);
    }

    private static AppSettings? ReadFile() {
        try {
            if (!File.Exists(SettingsFile)) {
                return null;
            }
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsFile));
        } catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException) {
            return null;
        }
    }
}
