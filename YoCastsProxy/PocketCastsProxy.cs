using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
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
    private const int MaxUpstreamResponseBytes = 2 * 1024 * 1024;
    private const int MaxMetadataResponseBytes = 4 * 1024 * 1024;
    private const int MaxLocationResponseBytes = 64 * 1024;
    private const int MaxRequestBodyBytes = 64 * 1024;
    private const int MaxPodcastCount = 30;
    private const int MaxGarminResponseBytes = 28 * 1024;

    private static readonly HashSet<string> AllowedPaths =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "user/podcast/list",
            "user/podcast/episodes",
            "yocasts/podcast/episodes",
            "user/episode",
            "yocasts/episode/details",
            "user/in_progress",
            "up_next/list",
            "up_next/play_last",
            "up_next/remove",
            "sync/update_episode"
        };

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

        var normalizedPath = path.Trim('/').ToLowerInvariant();
        if (!AllowedPaths.Contains(normalizedPath))
        {
            return new NotFoundObjectResult(new { error = "Unsupported proxy path" });
        }

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
        var upstreamPath = normalizedPath == "yocasts/episode/details"
            ? "user/episode"
            : normalizedPath == "yocasts/podcast/episodes"
                ? "user/podcast/episodes"
                : normalizedPath;
        var upstreamUrl = $"/{upstreamPath}";
        var upstream = new HttpRequestMessage(new HttpMethod(req.Method), upstreamUrl);
        upstream.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
            "Bearer", authHeader["Bearer ".Length..]);

        var requestBody = "{}";
        // Forward request body for POST
        if (req.Method.Equals("POST", StringComparison.OrdinalIgnoreCase))
        {
            if (req.ContentLength > MaxRequestBodyBytes)
            {
                return new ObjectResult(new { error = "Request body too large" })
                {
                    StatusCode = StatusCodes.Status413PayloadTooLarge
                };
            }
            try
            {
                requestBody = await ReadLimitedRequestBodyAsync(
                    req.Body,
                    req.HttpContext.RequestAborted);
            }
            catch (InvalidDataException)
            {
                return new ObjectResult(new { error = "Request body too large" })
                {
                    StatusCode = StatusCodes.Status413PayloadTooLarge
                };
            }
            upstream.Content = new StringContent(
                string.IsNullOrWhiteSpace(requestBody) ? "{}" : requestBody,
                System.Text.Encoding.UTF8,
                "application/json");
        }

        // Send to PocketCasts
        HttpResponseMessage response;
        string responseBody;
        try
        {
            response = await client.SendAsync(
                upstream,
                HttpCompletionOption.ResponseHeadersRead);
            responseBody = await ContentText.ReadLimitedStringAsync(
                response.Content,
                MaxUpstreamResponseBytes);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to reach PocketCasts API");
            return new ObjectResult(new { error = "Failed to reach PocketCasts API" })
            {
                StatusCode = StatusCodes.Status502BadGateway
            };
        }
        using var responseLease = response;

        if (!response.IsSuccessStatusCode)
        {
            return new ContentResult
            {
                Content = responseBody,
                ContentType = "application/json",
                StatusCode = (int)response.StatusCode
            };
        }

        var stripped = normalizedPath == "yocasts/podcast/episodes"
            ? await BuildCompactEpisodeList(responseBody, requestBody)
            : await StripFields(path, responseBody);

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
                "user/episode" => StripEpisodeDetail(json, 700),
                "yocasts/episode/details" =>
                    await EnrichEpisodeDetails(json),
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
        foreach (var podcast in podcasts.Take(MaxPodcastCount))
        {
            if (podcast is not JsonObject podObj) continue;
            var slim = new JsonObject();
            foreach (var field in keepFields)
            {
                if (podObj[field] != null)
                    slim[field] = podObj[field]!.DeepClone();
            }
            var description = ContentText.FirstText(
                podObj,
                "description",
                "descriptionHtml");
            slim["description"] = ContentText.Compact(description, 480);
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

        var options = new JsonSerializerOptions { WriteIndented = false };
        var result = root.ToJsonString(options);
        if (System.Text.Encoding.UTF8.GetByteCount(result) <=
            MaxGarminResponseBytes)
            return result;

        foreach (var podcast in stripped.OfType<JsonObject>())
        {
            var description = podcast["description"]?.GetValue<string>() ?? "";
            podcast["description"] = ContentText.Compact(description, 160);
        }
        result = root.ToJsonString(options);
        while (stripped.Count > 0 &&
               System.Text.Encoding.UTF8.GetByteCount(result) >
                   MaxGarminResponseBytes)
        {
            stripped.RemoveAt(stripped.Count - 1);
            result = root.ToJsonString(options);
        }
        return result;
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
    /// For /user/episode — collapse HTML show notes into bounded plain text.
    /// </summary>
    private static string StripEpisodeDetail(string json, int summaryLimit)
    {
        var doc = JsonNode.Parse(json);
        if (doc is not JsonObject root) return json;

        var summary = ContentText.FirstText(
            root,
            "showNotes",
            "descriptionHtml",
            "description",
            "notes");
        root["summary"] = ContentText.Compact(summary, summaryLimit);
        var removeFields = new[] { "description", "descriptionHtml", "notes", "showNotes" };
        foreach (var field in removeFields)
            root.Remove(field);

        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }

    private async Task<string> EnrichEpisodeDetails(string json)
    {
        var doc = JsonNode.Parse(json);
        if (doc is not JsonObject root) return json;

        var episodeUuid = root["uuid"]?.GetValue<string>();
        var podcastUuid = root["podcastUuid"]?.GetValue<string>();
        if (!string.IsNullOrWhiteSpace(episodeUuid) &&
            !string.IsNullOrWhiteSpace(podcastUuid))
        {
            try
            {
                var cacheClient =
                    _httpClientFactory.CreateClient("PocketCastsPodcastCache");
                var locationUri = new Uri(
                    cacheClient.BaseAddress!,
                    $"/mobile/show_notes/full/{podcastUuid}?disableredirect=true");
                var locationJson = await ContentText.GetLimitedStringAsync(
                    cacheClient,
                    locationUri,
                    MaxLocationResponseBytes);
                var location = JsonNode.Parse(locationJson)?["url"]
                    ?.GetValue<string>();

                if (Uri.TryCreate(location, UriKind.Absolute, out var notesUri) &&
                    notesUri.Scheme == Uri.UriSchemeHttps &&
                    IsPocketCastsShowNotesHost(notesUri.Host))
                {
                    var notesClient = _httpClientFactory.CreateClient(
                        "PocketCastsShowNotes");
                    var notesJson = await ContentText.GetLimitedStringAsync(
                        notesClient,
                        notesUri,
                        MaxMetadataResponseBytes);
                    var episodes = JsonNode.Parse(notesJson)?["podcast"]
                        ?["episodes"]?.AsArray();
                    var match = episodes?
                        .OfType<JsonObject>()
                        .FirstOrDefault(episode =>
                            episode["uuid"]?.GetValue<string>() == episodeUuid);
                    var showNotes = match?["show_notes"]?.GetValue<string>();
                    if (!string.IsNullOrWhiteSpace(showNotes))
                        root["summary"] = ContentText.Compact(showNotes, 5000);
                }

            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Failed to enrich show notes for episode {EpisodeUuid}",
                    episodeUuid);
            }
        }

        // Fall back to any notes embedded in the episode response.
        var fallback = ContentText.FirstText(
            root,
            "summary",
            "showNotes",
            "descriptionHtml",
            "description",
            "notes");
        root["summary"] = ContentText.Compact(fallback, 5000);
        foreach (var field in new[]
                 { "description", "descriptionHtml", "notes", "showNotes" })
            root.Remove(field);

        return root.ToJsonString(new JsonSerializerOptions
        {
            WriteIndented = false
        });
    }

    private async Task<string> BuildCompactEpisodeList(
        string json,
        string requestBody)
    {
        var root = JsonNode.Parse(json) as JsonObject;
        var states = root?["episodes"]?.AsArray();
        if (states == null)
            return """{"episodes":[]}""";

        var podcastUuid = (JsonNode.Parse(requestBody) as JsonObject)?
            ["uuid"]?.GetValue<string>() ?? "";
        var podcastTitle = "";
        var detailsByUuid =
            new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        var metadataOrder = new List<JsonObject>();
        if (!string.IsNullOrWhiteSpace(podcastUuid))
        {
            try
            {
                var cacheClient = _httpClientFactory.CreateClient(
                    "PocketCastsPodcastCache");
                var metadataJson = await GetPodcastMetadataJson(
                    cacheClient,
                    podcastUuid);
                var metadata = JsonNode.Parse(metadataJson)?["podcast"]
                    as JsonObject;
                podcastTitle = metadata?["title"]?.GetValue<string>() ?? "";
                var metadataEpisodes = metadata?["episodes"]?.AsArray();
                if (metadataEpisodes != null)
                {
                    foreach (var episode in metadataEpisodes.OfType<JsonObject>())
                    {
                        var uuid = episode["uuid"]?.GetValue<string>();
                        if (!string.IsNullOrWhiteSpace(uuid))
                        {
                            detailsByUuid[uuid] = episode;
                            metadataOrder.Add(episode);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Failed to fetch full podcast metadata for {PodcastUuid}",
                    podcastUuid);
            }
        }

        var statesByUuid = states
            .OfType<JsonObject>()
            .Where(state =>
                !string.IsNullOrWhiteSpace(
                    state["uuid"]?.GetValue<string>()))
            .ToDictionary(
                state => state["uuid"]!.GetValue<string>(),
                StringComparer.Ordinal);

        JsonObject[] selectedDetails;
        if (metadataOrder.Count > 0)
        {
            selectedDetails = metadataOrder.Take(15).ToArray();
        }
        else
        {
            selectedDetails = statesByUuid.Values.Take(15).ToArray();
        }

        var episodes = selectedDetails.Select(detail =>
        {
            var uuid = detail["uuid"]?.GetValue<string>() ?? "";
            var state = statesByUuid.GetValueOrDefault(uuid) ??
                        new JsonObject();
            return BuildSlimEpisode(
                detail,
                state,
                uuid,
                podcastUuid,
                podcastTitle);
        }).ToArray();

        return new JsonObject
        {
            ["episodes"] = new JsonArray(
                episodes.Cast<JsonNode?>().ToArray())
        }.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }

    private static JsonObject BuildSlimEpisode(
        JsonObject detail,
        JsonObject state,
        string uuid,
        string podcastUuid,
        string podcastTitle)
    {
        var summary = ContentText.FirstText(
            detail,
            "showNotes",
            "descriptionHtml",
            "description",
            "notes");

        return new JsonObject
        {
            ["uuid"] = uuid,
            ["title"] = StringValue(detail, "title", "Episode"),
            ["duration"] = NumberValue(detail, state, "duration"),
            ["playedUpTo"] = NumberValue(state, detail, "playedUpTo"),
            ["playingStatus"] =
                NumberValue(state, detail, "playingStatus"),
            ["podcastUuid"] =
                StringValue(detail, "podcastUuid",
                    StringValue(detail, "podcast", podcastUuid)),
            ["podcastTitle"] =
                StringValue(detail, "podcastTitle", podcastTitle),
            ["starred"] = BooleanValue(state, detail, "starred"),
            ["isDeleted"] = BooleanValue(state, detail, "isDeleted"),
            ["summary"] = ContentText.Compact(summary, 700),
            ["published"] = StringValue(detail, "published", ""),
            ["url"] = StringValue(detail, "url", ""),
            ["fileType"] = StringValue(
                detail,
                "fileType",
                StringValue(detail, "file_type", "")),
            ["size"] = NodeString(
                detail["size"] ?? detail["file_size"])
        };
    }

    private static string StringValue(
        JsonObject source,
        string field,
        string fallback)
    {
        return source[field] is JsonValue value &&
               value.TryGetValue<string>(out var result) &&
               !string.IsNullOrWhiteSpace(result)
            ? result
            : fallback;
    }

    private static JsonNode NumberValue(
        JsonObject primary,
        JsonObject fallback,
        string field)
    {
        var node = primary[field] ?? fallback[field];
        return node?.DeepClone() ?? JsonValue.Create(0)!;
    }

    private static JsonNode BooleanValue(
        JsonObject primary,
        JsonObject fallback,
        string field)
    {
        var node = primary[field] ?? fallback[field];
        return node?.DeepClone() ?? JsonValue.Create(false)!;
    }

    private static string NodeString(JsonNode? node)
    {
        if (node is not JsonValue value)
            return "";
        if (value.TryGetValue<string>(out var text))
            return text;
        if (value.TryGetValue<long>(out var number))
            return number.ToString();
        return node.ToString();
    }

    private async Task<string> GetPodcastMetadataJson(
        HttpClient cacheClient,
        string podcastUuid)
    {
        using var response = await cacheClient.GetAsync(
            $"/podcast/full/{podcastUuid}",
            HttpCompletionOption.ResponseHeadersRead);
        if (response.IsSuccessStatusCode)
            return await ContentText.ReadLimitedStringAsync(
                response.Content,
                MaxMetadataResponseBytes);

        if (!IsRedirect(response.StatusCode) ||
            response.Headers.Location == null)
            throw new HttpRequestException(
                $"Podcast metadata returned {response.StatusCode}");

        var location = response.Headers.Location;
        if (!location.IsAbsoluteUri)
            location = new Uri(cacheClient.BaseAddress!, location);
        if (location.Scheme != Uri.UriSchemeHttps ||
            !IsPocketCastsPublicContentHost(location.Host))
            throw new HttpRequestException(
                "Podcast metadata redirected to an unsupported host");

        var contentClient = _httpClientFactory.CreateClient(
            "PocketCastsPublicContent");
        return await ContentText.GetLimitedStringAsync(
            contentClient,
            location,
            MaxMetadataResponseBytes);
    }

    private static bool IsRedirect(HttpStatusCode statusCode)
    {
        return statusCode is HttpStatusCode.MovedPermanently
            or HttpStatusCode.Redirect
            or HttpStatusCode.RedirectMethod
            or HttpStatusCode.TemporaryRedirect
            or HttpStatusCode.PermanentRedirect;
    }

    private static bool IsPocketCastsPublicContentHost(string host)
    {
        return host.Equals(
                   "podcasts.pocketcasts.com",
                   StringComparison.OrdinalIgnoreCase) ||
               host.EndsWith(
                   ".pocketcasts.com",
                   StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsPocketCastsShowNotesHost(string host)
    {
        return host.Equals("shownotes.pocketcasts.com",
                           StringComparison.OrdinalIgnoreCase) ||
               host.EndsWith(".pocketcasts.com",
                             StringComparison.OrdinalIgnoreCase);
    }

    private static async Task<string> ReadLimitedRequestBodyAsync(
        Stream stream,
        CancellationToken cancellationToken)
    {
        using var buffer = new MemoryStream();
        var chunk = new byte[4096];
        var total = 0;
        while (true)
        {
            var read = await stream.ReadAsync(chunk, cancellationToken);
            if (read == 0)
                break;
            total += read;
            if (total > MaxRequestBodyBytes)
                throw new InvalidDataException("Request body too large");
            await buffer.WriteAsync(
                chunk.AsMemory(0, read),
                cancellationToken);
        }
        return System.Text.Encoding.UTF8.GetString(buffer.ToArray());
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
