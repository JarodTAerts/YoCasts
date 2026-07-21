using System.Net;
using System.Net.Sockets;

namespace YoCastsProxy;

internal static class NetworkGuard
{
    public static async ValueTask<Stream> ConnectPublicAsync(
        SocketsHttpConnectionContext context,
        CancellationToken cancellationToken)
    {
        var addresses = await ResolvePublicAddressesAsync(
            context.DnsEndPoint.Host,
            cancellationToken);

        Exception? lastError = null;
        foreach (var address in addresses)
        {
            var socket = new Socket(
                address.AddressFamily,
                SocketType.Stream,
                ProtocolType.Tcp);
            try
            {
                await socket.ConnectAsync(
                    new IPEndPoint(address, context.DnsEndPoint.Port),
                    cancellationToken);
                return new NetworkStream(socket, ownsSocket: true);
            }
            catch (Exception ex)
            {
                lastError = ex;
                socket.Dispose();
            }
        }

        throw new HttpRequestException(
            $"Unable to connect to public host {context.DnsEndPoint.Host}",
            lastError);
    }

    public static async Task<bool> IsPublicHostAsync(string host)
    {
        try
        {
            await ResolvePublicAddressesAsync(host, CancellationToken.None);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static async Task<IPAddress[]> ResolvePublicAddressesAsync(
        string host,
        CancellationToken cancellationToken)
    {
        var addresses = await Dns.GetHostAddressesAsync(host, cancellationToken);
        if (addresses.Length == 0 || addresses.Any(address => !IsPublic(address)))
            throw new HttpRequestException($"Blocked non-public host {host}");
        return addresses;
    }

    private static bool IsPublic(IPAddress address)
    {
        if (IPAddress.IsLoopback(address))
            return false;

        if (address.IsIPv4MappedToIPv6)
            address = address.MapToIPv4();

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            var bytes = address.GetAddressBytes();

            // Only globally routed unicast space is useful for enclosure and
            // Pocket Casts content. This also rejects ULA, link-local,
            // multicast, IPv4-compatible, and NAT64-embedded destinations.
            if ((bytes[0] & 0xE0) != 0x20)
                return false;
            if (bytes[0] == 0x20 && bytes[1] == 0x02)
                return false;

            // Documentation, transition, benchmarking, and ORCHID ranges are
            // not globally reachable application endpoints.
            if (bytes[0] == 0x20 && bytes[1] == 0x01 &&
                ((bytes[2] == 0x0D && bytes[3] == 0xB8) ||
                 (bytes[2] == 0x00 && bytes[3] == 0x00) ||
                 (bytes[2] == 0x00 && bytes[3] == 0x02) ||
                 (bytes[2] == 0x00 &&
                  (bytes[3] & 0xF0) is 0x10 or 0x20)))
                return false;

            return true;
        }

        var octets = address.GetAddressBytes();
        var first = octets[0];
        var second = octets[1];
        var third = octets[2];
        var fourth = octets[3];

        if (first == 0 || first == 10 || first == 127 || first >= 224)
            return false;
        if (first == 100 && second is >= 64 and <= 127)
            return false;
        if (first == 169 && second == 254)
            return false;
        if (first == 172 && second is >= 16 and <= 31)
            return false;
        if (first == 192 &&
            ((second == 0 && third is 0 or 2) ||
             second == 168 ||
             (second == 88 && third == 99)))
            return false;
        if (first == 198 &&
            (second is 18 or 19 ||
             (second == 51 && third == 100)))
            return false;
        if (first == 203 && second == 0 && third == 113)
            return false;

        // Azure exposes host infrastructure at this otherwise public-looking
        // address from inside Function App workers.
        if (first == 168 && second == 63 && third == 129 && fourth == 16)
            return false;

        return true;
    }
}
