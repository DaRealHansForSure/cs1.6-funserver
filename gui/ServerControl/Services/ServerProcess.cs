using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace ServerControl.Services;

/// <summary>
/// Starts and stops hlds.exe and the fast download server with the same
/// arguments as start-server.ps1, or attaches to a server that
/// 2_START_SERVER.bat started.
/// </summary>
public sealed class ServerProcess(PackagePaths paths) {
    public const int GamePort = 27015;
    public const int FastDownloadPort = 27080;
    public const int TvPort = 27020;

    // Below 10 seconds HLTV turns its automatic camera director off, and on
    // a LAN there is nobody to cheat with a longer delay.
    private const int TvDelaySeconds = 10;

    private Process? _hlds;
    private Process? _fastDownload;
    private Process? _tv;

    public bool IsRunning => FindHlds() != null;
    public bool IsTvRunning => _tv != null && !_tv.HasExited;

    public static IPAddress FindLanAddress() {
        // The adapter with a default gateway is the one connected to the router,
        // which is the address other players can reach (same as Get-LanAddress).
        foreach (NetworkInterface adapter in NetworkInterface.GetAllNetworkInterfaces()) {
            if (adapter.OperationalStatus != OperationalStatus.Up) {
                continue;
            }

            IPInterfaceProperties properties = adapter.GetIPProperties();
            bool hasGateway = properties.GatewayAddresses.Any(gateway =>
                gateway.Address.AddressFamily == AddressFamily.InterNetwork && !gateway.Address.Equals(IPAddress.Any));
            if (!hasGateway) {
                continue;
            }

            UnicastIPAddressInformation? address = properties.UnicastAddresses
                .FirstOrDefault(unicast => unicast.Address.AddressFamily == AddressFamily.InterNetwork);
            if (address != null) {
                return address.Address;
            }
        }

        IPAddress? anyAddress = Dns.GetHostAddresses(Dns.GetHostName())
            .FirstOrDefault(address => address.AddressFamily == AddressFamily.InterNetwork
                && !IPAddress.IsLoopback(address)
                && !address.ToString().StartsWith("169.254.", StringComparison.Ordinal));
        return anyAddress ?? IPAddress.Loopback;
    }

    public void Start(string modeId, string startMap, int maxPlayers, IPAddress lanAddress) {
        if (!paths.IsServerInstalled) {
            throw new InvalidOperationException("The server is not installed yet. Run 1_INSTALL.bat first.");
        }
        if (IsRunning) {
            throw new InvalidOperationException("The server is already running.");
        }

        _fastDownload = Process.Start(new ProcessStartInfo {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{paths.FastDownloadScript}\" -Root \"{paths.CstrikeDir}\" -Port {FastDownloadPort}",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Minimized,
        });

        // localinfo tells fun_modes.amxx which mode to run on the very first map.
        string arguments = string.Join(' ',
            "-console", "-game cstrike",
            $"-port {GamePort}",
            $"+ip {lanAddress}",
            $"+maxplayers {maxPlayers}",
            "+sv_lan 1",
            $"+localinfo fun_mode {modeId}",
            $"+mapcyclefile mapcycle_{modeId}.txt",
            $"+sv_downloadurl \"http://{lanAddress}:{FastDownloadPort}/\"",
            $"+map {startMap}");

        _hlds = Process.Start(new ProcessStartInfo {
            FileName = paths.HldsExe,
            Arguments = arguments,
            WorkingDirectory = paths.ServerDir,
            UseShellExecute = true,
        });
        if (_hlds != null) {
            _hlds.EnableRaisingEvents = true;
            _hlds.Exited += (_, _) => StopFastDownload();
        }
    }

    /// <summary>
    /// Starts an HLTV proxy for a big screen: it joins the game server as a
    /// spectator slot, and TV PCs connect to it on port 27020.
    /// </summary>
    public void StartTv(IPAddress lanAddress) {
        if (IsTvRunning) {
            return;
        }

        string hltvExe = Path.Combine(paths.ServerDir, "hltv.exe");
        if (!File.Exists(hltvExe)) {
            throw new InvalidOperationException("hltv.exe is missing. Run 1_INSTALL.bat to repair the server.");
        }

        _tv = Process.Start(new ProcessStartInfo {
            FileName = hltvExe,
            Arguments = string.Join(' ',
                $"-port {TvPort}",
                $"+connect {lanAddress}:{GamePort}",
                $"+delay {TvDelaySeconds}",
                "+maxrate 10000",
                "+name LAN-TV"),
            WorkingDirectory = paths.ServerDir,
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Minimized,
        });
    }

    public void StopTv() {
        if (_tv != null) {
            TryKill(_tv);
            _tv = null;
        }
    }

    /// <summary>
    /// Waits for the server to end after RCON "quit" and kills it when it does
    /// not, then also ends the fast download server and TV this window started.
    /// </summary>
    public async Task StopAsync(TimeSpan gracePeriod) {
        Process? hlds = FindHlds();
        if (hlds != null) {
            using var timeout = new CancellationTokenSource(gracePeriod);
            try {
                await hlds.WaitForExitAsync(timeout.Token);
            } catch (OperationCanceledException) {
                TryKill(hlds);
            }
        }
        StopFastDownload();
        StopTv();
    }

    private Process? FindHlds() {
        if (_hlds != null && !_hlds.HasExited) {
            return _hlds;
        }

        // Also find a server started by 2_START_SERVER.bat, but only this
        // package's hlds.exe, never another server on the same PC.
        foreach (Process candidate in Process.GetProcessesByName("hlds")) {
            try {
                string? exePath = candidate.MainModule?.FileName;
                if (exePath != null && Path.GetFullPath(exePath).Equals(Path.GetFullPath(paths.HldsExe), StringComparison.OrdinalIgnoreCase)) {
                    return candidate;
                }
            } catch (Win32Exception) {
                // Processes of other users can not be inspected, they are not ours.
            } catch (InvalidOperationException) {
                // Ended while we looked at it.
            }
        }
        return null;
    }

    private void StopFastDownload() {
        if (_fastDownload != null) {
            TryKill(_fastDownload);
            _fastDownload = null;
        }
    }

    private static void TryKill(Process process) {
        try {
            if (!process.HasExited) {
                process.Kill(entireProcessTree: true);
            }
        } catch (InvalidOperationException) {
            // Already gone.
        } catch (Win32Exception) {
            // No permission, nothing more this window can do.
        }
    }
}
