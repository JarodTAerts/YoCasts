# Squad Decisions

## Active Decisions

### Live PocketCasts API Schema Validated (2026-04-12)

**By:** Wash (API Dev)  
**Date:** 2026-04-12  
**Affects:** Mal (Lead), Kaylee (Garmin Dev)

Executed comprehensive live API testing: 25 endpoints tested, 20 confirmed working, 5 failed. All responses captured for reference.

**Critical Findings for Garmin App:**
1. **Up Next is a map, not array** — `/up_next/list` returns `{ order: [...], episodes: {...} }`. Episodes field is dictionary keyed by UUID. Garmin code must iterate order and lookup UUIDs.
2. **Episode metadata gaps** — `/user/podcast/episodes` omits titles, URLs, dates. Only returns status fields (playingStatus, playedUpTo, starred, duration, isDeleted). Full metadata requires per-episode `POST /user/episode` call or bulk fetch from `podcast-api.pocketcasts.com`.
3. **Token refresh broken** — `POST /user/token` returns 400. Workaround: re-login with credentials if token expires.
4. **Search requires auth** — `POST /discover/search` returns 401 without Bearer token.
5. **Stats are strings** — `/user/stats/summary` time values are strings, not numbers. Parse accordingly.

**Confirmed Working:** Login, podcast list, episodes, episode detail, new releases, in progress, starred, history, up next, bookmarks, stats, subscription, search, recommend episodes, podcast recs, social recs, podcast full metadata, featured, trending, categories, discover.

**Failed:** Token refresh (400), named settings (404), user profile (404), files list (404), user filters (404), user_podcast recs (404).

---

### PocketCasts API Surface Documented

**By:** Wash (API Dev)  
**Date:** 2026-04-11  
**Affects:** All agents

Completed full investigation of the PocketCasts API. Discovered 30+ endpoints beyond the 4 in the old code. Rebuilt the C# test tool (`PocketcastsApiTesting/`) and created `docs/pocketcasts-api-reference.md`.

**Key Findings:**
1. **The real queue is `/up_next/*`**, not `/user/new_releases`. The old code's "queue" was just new episodes.
2. **Playback sync is via `/sync/update_episode`** — critical for reporting position back to PocketCasts.
3. **Origin header changed** from `playbeta.pocketcasts.com` to `play.pocketcasts.com`.
4. **No official API docs exist.** Everything is reverse-engineered. Reference doc should be treated as living documentation.
5. **Credentials no longer hardcoded.** Test tool uses env vars (`POCKETCASTS_EMAIL`, `POCKETCASTS_PASSWORD`) or CLI args.

---

### Garmin App Architecture & Implementation Plan

**Author:** Mal (Lead)  
**Date:** 2026-04-11  
**Status:** Active

Clear blueprint for the Garmin Connect IQ watch app with decision rationale.

**Decisions:**
1. **Menu2 for all list UIs** — Queue, Subscribed Podcasts, Episode List use `WatchUi.Menu2`. Handles round/rectangular screens natively.
2. **No text input on watch** — Credentials entered via Garmin Connect Mobile settings (`Application.Properties`).
3. **Dictionaries, not classes** — Data models are `Dictionary` instances. Matches `makeWebRequest` output, saves memory.
4. **Single PocketCastsService module** — Merged accessor/service pattern. No indirection needed on constrained device.
5. **Cache with LRU eviction** — `Application.Storage` for offline support (~61 KB budget). Episode caches per podcast with `ep_<uuid>` keys.
6. **Five-phase build plan** — Phase 1: skeleton + auth. Phase 2: queue + subscribed. Phase 3: episode browsing. Phase 4: polish + hardware. Phase 5: stretch goals.
7. **Audio download is Phase 5** — Too complex and memory-heavy for MVP.

---

### Offline Mode & Sync Reconciliation Architecture (2026-04-12)

**By:** Mal (Lead)  
**Date:** 2026-04-12  
**Affects:** Kaylee (Garmin Dev), Wash (API Dev)  
**Document:** `docs/offline-sync-design.md`

Comprehensive offline mode and sync reconciliation architecture for YoCasts.

**Key Decisions:**
1. **"Furthest position wins"** — Playback conflicts resolved by `max(localPos, serverPos)`. Status hierarchy: COMPLETED > IN_PROGRESS > NOT_PLAYED. Completed is terminal.
2. **Structured changelog** — All offline mutations in `Application.Storage` key `"changelog"`, per-episode coalescing, cleared only after confirmed server push.
3. **Queue reconciliation** — Server order is base. Local completions remove episodes. Phone-side additions merged. Server wins for removals.
4. **Authority split** — Server authoritative for metadata/subscriptions. Watch participates in playback resolution via max().
5. **Push-then-pull sync** — 7-step idempotent state machine: auth → read changelog → fetch server → reconcile → push → refresh caches → cleanup.
6. **Four-phase implementation** — (1) Metadata caching, (2) Position tracking + sync, (3) Audio download via Media module, (4) Full reconciliation. Audio download elevated from Phase 5 to Phase 3.

**Open Questions:**
- Garmin Media module API specifics — Kaylee needs to prototype ContentProvider/SyncDelegate.
- Exact Application.Storage limit on Venu 4 41mm — needs hardware testing.
- Whether `/user/in_progress` supports bulk reconciliation.

---

### User Directive: Always Use Best Models (2026-04-12)

**By:** Jarod Aerts  
**Date:** 2026-04-12  
**Affects:** All agents

All agents should always be started with Claude Opus 4.6 or better — always use the best models available.

---

### Garmin UX Spec Established

**Author:** Kaylee (Garmin Dev)  
**Date:** 2026-04-11  
**Affects:** All team members

Complete Garmin Connect IQ UX design with 7 screens and memory budgets.

**Key Architectural Choices:**
1. **Settings-based auth** — no on-watch login form.
2. **Menu2 for all list screens** — Home, Queue, Podcasts, Episodes.
3. **Now Playing as custom View** — only fully custom screen (progress arc, controls).
4. **makeWebRequest + proxy for v1** — watch calls proxy via phone, no custom companion app.
5. **Memory-first design** — 100 KB peak budget, hard caps on list sizes.
6. **No artwork in v1** — text-only lists.

**Open Questions:**
- Audio playback: stream vs download? (Biggest unresolved architecture question)
- Proxy hosting location and auth token management

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
