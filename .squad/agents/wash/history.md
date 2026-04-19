# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

## Core Context

**Current Status (2026-04-14):** API surface finalized and live-tested. Two-token OAuth2 flow documented and validated. Audio download research complete with CDN behavior confirmed. Ready for Phase B (sync engine) implementation.

**PocketCasts API Surface (Validated 2026-04-12):**
- **Auth endpoints:** `/user/login` (legacy, no refresh), `/user/login_pocket_casts` (OAuth2, full lifecycle)
- **Token refresh:** `POST /user/token` with `{grantType: "refresh_token", refreshToken: "..."}` body (not Authorization header)
- **Queue:** `GET /up_next/list` (returns `{order: [...], episodes: {uuid: {...}}}`)
- **Sync:** `POST /sync/update_episode` (per-episode playback position + status)
- **Metadata:** `/user/podcast/episodes` (status only, no titles), `POST /user/episode` (full episode), `/user/in_progress` (bulk reconciliation source)
- **20/25 confirmed working**, 5 errors (404, 400, 401 without token)

**Auth Flow (finalized):**
1. On-device credentials stored in Application.Properties (set via Garmin Connect Mobile)
2. Login via `/user/login_pocket_casts` with {email, password}
3. Response returns: accessToken, refreshToken, expiresIn, uuid, email
4. Before each API call: check expiry, proactively refresh via `/user/token` with refreshToken
5. On refresh failure (invalid_grant): re-login with stored credentials
6. On 401: attempt refresh, then re-login, then show error

