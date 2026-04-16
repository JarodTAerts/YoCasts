# YoCastsProxy — Azure Function Proxy for PocketCasts API

A lightweight Azure Function that proxies PocketCasts API requests from the Garmin watch, stripping heavy fields to stay within Garmin's ~32-44 KB `makeWebRequest` response size limit.

## Why?

Garmin Connect IQ's `Communications.makeWebRequest()` has a hard ~32-44 KB response size limit (error `-402 NETWORK_RESPONSE_TOO_LARGE`). The PocketCasts `/user/podcast/list` endpoint returns ~43 KB for just 15 podcasts, mostly due to `description` and `descriptionHtml` fields the watch doesn't need.

This proxy strips unnecessary fields and forwards the rest, reducing responses to ~3-5 KB.

## How It Works

```
Garmin Watch → (Bearer token) → YoCastsProxy → PocketCasts API
                                    ↓
                              Strip heavy fields
                                    ↓
                           Return slim response
```

- **No credentials stored** — the Garmin watch logs into PocketCasts directly and sends its Bearer token with each request
- **No caching, no database** — pure strip-and-forward proxy
- **Mirrors PocketCasts paths** — `POST /api/pocketcasts/user/podcast/list` → `POST https://api.pocketcasts.com/user/podcast/list`

### Field Stripping

| Endpoint | Action |
|----------|--------|
| `/user/podcast/list` | Keep only: uuid, title, author, lastEpisodePublished, unplayed, lastEpisodeUuid, folderUuid, sortPosition, dateAdded, url, episodesSortOrder |
| `/up_next/list` | Pass through as-is (already small, ~540 bytes) |
| `/user/episode` | Strip description, descriptionHtml, notes, showNotes |
| All others | Strip description, descriptionHtml if present |

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Azure Functions Core Tools v4](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- An Azure account (for deployment)

## Local Development

1. Copy the example settings file:

   ```bash
   cp local.settings.json.example local.settings.json
   ```

2. Start Azurite (local storage emulator) or set `AzureWebJobsStorage` to a real connection string.

3. Run locally:

   ```bash
   func start
   ```

4. Test with curl:

   ```bash
   curl -X POST http://localhost:7071/api/pocketcasts/user/podcast/list \
     -H "Authorization: Bearer YOUR_POCKETCASTS_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{}"
   ```

## Build

```bash
cd YoCastsProxy
dotnet build
```

## Deploy to Azure

### Option 1: Azure CLI

```bash
# Create resources (one-time)
az group create --name yocasts-rg --location eastus
az storage account create --name yocastsstorage --resource-group yocasts-rg --sku Standard_LRS
az functionapp create \
  --name yocasts-proxy \
  --resource-group yocasts-rg \
  --storage-account yocastsstorage \
  --consumption-plan-location eastus \
  --runtime dotnet-isolated \
  --runtime-version 8 \
  --functions-version 4 \
  --os-type Linux

# Deploy
func azure functionapp publish yocasts-proxy
```

### Option 2: Visual Studio / VS Code

1. Right-click the project → **Publish** → **Azure** → **Function App (Linux)**
2. Select your subscription and create a new Function App on the **Consumption** plan
3. Click **Publish**

### Option 3: GitHub Actions

Add a publish profile secret (`AZURE_FUNCTIONAPP_PUBLISH_PROFILE`) and use the [Azure Functions GitHub Action](https://github.com/Azure/functions-action).

## Garmin App Configuration

After deploying, update the Garmin app's base URL from `https://api.pocketcasts.com` to `https://yocasts-proxy.azurewebsites.net/api/pocketcasts`.

The auth flow stays the same — the watch still logs in directly to PocketCasts at `https://api.pocketcasts.com/user/login_pocket_casts` and sends the token to the proxy for subsequent data requests.

## Architecture Notes

- **Azure Functions v4** with .NET 8 isolated worker (out-of-process)
- **Consumption tier** — scales to zero, pay only for requests
- **Anonymous auth level** — the proxy itself has no auth; it relies on the PocketCasts Bearer token for access control
- The proxy only targets `api.pocketcasts.com`. Secondary hosts (`podcast-api.pocketcasts.com`, `lists.pocketcasts.com`) are not proxied — those endpoints return small responses and can be called directly if needed.
