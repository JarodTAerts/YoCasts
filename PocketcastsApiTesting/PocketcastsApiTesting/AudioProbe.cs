using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace PocketcastsApiTesting;

/// <summary>
/// Probes audio URLs from PocketCasts episodes to determine download mechanics.
/// READ-ONLY: only uses HEAD and GET (with Range) — no audio is fully downloaded.
/// </summary>
public class AudioProbe
{
    private readonly string _authToken;
    private readonly string _resultsDir;
    private readonly JsonSerializerOptions _jsonOpts = new() { WriteIndented = true };

    public AudioProbe(string authToken, string resultsDir)
    {
        _authToken = authToken;
        _resultsDir = resultsDir;
    }

    public async Task ProbeEpisodeAudio(string title, string audioUrl, string? fileType, string? sizeStr, int? duration)
    {
        Console.WriteLine();
        Console.WriteLine($"══════════════════════════════════════════════════════════");
        Console.WriteLine($"  AUDIO PROBE: {title}");
        Console.WriteLine($"══════════════════════════════════════════════════════════");
        Console.WriteLine($"  Original URL:  {audioUrl}");
        Console.WriteLine($"  API fileType:  {fileType ?? "(null)"}");
        Console.WriteLine($"  API size:      {sizeStr ?? "(null)"}");
        Console.WriteLine($"  API duration:  {(duration.HasValue ? $"{duration}s ({duration / 60}m {duration % 60}s)" : "(null)")}");
        Console.WriteLine();

        // Extract the hosting provider from the URL
        var uri = new Uri(audioUrl);
        Console.WriteLine($"  Host chain:    {uri.Host}");
        AnalyzeUrlChain(audioUrl);
        Console.WriteLine();

        // Test 1: HEAD request WITHOUT auth — does the audio URL require authentication?
        Console.WriteLine("  ── Test 1: HEAD without auth ──");
        var noAuthResult = await HeadRequest(audioUrl, withAuth: false, followRedirects: true);

        // Test 2: HEAD request WITH auth (PocketCasts Bearer token)
        Console.WriteLine("  ── Test 2: HEAD with PocketCasts auth ──");
        var authResult = await HeadRequest(audioUrl, withAuth: true, followRedirects: true);

        // Test 3: HEAD without following redirects — see the redirect chain
        Console.WriteLine("  ── Test 3: HEAD without following redirects (redirect chain) ──");
        await TraceRedirectChain(audioUrl);

        // Test 4: Range request — first 1 byte to check Accept-Ranges
        Console.WriteLine("  ── Test 4: GET with Range header (bytes=0-0) ──");
        await TestRangeRequest(audioUrl);

        // Save results
        var result = new
        {
            title,
            originalUrl = audioUrl,
            host = uri.Host,
            apiFileType = fileType,
            apiSize = sizeStr,
            apiDuration = duration,
            noAuthHead = noAuthResult,
            authHead = authResult,
            timestamp = DateTime.UtcNow.ToString("o")
        };

        var fileName = $"audio-probe-{SanitizeFileName(title)}.json";
        var filePath = Path.Combine(_resultsDir, fileName);
        await File.WriteAllTextAsync(filePath, JsonSerializer.Serialize(result, _jsonOpts));
        Console.WriteLine($"\n  📄 Results saved to: {fileName}");
    }

    private async Task<Dictionary<string, string?>> HeadRequest(string url, bool withAuth, bool followRedirects)
    {
        var result = new Dictionary<string, string?>();

        using var handler = new HttpClientHandler
        {
            AllowAutoRedirect = followRedirects
        };
        using var http = new HttpClient(handler);
        http.DefaultRequestHeaders.Add("User-Agent", "YoCasts-AudioProbe/1.0");

        if (withAuth)
        {
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _authToken);
        }

