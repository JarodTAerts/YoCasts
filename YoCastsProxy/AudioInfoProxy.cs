using System.Net;
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
/// Returns: { audioUrl, fileSize, contentType, duration, title, podcastUuid }
/// </summary>
public class AudioInfoProxy
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<AudioInfoProxy> _logger;

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
            episodeResponse = await pocketCastsClient.SendAsync(episodeRequest);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AudioInfo: failed to fetch episode metadata");
            return new ObjectResult(new { error = "Failed to fetch episode metadata" })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }

        if (!episodeResponse.IsSuccessStatusCode)
        {
            var errorBody = await episodeResponse.Content.ReadAsStringAsync();
            _logger.LogWarning("AudioInfo: PocketCasts returned {StatusCode} for episode {Uuid}",
                episodeResponse.StatusCode, uuid);
            return new ContentResult
            {
                Content = errorBody,
                ContentType = "application/json",
                StatusCode = (int)episodeResponse.StatusCode
            };
        }

        var episodeJson = await episodeResponse.Content.ReadAsStringAsync();
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
        var fileType = episodeData.TryGetProperty("fileType", out var ftProp)
            ? ftProp.GetString() : "";

        if (string.IsNullOrEmpty(audioUrl))
        {
            return new ObjectResult(new { error = "No audio URL found for episode", uuid })
            {
                StatusCode = StatusCodes.Status404NotFound
            };
        }

        // Step 2: HEAD request to the audio URL to get real file size
        // Audio URLs are public CDN links — no auth needed.
        // The HEAD client follows redirects automatically.
        long fileSize = 0;
        string contentType = fileType ?? "audio/mpeg";
        string finalUrl = audioUrl!;

        try
        {
            using var headClient = _httpClientFactory.CreateClient("AudioHead");
            var headRequest = new HttpRequestMessage(HttpMethod.Head, audioUrl);
            var headResponse = await headClient.SendAsync(headRequest);

            if (headResponse.IsSuccessStatusCode)
            {
                if (headResponse.Content.Headers.ContentLength.HasValue)
                {
                    fileSize = headResponse.Content.Headers.ContentLength.Value;
                }
                if (headResponse.Content.Headers.ContentType?.MediaType != null)
                {
                    contentType = headResponse.Content.Headers.ContentType.MediaType;
                }
                // Capture final URL after redirects
                if (headResponse.RequestMessage?.RequestUri != null)
                {
                    finalUrl = headResponse.RequestMessage.RequestUri.ToString();
                }
            }
            else
            {
                _logger.LogWarning("AudioInfo: HEAD request returned {StatusCode} for {Url}",
                    headResponse.StatusCode, audioUrl);
                // Non-fatal — we still have the URL and can try downloading
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "AudioInfo: HEAD request failed for {Url}", audioUrl);
            // Non-fatal — return what we have without file size
        }

        var result = new
        {
            audioUrl = finalUrl,
            fileSize,
            contentType,
            duration,
            title,
            podcastUuid,
            episodeUuid = uuid
        };

        _logger.LogInformation("AudioInfo: {Uuid} → {FileSize} bytes, {ContentType}",
            uuid, fileSize, contentType);

        return new OkObjectResult(result);
    }
}
