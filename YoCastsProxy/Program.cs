using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using YoCastsProxy;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Services.AddHttpClient("PocketCasts", client =>
{
    client.BaseAddress = new Uri("https://api.pocketcasts.com");
    client.DefaultRequestHeaders.Add("Origin", "https://play.pocketcasts.com");
    client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
});

builder.Services.AddHttpClient("PocketCastsStatic", client =>
{
    client.BaseAddress = new Uri("https://static.pocketcasts.com");
    client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
});

builder.Services
    .AddHttpClient("PocketCastsPodcastCache", client =>
    {
        client.BaseAddress = new Uri("https://podcast-api.pocketcasts.com");
        client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
        client.Timeout = TimeSpan.FromSeconds(15);
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        AutomaticDecompression = System.Net.DecompressionMethods.All,
        ConnectCallback = NetworkGuard.ConnectPublicAsync
    });

builder.Services
    .AddHttpClient("PocketCastsPublicContent", client =>
    {
        client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
        client.Timeout = TimeSpan.FromSeconds(20);
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        AutomaticDecompression = System.Net.DecompressionMethods.All,
        ConnectCallback = NetworkGuard.ConnectPublicAsync
    });

builder.Services
    .AddHttpClient("PocketCastsShowNotes", client =>
    {
        client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
        client.Timeout = TimeSpan.FromSeconds(15);
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        AutomaticDecompression = System.Net.DecompressionMethods.All,
        ConnectCallback = NetworkGuard.ConnectPublicAsync
    });

// Redirects are followed manually in AudioInfoProxy so every hop is validated.
builder.Services
    .AddHttpClient("AudioHead", client =>
    {
        client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
        client.Timeout = TimeSpan.FromSeconds(15);
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        ConnectCallback = NetworkGuard.ConnectPublicAsync
    });

builder.Build().Run();
