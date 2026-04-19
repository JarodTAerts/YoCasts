using System.Text.Json.Serialization;

namespace PocketcastsApiTesting.Models;

public class AuthResponse
{
    [JsonPropertyName("token")]
    public string Token { get; set; } = "";

    [JsonPropertyName("uuid")]
    public string Uuid { get; set; } = "";

    [JsonPropertyName("email")]
    public string? Email { get; set; }
}
