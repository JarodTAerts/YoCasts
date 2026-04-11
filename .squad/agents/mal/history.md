# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- The repo contains an older Tizen watch app (C#/Xamarin) in `PodcastApp/` with reverse-engineered PocketCasts API work in `PodcastApp/Services/PocketCastsApiService.cs` and `PodcastApp/Accessors/`. The API endpoints and auth flow documented there may be outdated but are a useful starting reference.
- PocketCasts API uses token-based auth (login returns a token used in subsequent requests).
- Known API operations from prior work: login, get subscribed podcasts, get episodes for podcast, get queue (new/unplayed episodes).
- Created comprehensive implementation guide at `docs/garmin-app-implementation-guide.md` covering architecture, constraints, API surface, data flow, UI screens, caching, and build phases.
- Architecture decision: Use `WatchUi.Menu2` for all list views (Queue, Subscribed, Episodes) — it handles scrolling and layout across round/rectangular screens automatically.
- Architecture decision: No text input on watch. User credentials entered via Garmin Connect Mobile app settings (`Application.Properties`), not typed on the watch.
- Architecture decision: Data models are `Dictionary` instances (not classes) — this matches how `makeWebRequest` delivers parsed JSON and avoids unnecessary object overhead.
- Architecture decision: 5-phase build plan — Phase 1 (skeleton + auth), Phase 2 (queue + subscribed), Phase 3 (episode browsing), Phase 4 (polish + hardware test), Phase 5 (enhancements/stretch).
- Architecture decision: Merge PocketCastsApiService and PocketCastsApiAccessor into a single `PocketCastsService.mc` on Garmin — no need for the accessor pattern on a constrained device.
- Architecture decision: Cache strategy uses `Application.Storage` with LRU eviction for per-podcast episode caches. 32 KB per-value limit means trimming episode fields to essentials.
- The Tizen app's `DownloadService.cs` handles episode audio download — this is explicitly deferred to Phase 5 (stretch) on Garmin due to complexity and memory constraints.
- The `Origin: https://playbeta.pocketcasts.com` header is required on PocketCasts API requests (see accessor code).
- **Cross-team update (2026-04-11):** Wash discovered the real queue endpoints are `/up_next/*`, not `/user/new_releases`. Playback sync uses `/sync/update_episode`. This resolves a critical API surface question — the endpoints our service module will use are now fully documented in `docs/pocketcasts-api-reference.md`. Kaylee's UX directly targets these endpoints.
