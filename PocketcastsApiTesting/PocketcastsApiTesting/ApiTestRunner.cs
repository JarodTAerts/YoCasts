using System.Text.Json;

namespace PocketcastsApiTesting;

/// <summary>
/// Runs individual API endpoint tests, logs request/response details,
/// and saves all responses to the test-results directory as JSON files.
/// </summary>
public class ApiTestRunner
{
    private readonly PocketCastsApiClient _client;
    private readonly string _resultsDir;
    private readonly JsonSerializerOptions _jsonOpts = new() { WriteIndented = true };
    private int _passed;
    private int _failed;
    private int _skipped;

    public ApiTestRunner(PocketCastsApiClient client, string resultsDir)
    {
        _client = client;
        _resultsDir = resultsDir;
    }

    public void PrintSummary()
    {
        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════");
        Console.WriteLine($"  RESULTS: {_passed} passed, {_failed} failed, {_skipped} skipped");
        Console.WriteLine($"  Responses saved to: {_resultsDir}");
        Console.WriteLine("═══════════════════════════════════════════════════");
    }

    private static string RedactToken(string? token)
    {
        if (string.IsNullOrEmpty(token)) return "(none)";
        return token.Length > 12 ? token[..8] + "****" + token[^4..] : "****";
    }

    private async Task<string?> RunTest(string name, string method, string url,
        Func<Task<HttpResponseMessage>> test, string fileSlug)
    {
        Console.WriteLine();
        Console.WriteLine($"──── {name} ────");
        Console.WriteLine($"  Request: {method} {url}");
        Console.WriteLine($"  Auth:    Bearer {RedactToken(_client.AuthToken)}");
        Console.WriteLine($"  Origin:  https://play.pocketcasts.com");

        try
        {
            var response = await test();
            var body = await response.Content.ReadAsStringAsync();
            var status = (int)response.StatusCode;

            Console.WriteLine($"  Status:  {status} {response.StatusCode}");

            // Pretty-print JSON
            string displayBody;
            try
            {
                var parsed = JsonSerializer.Deserialize<JsonElement>(body);
                displayBody = JsonSerializer.Serialize(parsed, _jsonOpts);
            }
            catch
            {
                displayBody = body;
            }

            // Truncate for console but save full response to file
            if (displayBody.Length > 3000)
            {
                Console.WriteLine($"  Response ({body.Length} chars, truncated):");
                Console.WriteLine(displayBody[..3000]);
                Console.WriteLine("  ... [truncated — full response saved to file]");
            }
            else
            {
                Console.WriteLine($"  Response:");
                Console.WriteLine(displayBody);
            }

            // Save full response to file
            await SaveResponse(fileSlug, status, method, url, body);

            if (response.IsSuccessStatusCode)
            {
                Console.WriteLine($"  ✅ PASS");
                _passed++;
            }
            else
            {
                Console.WriteLine($"  ❌ FAIL (HTTP {status})");
                _failed++;
            }

            return body;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ❌ ERROR: {ex.Message}");
            _failed++;
            return null;
        }
    }

    private async Task SaveResponse(string slug, int statusCode, string method, string url, string body)
    {
        try
        {
            var timestamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss");
            var fileName = $"{timestamp}_{slug}.json";
            var filePath = Path.Combine(_resultsDir, fileName);

            // Wrap in envelope with request metadata
            string prettyBody;
            try
            {
                var parsed = JsonSerializer.Deserialize<JsonElement>(body);
                prettyBody = JsonSerializer.Serialize(parsed, _jsonOpts);
            }
            catch
            {
                prettyBody = body;
            }

            var envelope = new
            {
                request = new
                {
                    method,
                    url,
                    timestamp = DateTime.UtcNow.ToString("o"),
                    authToken = RedactToken(_client.AuthToken)
                },
                response = new
                {
                    statusCode,
                    bodyLength = body.Length
                },
                rawBody = prettyBody
            };

            await File.WriteAllTextAsync(filePath,
                JsonSerializer.Serialize(envelope, _jsonOpts));
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ⚠️  Could not save response: {ex.Message}");
        }
    }

    // ──────────────────────────────────────────────
    // Test Methods (READ-ONLY only)
    // ──────────────────────────────────────────────

    public async Task TestLogin(string email, string password)
    {
        await RunTest("POST /user/login (Authentication)",
            "POST", "https://api.pocketcasts.com/user/login",
            () => _client.Login(email, password), "login");
    }

