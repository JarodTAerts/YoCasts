using System.Collections.Concurrent;
using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace YoCastsProxy;

/// <summary>
/// Transparent proxy for PocketCasts API that strips heavy fields to fit
/// within Garmin's ~32-44 KB makeWebRequest response limit.
/// Auth token comes from the Garmin watch — the proxy stores nothing.
/// </summary>
public class PocketCastsProxy
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<PocketCastsProxy> _logger;

    public PocketCastsProxy(IHttpClientFactory httpClientFactory, ILogger<PocketCastsProxy> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    [Function("PocketCastsProxy")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = "pocketcasts/{*path}")] HttpRequest req,
        string path)
    {
        _logger.LogInformation("Proxying {Method} /{Path}", req.Method, path);

        // Extract Bearer token from incoming request
        var authHeader = req.Headers.Authorization.FirstOrDefault();
        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return new ObjectResult(new { error = "Missing or invalid Bearer token" })
            {
                StatusCode = StatusCodes.Status401Unauthorized
            };
        }

        var client = _httpClientFactory.CreateClient("PocketCasts");

        // Build upstream request
        var upstreamUrl = $"/{path}";
        var upstream = new HttpRequestMessage(new HttpMethod(req.Method), upstreamUrl);
        upstream.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
            "Bearer", authHeader["Bearer ".Length..]);

        // Forward request body for POST
        if (req.Method.Equals("POST", StringComparison.OrdinalIgnoreCase))
        {
            using var reader = new StreamReader(req.Body);
            var body = await reader.ReadToEndAsync();
            upstream.Content = new StringContent(
                string.IsNullOrWhiteSpace(body) ? "{}" : body,
                System.Text.Encoding.UTF8,
                "application/json");
        }

        // Send to PocketCasts
        HttpResponseMessage response;
        try
        {
            response = await client.SendAsync(upstream);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to reach PocketCasts API");
            return new ObjectResult(new { error = "Failed to reach PocketCasts API" })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }

        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            return new ContentResult
            {
                Content = responseBody,
                ContentType = "application/json",
                StatusCode = (int)response.StatusCode
            };
        }

        // Strip fields based on the path
        var stripped = await StripFields(path, responseBody);

        _logger.LogInformation("/{Path}: {OriginalSize} bytes → {StrippedSize} bytes",
            path, responseBody.Length, stripped.Length);

        return new ContentResult
        {
            Content = stripped,
            ContentType = "application/json",
            StatusCode = (int)response.StatusCode
        };
    }

    private async Task<string> StripFields(string path, string json)
    {
        var normalizedPath = path.TrimStart('/').ToLowerInvariant();

        try
        {
            return normalizedPath switch
            {
                "user/podcast/list" => await StripAndEnrichPodcastList(json),
                "user/episode" => StripEpisodeDetail(json),
                _ => StripGenericDescriptions(json)
            };
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Failed to parse JSON for stripping on /{Path}, returning raw", path);
            return json;
        }
    }

    /// <summary>
    /// For /user/podcast/list — keep only fields the Garmin watch needs,
    /// then enrich each podcast with art colors from PocketCasts' static metadata.
    /// </summary>
    private async Task<string> StripAndEnrichPodcastList(string json)
    {
        var doc = JsonNode.Parse(json);
        if (doc is not JsonObject root) return json;

        var podcasts = root["podcasts"]?.AsArray();
        if (podcasts == null) return json;

        var keepFields = new HashSet<string>
        {
            "uuid", "title", "author", "lastEpisodePublished",
            "unplayed", "lastEpisodeUuid", "folderUuid",
            "sortPosition", "dateAdded", "url", "episodesSortOrder"
        };

        var stripped = new JsonArray();
        foreach (var podcast in podcasts)
        {
            if (podcast is not JsonObject podObj) continue;
            var slim = new JsonObject();
            foreach (var field in keepFields)
            {
                if (podObj[field] != null)
                    slim[field] = podObj[field]!.DeepClone();
            }
            stripped.Add(slim);
        }

        root["podcasts"] = stripped;

        // Enrich with art colors in parallel
        var staticClient = _httpClientFactory.CreateClient("PocketCastsStatic");
        var colorTasks = new List<Task>();

        foreach (var podcast in stripped)
        {
            if (podcast is not JsonObject podObj) continue;
            var uuid = podObj["uuid"]?.GetValue<string>();
            if (string.IsNullOrEmpty(uuid)) continue;

            colorTasks.Add(EnrichPodcastWithColors(staticClient, podObj, uuid));
        }

        await Task.WhenAll(colorTasks);

        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }

    /// <summary>
    /// Fetches color metadata for a single podcast and adds artColor, artTint, artUrl fields.
    /// Failures are silently ignored — the podcast just won't have color data.
    /// </summary>
    private async Task EnrichPodcastWithColors(HttpClient staticClient, JsonObject podObj, string uuid)
    {
        try
        {
            // Check in-memory cache first
            if (_artColorCache.TryGetValue(uuid, out var cached) &&
                cached.FetchedAt > DateTime.UtcNow.AddDays(-7))
            {
                podObj["artColor"] = cached.Background;
                podObj["artTint"] = cached.Tint;
                podObj["artUrl"] = $"https://static.pocketcasts.com/discover/images/webp/200/{uuid}.webp";
                return;
            }

            var metadataJson = await staticClient.GetStringAsync(
                $"/discover/images/metadata/{uuid}.json");
            var metaDoc = JsonNode.Parse(metadataJson);
            var colors = metaDoc?["colors"];
            if (colors == null) return;

            var background = colors["background"]?.GetValue<string>() ?? "#000000";
            var tint = colors["tintForDarkBg"]?.GetValue<string>() ?? "#FFFFFF";

            // Cache for future requests (survives within Azure Function instance lifetime)
            _artColorCache[uuid] = new ArtColorEntry(background, tint, DateTime.UtcNow);

            podObj["artColor"] = background;
            podObj["artTint"] = tint;
            podObj["artUrl"] = $"https://static.pocketcasts.com/discover/images/webp/200/{uuid}.webp";
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to fetch art colors for podcast {Uuid}", uuid);
        }
    }

    private static readonly ConcurrentDictionary<string, ArtColorEntry> _artColorCache = new();
    private record ArtColorEntry(string Background, string Tint, DateTime FetchedAt);

    /// <summary>
    /// For /user/episode — strip description/notes, keep playback-relevant fields.
    /// </summary>
    private static string StripEpisodeDetail(string json)
    {
        var doc = JsonNode.Parse(json);
        if (doc is not JsonObject root) return json;

        var removeFields = new[] { "description", "descriptionHtml", "notes", "showNotes" };
        foreach (var field in removeFields)
            root.Remove(field);

        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }

    /// <summary>
    /// Generic fallback: strip description/descriptionHtml from any response.
    /// Handles both top-level objects and arrays of objects.
    /// </summary>
    private static string StripGenericDescriptions(string json)
    {
        var doc = JsonNode.Parse(json);
        if (doc == null) return json;

        var fieldsToRemove = new[] { "description", "descriptionHtml" };

        if (doc is JsonObject obj)
        {
            StripFieldsRecursive(obj, fieldsToRemove);
        }
        else if (doc is JsonArray arr)
        {
            foreach (var item in arr)
            {
                if (item is JsonObject itemObj)
                    StripFieldsRecursive(itemObj, fieldsToRemove);
            }
        }

        return doc.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }

    private static void StripFieldsRecursive(JsonObject obj, string[] fieldsToRemove)
    {
        foreach (var field in fieldsToRemove)
            obj.Remove(field);

        // Check nested arrays (e.g., "podcasts", "episodes", "order")
        foreach (var prop in obj.ToArray())
        {
            if (prop.Value is JsonObject nested)
            {
                StripFieldsRecursive(nested, fieldsToRemove);
            }
            else if (prop.Value is JsonArray arr)
            {
                foreach (var item in arr)
                {
                    if (item is JsonObject itemObj)
                        StripFieldsRecursive(itemObj, fieldsToRemove);
                }
            }
        }
    }
}
