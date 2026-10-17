using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.RegularExpressions;

namespace CsServerControl.Services;

/// <summary>
/// Starts and stops hlds.exe and the fast download server, or attaches to an
/// hlds.exe of this package that 2_START_SERVER.bat started.
/// </summary>
public sealed partial class ServerProcess {
    public const int GamePort = 27015;
    public const int FastDownloadPort = 27080;
    public const int MaxPlayers = 20;

    private static readonly TimeSpan QuitTimeout = TimeSpan.FromSeconds(10);

    private static readonly (string Name, string Protocol, int Port)[] FirewallRules = [
        ("CS16 LAN Server (UDP)", "UDP", GamePort),
        ("CS16 LAN Server (TCP)", "TCP", GamePort),
        ("CS16 LAN Fast-Download", "TCP", FastDownloadPort),
    ];

    private readonly PackagePaths _paths;
    private Process? _fastDownload;

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

    public void Start(string modeId, string startMap, IPAddress lanAddress, string rconPassword) {
        if (!_paths.IsServerInstalled) {
            throw new InvalidOperationException("The server is not installed yet. Run 1_INSTALL.bat first.");
        }
        if (IsRunning) {
            throw new InvalidOperationException("The server is already running.");
        }

        WriteLocalConfigPassword(rconPassword);

        _fastDownload = Process.Start(new ProcessStartInfo {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{_paths.FastDownloadScript}\" -Root \"{_paths.CstrikeDir}\" -Port {FastDownloadPort}",
            WindowStyle = ProcessWindowStyle.Minimized,
            UseShellExecute = true,
        });

        string arguments = string.Join(' ',
            "-console -condebug -game cstrike",
            $"-port {GamePort}",
            $"+ip {lanAddress}",
            $"+maxplayers {MaxPlayers}",
            "+sv_lan 1",
            // The app polls status every 2 s; without this each poll lands in the console log.
            "+sv_rcon_condebug 0",
            $"+localinfo fun_mode {modeId}",
            $"+mapcyclefile mapcycle_{modeId}.txt",
            $"+sv_downloadurl \"http://{lanAddress}:{FastDownloadPort}/\"",
            $"+rcon_password {rconPassword}",
            $"+map {startMap}");

        Process.Start(new ProcessStartInfo {
            FileName = _paths.HldsExe,
            Arguments = arguments,
            WorkingDirectory = _paths.ServerDir,
            WindowStyle = ProcessWindowStyle.Minimized,
            UseShellExecute = true,
        });
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
    }

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
        string passwordLine = $"rcon_password \"{rconPassword}\"";
        List<string> lines = File.Exists(_paths.LocalConfigFile)
            ? File.ReadAllLines(_paths.LocalConfigFile).ToList()
            : ["// Created by CS 1.6 Server Control. Local settings of this PC, never overwritten by the installer."];

        int index = lines.FindIndex(line => RconPasswordLine().IsMatch(line));
        if (index >= 0) {
            lines[index] = passwordLine;
        } else {
            lines.Add(passwordLine);
        }
        File.WriteAllLines(_paths.LocalConfigFile, lines);
    }

    /// <summary>The password in local.cfg, used by a server that 2_START_SERVER.bat started.</summary>
    public string? ReadLocalConfigPassword() {
        if (!File.Exists(_paths.LocalConfigFile)) {
            return null;
        }
        foreach (string line in File.ReadLines(_paths.LocalConfigFile)) {
            Match match = RconPasswordValue().Match(line);
            if (match.Success) {
                return match.Groups["password"].Value;
            }
        }
        return null;
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

    [GeneratedRegex(@"^\s*rcon_password\s")]
    private static partial Regex RconPasswordLine();

    [GeneratedRegex("^\\s*rcon_password\\s+\"(?<password>[^\"]*)\"")]
    private static partial Regex RconPasswordValue();
}
