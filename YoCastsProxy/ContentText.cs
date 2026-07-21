using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json.Nodes;

namespace YoCastsProxy;

internal static partial class ContentText
{
    public static async Task<string> ReadLimitedStringAsync(
        HttpContent content,
        int maxBytes,
        CancellationToken cancellationToken = default)
    {
        await using var stream =
            await content.ReadAsStreamAsync(cancellationToken);
        using var buffer = new MemoryStream(Math.Min(maxBytes, 64 * 1024));
        var chunk = new byte[8192];
        var total = 0;

        while (true)
        {
            var read = await stream.ReadAsync(chunk, cancellationToken);
            if (read == 0)
                break;
            total += read;
            if (total > maxBytes)
                throw new InvalidDataException(
                    $"Response exceeded {maxBytes} bytes");
            await buffer.WriteAsync(
                chunk.AsMemory(0, read),
                cancellationToken);
        }

        var encoding = Encoding.UTF8;
        var charset = content.Headers.ContentType?.CharSet?.Trim('"');
        if (!string.IsNullOrWhiteSpace(charset))
        {
            try
            {
                encoding = Encoding.GetEncoding(charset);
            }
            catch (ArgumentException)
            {
                // Pocket Casts JSON is UTF-8 when no supported charset is set.
            }
        }
        return encoding.GetString(buffer.ToArray());
    }

    public static async Task<string> GetLimitedStringAsync(
        HttpClient client,
        Uri uri,
        int maxBytes,
        CancellationToken cancellationToken = default)
    {
        using var response = await client.GetAsync(
            uri,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        response.EnsureSuccessStatusCode();
        return await ReadLimitedStringAsync(
            response.Content,
            maxBytes,
            cancellationToken);
    }

    public static string FirstText(JsonObject source, params string[] fields)
    {
        foreach (var field in fields)
        {
            if (source[field] is JsonValue value &&
                value.TryGetValue<string>(out var text) &&
                !string.IsNullOrWhiteSpace(text))
                return text;
        }
        return "";
    }

    public static string Compact(string text, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(text))
            return "";

        var normalized = BreakRegex().Replace(text, "\n");
        normalized = TagRegex().Replace(normalized, " ");
        normalized = WebUtility.HtmlDecode(normalized);
        normalized = SpaceRegex().Replace(normalized, " ");
        normalized = NewlineRegex().Replace(normalized, "\n");
        normalized = normalized.Trim();

        if (normalized.Length <= maxLength)
            return normalized;

        var cut = normalized[..maxLength];
        var lastSpace = cut.LastIndexOf(' ');
        if (lastSpace > maxLength * 3 / 4)
            cut = cut[..lastSpace];
        return cut.TrimEnd() + "...";
    }

    [GeneratedRegex(@"(?i)<\s*(br|/p|/li)\s*/?>")]
    private static partial Regex BreakRegex();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex TagRegex();

    [GeneratedRegex(@"[^\S\r\n]+")]
    private static partial Regex SpaceRegex();

    [GeneratedRegex(@"\s*\r?\n\s*(\r?\n\s*)+")]
    private static partial Regex NewlineRegex();
}
