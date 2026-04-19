using System.Text.Json.Serialization;

namespace PocketcastsApiTesting.Models;

public class SubscriptionStatus
{
    [JsonPropertyName("paid")]
    public int? Paid { get; set; }

    [JsonPropertyName("platform")]
    public int? Platform { get; set; }

    [JsonPropertyName("expiryDate")]
    public string? ExpiryDate { get; set; }

    [JsonPropertyName("autoRenewing")]
    public bool? AutoRenewing { get; set; }

    [JsonPropertyName("type")]
    public int? Type { get; set; }

    [JsonPropertyName("frequency")]
    public int? Frequency { get; set; }
}
