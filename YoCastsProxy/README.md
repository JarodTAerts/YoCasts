# YoCastsProxy

YoCastsProxy is a .NET 8 Azure Functions service that adapts Pocket Casts data
for the constrained Garmin Connect IQ networking and storage model. The watch
still authenticates with Pocket Casts and sends its bearer token on each
request; the proxy does not store account credentials or tokens.

The deployed Garmin configuration currently uses:

```text
https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts
```

## Responsibilities

- Allowlist the Pocket Casts operations needed by the watch.
- Strip or bound large fields so responses remain below Connect IQ's response
  limit (`-402 NETWORK_RESPONSE_TOO_LARGE`).
- Build a compact, newest-first episode list with user progress overlaid.
- Fetch and normalize podcast descriptions and episode show notes.
- Resolve enclosure redirects and return final audio URL, size, type, and
  download metadata before Garmin starts a media download.
- Scope cached signed audio URLs to a token fingerprint.
- Reject unsafe redirect targets and pin outbound connections to resolved public
  addresses to reduce SSRF and DNS-rebinding risk.

## Routes

| Route | Purpose |
|-------|---------|
| `POST /api/pocketcasts/user/podcast/list` | Compact subscriptions with bounded descriptions and artwork colors |
| `POST /api/pocketcasts/up_next/list` | Up Next order and episode map |
| `POST /api/pocketcasts/yocasts/podcast/episodes` | Up to 15 recent episodes with progress and compact metadata |
| `POST /api/pocketcasts/yocasts/episode/details` | Episode metadata plus bounded plain-text show notes |
| `POST /api/pocketcasts/user/episode` | Compact current episode state used during mutation reconciliation |
| `POST /api/pocketcasts/sync/update_episode` | Forward playback progress/status mutations |
| `POST /api/pocketcasts/up_next/play_last` | Forward queue additions |
| `POST /api/pocketcasts/up_next/remove` | Forward queue removals |
| `GET /api/pocketcasts/episode/{uuid}/audio-info` | Resolve final enclosure URL and download metadata |

Unsupported generic proxy paths return 404.

## Local development

Prerequisites:

- .NET 8 SDK
- Azure Functions Core Tools v4
- Azurite or an Azure Storage connection string

```powershell
Copy-Item local.settings.json.example local.settings.json
dotnet build
func start
```

`local.settings.json` is intentionally ignored and must not be committed.

## Deployment

The existing personal function app can be published with:

```powershell
func azure functionapp publish yocasts-proxy-personal
```

The function app is currently in resource group `yocasts-rg`. Run
`dotnet build` before publishing, then probe the compact episode, detail, and
audio-info routes with a valid bearer token.

## Operational notes

- Connect IQ's response-size error `-402` is addressed by endpoint-specific
  compaction rather than returning raw Pocket Casts payloads.
- Metadata and show-note services may return compressed responses and redirects;
  configured clients decompress automatically and redirects are followed only
  after validating each target.
- Standard audio metadata is cached in-memory for two hours. Private/premium
  capability URLs are cached for 30 minutes and are isolated per account token
  fingerprint.
- Pocket Casts does not provide a supported public third-party API. These
  integrations may need maintenance if its first-party endpoints change.
