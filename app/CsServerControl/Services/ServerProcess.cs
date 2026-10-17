using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace CsServerControl.Services;

/// <summary>
/// Starts and stops hlds.exe and the fast download server, or attaches to an
/// hlds.exe of this package that 2_START_SERVER.bat started.
/// </summary>
public sealed class ServerProcess {
    public const int GamePort = 27015;
    public const int FastDownloadPort = 27080;
    public const int DefaultMaxPlayers = 20;
    public const int MaxPlayersLimit = 32;
    public const int TvPort = 27020;

    // Below 10 seconds HLTV turns its automatic camera director off, and on
    // a LAN there is nobody to cheat with a longer delay.
    private const int TvDelaySeconds = 10;

    private static readonly TimeSpan QuitTimeout = TimeSpan.FromSeconds(10);

    private static readonly (string Name, string Protocol, int Port)[] FirewallRules = [
        ("CS16 LAN Server (UDP)", "UDP", GamePort),
        ("CS16 LAN Server (TCP)", "TCP", GamePort),
        ("CS16 LAN Fast-Download", "TCP", FastDownloadPort),
        ("CS16 LAN TV (HLTV)", "UDP", TvPort),
    ];

    private readonly PackagePaths _paths;
    private Process? _fastDownload;
    private Process? _tv;

    public ServerProcess(PackagePaths paths) {
        _paths = paths;
    }

    public bool IsRunning => FindHlds() != null;

    /// <summary>When hlds.exe was started, also for a server started by the .bat.</summary>
    public DateTime? StartedAt {
        get {
            try {
                return FindHlds()?.StartTime;
            } catch (Exception exception) when (exception is InvalidOperationException or Win32Exception) {
                return null;
            }
        }
    }