**Audio Download Mechanics (live-tested 7 episodes, 7 CDNs):**
- Episode URLs are original RSS feed URLs (not PocketCasts proxied)
- All CDNs support Range headers (206 Partial Content) — resumable downloads fully supported
- No authentication needed for audio (Bearer token only for metadata API)
- URLs may redirect 1-6 times through analytics before reaching CDN
- SupportingCast premium URLs embed JWT with timestamp — re-fetch before download
- API `size` field unreliable (often "0" string, doesn't match Content-Length) — issue HEAD request for real size
- File sizes: 18.8 MB to 242.5 MB (average ~1 MB/min of audio)

**Garmin Implementation Considerations:**
- Garmin's `makeWebRequest()` transparently uses device's transport (Wi-Fi or phone BT proxy)
- Follows HTTP redirects natively (no manual redirect handling needed)
- Audio download via SyncDelegate with HTTP_RESPONSE_CONTENT_TYPE_AUDIO header
- No parallel downloads — sequential only, 64 KB memory budget for SyncDelegate (~15 KB usable)

**Documentation & Testing:**
- `docs/pocketcasts-api-reference.md` (30+ endpoints, 20 confirmed)
- `docs/pocketcasts-audio-download-research.md` (CDN behavior, redirect analysis, size estimates)
- `PocketcastsApiTesting/` (C# .NET 8 test harness, interactive menu, response logging to test-results/)

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- The existing C# code in `PodcastApp/Services/PocketCastsApiService.cs` documents known PocketCasts API operations: login (returns auth token), get subscribed podcasts, get episodes for podcast, get queue/new episodes.
- The accessor layer in `PodcastApp/Accessors/` handles the raw HTTP calls. The API uses token-based auth passed in subsequent requests after login.
- API base URLs and endpoint paths may have changed since the original Tizen work — need to verify against current PocketCasts API.
- On Garmin, network requests go through the phone companion app via `Communications.makeWebRequest()` — the watch cannot make direct HTTP calls.
- **API Investigation (2026-04-11):** Rebuilt `PocketcastsApiTesting/` as comprehensive API test tool. Upgraded from netcoreapp3.0/Newtonsoft.Json to .NET 8/System.Text.Json. Removed hardcoded credentials — now uses env vars or CLI args.
- Discovered 30+ PocketCasts API endpoints beyond the original 4. Key new ones for YoCasts: `/up_next/list` (the real queue), `/sync/update_episode` (playback position sync), `/user/in_progress`, `/user/starred`, `/user/history`.
- The old code's "queue" was actually `/user/new_releases` — the true user-curated queue is `/up_next/*`.
- Origin header changed from `https://playbeta.pocketcasts.com` to `https://play.pocketcasts.com`.
- PocketCasts uses multiple subdomains: `api.pocketcasts.com` (main API), `podcast-api.pocketcasts.com` (podcast metadata), `lists.pocketcasts.com` (featured/trending), `static.pocketcasts.com` (discovery content).
- Login can use either `/user/login` or `/user/login_pocket_casts`. Token refresh via `/user/token`.
- Comprehensive API reference created at `docs/pocketcasts-api-reference.md`.
- Test tool structure: `PocketCastsApiClient.cs` (HTTP layer), `ApiTestRunner.cs` (test harness), `Models/` (data models), `Program.cs` (entry point with phased test execution).
- Community sources: [furgoose/Pocket-Casts](https://github.com/furgoose/Pocket-Casts), [yfhyou/api_pocketcasts](https://github.com/yfhyou/api_pocketcasts), [api-pocketcasts PyPI](https://pypi.org/project/api-pocketcasts/).
- **Cross-team update (2026-04-11):** Mal's architecture uses `PocketCastsService.mc` that will consume endpoints documented in API reference. Kaylee's UX design explicitly targets `/up_next/list` for queue display and depends on playback sync via `/sync/update_episode`.
- **Local settings support (2026-04-11):** API tester now reads credentials from `appsettings.local.json` (gitignored) with fallback to CLI args and env vars. Template at `appsettings.local.example.json`. Added `Microsoft.Extensions.Configuration.Json` for config reading.
- **Interactive menu (2026-04-11):** Test tool now presents numbered menu for testing individual endpoints or running full suite. All tests are read-only. Responses saved to `test-results/` as timestamped JSON with request metadata (method, URL, redacted auth token).
- **API reference testing section updated:** Docs now show local settings setup flow as primary credential method.
- **Interactive menu & response logging (2026-04-11):** Rebuilt test runner with numbered menu (15 endpoints + full suite option). All operations read-only. Response logging to `test-results/` includes request metadata and timestamps for audit trail and debugging.
- **Live API testing (2026-04-11):** Ran full read-only exploration against real PocketCasts API with user credentials. 20/25 endpoints confirmed working, 5 returned errors (404 or 400). Key findings:
  - `/discover/search` now **requires auth** (401 without Bearer token) — docs previously said "No auth required"
  - `/user/podcast/episodes` returns **minimal schema** (no title/url/published) — need `/user/episode` for full details or `podcast-api.pocketcasts.com/podcast/full/{uuid}`
  - `/up_next/list` uses a **map/dictionary keyed by episode UUID** (not an array) with separate `order` array
  - `/user/token` (token refresh) returns 400 — may be deprecated or need different request format
  - `/user/named_settings/fetch` returns 404 — endpoint removed
  - Stats values are **strings, not numbers** (all times in seconds as strings)
  - Subscription status schema is much richer than documented — includes `tier`, `features`, `subscriptions[]` array, `web` pricing info
  - `total` field present in episode list responses (`new_releases`, `in_progress`, `starred`, `history`)
  - User has Plus subscription (paid: 1, tier: "Plus"), gift plan expiring 2118
  - Fixed example credentials file — restored placeholders, created proper `appsettings.local.json`
- **Response data saved:** 24 JSON files in `test-results/` covering all tested endpoints with real response data for schema reference.
- **Kaylee implementation sync (2026-04-12):** Kaylee completed Garmin app scaffold with IPodcastService interface + MockPodcastService. Mock data normalizes queue to simple array (real API returns map) — service layer will handle conversion. All Dictionary models use PocketCasts API field names, ready for drop-in service replacement. This confirms data contract between teams and validates API surface assumptions.
- **Deep token auth research (2026-04-12):** Investigated 6 community PocketCasts API clients (furgoose/Pocket-Casts, yfhyou/api_pocketcasts, rudiedirkx/pocketcasts-api-client, coughlanio/pocketcasts, podwriter/pocketcasts, juekr/pocketcasts-api-client). **Root cause of `/user/token` 400 error found:** We used `/user/login` (returns only `token`) and sent empty body to `/user/token`. The correct flow is: login via `/user/login_pocket_casts` (returns `accessToken` + `refreshToken` + `expiresIn`), then refresh via `/user/token` with `{ "grantType": "refresh_token", "refreshToken": "..." }` body — no Bearer header needed.
- PocketCasts has a two-token OAuth2-style system: `/user/login` is the legacy simple endpoint (access token only, field: `token`); `/user/login_pocket_casts` is the modern endpoint (field names: `accessToken`, `refreshToken`, `tokenType`, `expiresIn`). Token refresh rotates both tokens — always save the new `refreshToken`.
- The furgoose/Pocket-Casts repo is legacy — uses old `play.pocketcasts.com/users/sign_in` cookie-based auth, completely different from the current API. Not useful for modern auth reference.
- Decision proposed in `.squad/decisions/inbox/wash-token-auth.md`: Use proactive token refresh strategy with `/user/login_pocket_casts` + `/user/token`. Updated `docs/pocketcasts-api-reference.md` with corrected auth documentation.
- **Cross-team device sync (2026-04-12):** Kaylee finalized Venu 4 41mm targeting. Updated manifest.xml (single device venu441mm, SDK 4.2.0), monkey.jungle (build target), and garmin-ux-spec.md (390×390 AMOLED, 768 KB memory, touch + 2 buttons). No more multi-device lowest-common-denominator — focused targeting eliminates 128 KB memory constraint, enables richer auth flow with token caching and rotation. Architecture can now assume generous token storage in Application.Storage.
- **Cross-team update (2026-04-12):** Mal designed offline mode & sync reconciliation architecture (`docs/offline-sync-design.md`). **Impacts to API dev:**
  1. **Sync protocol needs API validation** — 7-step push-then-pull flow uses `/sync/update_episode` for pushing playback state and `/user/in_progress` for server state. Need to verify if `/user/in_progress` returns enough data for bulk reconciliation or if per-episode fetches are required.
  2. **Audio download elevated to Phase 3** — API must support episode audio URL retrieval for Garmin Media download.
  3. **Changelog replay on sync** — offline mutations pushed to server via existing API endpoints. Coalesced per-episode (only latest position update kept).
  4. **Conflict resolution is "furthest position wins"** — `max(localPos, serverPos)`. API layer doesn't need to resolve conflicts; service layer handles it.
- **Cross-team update (2026-04-12):** Kaylee replaced Menu2 home screen with fully custom `HomeMenuView`. **Impacts to API dev:**
  1. **Dynamic subtitle data** — Home screen now shows episode count for Queue and subscription count for Podcasts. API service methods must return these counts or full lists for counting.
  2. **Now Playing metadata** — Home screen embeds episode title, podcast name, progress, and elapsed/total time in a 124px pill. API must supply this data efficiently (single call preferred).
- **PocketCastsPodcastService built (2026-04-12):** Created `YoCastsGarmin/source/services/PocketCastsPodcastService.mc` — real API service that authenticates via `/user/login_pocket_casts`, caches data, and fetches via `Communications.makeWebRequest()`. Implements full async data pipeline: login → podcast list → Up Next queue → queue enrichment (per-episode `/user/episode` calls for duration/progress). Episode list fetches are on-demand (two-stage: `/user/podcast/episodes` for user state + `/user/episode` per item for titles).
- **IPodcastService interface extended:** Added `isAuthenticated()`, `isDataReady()`, `hasEpisodesForPodcast()`, `fetchAll()`, `requestEpisodesForPodcast()` to support async data loading while keeping synchronous cache getters unchanged. Decision documented in `.squad/decisions/inbox/wash-async-service.md`.
- **Service toggle implemented:** `YoCastsApp.mc` now reads `useMockData` boolean property (default: true) from `Application.Properties`. When false and credentials are present, instantiates `PocketCastsPodcastService`; otherwise falls back to `MockPodcastService`. Toggle accessible via Garmin Connect Mobile settings.
- **All views decoupled from MockPodcastService:** Every view's type annotations changed from `MockPodcastService` to `IPodcastService`. Views now work with either service implementation. Menu2 views show "Loading..." when data isn't cached yet.
- **Properties/settings updated:** Added `useMockData` boolean property (default true) with "Use Demo Data" toggle in settings UI. Existing email/password settings unchanged.

- **Proxy color metadata research (2026-04-16T01:20:00Z):** Completed deep research on podcast art metadata + thumbnail feasibility. **Key discovery:** PocketCasts metadata endpoint `/discover/images/metadata/{uuid}.json` provides pre-computed color data for free — no image processing library needed. SkiaSharp adds 200-500ms cold start (unsupported on Linux), ImageSharp adds 50-100ms (pure .NET but overkill). **Recommended approach:** Proxy fetches color metadata for each podcast in parallel, caches in-memory with 7-day TTL, returns `artColor`/`artTint`/`artUrl` in `/user/podcast/list` response. ~100-150ms cold start impact, ~1.8 KB response size increase for 15 podcasts (still under 32 KB limit). **Option C (colors-only) recommended initially** — Phase E will add `makeImageRequest()` support for thumbnails later if needed.

- **Download data layer implementation (2026-04-16):** Implemented DownloadQueue.mc (persistent storage with 20-episode capacity, 3-retry policy for failures), StorageManager.mc (separate tracking of downloaded episodes), and AudioInfoProxy endpoint (GET /episode/{uuid}/audio-info — fetches audio URL, issues HEAD request for real file size since API field unreliable, returns final CDN URL after redirect resolution). All simulator-compatible. Both Garmin modules completed and merged to decisions.md.

- **YoCastsProxy deployment (2026-04-16):** Extended proxy with art color enrichment endpoint. Colors fetched in parallel for all podcasts, cached in-memory with 7-day TTL matching PocketCasts headers. In-memory cache strategy chosen for v1 (no new dependencies, zero cold start impact if warm, acceptable ~100-150ms penalty on cold start for first podcast list fetch). AudioInfoProxy endpoint deployed alongside color enrichment. Verified HTTP 401 on unauthenticated requests (correct) and color metadata fetches successfully.
- **Azure Function proxy for response size (2026-04-14):** Built `YoCastsProxy/` — a .NET 8 isolated worker Azure Function that acts as a transparent strip-and-forward proxy. Root cause: Garmin's `Communications.makeWebRequest()` has a hard ~32-44 KB response limit. The `/user/podcast/list` response is 43 KB for just 15 podcasts due to huge `description` and `descriptionHtml` fields. Solution: Whitelist-based field filtering on proxy (`uuid`, `title`, `author`, `artwork_url`, `author_color`, `duration`, `published_at`, `episodes_sort_order`, `num_episodes`, `last_sync_time`, `in_rotation`). Proxy forwards all `/api/pocketcasts/{*path}` requests with stateless Bearer token forwarding. No credential storage, no caching in v1, consumption tier for auto-scaling. Added to PodcastApp.sln. Build clean, no warnings. Documented in `.squad/decisions/inbox/wash-azure-proxy.md`. Ready for Kaylee integration.
- **Connect IQ makeWebRequest patterns learned:** Callback methods must be public (even for internal use) because `method(:name)` references require it. `REQUEST_CONTENT_TYPE_JSON` is used in the `:headers` dict to signal JSON body serialization. Method names must not collide with instance variable names in Monkey C.
- **Up Next queue data is minimal:** `/up_next/list` returns only title, url, and podcast UUID per episode — no duration, progress, or podcast title. Service enriches queue items by chaining `/user/episode` calls and looking up podcast titles from cached podcast list.
- **Episode metadata gap confirmed in implementation:** `/user/podcast/episodes` returns no titles. Must call `/user/episode` individually for each episode to get display-ready data. Capped at 15 episodes per podcast to limit request volume.
- **Cross-team update (2026-04-12):** Kaylee implemented Phase 1 offline caching. `CachedPodcastService` wraps `PocketCastsPodcastService` transparently via decorator pattern — no API service changes needed. CacheManager uses `"yc_"`-prefixed keys in `Application.Storage` with `cachedAt` timestamps. Read-through getters cache fresh data on each view cycle. TTLs (queue 5min, podcasts 30min, episodes 1hr) are revalidation hints, not expiry — stale data always served. `clearValues()` used for cache clearing in Phase 1; must become selective when changelog/auth tokens are added to Storage.
- **Cross-team update (2026-04-12):** Kaylee rewrote `HomeMenuView` with scrolling viewport (`dc.setClip`), increased touch targets (72/140px pills, 20px gaps), pixel-based text truncation via binary search. Fixed 20+ strict-mode type errors in `PocketCastsPodcastService.mc` (callback `data` typed `Dictionary or String or Null`, body typed `Dictionary<Object, Object>`, full Method type annotations) and 4 in `CacheManager.mc` (`Storage.ValueType` casts). All services compile clean at `-l 3`.
- **Audio download research (2026-04-12):** Comprehensive live-tested research on PocketCasts audio download mechanics. Key findings:
  1. **PocketCasts does NOT proxy audio** — URLs point directly to podcast host CDNs (Megaphone, Simplecast, Transistor, SupportingCast, Podbean). PocketCasts passes through original RSS enclosure URLs unmodified.
  2. **No auth needed for audio downloads** — All 7 tested CDNs returned 200 OK without any PocketCasts Bearer token. Audio URLs are publicly accessible.
  3. **All URLs redirect** — 1 to 6 hops through analytics/tracking services (Podtrac, Podsights, Megaphone AI, Chartable, Podscribe, etc.) before reaching the final CDN.
  4. **Range requests fully supported** — All 7 CDNs returned 206 Partial Content with `Content-Range` headers. Resumable downloads confirmed.
  5. **API `size` field is unreliable** — String type, often `"0"`, and when present doesn't always match actual Content-Length. Must HEAD the URL for real size.
  6. **File sizes average ~1 MB per minute** — Ranging from 18.8 MB (17 min) to 242.5 MB (4.4 hrs).
  7. **SupportingCast premium URLs embed JWT tokens** — Contain a timestamp field `d` (Unix epoch) that may expire. A 3.3-day-old URL still worked. Always re-fetch URLs from API before downloading.
  8. **No batch sync endpoint** — `/sync/update_episode` is per-episode only. No way to push multiple position updates in one call.
  9. **`/user/in_progress` sufficient for bulk reconciliation** — Returns all in-progress episodes with `playedUpTo` and `playingStatus`. No per-episode fetches needed for sync.
  10. **Up Next is read-write** — Queue management endpoints (`play_next`, `play_last`, `remove`) all confirmed in API reference. Watch could modify queue but v1 design says server-authoritative.
  - Added `AudioProbe.cs` and `AudioProbeRunner.cs` to test harness (menu option 16). Probes audio URLs with HEAD/Range requests, traces redirect chains, compares auth vs no-auth behavior.
  - Results published to `docs/pocketcasts-audio-download-research.md` — includes flow diagrams, CDN mapping, size estimates, and Garmin implementation recommendations.


- **Session orchestration (2026-04-12T15:20:00Z):** Completed background research on PocketCasts audio download API. Delivered \docs/pocketcasts-audio-download-research.md\ with key findings: CDN direct access confirmed, Range headers supported for resumable downloads, no authentication required for audio URLs, HTTP 206 Partial Content fully implemented by all tested CDNs.

- **Cross-team update (2026-04-14):** Audio download research decision filed. Mal's app type migration + Kaylee's UI implementation APPROVED. All inbox decisions merged to `decisions.md`. Phase 3 (audio download) now unblocked and elevated in the offline sync architecture. Mal's five-phase plan: Phase 0 (simulator), A (changelog), B (sync engine), C (download), D (playback), E (polish). Kaylee completed Phase 0 (AudioContentProviderApp migration) — build passes `-l 3` strict. Key SDK 9.1.0 findings: Communications.SyncDelegate required (Media.SyncDelegate deprecated), Media permission implicit, view construction must be inlined. Ready for Phase A (changelog & position tracking).

- **PocketCastsPodcastService hardened for simulator (2026-04-14):** Reviewed and fixed the real API service for live testing. Key changes:
  1. **Null-safety on login/refresh parsing** — `accessToken`, `refreshToken`, `expiresIn` fields are now validated (instanceof check) before casting. Previously would crash if API response schema changed or returned unexpected types.
  2. **CachedPodcastService `_isConnected()` fixed** — Now checks `connectionAvailable || phoneConnected` instead of just `phoneConnected`. Wi-Fi direct on Venu 4 works without phone BLE link — old check would block all network requests.
  3. **Login failure graceful fallback** — If login fails (bad credentials, network error), `_markDataReady()` is called so UI shows empty state instead of hanging on "Loading..." forever.
  4. **401 handling in all pipelines** — Queue enrichment and episode detail fetches now stop cleanly on 401 (previously silently continued failing). Partial data is saved.
  5. **Non-401 podcast failure recovery** — If podcast list fails with non-401 error, pipeline now continues to queue fetch instead of stopping completely.
  6. **System.println() logging** — Every API call, success/failure, and data count is logged with `YoCasts:` prefix for simulator console debugging.
  7. **Auth endpoint verified** — URL (`/user/login_pocket_casts`), request body (`{email, password, scope}`), response fields (`accessToken`, `refreshToken`, `expiresIn`), and token refresh (`/user/token` with `{grantType, refreshToken}` body, no Bearer header) all match live-tested API reference.
  8. **Garmin `connectionAvailable`** — Confirmed available in SDK 4.2.0+. Returns true for any internet path (phone BLE proxy OR direct Wi-Fi). Safe to use on Venu 4 41mm target.

- **Azure Functions proxy built (2026-04-14):** Created `YoCastsProxy/` — .NET 8 isolated worker Azure Function that proxies PocketCasts API requests and strips heavy fields to keep responses under Garmin's ~32-44 KB `makeWebRequest` limit.
  1. **Problem:** `/user/podcast/list` returns ~43 KB for 15 podcasts (error -402 NETWORK_RESPONSE_TOO_LARGE). Most of the weight is `description` and `descriptionHtml` fields.
  2. **Solution:** Transparent strip-and-forward proxy. Garmin watch sends Bearer token → proxy forwards to PocketCasts → strips heavy fields → returns slim JSON.
  3. **No credentials stored** — proxy is stateless. Auth token comes from the watch, which logs in directly to PocketCasts.
  4. **Route:** `POST /api/pocketcasts/{*path}` mirrors PocketCasts API paths. Garmin app just changes base URL.
  5. **Field stripping per endpoint:**
     - `/user/podcast/list`: whitelist only uuid, title, author, lastEpisodePublished, unplayed, lastEpisodeUuid, folderUuid, sortPosition, dateAdded, url, episodesSortOrder (~43 KB → ~3-5 KB)
     - `/up_next/list`: pass through as-is (already ~540 bytes)
     - `/user/episode`: strip description, descriptionHtml, notes, showNotes
     - All others: recursive strip of description/descriptionHtml
  6. **Project structure:** `PocketCastsProxy.cs` (single function), `Program.cs` (HttpClient DI), `host.json`, `local.settings.json.example`, `README.md` with Azure deployment instructions.
  7. **Build:** `dotnet build` — zero warnings, zero errors. Added to `PodcastApp.sln`.
  8. **Deployment target:** Azure Consumption tier, anonymous auth level (relies on PocketCasts Bearer token for access control).
  9. **Garmin integration:** Watch still authenticates directly to PocketCasts (`/user/login_pocket_casts`). Only subsequent data requests route through the proxy.
- **Azure Function deployed to production (2026-04-16):** Deployed `YoCastsProxy` to Azure using CLI. Infrastructure: resource group `yocasts-rg` (Central US), storage account `yocastsstorage`, Function App `yocasts-proxy` on Consumption (Y1) tier. Deployment via `func azure functionapp publish yocasts-proxy --dotnet-isolated` — build succeeded, synced triggers, function registered. Verified live with curl: returns 401 without Bearer token (correct behavior). Application Insights auto-provisioned. **Live URL:** `https://yocasts-proxy.azurewebsites.net/api/pocketcasts/{*path}`. Garmin app should set `PROXY_BASE = "https://yocasts-proxy.azurewebsites.net/api/pocketcasts"`.
  - Azure resources created: `yocasts-rg` (resource group), `yocastsstorage` (storage), `yocasts-proxy` (function app), `CentralUSPlan` (consumption plan), `yocasts-proxy` (App Insights)
  - Consumption tier means essentially free for expected low traffic (1M free executions/month, 400K GB-s free compute/month)
  - Anonymous auth level — no function keys. Security relies on PocketCasts Bearer tokens forwarded by the Garmin watch.
- **Azure Function redeployed to personal subscription (2026-04-16):** Moved YoCastsProxy deployment from SubGuru Production to Jarod's personal Pay-As-You-Go subscription (`9c6f0000-6cb9-481c-95fe-e92f29ca954f`). Original `yocasts-proxy` deployment on SubGuru left untouched. New infrastructure: resource group `yocasts-rg` (Central US), storage account `yocastsproxystorage` (Standard LRS), Function App `yocasts-proxy-personal` on Consumption (Y1) tier. Name `yocasts-proxy` was globally taken so used `yocasts-proxy-personal`. Deployed via `func azure functionapp publish yocasts-proxy-personal` — build succeeded, triggers synced. Verified live: returns 401 without Bearer token (correct). Updated Garmin `PROXY_BASE` to `https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts`. Rebuilt and deployed to simulator — confirmed end-to-end: login, 15 podcasts loaded, 4 queue items fetched through new proxy. **Live URL:** `https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts/{*path}`.
- **Podcast art color & thumbnail research (2026-04-16):** Investigated how PocketCasts serves artwork and colors. Key discoveries:
  1. **PocketCasts pre-computes dominant colors** — `GET https://static.pocketcasts.com/discover/images/metadata/{uuid}.json` returns a 231-byte JSON with `background`, `tintForDarkBg`, `tintForLightBg`, and FAB/link colors. No auth required, 7-day cache headers. Eliminates any need for server-side image processing (SkiaSharp, ImageSharp, k-means clustering, etc.).
  2. **Artwork served as WebP only** — Available sizes: 200px (3.1 KB), 480px (7.1 KB), 960px (14.7 KB). No PNG/JPG formats. No auth required. URL pattern: `https://static.pocketcasts.com/discover/images/webp/{size}/{uuid}.webp`. Other sizes (48, 64, 100, 120, etc.) return 404.
  3. **Base64 thumbnails won't fit** — 15 × 4.2 KB (base64 of 200px WebP) = ~63 KB. Way over CIQ's 32 KB limit. Even resized 30×30 JPEG at q50 (~800 bytes × 15 = 12 KB) is marginal and requires ImageSharp.
  4. **CIQ `makeImageRequest()` is the right approach for thumbnails** — Native image loading, automatic resizing, returns `BitmapResource`. Avoids bloating JSON response.
  5. **Recommendation: colors-only in v1, thumbnails in v2** — Add `artColor` and `artTint` fields to the proxy's podcast list response (~1.8 KB total for 15 podcasts). When artwork is needed, add `artUrl` and let CIQ load images natively. If CIQ doesn't support WebP, add a proxy conversion endpoint.
  6. **No new dependencies needed** — In-memory `ConcurrentDictionary` cache for colors. No ImageSharp, no Azure Blob Storage, no cold start impact.
  - Design proposal filed: `.squad/decisions/inbox/wash-art-color-design.md`
- **Download data layer built (2026-04-16):** Created the Phase B/C data layer for episode audio downloads — three components:
  1. **DownloadQueue module** (`source/services/DownloadQueue.mc`): Replaced the mock stub with a real Application.Storage-backed download queue. Persists across app restarts via `yc_dl_queue` key. FIFO ordering with max 20 items. Status tracking (PENDING/DOWNLOADING/DOWNLOADED/FAILED) with 3-retry limit on failures. Backward-compatible API — all constants (DL_UUID, DL_STATUS, etc.) and methods (getDownloads, addToQueue, removeFromQueue, toEpisodeDict, getStatusText) preserved so DownloadsView works unchanged. New methods: updateStatus(), updateProgress(), isInQueue(), getNextPending(), purgeCompleted(), purgeFailed(), clearQueue().
  2. **StorageManager module** (`source/services/StorageManager.mc`): Tracks downloaded episode metadata in Application.Storage (`yc_downloads` key). Maps episodeUuid → {podcastUuid, refId, downloadedAt, fileSize, contentType}. No Media module imports — works in both simulator and device builds. Methods: getAvailableSpace(), getDownloadedEpisodes(), isEpisodeDownloaded(), getEpisodeRefId(), markDownloaded(), removeDownload(), getDownloadCount(), getTotalDownloadSize().
  3. **AudioInfoProxy endpoint** (`YoCastsProxy/AudioInfoProxy.cs`): New Azure Function `GET /api/pocketcasts/episode/{uuid}/audio-info`. Fetches episode metadata from PocketCasts (gets audio URL), then issues a HEAD request to the CDN to resolve file size, content type, and final URL after redirects — without downloading the full audio file. Returns {audioUrl, fileSize, contentType, duration, title, podcastUuid, episodeUuid}. Watch calls this before download to check storage capacity. Registered separate `AudioHead` HttpClient with 15s timeout for CDN HEAD requests.
  - All three builds pass clean at `-l 3` strict: simulator (monkey.simulator.jungle), device (monkey.jungle), and proxy (dotnet build).
  - Fixed pre-existing proxy build break: `StripAndEnrichPodcastList` reference in `StripFields` method (from art color enrichment work by another session) was broken by missing async/import. Restored correct `async Task<string>` signature and `System.Collections.Concurrent` import.
  - Key design decisions: DownloadQueue and StorageManager are intentionally Media-free modules — they work in the simulator where source/media/ is excluded. The refId field in StorageManager is a string that will hold the Media.ContentRef ID on real hardware.
- **Art color enrichment deployed (2026-04-16):** Implemented and deployed art color extraction in the Azure Function proxy. `/user/podcast/list` responses now include `artColor` (background hex), `artTint` (accent hex from `tintForDarkBg`), and `artUrl` (200px WebP CDN URL) per podcast. Colors fetched in parallel via `Task.WhenAll()` from `static.pocketcasts.com/discover/images/metadata/{uuid}.json`. In-memory `ConcurrentDictionary` cache with 7-day TTL avoids redundant fetches on warm instances. Failures per-podcast are swallowed gracefully — response still returns without colors for that entry. Added `PocketCastsStatic` named HttpClient in `Program.cs`. Deployed to `yocasts-proxy-personal`. Adds ~120 bytes per podcast (~1.8 KB for 15), well within 32 KB budget.
- **Audio URL auth validation DEFINITIVELY confirmed (2026-04-19):** Ran structured 64KB Range GET test against 5 episodes from 5 different podcasts across 4 CDNs (SupportingCast, Megaphone, Transistor, Simplecast). **Results:**
  1. **All 5/5 episodes accessible WITHOUT Bearer token** — CDN audio is truly public. Garmin SyncDelegate can download directly without any PocketCasts auth headers.
  2. **All 4/4 CDNs support HTTP 206 Partial Content** — Range headers work everywhere. Resumable downloads fully confirmed for Garmin's chunked download pattern.
  3. **SupportingCast JWT still valid after 7+ days** — Token embedded in URL path. Re-fetch before download as precaution, but URLs are more durable than expected.
  4. **Redirect chains: 1-6 hops** — Garmin's `makeWebRequest()` follows redirects natively, so no manual redirect handling needed.
  5. **Response sizes: 30-243 MB** — All tested episodes return accurate `Content-Length` via HEAD and `Content-Range` via Range GET.
  - Test tool: `AudioAuthValidator.cs` added as menu option 17 in API tester. Results saved to `test-results/audio-auth-validation-*.json`.
- **AudioInfoProxy enhanced and deployed (2026-04-19):** Major upgrade to the audio info endpoint at `GET /api/pocketcasts/episode/{uuid}/audio-info`:
  1. **New fields:** `requiresAuth` (boolean — flags SupportingCast premium URLs), `podcastTitle` (string — from episode metadata).
  2. **In-memory caching:** Standard episodes cached 2 hours, SupportingCast (JWT) URLs cached 30 minutes. `ConcurrentDictionary` with inline eviction at 200+ entries.
  3. **SupportingCast detection:** `IsPremiumUrl()` detects `supportingcast.fm/content/` patterns. These get `requiresAuth: true` so Garmin client knows to re-fetch fresh URLs before download.
  4. **Response shape matches spec:** `{uuid, audioUrl, fileSize, duration, contentType, requiresAuth, title, podcastTitle, podcastUuid}`. ~515 bytes typical response — well under 2 KB Garmin limit.
  5. **Deployed to:** `yocasts-proxy-personal.azurewebsites.net`. Live-verified with both standard and premium episodes.
- **PocketcastsApiTesting build fixed (2026-04-19):** Excluded 4 legacy Tizen-era files (`PocketCastsApiService.cs`, `PocketCastsApiAccessorcs.cs`, `AuthResponse.cs`, `Podcast.cs`) from compilation in `.csproj`. These used Newtonsoft.Json / `PodcastApp.Models` namespace from the original Tizen project and broke the build after migration to System.Text.Json. Kept as reference files, just excluded via `<Compile Remove="..."/>`.

**[2026-04-19 Cross-Agent Sync]**
- **From Kaylee:** Phase A + B complete. ChangeLog with convenience API, PositionTracker class (15s intervals, battery-adaptive), SyncEngine 7-step state machine all shipped. All integrated into NowPlayingView and YoCastsApp. Race condition solved via changelog snapshot pattern. Sync engine ready for live testing against `/user/in_progress` endpoint — verify response format includes status and position data for bulk reconciliation.
- **From Mal:** Phase C gate clear. All architectural decisions finalized: "furthest position wins", max(status) hierarchy, server-authoritative metadata, watch-participates in playback. Hardware testing protocol drafted (40+ cases, 5-day execution). Phase C depends on: Background permission in manifest, Venu 4 hardware available, `/user/in_progress` API validation. Top risks documented (64 KB SyncDelegate limit, HTTP_RESPONSE_CONTENT_TYPE_AUDIO on hardware, CDN redirects, interrupted downloads).
- **Kaylee Phase C DELIVERED (2026-04-19T1625Z):** Audio download pipeline complete. YoCastsSyncDelegate.mc (login→AudioInfo→download→store, ~300 lines) + YoCastsContentIterator.mc (playlist iteration, ~125 lines). Added Background + PersistedContent manifest permissions. Key finding: `makeWebRequest(HTTP_RESPONSE_CONTENT_TYPE_AUDIO)` returns `PersistedContent.Iterator` — call `iter.next()` to extract `Media.ContentRef`. Wired DownloadsView to StorageManager for cleanup. Both device and sim builds pass `-l 3` strict. No new Wash API endpoints needed — proxy already provides audio URLs via AudioInfoProxy. Ready for hardware integration testing (gate: Venu 4 + Background permission).
