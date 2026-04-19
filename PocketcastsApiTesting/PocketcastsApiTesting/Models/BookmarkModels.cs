using System.Text.Json.Serialization;

namespace PocketcastsApiTesting.Models;

public class Bookmark
{
    [JsonPropertyName("bookmarkUuid")]
    public string? BookmarkUuid { get; set; }

    [JsonPropertyName("podcastUuid")]
    public string? PodcastUuid { get; set; }

    [JsonPropertyName("episodeUuid")]
    public string? EpisodeUuid { get; set; }

    [JsonPropertyName("time")]
    public int? Time { get; set; }

    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("createdAt")]
    public string? CreatedAt { get; set; }

    public override string ToString() => $"  [{BookmarkUuid}] {Title} @ {Time}s";
}

public class BookmarkListResponse
{
    [JsonPropertyName("bookmarks")]
    public List<Bookmark> Bookmarks { get; set; } = new();
}
