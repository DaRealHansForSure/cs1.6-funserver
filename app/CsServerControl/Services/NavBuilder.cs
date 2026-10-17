using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace CsServerControl.Services;

/// <summary>
/// Builds zBot navigation files for maps the game server is not running.
/// zBot can only analyze a loaded map, so a second, hidden hlds.exe on
/// 127.0.0.1:27016 loads the map with one bot (navbuild.cfg) and without
/// Metamod plugins (no live feed, no mode configs), waits until zBot wrote
/// maps\&lt;map&gt;.nav and is stopped again. The game in progress is not touched.
/// </summary>
public sealed class NavBuilder {
    public const int HelperPort = 27016;

    private static readonly TimeSpan BuildTimeout = TimeSpan.FromMinutes(6);
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan StableFor = TimeSpan.FromSeconds(2);

    private const int HideWindow = 0;

    private readonly PackagePaths _paths;
    private readonly SemaphoreSlim _oneAtATime = new(1, 1);

    public NavBuilder(PackagePaths paths) {
        _paths = paths;
    }

    public bool IsAvailable => File.Exists(HelperConfigFile) && File.Exists(HelperPluginsFile) && _paths.IsServerInstalled;

    private string HelperConfigFile => Path.Combine(_paths.CstrikeDir, "navbuild.cfg");
    private string HelperPluginsFile => Path.Combine(_paths.CstrikeDir, "addons", "metamod", "plugins_navbuild.ini");

    /// <summary>
    /// Builds the .nav of one map; "replace" deletes an existing one first,
    /// because zBot only analyzes maps without a mesh. True when a new file exists.
    /// </summary>
    public async Task<bool> BuildAsync(string mapName, bool replace, CancellationToken cancellation = default) {
        await _oneAtATime.WaitAsync(cancellation);
        Process? helper = null;
        try {
            string navFile = _paths.NavFile(mapName);
            if (replace && File.Exists(navFile)) {
                File.Delete(navFile);
            }
            DateTime startedAt = DateTime.UtcNow;

            helper = Process.Start(new ProcessStartInfo {
                FileName = _paths.HldsExe,
                WorkingDirectory = _paths.ServerDir,
                Arguments = string.Join(' ',
                    "-console -game cstrike",
                    $"-port {HelperPort} +ip 127.0.0.1 +maxplayers 2 +sv_lan 1",
                    "+servercfgfile navbuild.cfg",
                    "+localinfo mm_pluginsfile addons/metamod/plugins_navbuild.ini",
                    $"+map {mapName}"),
                WindowStyle = ProcessWindowStyle.Minimized,
                UseShellExecute = true,
            });
            if (helper == null) {
                return false;
            }
            _ = HideConsoleWindowAsync(helper);

            return await WaitForNavFileAsync(navFile, startedAt, helper, cancellation);
        } catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or Win32Exception) {
            return false;
        } finally {
            if (helper != null) {
                TryKill(helper);
            }
            _oneAtATime.Release();
        }
    }

    private static async Task<bool> WaitForNavFileAsync(string navFile, DateTime startedAt, Process helper, CancellationToken cancellation) {
        var deadline = DateTime.UtcNow + BuildTimeout;
        long lastSize = -1;
        DateTime sizeSince = DateTime.UtcNow;

        while (DateTime.UtcNow < deadline) {
            await Task.Delay(PollInterval, cancellation);
            if (helper.HasExited) {
                return File.Exists(navFile) && File.GetLastWriteTimeUtc(navFile) >= startedAt;
            }
            if (!File.Exists(navFile) || File.GetLastWriteTimeUtc(navFile) < startedAt) {
                continue;
            }

            // zBot writes the file in one go; a size that holds still means it is done.
            long size = new FileInfo(navFile).Length;
            if (size != lastSize) {
                lastSize = size;
                sizeSince = DateTime.UtcNow;
                continue;
            }
            if (DateTime.UtcNow - sizeSince >= StableFor) {
                return true;
            }
        }
        return false;
    }

    /// <summary>hlds.exe -console opens its own console window; nobody needs to see the helper's.</summary>
    private static async Task HideConsoleWindowAsync(Process helper) {
        for (int attempt = 0; attempt < 40 && !helper.HasExited; attempt++) {
            await Task.Delay(100);
            helper.Refresh();
            if (helper.MainWindowHandle != IntPtr.Zero) {
                ShowWindow(helper.MainWindowHandle, HideWindow);
                return;
            }
        }
    }

    private static void TryKill(Process process) {
        try {
            if (!process.HasExited) {
                process.Kill(entireProcessTree: true);
            }
        } catch (Exception exception) when (exception is Win32Exception or InvalidOperationException) {
            // Already gone.
        }
        process.Dispose();
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);
}
