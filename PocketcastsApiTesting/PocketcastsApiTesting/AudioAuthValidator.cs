using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace PocketcastsApiTesting;

/// <summary>
/// Validates audio URL authentication requirements for Phase C (Garmin audio download).
/// 
/// Tests:
/// 1. Fetches episodes from /user/in_progress and /up_next/list
/// 2. Gets full episode detail via POST /user/episode for each
/// 3. Attempts 64KB Range GET without auth headers
/// 4. Confirms CDN audio URLs don't need Bearer tokens
/// 5. Documents CDN hosts, redirect chains, Range header support
/// 6. Checks for time-limited tokens (SupportingCast JWT)
/// 
/// All operations are READ-ONLY — no state is modified.
/// </summary>
public class AudioAuthValidator
{
    private readonly PocketCastsApiClient _apiClient;
    private readonly string _resultsDir;
    private readonly JsonSerializerOptions _jsonOpts = new() { WriteIndented = true };

    public AudioAuthValidator(PocketCastsApiClient apiClient, string resultsDir)
    {
        _apiClient = apiClient;
        _resultsDir = resultsDir;
    }

    public async Task RunValidation()
    {
        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine("  AUDIO URL AUTH VALIDATION (Phase C Prep)");
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine("  Goal: Confirm CDN audio URLs work without PocketCasts auth");
        Console.WriteLine("  Method: 64KB Range GET per episode, no Bearer token");
        Console.WriteLine();

        // Step 1: Gather episode UUIDs from multiple sources
        var episodes = await GatherDiverseEpisodes();

        if (episodes.Count < 3)
        {
            Console.WriteLine($"  ⚠️  Only found {episodes.Count} episodes — need at least 3.");
            Console.WriteLine("  Aborting validation.");
            return;
        }

        Console.WriteLine($"  📊 Selected {episodes.Count} episodes from {episodes.Select(e => e.PodcastTitle).Distinct().Count()} different podcasts");
        Console.WriteLine();

        // Step 2: Validate each episode
        var results = new List<EpisodeValidationResult>();
        foreach (var ep in episodes)
        {
            var result = await ValidateEpisode(ep);
            results.Add(result);
        }

        // Step 3: Print summary
        PrintSummary(results);

        // Step 4: Save results
        await SaveResults(results);
    }

