using System.Text.Json;
using PocketcastsApiTesting.Models;

namespace PocketcastsApiTesting;

/// <summary>
/// Orchestrates audio URL probing across multiple episode sources.
/// Gathers diverse episodes (different hosts/providers) and runs AudioProbe on each.
/// </summary>
public static class AudioProbeRunner
{
    public static async Task RunAudioProbes(PocketCastsApiClient client, string resultsDir)
    {
        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════════");
        Console.WriteLine("  AUDIO DOWNLOAD RESEARCH PROBE (READ-ONLY)");
        Console.WriteLine("═══════════════════════════════════════════════════════");
        Console.WriteLine();

        var probe = new AudioProbe(client.AuthToken!, resultsDir);
        var allEpisodes = new List<Episode>();

        // Source 1: New releases
        Console.WriteLine("  ▶ Fetching new releases...");
        var newRelResp = await client.GetNewReleases();
        if (newRelResp.IsSuccessStatusCode)
        {
            var body = await newRelResp.Content.ReadAsStringAsync();
            var list = JsonSerializer.Deserialize<EpisodeListResponse>(body);
            if (list?.Episodes != null)
            {
                allEpisodes.AddRange(list.Episodes);
                Console.WriteLine($"    Found {list.Episodes.Count} new release episodes");
            }
        }

        // Source 2: In progress
        Console.WriteLine("  ▶ Fetching in-progress...");
        var inProgResp = await client.GetInProgress();
        if (inProgResp.IsSuccessStatusCode)
        {
            var body = await inProgResp.Content.ReadAsStringAsync();
            var list = JsonSerializer.Deserialize<EpisodeListResponse>(body);
            if (list?.Episodes != null)
            {
                foreach (var ep in list.Episodes)
                {
                    if (!allEpisodes.Any(e => e.Uuid == ep.Uuid))
                        allEpisodes.Add(ep);
                }
                Console.WriteLine($"    Found {list.Episodes.Count} in-progress episodes");
            }
        }

        // Source 3: Up Next — fetch full details for minimal entries
        Console.WriteLine("  ▶ Fetching Up Next queue...");
        var upNextResp = await client.GetUpNext();
        if (upNextResp.IsSuccessStatusCode)
        {
            var body = await upNextResp.Content.ReadAsStringAsync();
            var json = JsonSerializer.Deserialize<JsonElement>(body);
            if (json.TryGetProperty("episodes", out var episodesMap) && episodesMap.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in episodesMap.EnumerateObject())
                {
                    var uuid = prop.Name;
                    if (!allEpisodes.Any(e => e.Uuid == uuid))
                    {
                        var detailResp = await client.GetEpisode(uuid);
                        if (detailResp.IsSuccessStatusCode)
                        {
                            var detailBody = await detailResp.Content.ReadAsStringAsync();
                            var ep = JsonSerializer.Deserialize<Episode>(detailBody);
                            if (ep != null) allEpisodes.Add(ep);
                        }
                    }
                }
                Console.WriteLine($"    Processed Up Next episodes");
            }
        }

        var withUrls = allEpisodes.Where(e => !string.IsNullOrEmpty(e.Url)).ToList();
        Console.WriteLine();
        Console.WriteLine($"  📊 Total unique episodes with URLs: {withUrls.Count}");

        // Select diverse samples — one per hosting provider (by first hostname)
        var byHost = withUrls
            .GroupBy(e => new Uri(e.Url!).Host)
            .Select(g => g.First())
            .Take(8)
            .ToList();

        Console.WriteLine($"  🔍 Probing {byHost.Count} episodes (one per hosting provider):");
        foreach (var ep in byHost)
        {
            Console.WriteLine($"    • {ep.Title} ({new Uri(ep.Url!).Host})");
        }

        foreach (var ep in byHost)
        {
            await probe.ProbeEpisodeAudio(ep.Title, ep.Url!, ep.FileType, ep.Size, ep.Duration);
        }

        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════════");
        Console.WriteLine("  AUDIO PROBE COMPLETE");
        Console.WriteLine($"  Results saved to: {resultsDir}");
        Console.WriteLine("═══════════════════════════════════════════════════════");
    }
}
