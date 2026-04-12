using System.Text.Json;
using Microsoft.Extensions.Configuration;
using PocketcastsApiTesting;
using PocketcastsApiTesting.Models;

// ═══════════════════════════════════════════════════════════
//  YoCasts — PocketCasts API Test Tool (READ-ONLY)
//
//  Credential sources (checked in order):
//    1. CLI args:  dotnet run -- <email> <password>
//    2. Local settings file: appsettings.local.json
//    3. Env vars:  POCKETCASTS_EMAIL / POCKETCASTS_PASSWORD
// ═══════════════════════════════════════════════════════════

string? email = null;
string? password = null;

// 1. CLI args
if (args.Length >= 2)
{
    email = args[0];
    password = args[1];
}

// 2. Local settings file
if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password))
{
    var settingsPath = Path.Combine(AppContext.BaseDirectory, "appsettings.local.json");
    // Also check the project directory (for `dotnet run` without publish)
    var projectSettingsPath = Path.Combine(Directory.GetCurrentDirectory(), "appsettings.local.json");

    string? resolvedPath = null;
    if (File.Exists(projectSettingsPath))
        resolvedPath = projectSettingsPath;
    else if (File.Exists(settingsPath))
        resolvedPath = settingsPath;

    if (resolvedPath != null)
    {
        try
        {
            var config = new ConfigurationBuilder()
                .AddJsonFile(resolvedPath, optional: false)
                .Build();

            email ??= config["PocketCasts:Email"];
            password ??= config["PocketCasts:Password"];
            Console.WriteLine($"  📄 Loaded credentials from {Path.GetFileName(resolvedPath)}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ⚠️  Error reading settings file: {ex.Message}");
        }
    }
}

// 3. Environment variables
email ??= Environment.GetEnvironmentVariable("POCKETCASTS_EMAIL");
password ??= Environment.GetEnvironmentVariable("POCKETCASTS_PASSWORD");

if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password))
{
    Console.WriteLine();
    Console.WriteLine("═══════════════════════════════════════════════════════");
    Console.WriteLine("  ⛔ No PocketCasts credentials found!");
    Console.WriteLine("═══════════════════════════════════════════════════════");
    Console.WriteLine();
    Console.WriteLine("  Create an appsettings.local.json file in the project");
    Console.WriteLine("  directory with your credentials:");
    Console.WriteLine();
    Console.WriteLine("    {");
    Console.WriteLine("      \"PocketCasts\": {");
    Console.WriteLine("        \"Email\": \"your-email@example.com\",");
    Console.WriteLine("        \"Password\": \"your-password-here\"");
    Console.WriteLine("      }");
    Console.WriteLine("    }");
    Console.WriteLine();
    Console.WriteLine("  See appsettings.local.example.json for the template.");
    Console.WriteLine("  This file is gitignored — your credentials stay local.");
    Console.WriteLine();
    Console.WriteLine("  Alternatively:");
    Console.WriteLine("    dotnet run -- <email> <password>");
    Console.WriteLine("    set POCKETCASTS_EMAIL=... && set POCKETCASTS_PASSWORD=...");
    Console.WriteLine();
    return;
}

Console.WriteLine();
Console.WriteLine("═══════════════════════════════════════════════════════");
Console.WriteLine("  YoCasts — PocketCasts API Explorer (READ-ONLY)");
Console.WriteLine("═══════════════════════════════════════════════════════");
Console.WriteLine($"  Email: {email}");
Console.WriteLine($"  Time:  {DateTime.UtcNow:u}");
Console.WriteLine();

// Ensure test-results directory exists
var resultsDir = Path.Combine(Directory.GetCurrentDirectory(), "test-results");
Directory.CreateDirectory(resultsDir);

using var client = new PocketCastsApiClient();
var runner = new ApiTestRunner(client, resultsDir);

// ── Authenticate first ──
Console.WriteLine("▶ Authenticating...");
await runner.TestLogin(email, password);

if (!client.IsAuthenticated)
{
    Console.WriteLine("\n⛔ Login failed — check your credentials.");
    return;
}

