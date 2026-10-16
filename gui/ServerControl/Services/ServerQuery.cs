using System.Net;
using System.Net.Sockets;
using System.Text;

namespace ServerControl.Services;

public sealed record ServerInfo(string Name, string Map, int Players, int MaxPlayers, int Bots);

/// <summary>
/// Asks the server for its name, map and player count with the public server
/// query (A2S_INFO), the same packet the LAN browser of the game sends. Needs
/// no password, so the status bar works even before RCON is set up.
/// </summary>
public sealed class ServerQuery {
    private static readonly byte[] InfoRequest = BuildInfoRequest();
    private static readonly TimeSpan Timeout = TimeSpan.FromMilliseconds(800);

    public async Task<ServerInfo?> QueryAsync(IPEndPoint server, CancellationToken cancellation) {
        using var client = new UdpClient(server.AddressFamily);
        try {
            byte[]? reply = await ExchangeAsync(client, server, InfoRequest, cancellation);
            if (reply == null) {
                return null;
            }

            // Newer engines answer the first request with a challenge that has
            // to be sent back, older ones answer right away.
            if (QueryParser.TryReadChallenge(reply, out byte[] challenge)) {
                reply = await ExchangeAsync(client, server, [.. InfoRequest, .. challenge], cancellation);
                if (reply == null) {
                    return null;
                }
            }
            return QueryParser.ParseInfo(reply);
        } catch (SocketException) {
            return null;
        }
    }

    private static async Task<byte[]?> ExchangeAsync(UdpClient client, IPEndPoint server, byte[] request, CancellationToken cancellation) {
        await client.SendAsync(request, server, cancellation);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(Timeout);
        try {
            UdpReceiveResult result = await client.ReceiveAsync(timeout.Token);
            return result.Buffer;
        } catch (OperationCanceledException) when (!cancellation.IsCancellationRequested) {
            return null;
        }
    }

    private static byte[] BuildInfoRequest() {
        byte[] text = Encoding.ASCII.GetBytes("TSource Engine Query\0");
        return [0xFF, 0xFF, 0xFF, 0xFF, .. text];
    }
}

/// <summary>
/// Reads A2S_INFO answers. Kept separate from the network code so the tests
/// can feed it captured packets.
/// </summary>
internal static class QueryParser {
    private const byte ChallengeHeader = (byte)'A';
    private const byte SourceInfoHeader = (byte)'I';
    private const byte GoldSrcInfoHeader = (byte)'m';

    public static bool TryReadChallenge(byte[] packet, out byte[] challenge) {
        challenge = [];
        if (packet.Length < 9 || !HasSimpleHeader(packet) || packet[4] != ChallengeHeader) {
            return false;
        }
        challenge = packet[5..9];
        return true;
    }

    public static ServerInfo? ParseInfo(byte[] packet) {
        if (packet.Length < 6 || !HasSimpleHeader(packet)) {
            return null;
        }

        var reader = new PacketReader(packet, 5);
        switch (packet[4]) {
            case SourceInfoHeader: {
                reader.ReadByte();
                string name = reader.ReadString();
                string map = reader.ReadString();
                reader.ReadString();
                reader.ReadString();
                reader.ReadShort();
                int players = reader.ReadByte();
                int maxPlayers = reader.ReadByte();
                int bots = reader.ReadByte();
                return new ServerInfo(name, map, players, maxPlayers, bots);
            }
            case GoldSrcInfoHeader: {
                reader.ReadString();
                string name = reader.ReadString();
                string map = reader.ReadString();
                reader.ReadString();
                reader.ReadString();
                int players = reader.ReadByte();
                int maxPlayers = reader.ReadByte();
                return new ServerInfo(name, map, players, maxPlayers, 0);
            }
            default:
                return null;
        }
    }

    private static bool HasSimpleHeader(byte[] packet) {
        return packet[0] == 0xFF && packet[1] == 0xFF && packet[2] == 0xFF && packet[3] == 0xFF;
    }

    private sealed class PacketReader(byte[] data, int position) {
        private int _position = position;

        public int ReadByte() {
            if (_position >= data.Length) {
                return 0;
            }
            return data[_position++];
        }

        public int ReadShort() {
            int low = ReadByte();
            int high = ReadByte();
            return low | (high << 8);
        }

        public string ReadString() {
            int start = _position;
            while (_position < data.Length && data[_position] != 0) {
                _position++;
            }
            string text = Encoding.UTF8.GetString(data, start, _position - start);
            _position = Math.Min(_position + 1, data.Length);
            return text;
        }
    }
}