        try
        {
            var request = new HttpRequestMessage(HttpMethod.Head, url);
            var response = await http.SendAsync(request);

            var statusCode = (int)response.StatusCode;
            result["statusCode"] = statusCode.ToString();
            result["statusText"] = response.StatusCode.ToString();

            Console.WriteLine($"    Status:         {statusCode} {response.StatusCode}");

            if (response.Content.Headers.ContentType != null)
            {
                var ct = response.Content.Headers.ContentType.ToString();
                result["contentType"] = ct;
                Console.WriteLine($"    Content-Type:   {ct}");
            }

            if (response.Content.Headers.ContentLength.HasValue)
            {
                var len = response.Content.Headers.ContentLength.Value;
                result["contentLength"] = len.ToString();
                var mb = len / (1024.0 * 1024.0);
                Console.WriteLine($"    Content-Length:  {len} bytes ({mb:F1} MB)");
            }
            else
            {
                Console.WriteLine($"    Content-Length:  (not present)");
            }

            if (response.Headers.TryGetValues("Accept-Ranges", out var acceptRanges))
            {
                var ar = string.Join(", ", acceptRanges);
                result["acceptRanges"] = ar;
                Console.WriteLine($"    Accept-Ranges:  {ar}");
            }
            else
            {
                Console.WriteLine($"    Accept-Ranges:  (not present)");
            }

            // Check final URL after redirects
            var finalUrl = response.RequestMessage?.RequestUri?.ToString();
            if (finalUrl != null && finalUrl != url)
            {
                result["finalUrl"] = finalUrl;
                var finalUri = new Uri(finalUrl);
                Console.WriteLine($"    Final URL:      {finalUrl}");
                Console.WriteLine($"    Final Host:     {finalUri.Host}");
            }

            // Check cache-related headers
            if (response.Headers.TryGetValues("Cache-Control", out var cacheControl))
            {
                var cc = string.Join(", ", cacheControl);
                result["cacheControl"] = cc;
                Console.WriteLine($"    Cache-Control:  {cc}");
            }
            if (response.Headers.TryGetValues("ETag", out var etag))
            {
                result["etag"] = string.Join(", ", etag);
                Console.WriteLine($"    ETag:           {result["etag"]}");
            }
            if (response.Content.Headers.TryGetValues("Content-Disposition", out var contentDisp))
            {
                result["contentDisposition"] = string.Join(", ", contentDisp);
                Console.WriteLine($"    Content-Disp:   {result["contentDisposition"]}");
            }
            if (response.Headers.TryGetValues("X-Served-By", out var servedBy))
            {
                result["xServedBy"] = string.Join(", ", servedBy);
                Console.WriteLine($"    X-Served-By:    {result["xServedBy"]}");
            }

            // Dump all response headers for completeness
            Console.WriteLine($"    --- All headers ---");
            foreach (var header in response.Headers)
            {
                Console.WriteLine($"      {header.Key}: {string.Join(", ", header.Value)}");
            }
            foreach (var header in response.Content.Headers)
            {
                Console.WriteLine($"      {header.Key}: {string.Join(", ", header.Value)}");
            }
        }
        catch (Exception ex)
        {
            result["error"] = ex.Message;
            Console.WriteLine($"    ERROR: {ex.Message}");
        }

