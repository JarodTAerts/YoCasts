using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

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

// Client for HEAD requests to audio CDNs — follows redirects, no base URL
builder.Services.AddHttpClient("AudioHead", client =>
{
    client.DefaultRequestHeaders.Add("User-Agent", "YoCastsProxy/1.0");
    client.Timeout = TimeSpan.FromSeconds(15);
});

builder.Build().Run();
