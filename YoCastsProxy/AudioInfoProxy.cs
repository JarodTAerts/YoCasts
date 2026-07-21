using System.Collections.Concurrent;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace YoCastsProxy;

/// <summary>
/// Resolves audio download metadata for an episode without downloading
/// the full audio file. Issues a HEAD request to the episode's audio URL
/// to get file size, content type, and final URL (after redirects).
///
/// The watch calls this before starting a download so it can check
/// whether there's enough storage space on the device.
///
/// GET /api/pocketcasts/episode/{uuid}/audio-info
/// Requires Bearer token (used to fetch episode metadata from PocketCasts).
/// Returns: { audioUrl, fileSize, contentType, duration, title, podcastTitle, podcastUuid, requiresAuth }
///
/// Caching: Results cached in-memory for 2 hours (audio URLs are stable for hours/days).
/// SupportingCast premium URLs with embedded JWT are cached for only 30 minutes
/// and flagged with requiresAuth=true so the client knows to re-fetch before download.
/// </summary>
public class AudioInfoProxy
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<AudioInfoProxy> _logger;

    // In-memory cache: survives across requests within the same Azure Function instance.
    // Standard episodes: 2 hour TTL. SupportingCast (JWT): 30 minute TTL.
    private static readonly ConcurrentDictionary<string, AudioInfoCacheEntry> _cache = new();
    private static readonly TimeSpan StandardCacheTtl = TimeSpan.FromHours(2);
    private static readonly TimeSpan PremiumCacheTtl = TimeSpan.FromMinutes(30);
    private const int MaxEpisodeResponseBytes = 1024 * 1024;
    private const int MaxErrorResponseBytes = 64 * 1024;

    public AudioInfoProxy(IHttpClientFactory httpClientFactory, ILogger<AudioInfoProxy> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    [Function("AudioInfo")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "pocketcasts/episode/{uuid}/audio-info")] HttpRequest req,
        string uuid)
    {
        _logger.LogInformation("AudioInfo: resolving audio metadata for episode {Uuid}", uuid);

        // Extract Bearer token
        var authHeader = req.Headers.Authorization.FirstOrDefault();
        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return new ObjectResult(new { error = "Missing or invalid Bearer token" })
            {
                StatusCode = StatusCodes.Status401Unauthorized
            };
        }
        var token = authHeader["Bearer ".Length..];

        // Private/premium feed URLs can be account-specific. Scope cached
        // capability URLs to a token fingerprint so one user never receives
        // another user's signed enclosure URL.
        var cacheKey = CreateCacheKey(uuid, token);
        if (_cache.TryGetValue(cacheKey, out var cached) &&
            cached.ExpiresAt > DateTime.UtcNow)
        {
            _logger.LogInformation("AudioInfo: cache hit for {Uuid}", uuid);
            return new OkObjectResult(cached.Response);
        }

        // Step 1: Fetch episode metadata from PocketCasts to get the audio URL
        var pocketCastsClient = _httpClientFactory.CreateClient("PocketCasts");
        var episodeRequest = new HttpRequestMessage(HttpMethod.Post, "/user/episode")
        {
            Content = new StringContent(
                JsonSerializer.Serialize(new { uuid }),
                System.Text.Encoding.UTF8,
                "application/json")
        };
        episodeRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        HttpResponseMessage episodeResponse;
        try
        {
            episodeResponse = await pocketCastsClient.SendAsync(
                episodeRequest,
                HttpCompletionOption.ResponseHeadersRead);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AudioInfo: failed to fetch episode metadata");
            return new ObjectResult(new { error = "Failed to fetch episode metadata" })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }
        using var episodeResponseLease = episodeResponse;

        if (!episodeResponse.IsSuccessStatusCode)
        {
            var errorBody = await ContentText.ReadLimitedStringAsync(
                episodeResponse.Content,
                MaxErrorResponseBytes);
            _logger.LogWarning("AudioInfo: PocketCasts returned {StatusCode} for episode {Uuid}",
                episodeResponse.StatusCode, uuid);
            return new ContentResult
            {
                Content = errorBody,
                ContentType = "application/json",
                StatusCode = (int)episodeResponse.StatusCode
            };
        }

        string episodeJson;
        try
        {
            episodeJson = await ContentText.ReadLimitedStringAsync(
                episodeResponse.Content,
                MaxEpisodeResponseBytes);
        }
        catch (InvalidDataException ex)
        {
            _logger.LogWarning(
                ex,
                "AudioInfo: oversized episode metadata for {Uuid}",
                uuid);
            return new ObjectResult(
                new { error = "Episode metadata response too large" })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }
        var episodeData = JsonSerializer.Deserialize<JsonElement>(episodeJson);

        // Extract the audio URL and metadata from the episode response
        var audioUrl = episodeData.TryGetProperty("url", out var urlProp)
            ? urlProp.GetString() : null;
        var duration = episodeData.TryGetProperty("duration", out var durProp)
            ? durProp.GetInt32() : 0;
        var title = episodeData.TryGetProperty("title", out var titleProp)
            ? titleProp.GetString() : "";
        var podcastUuid = episodeData.TryGetProperty("podcastUuid", out var podProp)
            ? podProp.GetString() : "";
        var podcastTitle = episodeData.TryGetProperty("podcastTitle", out var ptProp)
            ? ptProp.GetString() : "";
        var fileType = episodeData.TryGetProperty("fileType", out var ftProp)
            ? ftProp.GetString() : "";
        var summary = "";
        foreach (var field in new[] { "showNotes", "descriptionHtml", "description", "notes" })
        {
            if (episodeData.TryGetProperty(field, out var summaryProp) &&
                summaryProp.ValueKind == JsonValueKind.String)
            {
                summary = summaryProp.GetString() ?? "";
                if (!string.IsNullOrWhiteSpace(summary))
                    break;
            }
        }
        summary = ContentText.Compact(summary, 700);
        var published = episodeData.TryGetProperty("published", out var pubProp)
            ? pubProp.ToString() : "";

        if (string.IsNullOrEmpty(audioUrl))
        {
            return new ObjectResult(new { error = "No audio URL found for episode", uuid })
            {
                StatusCode = StatusCodes.Status404NotFound
            };
        }

        // Detect SupportingCast premium URLs with embedded JWT tokens.
        // These URLs have time-limited tokens and should be re-fetched before download.
        var requiresAuth = IsPremiumUrl(audioUrl);

        // Step 2: HEAD request to the audio URL to get real file size.
        // Audio URLs are public CDN links — no Bearer token needed.
        // Redirects are resolved manually so every hop can be checked for SSRF.
        long fileSize = 0;
        string contentType = fileType ?? "audio/mpeg";
        string finalUrl = audioUrl!;

        try
        {
            var headClient = _httpClientFactory.CreateClient("AudioHead");
            var resolved = await ResolveAudioHeadAsync(headClient, audioUrl);
            if (resolved == null)
            {
                return new ObjectResult(new { error = "Unsafe audio URL" })
                {
                    StatusCode = StatusCodes.Status400BadRequest
                };
            }

            finalUrl = resolved.FinalUrl;
            if (resolved.FileSize > 0)
            {
                fileSize = resolved.FileSize;
            }
            if (!string.IsNullOrEmpty(resolved.ContentType))
            {
                contentType = resolved.ContentType;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "AudioInfo: HEAD request failed for {Url}", audioUrl);
            // Non-fatal — return what we have without file size
        }

        var result = new
        {
            uuid,
            audioUrl = finalUrl,
            fileSize,
            duration,
            contentType,
            requiresAuth,
            title,
            podcastTitle,
            podcastUuid,
            summary,
            published
        };

        // Cache the result
        var ttl = requiresAuth ? PremiumCacheTtl : StandardCacheTtl;
        _cache[cacheKey] = new AudioInfoCacheEntry(result, DateTime.UtcNow + ttl);

        // Evict expired entries periodically (simple inline eviction)
        if (_cache.Count > 200)
        {
            foreach (var key in _cache.Keys)
            {
                if (_cache.TryGetValue(key, out var entry) && entry.ExpiresAt < DateTime.UtcNow)
                    _cache.TryRemove(key, out _);
            }
        }

        _logger.LogInformation("AudioInfo: {Uuid} → {FileSize} bytes, {ContentType}, requiresAuth={RequiresAuth}",
            uuid, fileSize, contentType, requiresAuth);

        return new OkObjectResult(result);
    }

    /// <summary>
    /// Detects SupportingCast premium URLs that embed JWT tokens with timestamps.
    /// These URLs expire and should be re-fetched before each download.
    /// </summary>
    private static bool IsPremiumUrl(string url)
    {
        return url.Contains("supportingcast.fm/content/", StringComparison.OrdinalIgnoreCase) ||
               (url.Contains("|") && url.Contains("supportingcast", StringComparison.OrdinalIgnoreCase));
    }

    private static string CreateCacheKey(string uuid, string token)
    {
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return $"{uuid}:{Convert.ToHexString(digest.AsSpan(0, 8))}";
    }

    private async Task<ResolvedAudioHead?> ResolveAudioHeadAsync(
        HttpClient client,
        string audioUrl)
    {
        if (!Uri.TryCreate(audioUrl, UriKind.Absolute, out var current))
            return null;

        for (var redirectCount = 0; redirectCount <= 10; redirectCount++)
        {
            if (!await IsSafePublicUriAsync(current))
            {
                _logger.LogWarning("AudioInfo: blocked unsafe audio URL host {Host}",
                    current.Host);
                return null;
            }

            using var request = new HttpRequestMessage(HttpMethod.Head, current);
            using var response = await client.SendAsync(request);

            if (IsRedirect(response.StatusCode))
            {
                var location = response.Headers.Location;
                if (location == null)
                    return null;
                current = location.IsAbsoluteUri
                    ? location
                    : new Uri(current, location);
                continue;
            }

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "AudioInfo: HEAD request returned {StatusCode} for {Url}",
                    response.StatusCode,
                    current);
                return new ResolvedAudioHead(current.ToString(), 0, "");
            }

            return new ResolvedAudioHead(
                current.ToString(),
                response.Content.Headers.ContentLength ?? 0,
                response.Content.Headers.ContentType?.MediaType ?? "");
        }

        _logger.LogWarning("AudioInfo: redirect limit exceeded for {Url}", audioUrl);
        return null;
    }

    private static bool IsRedirect(HttpStatusCode statusCode)
    {
        return statusCode is HttpStatusCode.MovedPermanently
            or HttpStatusCode.Redirect
            or HttpStatusCode.RedirectMethod
            or HttpStatusCode.TemporaryRedirect
            or HttpStatusCode.PermanentRedirect;
    }

    private static async Task<bool> IsSafePublicUriAsync(Uri uri)
    {
        if (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)
            return false;
        if (string.IsNullOrWhiteSpace(uri.Host))
            return false;

        return await NetworkGuard.IsPublicHostAsync(uri.DnsSafeHost);
    }

    private record AudioInfoCacheEntry(object Response, DateTime ExpiresAt);
    private record ResolvedAudioHead(
        string FinalUrl,
        long FileSize,
        string ContentType);
}
