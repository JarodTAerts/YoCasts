using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace PocketcastsApiTesting;

/// <summary>
/// Low-level HTTP client for the PocketCasts API.
/// All methods return raw HttpResponseMessage for inspection by the test harness.
/// </summary>
public class PocketCastsApiClient : IDisposable
{
    private readonly HttpClient _http;
    private string? _authToken;

    private const string BaseUrl = "https://api.pocketcasts.com";
    private const string PodcastApiUrl = "https://podcast-api.pocketcasts.com";
    private const string ListsUrl = "https://lists.pocketcasts.com";
    private const string StaticUrl = "https://static.pocketcasts.com";

    public string? AuthToken => _authToken;
    public bool IsAuthenticated => !string.IsNullOrEmpty(_authToken);

    public PocketCastsApiClient()
    {
        _http = new HttpClient();
        _http.DefaultRequestHeaders.Add("Origin", "https://play.pocketcasts.com");
        _http.DefaultRequestHeaders.Add("User-Agent", "YoCasts-ApiTester/1.0");
    }

    private void EnsureAuth()
    {
        if (!IsAuthenticated)
            throw new InvalidOperationException("Not authenticated. Call Login() first.");
    }

    private StringContent JsonBody(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        return new StringContent(json, Encoding.UTF8, "application/json");
    }

    private StringContent EmptyJsonBody() => new StringContent("{}", Encoding.UTF8, "application/json");

    private void SetAuth()
    {
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _authToken);
    }

    // ──────────────────────────────────────────────
    // Authentication
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> Login(string email, string password)
    {
        var body = JsonBody(new { email, password, scope = "webplayer" });
        var response = await _http.PostAsync($"{BaseUrl}/user/login", body);
        if (response.IsSuccessStatusCode)
        {
            var json = await response.Content.ReadAsStringAsync();
            var auth = JsonSerializer.Deserialize<Models.AuthResponse>(json);
            _authToken = auth?.Token;
            SetAuth();
        }
        return response;
    }

    public async Task<HttpResponseMessage> LoginPocketCasts(string email, string password)
    {
        var body = JsonBody(new { email, password, scope = "webplayer" });
        return await _http.PostAsync($"{BaseUrl}/user/login_pocket_casts", body);
    }

    public async Task<HttpResponseMessage> RefreshToken()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/token", EmptyJsonBody());
    }

    // ──────────────────────────────────────────────
    // Subscription
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> GetSubscriptionStatus()
    {
        EnsureAuth();
        return await _http.GetAsync($"{BaseUrl}/subscription/status");
    }

    // ──────────────────────────────────────────────
    // Podcasts
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> GetSubscribedPodcasts()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/podcast/list", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> GetEpisodesForPodcast(string podcastUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/podcast/episodes", JsonBody(new { uuid = podcastUuid }));
    }

    public async Task<HttpResponseMessage> SubscribePodcast(string podcastUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/podcast/subscribe", JsonBody(new { uuid = podcastUuid }));
    }

    public async Task<HttpResponseMessage> UnsubscribePodcast(string podcastUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/podcast/unsubscribe", JsonBody(new { uuid = podcastUuid }));
    }

    public async Task<HttpResponseMessage> GetPodcastFull(string podcastUuid)
    {
        return await _http.GetAsync($"{PodcastApiUrl}/podcast/full/{podcastUuid}");
    }

    // ──────────────────────────────────────────────
    // Episodes
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> GetEpisode(string episodeUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/episode", JsonBody(new { uuid = episodeUuid }));
    }

    public async Task<HttpResponseMessage> GetNewReleases()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/new_releases", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> GetInProgress()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/in_progress", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> GetStarred()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/starred", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> GetHistory()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/history", EmptyJsonBody());
    }

    // ──────────────────────────────────────────────
    // Up Next (Queue)
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> GetUpNext()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/up_next/list", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> PlayNext(string episodeUuid, string podcastUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/up_next/play_next",
            JsonBody(new { uuid = episodeUuid, podcast = podcastUuid }));
    }

    public async Task<HttpResponseMessage> PlayLast(string episodeUuid, string podcastUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/up_next/play_last",
            JsonBody(new { uuid = episodeUuid, podcast = podcastUuid }));
    }

    public async Task<HttpResponseMessage> RemoveFromUpNext(string episodeUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/up_next/remove", JsonBody(new { uuid = episodeUuid }));
    }

    // ──────────────────────────────────────────────
    // Sync / Playback
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> SyncUpdateEpisode(string episodeUuid, string podcastUuid,
        int position, int status, int duration)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/sync/update_episode",
            JsonBody(new
            {
                uuid = episodeUuid,
                podcast = podcastUuid,
                position,
                status,
                duration
            }));
    }

    public async Task<HttpResponseMessage> SyncUpdateEpisodeStar(string episodeUuid, string podcastUuid, bool starred)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/sync/update_episode_star",
            JsonBody(new { uuid = episodeUuid, podcast = podcastUuid, starred }));
    }

    public async Task<HttpResponseMessage> SyncUpdateEpisodesArchive(string episodeUuid, string podcastUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/sync/update_episodes_archive",
            JsonBody(new { uuid = episodeUuid, podcast = podcastUuid }));
    }

    // ──────────────────────────────────────────────
    // Bookmarks
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> GetBookmarks()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/bookmark/list", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> AddBookmark(string episodeUuid, string podcastUuid, int time, string title)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/bookmark/add",
            JsonBody(new { episodeUuid, podcastUuid, time, title }));
    }

    public async Task<HttpResponseMessage> DeleteBookmark(string bookmarkUuid)
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/bookmark/delete",
            JsonBody(new { bookmarkUuid }));
    }

    // ──────────────────────────────────────────────
    // Discovery / Search
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> SearchPodcasts(string term)
    {
        return await _http.PostAsync($"{BaseUrl}/discover/search", JsonBody(new { term }));
    }

    public async Task<HttpResponseMessage> RecommendEpisodes()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/discover/recommend_episodes", EmptyJsonBody());
    }

    public async Task<HttpResponseMessage> GetRecommendationsForPodcast(string podcastUuid)
    {
        EnsureAuth();
        return await _http.GetAsync($"{BaseUrl}/recommendations/podcast/{podcastUuid}");
    }

    public async Task<HttpResponseMessage> GetFeatured()
    {
        return await _http.GetAsync($"{ListsUrl}/featured.json");
    }

    public async Task<HttpResponseMessage> GetTrending()
    {
        return await _http.GetAsync($"{ListsUrl}/trending.json");
    }

    public async Task<HttpResponseMessage> GetCategories()
    {
        return await _http.GetAsync($"{StaticUrl}/discover/json/categories_v2.json");
    }

    // ──────────────────────────────────────────────
    // Stats
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> GetStats()
    {
        EnsureAuth();
        return await _http.PostAsync($"{BaseUrl}/user/stats/summary", EmptyJsonBody());
    }

    // ──────────────────────────────────────────────
    // Generic helper for custom endpoint testing
    // ──────────────────────────────────────────────

    public async Task<HttpResponseMessage> RawPost(string url, string jsonBody)
    {
        return await _http.PostAsync(url, new StringContent(jsonBody, Encoding.UTF8, "application/json"));
    }

    public async Task<HttpResponseMessage> RawGet(string url)
    {
        return await _http.GetAsync(url);
    }

    public void Dispose() => _http.Dispose();
}