        return result;
    }

    private async Task TraceRedirectChain(string url)
    {
        using var handler = new HttpClientHandler
        {
            AllowAutoRedirect = false
        };
        using var http = new HttpClient(handler);
        http.DefaultRequestHeaders.Add("User-Agent", "YoCasts-AudioProbe/1.0");

        var current = url;
        var hop = 0;
        const int maxHops = 15;

        while (hop < maxHops)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Head, current);
                var response = await http.SendAsync(request);
                var statusCode = (int)response.StatusCode;

                Console.WriteLine($"    Hop {hop}: {statusCode} {response.StatusCode}");
                Console.WriteLine($"      URL: {current}");

                if (statusCode >= 300 && statusCode < 400)
                {
                    var location = response.Headers.Location?.ToString();
                    if (location == null)
                    {
                        Console.WriteLine($"      ⚠️  Redirect with no Location header");
                        break;
                    }

                    // Handle relative redirects
                    if (!location.StartsWith("http"))
                    {
                        var baseUri = new Uri(current);
                        location = new Uri(baseUri, location).ToString();
                    }

                    Console.WriteLine($"      → Location: {location}");
                    current = location;
                    hop++;
                }
                else
                {
                    Console.WriteLine($"      ✅ Final destination (status {statusCode})");
                    if (response.Content.Headers.ContentLength.HasValue)
                    {
                        var len = response.Content.Headers.ContentLength.Value;
                        Console.WriteLine($"      Content-Length: {len} ({len / 1024.0 / 1024.0:F1} MB)");
                    }
                    if (response.Content.Headers.ContentType != null)
                    {
                        Console.WriteLine($"      Content-Type: {response.Content.Headers.ContentType}");
                    }
                    break;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"    Hop {hop}: ERROR — {ex.Message}");
                break;
            }
        }

        if (hop >= maxHops)
            Console.WriteLine($"    ⚠️  Exceeded {maxHops} redirect hops");
    }

    private async Task TestRangeRequest(string url)
    {
        using var handler = new HttpClientHandler
        {
            AllowAutoRedirect = true
        };
        using var http = new HttpClient(handler);
        http.DefaultRequestHeaders.Add("User-Agent", "YoCasts-AudioProbe/1.0");

        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Range = new RangeHeaderValue(0, 0);
            var response = await http.SendAsync(request);

            var statusCode = (int)response.StatusCode;
            Console.WriteLine($"    Status:          {statusCode} {response.StatusCode}");

            if (statusCode == 206)
            {
                Console.WriteLine($"    ✅ Partial Content — Range requests SUPPORTED");
                if (response.Content.Headers.TryGetValues("Content-Range", out var contentRange))
                {
                    var cr = string.Join(", ", contentRange);
                    Console.WriteLine($"    Content-Range:   {cr}");
                    // Parse total size from Content-Range: bytes 0-0/TOTAL
                    if (cr.Contains('/'))
                    {
                        var totalStr = cr.Split('/').Last();
                        if (long.TryParse(totalStr, out var total))
                        {
                            Console.WriteLine($"    Total file size: {total} bytes ({total / 1024.0 / 1024.0:F1} MB)");
                        }
                    }
                }
            }
            else if (statusCode == 200)
            {
                Console.WriteLine($"    ⚠️  Got 200 instead of 206 — Range may not be supported (or server ignored it)");
                if (response.Content.Headers.ContentLength.HasValue)
                {
                    Console.WriteLine($"    Content-Length:   {response.Content.Headers.ContentLength.Value}");
                }
            }
            else
            {
                Console.WriteLine($"    ⚠️  Unexpected status for Range request");
            }

            if (response.Content.Headers.ContentType != null)
                Console.WriteLine($"    Content-Type:    {response.Content.Headers.ContentType}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"    ERROR: {ex.Message}");
        }
    }

    private void AnalyzeUrlChain(string url)
    {
        // Many podcast URLs are chains of tracking/analytics redirectors
        // e.g., pdst.fm -> mgln.ai -> claritaspod.com -> podscribe.com -> vpixl.com -> megaphone.fm
        var parts = url.Replace("https://", "").Replace("http://", "").Split('/');
        var hosts = new List<string>();

        // Walk the URL path looking for host-like segments
        foreach (var part in parts)
        {
            if (part.Contains('.') && !part.Contains('=') && !part.EndsWith(".mp3") && !part.EndsWith(".mp4") && !part.EndsWith(".m4a"))
            {
                // Check if it looks like a hostname
                var segments = part.Split('.');
                if (segments.Length >= 2 && segments.All(s => s.Length > 0 && !s.Contains('?')))
                {
                    hosts.Add(part);
                }
            }
        }

        if (hosts.Count > 1)
        {
            Console.WriteLine($"  URL chain:     {string.Join(" → ", hosts)}");
        }
    }

    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var clean = new StringBuilder();
        foreach (var c in name.Take(40))
        {
            if (invalid.Contains(c) || c == ' ')
                clean.Append('-');
            else
                clean.Append(c);
        }
        return clean.ToString().ToLower();
    }
}
