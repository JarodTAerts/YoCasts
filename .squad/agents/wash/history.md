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