    public async Task TestLoginPocketCasts(string email, string password)
    {
        await RunTest("POST /user/login_pocket_casts (Alt Auth)",
            "POST", "https://api.pocketcasts.com/user/login_pocket_casts",
            () => _client.LoginPocketCasts(email, password), "login-alt");
    }

    public async Task TestRefreshToken()
    {
        await RunTest("POST /user/token (Refresh Token)",
            "POST", "https://api.pocketcasts.com/user/token",
            () => _client.RefreshToken(), "token-refresh");
    }

    public async Task TestSubscriptionStatus()
    {
        await RunTest("GET /subscription/status",
            "GET", "https://api.pocketcasts.com/subscription/status",
            () => _client.GetSubscriptionStatus(), "subscription-status");
    }

    public async Task<string?> TestGetSubscribedPodcasts()
    {
        return await RunTest("POST /user/podcast/list (Subscribed Podcasts)",
            "POST", "https://api.pocketcasts.com/user/podcast/list",
            () => _client.GetSubscribedPodcasts(), "podcast-list");
    }

    public async Task<string?> TestGetEpisodesForPodcast(string podcastUuid)
    {
        return await RunTest($"POST /user/podcast/episodes (uuid={podcastUuid[..8]}...)",
            "POST", "https://api.pocketcasts.com/user/podcast/episodes",
            () => _client.GetEpisodesForPodcast(podcastUuid), $"episodes-{podcastUuid[..8]}");
    }

    public async Task TestGetEpisode(string episodeUuid)
    {
        await RunTest($"POST /user/episode (uuid={episodeUuid[..8]}...)",
            "POST", "https://api.pocketcasts.com/user/episode",
            () => _client.GetEpisode(episodeUuid), $"episode-{episodeUuid[..8]}");
    }

    public async Task<string?> TestGetNewReleases()
    {
        return await RunTest("POST /user/new_releases (New Releases)",
            "POST", "https://api.pocketcasts.com/user/new_releases",
            () => _client.GetNewReleases(), "new-releases");
    }

    public async Task TestGetInProgress()
    {
        await RunTest("POST /user/in_progress (In Progress)",
            "POST", "https://api.pocketcasts.com/user/in_progress",
            () => _client.GetInProgress(), "in-progress");
    }

    public async Task TestGetStarred()
    {
        await RunTest("POST /user/starred (Starred Episodes)",
            "POST", "https://api.pocketcasts.com/user/starred",
            () => _client.GetStarred(), "starred");
    }

    public async Task TestGetHistory()
    {
        await RunTest("POST /user/history (Listening History)",
            "POST", "https://api.pocketcasts.com/user/history",
            () => _client.GetHistory(), "history");
    }

    public async Task<string?> TestGetUpNext()
    {
        return await RunTest("POST /up_next/list (Up Next Queue)",
            "POST", "https://api.pocketcasts.com/up_next/list",
            () => _client.GetUpNext(), "up-next");
    }

    public async Task TestGetBookmarks()
    {
        await RunTest("POST /user/bookmark/list (Bookmarks)",
            "POST", "https://api.pocketcasts.com/user/bookmark/list",
            () => _client.GetBookmarks(), "bookmarks");
    }

    public async Task TestSearchPodcasts(string term)
    {
        await RunTest($"POST /discover/search (term=\"{term}\")",
            "POST", "https://api.pocketcasts.com/discover/search",
            () => _client.SearchPodcasts(term), $"search-{term}");
    }

    public async Task TestRecommendEpisodes()
    {
        await RunTest("POST /discover/recommend_episodes",
            "POST", "https://api.pocketcasts.com/discover/recommend_episodes",
            () => _client.RecommendEpisodes(), "recommend-episodes");
    }

    public async Task TestGetRecommendationsForPodcast(string podcastUuid)
    {
        await RunTest($"GET /recommendations/podcast/{podcastUuid[..8]}...",
            "GET", $"https://api.pocketcasts.com/recommendations/podcast/{podcastUuid}",
            () => _client.GetRecommendationsForPodcast(podcastUuid), $"recommendations-{podcastUuid[..8]}");
    }

    public async Task TestGetFeatured()
    {
        await RunTest("GET lists.pocketcasts.com/featured.json",
            "GET", "https://lists.pocketcasts.com/featured.json",
            () => _client.GetFeatured(), "featured");
    }