var tokenPreview = client.AuthToken!.Length > 20 ? client.AuthToken[..20] + "..." : "***";
Console.WriteLine($"  🔑 Authenticated (token: {tokenPreview})");
Console.WriteLine();

// ── Interactive Menu ──
var firstPodcastUuid = (string?)null;
var firstEpisodeUuid = (string?)null;

while (true)
{
    Console.WriteLine("═══════════════════════════════════════════════════════");
    Console.WriteLine("  Choose an action (READ-ONLY — no data is modified)");
    Console.WriteLine("═══════════════════════════════════════════════════════");
    Console.WriteLine("  1.  Run ALL read-only tests");
    Console.WriteLine("  2.  Get subscribed podcasts");
    Console.WriteLine("  3.  Get episodes for a podcast");
    Console.WriteLine("  4.  Get Up Next (queue)");
    Console.WriteLine("  5.  Get new releases");
    Console.WriteLine("  6.  Get in-progress episodes");
    Console.WriteLine("  7.  Get starred episodes");
    Console.WriteLine("  8.  Get listening history");
    Console.WriteLine("  9.  Get subscription status");
    Console.WriteLine("  10. Get listening stats");
    Console.WriteLine("  11. Get bookmarks");
    Console.WriteLine("  12. Search podcasts");
    Console.WriteLine("  13. Get featured/trending podcasts");
    Console.WriteLine("  14. Get categories");
    Console.WriteLine("  15. Test error handling");
    Console.WriteLine("  16. 🔊 Audio download research probe");
    Console.WriteLine("  0.  Exit");
    Console.WriteLine();
    Console.Write("  > ");

    var choice = Console.ReadLine()?.Trim();
    Console.WriteLine();

    switch (choice)
    {
        case "0":
            Console.WriteLine("Done. Results saved to test-results/");
            runner.PrintSummary();
            return;

        case "1":
            await RunAllTests(runner, client, email, password);
            break;

        case "2":
            var podJson = await runner.TestGetSubscribedPodcasts();
            CaptureFirstPodcast(podJson, ref firstPodcastUuid);
            break;

        case "3":
            if (firstPodcastUuid == null)
            {
                Console.Write("  Enter podcast UUID (or press Enter to fetch your first podcast): ");
                var uuid = Console.ReadLine()?.Trim();
                if (string.IsNullOrEmpty(uuid))
                {
                    var pj = await runner.TestGetSubscribedPodcasts();
                    CaptureFirstPodcast(pj, ref firstPodcastUuid);
                    if (firstPodcastUuid == null) { Console.WriteLine("  No podcasts found."); break; }
                    uuid = firstPodcastUuid;
                }
                firstPodcastUuid = uuid;
            }
            var epJson = await runner.TestGetEpisodesForPodcast(firstPodcastUuid);
            CaptureFirstEpisode(epJson, ref firstEpisodeUuid);
            break;

        case "4":
            await runner.TestGetUpNext();
            break;

        case "5":
            await runner.TestGetNewReleases();
            break;

        case "6":
            await runner.TestGetInProgress();
            break;

        case "7":
            await runner.TestGetStarred();
            break;

        case "8":
            await runner.TestGetHistory();
            break;

        case "9":
            await runner.TestSubscriptionStatus();
            break;

        case "10":
            await runner.TestGetStats();
            break;

        case "11":
            await runner.TestGetBookmarks();
            break;

        case "12":
            Console.Write("  Search term: ");
            var term = Console.ReadLine()?.Trim() ?? "technology";
            await runner.TestSearchPodcasts(term);
            break;

        case "13":
            await runner.TestGetFeatured();
            await runner.TestGetTrending();
            break;

        case "14":
            await runner.TestGetCategories();
            break;

        case "15":
            await runner.TestBadLogin();
            await runner.TestUnauthenticatedAccess();
            await runner.TestInvalidEndpoint();
            break;

        case "16":
            await AudioProbeRunner.RunAudioProbes(client, resultsDir);
            break;

        default:
            Console.WriteLine("  Invalid choice. Try again.");
            break;
    }

    Console.WriteLine();
}

