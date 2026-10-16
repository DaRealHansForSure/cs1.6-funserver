using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace ServerControl.Services;

public sealed class RconException(string message) : Exception(message);

/// <summary>
/// Sends console commands to HLDS with the GoldSrc RCON protocol over UDP:
/// first "challenge rcon" for a number, then "rcon number password command".
/// The server may split a long answer into several packets, so the reply is
/// collected until the server stays quiet for a moment.
/// </summary>
public sealed partial class RconClient {
    private static readonly TimeSpan FirstPacketTimeout = TimeSpan.FromMilliseconds(1200);
    private static readonly TimeSpan NextPacketTimeout = TimeSpan.FromMilliseconds(150);

    private readonly SemaphoreSlim _oneAtATime = new(1, 1);
    private string? _challenge;

    public IPEndPoint? Server { get; set; }
    public string Password { get; set; } = "";

    public async Task<string> SendAsync(string command, CancellationToken cancellation = default) {
        if (Server == null) {
            throw new RconException("The server address is unknown.");
        }
        if (string.IsNullOrEmpty(Password)) {
            throw new RconException("No RCON password in local.cfg. Start the server once from this window.");
        }

        await _oneAtATime.WaitAsync(cancellation);
        try {
            using var client = new UdpClient(Server.AddressFamily);
            _challenge ??= await RequestChallengeAsync(client, cancellation);

            string answer = await ExecuteAsync(client, command, cancellation);
            if (answer.Contains("Bad challenge", StringComparison.OrdinalIgnoreCase)) {
                // The challenge changes when the server restarts, ask once more.
                _challenge = await RequestChallengeAsync(client, cancellation);
                answer = await ExecuteAsync(client, command, cancellation);
            }
            if (answer.Contains("Bad rcon_password", StringComparison.OrdinalIgnoreCase)) {
                throw new RconException("The server refused the RCON password. Restart the server from this window so it reads local.cfg.");
            }
            return answer.TrimEnd();
        } catch (SocketException exception) {
            throw new RconException($"The server does not answer ({exception.SocketErrorCode}).");
        } finally {
            _oneAtATime.Release();
        }
    }

    /// <summary>Forgets the challenge, for example after the server restarted.</summary>
    public void Reset() {
        _challenge = null;
    }

    private async Task<string> RequestChallengeAsync(UdpClient client, CancellationToken cancellation) {
        await SendPacketAsync(client, "challenge rcon\n", cancellation);
        string reply = await ReceiveAllAsync(client, cancellation);

        Match match = ChallengePattern().Match(reply);
        if (!match.Success) {
            throw new RconException("The server does not answer RCON requests. Is it running?");
        }
        return match.Groups["number"].Value;
    }

    private async Task<string> ExecuteAsync(UdpClient client, string command, CancellationToken cancellation) {
        // A quote would end the password, the engine has no escaping for it.
        string password = Password.Replace("\"", "");
        await SendPacketAsync(client, $"rcon {_challenge} \"{password}\" {command}\n", cancellation);
        return await ReceiveAllAsync(client, cancellation);
    }

    private async Task SendPacketAsync(UdpClient client, string text, CancellationToken cancellation) {
        byte[] payload = Encoding.ASCII.GetBytes(text);
        byte[] packet = [0xFF, 0xFF, 0xFF, 0xFF, .. payload];
        await client.SendAsync(packet, Server!, cancellation);
    }

    private static async Task<string> ReceiveAllAsync(UdpClient client, CancellationToken cancellation) {
        var answer = new StringBuilder();
        TimeSpan waitFor = FirstPacketTimeout;

        while (true) {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(waitFor);
            try {
                UdpReceiveResult result = await client.ReceiveAsync(timeout.Token);
                answer.Append(RconPacket.ReadText(result.Buffer));
                waitFor = NextPacketTimeout;
            } catch (OperationCanceledException) when (!cancellation.IsCancellationRequested) {
                return answer.ToString();
            }
        }
    }

    [GeneratedRegex(@"challenge rcon (?<number>\d+)")]
    private static partial Regex ChallengePattern();
}

internal static class RconPacket {
    /// <summary>
    /// Strips the four 0xFF header bytes and the 'l' print marker the engine
    /// puts in front of console output.
    /// </summary>
    public static string ReadText(byte[] packet) {
        int start = 0;
        while (start < packet.Length && start < 4 && packet[start] == 0xFF) {
            start++;
        }
        if (start < packet.Length && packet[start] == (byte)'l') {
            start++;
        }

        int end = packet.Length;
        while (end > start && packet[end - 1] == 0) {
            end--;
        }
        return Encoding.UTF8.GetString(packet, start, end - start);
    }
}
