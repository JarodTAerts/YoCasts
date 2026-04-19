using System.Text.Json.Serialization;

namespace PocketcastsApiTesting.Models;

public class Episode
{
    [JsonPropertyName("uuid")]
    public string Uuid { get; set; } = "";

    [JsonPropertyName("url")]
    public string? Url { get; set; }

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("published")]
    public string? Published { get; set; }

    [JsonPropertyName("duration")]
    public int? Duration { get; set; }

    [JsonPropertyName("fileType")]
    public string? FileType { get; set; }

    [JsonPropertyName("size")]
    public string? Size { get; set; }

    [JsonPropertyName("playedUpTo")]
    public int? PlayedUpTo { get; set; }

    [JsonPropertyName("starred")]
    public bool? Starred { get; set; }

    [JsonPropertyName("podcastUuid")]
    public string? PodcastUuid { get; set; }

    [JsonPropertyName("podcastTitle")]
    public string? PodcastTitle { get; set; }

    [JsonPropertyName("isDeleted")]
    public bool? IsDeleted { get; set; }

    [JsonPropertyName("playingStatus")]
    public int? PlayingStatus { get; set; }

    public override string ToString()
    {
        var progress = PlayedUpTo.HasValue && Duration.HasValue && Duration > 0
            ? $" ({PlayedUpTo / 60}m/{Duration / 60}m)"
            : "";
        return $"  [{Uuid}] {Title}{progress}";
    }
}

public class EpisodeListResponse
{
    [JsonPropertyName("episodes")]
    public List<Episode> Episodes { get; set; } = new();
}

public class UpNextResponse
{
    [JsonPropertyName("episodes")]
    public List<Episode> Episodes { get; set; } = new();

    [JsonPropertyName("serverModified")]
    public long? ServerModified { get; set; }
}