// ═══════════════════════════════════════════
// Helper methods
// ═══════════════════════════════════════════

static void CaptureFirstPodcast(string? json, ref string? podcastUuid)
{
    if (json == null) return;
    try
    {
        var list = JsonSerializer.Deserialize<PodcastListResponse>(json);
        if (list?.Podcasts.Count > 0)
        {
            podcastUuid = list.Podcasts[0].Uuid;
            Console.WriteLine($"  📌 First podcast: {list.Podcasts[0].Title} [{podcastUuid[..8]}...]");
        }
    }
    catch { }
}

static void CaptureFirstEpisode(string? json, ref string? episodeUuid)
{
    if (json == null) return;
    try
    {
        var list = JsonSerializer.Deserialize<EpisodeListResponse>(json);
        if (list?.Episodes.Count > 0)
        {
            episodeUuid = list.Episodes[0].Uuid;
            Console.WriteLine($"  📌 First episode: {list.Episodes[0].Title} [{episodeUuid[..8]}...]");
        }
    }
    catch { }
}

static async Task RunAllTests(ApiTestRunner runner, PocketCastsApiClient client, string email, string password)
{
    Console.WriteLine("▶ Running all read-only tests...\n");

    // Error handling (pre-auth checks)
    Console.WriteLine("── Error Handling ──");
    await runner.TestBadLogin();
    await runner.TestUnauthenticatedAccess();

    // Auth variants
    Console.WriteLine("\n── Auth Variants ──");
    await runner.TestLoginPocketCasts(email, password);
    await runner.TestRefreshToken();

    // Account
    Console.WriteLine("\n── Account ──");
    await runner.TestSubscriptionStatus();
    await runner.TestGetStats();

    // Podcasts
    Console.WriteLine("\n── Podcasts ──");
    var podJson = await runner.TestGetSubscribedPodcasts();
    string? podUuid = null;
    string? epUuid = null;
    if (podJson != null)
    {
        try
        {
            var list = JsonSerializer.Deserialize<PodcastListResponse>(podJson);
            if (list?.Podcasts.Count > 0)
            {
                podUuid = list.Podcasts[0].Uuid;
                Console.WriteLine($"\n  📌 Using podcast: {list.Podcasts[0].Title}");
            }
        }
        catch { }
    }

    // Episodes
    Console.WriteLine("\n── Episodes ──");
    if (podUuid != null)
    {
        var epJson = await runner.TestGetEpisodesForPodcast(podUuid);
        if (epJson != null)
        {
            try
            {
                var list = JsonSerializer.Deserialize<EpisodeListResponse>(epJson);
                if (list?.Episodes.Count > 0)
                {
                    epUuid = list.Episodes[0].Uuid;
                    Console.WriteLine($"  📌 Using episode: {list.Episodes[0].Title}");
                }
            }
            catch { }
        }
    }
    if (epUuid != null)
        await runner.TestGetEpisode(epUuid);

    await runner.TestGetNewReleases();
    await runner.TestGetInProgress();
    await runner.TestGetStarred();
    await runner.TestGetHistory();

    // Queue
    Console.WriteLine("\n── Up Next ──");
    await runner.TestGetUpNext();

    // Bookmarks
    Console.WriteLine("\n── Bookmarks ──");
    await runner.TestGetBookmarks();

    // Discovery
    Console.WriteLine("\n── Discovery ──");
    await runner.TestSearchPodcasts("technology");
    await runner.TestGetFeatured();
    await runner.TestGetTrending();
    await runner.TestGetCategories();
    await runner.TestRecommendEpisodes();

    if (podUuid != null)
    {
        await runner.TestGetPodcastFull(podUuid);
        await runner.TestGetRecommendationsForPodcast(podUuid);
    }

    // Final error test
    Console.WriteLine("\n── Additional Errors ──");
    await runner.TestInvalidEndpoint();

    runner.PrintSummary();
}