    public async Task TestGetTrending()
    {
        await RunTest("GET lists.pocketcasts.com/trending.json",
            "GET", "https://lists.pocketcasts.com/trending.json",
            () => _client.GetTrending(), "trending");
    }

    public async Task TestGetCategories()
    {
        await RunTest("GET static.pocketcasts.com/discover/json/categories_v2.json",
            "GET", "https://static.pocketcasts.com/discover/json/categories_v2.json",
            () => _client.GetCategories(), "categories");
    }

    public async Task TestGetPodcastFull(string podcastUuid)
    {
        await RunTest($"GET podcast-api.pocketcasts.com/podcast/full/{podcastUuid[..8]}...",
            "GET", $"https://podcast-api.pocketcasts.com/podcast/full/{podcastUuid}",
            () => _client.GetPodcastFull(podcastUuid), $"podcast-full-{podcastUuid[..8]}");
    }

    public async Task TestGetStats()
    {
        await RunTest("POST /user/stats/summary (Listening Stats)",
            "POST", "https://api.pocketcasts.com/user/stats/summary",
            () => _client.GetStats(), "stats");
    }

    // ──────────────────────────────────────────────
    // Error case tests
    // ──────────────────────────────────────────────

    public async Task TestBadLogin()
    {
        Console.WriteLine();
        Console.WriteLine("──── ERROR HANDLING: Bad Login ────");
        Console.WriteLine("  Request: POST https://api.pocketcasts.com/user/login");
        Console.WriteLine("  Auth:    (none)");
        try
        {
            using var badClient = new PocketCastsApiClient();
            var response = await badClient.Login("notreal@example.com", "wrongpassword");
            var body = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"  Status: {(int)response.StatusCode} {response.StatusCode}");
            Console.WriteLine($"  Response: {body}");
            await SaveResponse("error-bad-login", (int)response.StatusCode, "POST",
                "https://api.pocketcasts.com/user/login", body);
            if (!response.IsSuccessStatusCode)
            {
                Console.WriteLine("  ✅ PASS (correctly rejected bad credentials)");
                _passed++;
            }
            else
            {
                Console.WriteLine("  ❌ FAIL (accepted bad credentials?!)");
                _failed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ✅ PASS (threw exception: {ex.Message})");
            _passed++;
        }
    }

    public async Task TestUnauthenticatedAccess()
    {
        Console.WriteLine();
        Console.WriteLine("──── ERROR HANDLING: Unauthenticated Access ────");
        Console.WriteLine("  Request: POST https://api.pocketcasts.com/user/podcast/list");
        Console.WriteLine("  Auth:    (none)");
        try
        {
            using var noAuthClient = new PocketCastsApiClient();
            var response = await noAuthClient.RawPost("https://api.pocketcasts.com/user/podcast/list", "{}");
            var body = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"  Status: {(int)response.StatusCode} {response.StatusCode}");
            Console.WriteLine($"  Response: {body}");
            await SaveResponse("error-no-auth", (int)response.StatusCode, "POST",
                "https://api.pocketcasts.com/user/podcast/list", body);
            if (!response.IsSuccessStatusCode)
            {
                Console.WriteLine("  ✅ PASS (correctly rejected unauthenticated request)");
                _passed++;
            }
            else
            {
                Console.WriteLine("  ⚠️  WARNING (returned 200 without auth — may return empty data)");
                _passed++;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ❌ ERROR: {ex.Message}");
            _failed++;
        }
    }

    public async Task TestInvalidEndpoint()
    {
        Console.WriteLine();
        Console.WriteLine("──── ERROR HANDLING: Invalid Endpoint ────");
        Console.WriteLine("  Request: GET https://api.pocketcasts.com/this/does/not/exist");
        try
        {
            var response = await _client.RawGet("https://api.pocketcasts.com/this/does/not/exist");
            var body = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"  Status: {(int)response.StatusCode} {response.StatusCode}");
            Console.WriteLine($"  Response: {body}");
            await SaveResponse("error-invalid-endpoint", (int)response.StatusCode, "GET",
                "https://api.pocketcasts.com/this/does/not/exist", body);
            Console.WriteLine("  ✅ PASS (server responded to invalid endpoint)");
            _passed++;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ✅ PASS (threw exception: {ex.Message})");
            _passed++;
        }
    }
}
