using System.Text.Json.Serialization;

namespace PocketcastsApiTesting.Models;

public class Podcast
{
    [JsonPropertyName("uuid")]
    public string Uuid { get; set; } = "";

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("author")]
    public string Author { get; set; } = "";

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("url")]
    public string? Url { get; set; }

    [JsonPropertyName("lastEpisodePublished")]
    public string? LastEpisodePublished { get; set; }

    [JsonPropertyName("lastEpisodeUuid")]
    public string? LastEpisodeUuid { get; set; }

    public override string ToString() => $"  [{Uuid}] {Title} by {Author}";
}

public class PodcastListResponse
{
    [JsonPropertyName("podcasts")]
    public List<Podcast> Podcasts { get; set; } = new();
}