    private async Task<List<EpisodeInfo>> GatherDiverseEpisodes()
    {
        var candidates = new List<EpisodeInfo>();
        var seenPodcasts = new HashSet<string>();

        // Source 1: In-progress episodes
        Console.WriteLine("  ▶ Fetching in-progress episodes...");
        try
        {
            var resp = await _apiClient.GetInProgress();
            if (resp.IsSuccessStatusCode)
            {
                var body = await resp.Content.ReadAsStringAsync();
                var json = JsonSerializer.Deserialize<JsonElement>(body);
                if (json.TryGetProperty("episodes", out var eps) && eps.ValueKind == JsonValueKind.Array)
                {
                    foreach (var ep in eps.EnumerateArray())
                    {
                        var uuid = ep.TryGetProperty("uuid", out var u) ? u.GetString() : null;
                        var podcastUuid = ep.TryGetProperty("podcastUuid", out var pu) ? pu.GetString() : null;
                        if (uuid != null && podcastUuid != null)
                        {
                            candidates.Add(new EpisodeInfo { Uuid = uuid, PodcastUuid = podcastUuid, Source = "in_progress" });
                        }
                    }
                    Console.WriteLine($"    Found {candidates.Count} in-progress episodes");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"    Error: {ex.Message}");
        }

        // Source 2: Up Next queue
        Console.WriteLine("  ▶ Fetching Up Next queue...");
        try
        {
            var resp = await _apiClient.GetUpNext();
            if (resp.IsSuccessStatusCode)
            {
                var body = await resp.Content.ReadAsStringAsync();
                var json = JsonSerializer.Deserialize<JsonElement>(body);
                if (json.TryGetProperty("episodes", out var episodesMap) && episodesMap.ValueKind == JsonValueKind.Object)
                {
                    var count = 0;
                    foreach (var prop in episodesMap.EnumerateObject())
                    {
                        var uuid = prop.Name;
                        var podcastUuid = prop.Value.TryGetProperty("podcastUuid", out var pu) ? pu.GetString() : null;
                        if (!candidates.Any(c => c.Uuid == uuid))
                        {
                            candidates.Add(new EpisodeInfo { Uuid = uuid, PodcastUuid = podcastUuid ?? "", Source = "up_next" });
                            count++;
                        }
                    }
                    Console.WriteLine($"    Found {count} Up Next episodes (new)");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"    Error: {ex.Message}");
        }

        // Step 2: Get full episode detail for each, selecting diverse podcasts
        Console.WriteLine("  ▶ Fetching full episode details...");
        var selected = new List<EpisodeInfo>();

        foreach (var candidate in candidates)
        {
            // Skip if we already have an episode from this podcast
            if (seenPodcasts.Contains(candidate.PodcastUuid) && selected.Count >= 3)
                continue;

            try
            {
                var resp = await _apiClient.GetEpisode(candidate.Uuid);
                if (resp.IsSuccessStatusCode)
                {
                    var body = await resp.Content.ReadAsStringAsync();
                    var detail = JsonSerializer.Deserialize<JsonElement>(body);

                    var url = detail.TryGetProperty("url", out var u) ? u.GetString() : null;
                    if (string.IsNullOrEmpty(url)) continue;

                    candidate.AudioUrl = url;
                    candidate.Title = detail.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
                    candidate.PodcastTitle = detail.TryGetProperty("podcastTitle", out var pt) ? pt.GetString() ?? "" : "";
                    candidate.Duration = detail.TryGetProperty("duration", out var d) && d.ValueKind == JsonValueKind.Number ? d.GetInt32() : 0;
                    candidate.FileType = detail.TryGetProperty("fileType", out var ft) ? ft.GetString() : null;
                    candidate.ApiSize = detail.TryGetProperty("size", out var s) ? s.ToString() : null;

                    seenPodcasts.Add(candidate.PodcastUuid);
                    selected.Add(candidate);

                    Console.WriteLine($"    ✓ {candidate.Title} [{candidate.PodcastTitle}]");
                    Console.WriteLine($"      Host: {new Uri(url).Host}");

                    if (selected.Count >= 5) break; // Cap at 5 for speed
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"    ✗ {candidate.Uuid}: {ex.Message}");
            }
        }

        return selected;
    }

    private async Task<EpisodeValidationResult> ValidateEpisode(EpisodeInfo episode)
    {
        var result = new EpisodeValidationResult
        {
            EpisodeUuid = episode.Uuid,
            Title = episode.Title,
            PodcastTitle = episode.PodcastTitle,
            OriginalUrl = episode.AudioUrl!,
            Source = episode.Source,
            OriginalHost = new Uri(episode.AudioUrl!).Host,
            HasEmbeddedToken = DetectEmbeddedToken(episode.AudioUrl!)
        };

        Console.WriteLine();
        Console.WriteLine($"  ┌─────────────────────────────────────────────────────");
        Console.WriteLine($"  │ {episode.Title}");
        Console.WriteLine($"  │ Podcast: {episode.PodcastTitle}");
        Console.WriteLine($"  │ Host:    {result.OriginalHost}");
        Console.WriteLine($"  │ Source:  {episode.Source}");
        if (result.HasEmbeddedToken)
            Console.WriteLine($"  │ ⚠️  Embedded JWT token detected (SupportingCast)");
        Console.WriteLine($"  └─────────────────────────────────────────────────────");

        // Test 1: 64KB Range GET without auth — the core validation
        Console.WriteLine($"    Test 1: GET Range bytes=0-65535 (64KB) WITHOUT auth...");
        using (var handler = new HttpClientHandler { AllowAutoRedirect = true })
        using (var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30) })
        {
            http.DefaultRequestHeaders.Add("User-Agent", "YoCasts-AuthValidator/1.0");

            try
            {
                var request = new HttpRequestMessage(HttpMethod.Get, episode.AudioUrl);
                request.Headers.Range = new RangeHeaderValue(0, 65535);
                var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);

                result.NoAuthStatusCode = (int)response.StatusCode;
                result.NoAuthSuccess = response.IsSuccessStatusCode;

                Console.WriteLine($"      Status: {result.NoAuthStatusCode} {response.StatusCode}");

                if (response.IsSuccessStatusCode)
                {
                    // Read the actual bytes to confirm data is returned
                    var stream = await response.Content.ReadAsStreamAsync();
                    var buffer = new byte[65536];
                    var totalRead = 0;
                    int bytesRead;
                    while (totalRead < buffer.Length && (bytesRead = await stream.ReadAsync(buffer, totalRead, buffer.Length - totalRead)) > 0)
                    {
                        totalRead += bytesRead;
                    }

                    result.BytesReceived = totalRead;
                    result.RangeSupported = response.StatusCode == HttpStatusCode.PartialContent;

                    Console.WriteLine($"      Bytes received: {totalRead:N0}");
                    Console.WriteLine($"      Range supported: {(result.RangeSupported ? "YES (206 Partial Content)" : "NO (200 OK — full response)")}");

                    if (response.Content.Headers.ContentType?.MediaType != null)
                    {
                        result.ContentType = response.Content.Headers.ContentType.MediaType;
                        Console.WriteLine($"      Content-Type: {result.ContentType}");
                    }

                    if (response.Content.Headers.ContentLength.HasValue)
                    {
                        result.ContentLength = response.Content.Headers.ContentLength.Value;
                    }

                    // Check Content-Range for total file size
                    if (response.Content.Headers.TryGetValues("Content-Range", out var rangeValues))
                    {
                        var rangeHeader = string.Join("", rangeValues);
                        result.ContentRange = rangeHeader;
                        Console.WriteLine($"      Content-Range: {rangeHeader}");
                        // Parse "bytes 0-65535/TOTAL"
                        if (rangeHeader.Contains('/'))
                        {
                            var totalStr = rangeHeader.Split('/').Last();
                            if (long.TryParse(totalStr, out var total))
                            {
                                result.TotalFileSize = total;
                                Console.WriteLine($"      Total file size: {total:N0} bytes ({total / 1024.0 / 1024.0:F1} MB)");
                            }
                        }
                    }

                    // Capture final URL after redirects
                    if (response.RequestMessage?.RequestUri != null)
                    {
                        result.FinalUrl = response.RequestMessage.RequestUri.ToString();
                        result.FinalHost = response.RequestMessage.RequestUri.Host;
                        if (result.FinalUrl != episode.AudioUrl)
                        {
                            result.RedirectOccurred = true;
                            Console.WriteLine($"      Final URL host: {result.FinalHost}");
                        }
                    }

                    Console.WriteLine($"      ✅ Audio accessible WITHOUT auth");
                }
                else
                {
                    Console.WriteLine($"      ❌ Audio NOT accessible without auth");
                }
            }
            catch (Exception ex)
            {
                result.NoAuthError = ex.Message;
                Console.WriteLine($"      ❌ Error: {ex.Message}");
            }
        }

