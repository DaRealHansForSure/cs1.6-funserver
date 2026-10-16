using System.IO;

namespace ServerControl.Services;

/// <summary>
/// Every folder and file of the package the window needs. The exe lives in the
/// package root when published and deep inside gui\ while developing, so the
/// root is found by walking up to the folder that holds server-files.
/// </summary>
public sealed class PackagePaths {
    public string Root { get; }
    public string ServerDir => Path.Combine(Root, "server");
    public string CstrikeDir => Path.Combine(ServerDir, "cstrike");
    public string HldsExe => Path.Combine(ServerDir, "hlds.exe");
    public string MapsDir => Path.Combine(CstrikeDir, "maps");
    public string OverviewsDir => Path.Combine(CstrikeDir, "overviews");
    public string LocalConfig => Path.Combine(CstrikeDir, "local.cfg");
    public string BaseModeConfig => Path.Combine(CstrikeDir, "modes", "base.cfg");
    public string MapTypeConfigDir => Path.Combine(CstrikeDir, "modes", "maps");

    public string ModeConfig(string modeId) => Path.Combine(CstrikeDir, "modes", modeId + ".cfg");

    /// <summary>Per-mode settings from the window, run by fun_modes right after the mode config.</summary>
    public string ModeLocalConfig(string modeId) => Path.Combine(CstrikeDir, $"local_{modeId}.cfg");
    public string AmxLogsDir => Path.Combine(CstrikeDir, "addons", "amxmodx", "logs");
    public string GameLogsDir => Path.Combine(CstrikeDir, "logs");
    public string FastDownloadScript => Path.Combine(Root, "tools", "fastdl-server.ps1");
    public string PreviewsDir => Path.Combine(Root, "tools", "previews");
    public string InstallBat => Path.Combine(Root, "1_INSTALL.bat");
    public string UpdateMapsBat => Path.Combine(Root, "3_UPDATE_MAPS.bat");
    public string WindowSettingsFile => Path.Combine(ServerDir, "server-control.json");

    public bool IsServerInstalled => File.Exists(HldsExe);

    private PackagePaths(string root) {
        Root = root;
    }

    public static PackagePaths Find() {
        // The exe folder first, then the working folder, for a shortcut or a
        // copy of the exe that was started from inside the package.
        foreach (string start in new[] { AppContext.BaseDirectory, Environment.CurrentDirectory }) {
            var directory = new DirectoryInfo(start);
            while (directory != null) {
                if (Directory.Exists(Path.Combine(directory.FullName, "server-files"))) {
                    return new PackagePaths(directory.FullName);
                }
                directory = directory.Parent;
            }
        }

        // Started outside the package: fall back to the exe folder, the window
        // then shows "not installed" instead of crashing.
        return new PackagePaths(AppContext.BaseDirectory);
    }
}
