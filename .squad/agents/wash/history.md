# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

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

- **Cross-team update (2026-04-14):** Audio download research decision filed. Mal's app type migration + Kaylee's UI implementation APPROVED. All inbox decisions merged to `decisions.md`. Phase 3 (audio download) now unblocked and elevated in the offline sync architecture. Mal's five-phase plan: Phase 0 (simulator), A (changelog), B (sync engine), C (download), D (playback), E (polish). Wash's two-token OAuth flow decision awaiting implementation kickoff.