        // Test 2: Trace redirect chain (without following redirects)
        Console.WriteLine($"    Test 2: Redirect chain analysis...");
        result.RedirectHops = await TraceRedirects(episode.AudioUrl!);
        Console.WriteLine($"      Hops: {result.RedirectHops.Count}");
        foreach (var hop in result.RedirectHops)
        {
            Console.WriteLine($"        {hop.Status} → {hop.Host}");
        }

        // Test 3: Check if URL has time-limited token
        if (result.HasEmbeddedToken)
        {
            Console.WriteLine($"    Test 3: SupportingCast JWT analysis...");
            AnalyzeEmbeddedToken(episode.AudioUrl!, result);
        }

        result.RequiresAuth = !result.NoAuthSuccess;
        return result;
    }

    private static bool DetectEmbeddedToken(string url)
    {
        // SupportingCast URLs contain base64-encoded JWT in the path
        return url.Contains("supportingcast.fm/content/") ||
               url.Contains("|") || // JWT|HMAC separator
               (url.Contains("eyJ") && url.Contains(".mp3")); // Base64-encoded JWT prefix
    }

    private static void AnalyzeEmbeddedToken(string url, EpisodeValidationResult result)
    {
        try
        {
            // SupportingCast format: /content/{base64jwt}|{hmac}.mp3
            var uri = new Uri(url);
            var path = uri.AbsolutePath;
            var contentIdx = path.IndexOf("/content/");
            if (contentIdx < 0) return;

            var tokenPart = path[(contentIdx + "/content/".Length)..];
            var pipeIdx = tokenPart.IndexOf('|');
            if (pipeIdx > 0)
            {
                var jwtBase64 = tokenPart[..pipeIdx];
                // Pad base64 if needed
                var padded = jwtBase64.PadRight(jwtBase64.Length + (4 - jwtBase64.Length % 4) % 4, '=');
                // Replace URL-safe base64 chars
                padded = padded.Replace('-', '+').Replace('_', '/');

                try
                {
                    var decoded = Convert.FromBase64String(padded);
                    var json = Encoding.UTF8.GetString(decoded);
                    var payload = JsonSerializer.Deserialize<JsonElement>(json);

                    if (payload.TryGetProperty("d", out var dProp))
                    {
                        var timestamp = dProp.GetString() ?? dProp.ToString();
                        if (long.TryParse(timestamp, out var epoch))
                        {
                            var generated = DateTimeOffset.FromUnixTimeSeconds(epoch);
                            var age = DateTimeOffset.UtcNow - generated;
                            result.TokenGeneratedAt = generated.ToString("o");
                            result.TokenAge = $"{age.TotalHours:F1} hours ({age.TotalDays:F1} days)";

                            Console.WriteLine($"      Token generated: {generated:u}");
                            Console.WriteLine($"      Token age: {result.TokenAge}");
                            Console.WriteLine($"      Token still valid: {(result.NoAuthSuccess ? "YES" : "NO")}");
                        }
                    }
                }
                catch
                {
                    Console.WriteLine($"      Could not decode JWT payload");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"      JWT analysis error: {ex.Message}");
        }
    }

    private async Task<List<RedirectHop>> TraceRedirects(string url)
    {
        var hops = new List<RedirectHop>();

        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15) };
        http.DefaultRequestHeaders.Add("User-Agent", "YoCasts-AuthValidator/1.0");

        var current = url;
        const int maxHops = 10;

        for (int i = 0; i < maxHops; i++)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Head, current);
                var response = await http.SendAsync(request);
                var statusCode = (int)response.StatusCode;
                var host = new Uri(current).Host;

                hops.Add(new RedirectHop
                {
                    Url = current,
                    Host = host,
                    Status = statusCode
                });

                if (statusCode >= 300 && statusCode < 400)
                {
                    var location = response.Headers.Location?.ToString();
                    if (location == null) break;

                    if (!location.StartsWith("http"))
                    {
                        var baseUri = new Uri(current);
                        location = new Uri(baseUri, location).ToString();
                    }
                    current = location;
                }
                else
                {
                    break;
                }
            }
            catch
            {
                break;
            }
        }

        return hops;
    }

    private void PrintSummary(List<EpisodeValidationResult> results)
    {
        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine("  VALIDATION SUMMARY");
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine();

        var allNoAuth = results.All(r => r.NoAuthSuccess);
        var allRange = results.All(r => r.RangeSupported);
        var cdnHosts = results.Where(r => r.FinalHost != null).Select(r => r.FinalHost!).Distinct().ToList();
        var withTokens = results.Where(r => r.HasEmbeddedToken).ToList();

        Console.WriteLine($"  Episodes tested:     {results.Count}");
        Console.WriteLine($"  Different podcasts:  {results.Select(r => r.PodcastTitle).Distinct().Count()}");
        Console.WriteLine($"  CDNs hit:            {cdnHosts.Count} ({string.Join(", ", cdnHosts)})");
        Console.WriteLine();

        // Auth requirement
        Console.WriteLine($"  ── Auth Requirement ──");
        if (allNoAuth)
        {
            Console.WriteLine($"  ✅ CONFIRMED: All audio URLs accessible WITHOUT Bearer token");
            Console.WriteLine($"     CDN audio is public. Garmin can download directly.");
        }
        else
        {
            var failedCount = results.Count(r => !r.NoAuthSuccess);
            Console.WriteLine($"  ⚠️  {failedCount}/{results.Count} episodes REQUIRED auth");
            foreach (var r in results.Where(r => !r.NoAuthSuccess))
                Console.WriteLine($"     • {r.Title} ({r.OriginalHost}): HTTP {r.NoAuthStatusCode}");
        }
        Console.WriteLine();

        // Range support
        Console.WriteLine($"  ── Range Header Support ──");
        if (allRange)
        {
            Console.WriteLine($"  ✅ All CDNs support Range requests (206 Partial Content)");
            Console.WriteLine($"     Resumable downloads fully supported.");
        }
        else
        {
            var noRange = results.Where(r => !r.RangeSupported && r.NoAuthSuccess).ToList();
            if (noRange.Any())
            {
                Console.WriteLine($"  ⚠️  {noRange.Count} CDN(s) did NOT return 206:");
                foreach (var r in noRange)
                    Console.WriteLine($"     • {r.FinalHost}: HTTP {r.NoAuthStatusCode}");
            }
        }
        Console.WriteLine();

        // Embedded tokens / URL expiry
        Console.WriteLine($"  ── URL Expiry / Embedded Tokens ──");
        if (withTokens.Any())
        {
            Console.WriteLine($"  ⚠️  {withTokens.Count} episode(s) have embedded JWT tokens:");
            foreach (var r in withTokens)
            {
                Console.WriteLine($"     • {r.Title} ({r.OriginalHost})");
                if (r.TokenAge != null) Console.WriteLine($"       Token age: {r.TokenAge}");
            }
            Console.WriteLine($"     → Re-fetch episode metadata before download to get fresh URLs.");
        }
        else
        {
            Console.WriteLine($"  ✅ No time-limited tokens detected. Standard RSS URLs are permanent.");
        }
        Console.WriteLine();

        // Per-episode detail table
        Console.WriteLine($"  ── Per-Episode Results ──");
        Console.WriteLine($"  {"Episode",-40} {"Podcast",-25} {"CDN",-30} {"Auth?",-6} {"Range?",-7} {"Size",-12}");
        Console.WriteLine($"  {new string('─', 40)} {new string('─', 25)} {new string('─', 30)} {new string('─', 6)} {new string('─', 7)} {new string('─', 12)}");
        foreach (var r in results)
        {
            var title = r.Title.Length > 38 ? r.Title[..38] + "…" : r.Title;
            var podcast = (r.PodcastTitle ?? "").Length > 23 ? r.PodcastTitle![..23] + "…" : r.PodcastTitle ?? "";
            var cdn = (r.FinalHost ?? r.OriginalHost).Length > 28 ? (r.FinalHost ?? r.OriginalHost)[..28] + "…" : (r.FinalHost ?? r.OriginalHost);
            var auth = r.RequiresAuth ? "YES" : "no";
            var range = r.RangeSupported ? "yes" : "no";
            var size = r.TotalFileSize > 0 ? $"{r.TotalFileSize / 1024.0 / 1024.0:F1} MB" : "?";
            Console.WriteLine($"  {title,-40} {podcast,-25} {cdn,-30} {auth,-6} {range,-7} {size,-12}");
        }

        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
    }

    private async Task SaveResults(List<EpisodeValidationResult> results)
    {
        var report = new
        {
            testName = "Audio URL Auth Validation",
            timestamp = DateTime.UtcNow.ToString("o"),
            summary = new
            {
                episodesTested = results.Count,
                distinctPodcasts = results.Select(r => r.PodcastTitle).Distinct().Count(),
                allAccessibleWithoutAuth = results.All(r => r.NoAuthSuccess),
                allSupportRange = results.All(r => r.RangeSupported),
                cdnHostsHit = results.Where(r => r.FinalHost != null).Select(r => r.FinalHost!).Distinct().ToList(),
                episodesWithEmbeddedTokens = results.Count(r => r.HasEmbeddedToken),
                conclusion = results.All(r => r.NoAuthSuccess)
                    ? "CDN audio URLs do NOT require PocketCasts auth. Garmin can download directly."
                    : "Some audio URLs require auth — investigate further."
            },
            episodes = results
        };

        var fileName = $"audio-auth-validation-{DateTime.UtcNow:yyyyMMdd-HHmmss}.json";
        var filePath = Path.Combine(_resultsDir, fileName);
        await File.WriteAllTextAsync(filePath, JsonSerializer.Serialize(report, _jsonOpts));
        Console.WriteLine($"  📄 Full results saved to: {fileName}");
    }

    // ── Data models ──

    private class EpisodeInfo
    {
        public string Uuid { get; set; } = "";
        public string PodcastUuid { get; set; } = "";
        public string? AudioUrl { get; set; }
        public string Title { get; set; } = "";
        public string PodcastTitle { get; set; } = "";
        public int Duration { get; set; }
        public string? FileType { get; set; }
        public string? ApiSize { get; set; }
        public string Source { get; set; } = "";
    }

    public class EpisodeValidationResult
    {
        public string EpisodeUuid { get; set; } = "";
        public string Title { get; set; } = "";
        public string? PodcastTitle { get; set; }
        public string Source { get; set; } = "";
        public string OriginalUrl { get; set; } = "";
        public string OriginalHost { get; set; } = "";
        public string? FinalUrl { get; set; }
        public string? FinalHost { get; set; }
        public bool RedirectOccurred { get; set; }
        public List<RedirectHop> RedirectHops { get; set; } = new();
        public bool NoAuthSuccess { get; set; }
        public int NoAuthStatusCode { get; set; }
        public string? NoAuthError { get; set; }
        public int BytesReceived { get; set; }
        public bool RangeSupported { get; set; }
        public string? ContentType { get; set; }
        public long ContentLength { get; set; }
        public string? ContentRange { get; set; }
        public long TotalFileSize { get; set; }
        public bool RequiresAuth { get; set; }
        public bool HasEmbeddedToken { get; set; }
        public string? TokenGeneratedAt { get; set; }
        public string? TokenAge { get; set; }
    }

    public class RedirectHop
    {
        public string Url { get; set; } = "";
        public string Host { get; set; } = "";
        public int Status { get; set; }
    }
}