    public static IPAddress FindLanAddress() {
        // The adapter with a default gateway is the one connected to the
        // router, which is the address the other PCs can reach.
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

    public void Start(string modeId, string startMap, int maxPlayers, IPAddress lanAddress, string rconPassword) {
        if (!_paths.IsServerInstalled) {
            throw new InvalidOperationException("The server is not installed yet. Run Install or repair on the Install screen first.");
        }
        if (IsRunning) {
            throw new InvalidOperationException("The server is already running.");
        }

        WriteLocalConfigPassword(rconPassword);

        string arguments = string.Join(' ',
            "-console -condebug -game cstrike",
            $"-port {GamePort}",
            $"+ip {lanAddress}",
            $"+maxplayers {maxPlayers}",
            "+sv_lan 1",
            // The engine echoes every RCON command into its console log; the app has its own.
            "+sv_rcon_condebug 0",
            $"+localinfo fun_mode {modeId}",
            $"+mapcyclefile mapcycle_{modeId}.txt",
            $"+sv_downloadurl \"http://{lanAddress}:{FastDownloadPort}/\"",
            $"+rcon_password {rconPassword}",
            $"+map {startMap}");

        Process? hlds = Process.Start(new ProcessStartInfo {
            FileName = _paths.HldsExe,
            Arguments = arguments,
            WorkingDirectory = _paths.ServerDir,
            WindowStyle = ProcessWindowStyle.Minimized,
            UseShellExecute = true,
        });
        if (hlds != null) {
            StartFastDownload(hlds.Id);
        }
    }

    /// <summary>
    /// The fast download server is this same exe again, without a window. It
    /// ends by itself when hlds.exe ends, so it neither dies with the window
    /// nor outlives the game server.
    /// </summary>
    public void StartFastDownload(int hldsProcessId) {
        string? exe = Environment.ProcessPath;
        if (exe == null || IsFastDownloadRunning()) {
            return;
        }

        _fastDownload = Process.Start(new ProcessStartInfo {
            FileName = exe,
            Arguments = $"--fastdl --root \"{_paths.CstrikeDir}\" --port {FastDownloadPort} --watch-pid {hldsProcessId}",
            UseShellExecute = false,
            CreateNoWindow = true,
        });
    }

    /// <summary>For a server the window attaches to: starts the download server if nobody serves the port.</summary>
    public void EnsureFastDownload() {
        Process? hlds = FindHlds();
        if (hlds != null) {
            StartFastDownload(hlds.Id);
        }
    }

    /// <summary>Another instance may already serve the port, e.g. after the window was reopened.</summary>
    private static bool IsFastDownloadRunning() {
        IPEndPoint[] listeners = System.Net.NetworkInformation.IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners();
        return listeners.Any(listener => listener.Port == FastDownloadPort);
    }

    /// <summary>Waits for hlds.exe to end after "quit", then kills what is left.</summary>
    public async Task WaitForExitOrKillAsync() {
        Process? hlds = FindHlds();
        if (hlds != null) {
            using var timeout = new CancellationTokenSource(QuitTimeout);
            try {
                await hlds.WaitForExitAsync(timeout.Token);
            } catch (OperationCanceledException) {
                TryKill(hlds);
            }
        }
        StopFastDownload();
        StopTv();
    }

    /// <summary>
    /// The HLTV proxy for a TV or projector: it joins the game server as one
    /// spectator slot, and the TV PC connects to it on port 27020.
    /// </summary>
    public void StartTv(IPAddress lanAddress) {
        if (IsTvRunning) {
            return;
        }

        string hltvExe = Path.Combine(_paths.ServerDir, "hltv.exe");
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
            WorkingDirectory = _paths.ServerDir,
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

    public bool IsTvRunning => _tv != null && !_tv.HasExited;

    public void StopFastDownload() {
        if (_fastDownload != null) {
            TryKill(_fastDownload);
            _fastDownload = null;
        }
    }

    /// <summary>
    /// The first map of the mode's cycle that is installed. Null when the mode
    /// has no installed map at all.
    /// </summary>
    public string? FirstMapOfMode(string modeId) {
        return MapCycleReader.Read(_paths.MapCycleFile(modeId))
            .FirstOrDefault(map => File.Exists(_paths.BspFile(map)));
    }

    public static bool AreFirewallRulesMissing() {
        foreach ((string name, _, _) in FirewallRules) {
            try {
                using Process? check = Process.Start(new ProcessStartInfo {
                    FileName = "netsh",
                    Arguments = $"advfirewall firewall show rule name=\"{name}\"",
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                });
                if (check == null) {
                    return false;
                }
                check.StandardOutput.ReadToEnd();
                check.WaitForExit();
                if (check.ExitCode != 0) {
                    return true;
                }
            } catch (Win32Exception) {
                return false;
            }
        }
        return false;
    }

    /// <summary>
    /// Adds the inbound rules through an elevated cmd. The live feed port is
    /// left closed on purpose: it only ever talks to this PC.
    /// </summary>
    public static void AddFirewallRules() {
        IEnumerable<string> commands = FirewallRules.Select(rule =>
            $"netsh advfirewall firewall add rule name=\"{rule.Name}\" dir=in action=allow protocol={rule.Protocol} localport={rule.Port}");
        try {
            Process.Start(new ProcessStartInfo {
                FileName = "cmd.exe",
                Arguments = "/c " + string.Join(" & ", commands),
                Verb = "runas",
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden,
            });
        } catch (Win32Exception) {
            // The user said no to the UAC prompt; Windows will ask on its own later.
        }
    }

    /// <summary>
    /// fun_modes runs local.cfg after the mode configs on every map start, so
    /// its rcon_password would win over the command line. Keeping both the
    /// same also lets a server started by 2_START_SERVER.bat accept this app.
    /// </summary>
    public void WriteLocalConfigPassword(string rconPassword) {
        var settings = new LocalSettings(_paths.LocalConfigFile);
        settings.Set("rcon_password", rconPassword);
        settings.Save();
    }

    /// <summary>The password in local.cfg, used by a server that 2_START_SERVER.bat started.</summary>
    public string? ReadLocalConfigPassword() {
        return new LocalSettings(_paths.LocalConfigFile).Get("rcon_password");
    }

    private Process? FindHlds() {
        foreach (Process process in Process.GetProcessesByName("hlds")) {
            try {
                string? path = process.MainModule?.FileName;
                if (path != null && string.Equals(Path.GetFullPath(path), Path.GetFullPath(_paths.HldsExe), StringComparison.OrdinalIgnoreCase)) {
                    return process;
                }
            } catch (Exception exception) when (exception is Win32Exception or InvalidOperationException) {
                // A process that ended or belongs to another user is not ours.
            }
        }
        return null;
    }

    private static void TryKill(Process process) {
        try {
            if (!process.HasExited) {
                process.Kill(entireProcessTree: true);
            }
        } catch (Exception exception) when (exception is Win32Exception or InvalidOperationException) {
            // Already gone.
        }
    }
}
