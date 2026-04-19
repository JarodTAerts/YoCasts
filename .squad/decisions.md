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

### Async Service Interface with Cache + Sync Getters (2026-04-12)

**By:** Wash (API Dev)  
**Date:** 2026-04-12  
**Affects:** Kaylee (Garmin Dev), Mal (Lead)

Changed `IPodcastService` from a purely synchronous interface to a hybrid **cache-first + async fetch** pattern to support `Communications.makeWebRequest()` (which is inherently async on Garmin).

**What Changed:**
1. **5 new methods on IPodcastService:** `isAuthenticated()`, `isDataReady()`, `hasEpisodesForPodcast(uuid)`, `fetchAll()`, `requestEpisodesForPodcast(uuid)`.
2. **Original 4 sync getters unchanged** — `getSubscribedPodcasts()`, `getEpisodesForPodcast(uuid)`, `getQueue()`, `getNowPlaying()` return cached data (empty array if not yet loaded).
3. **All view type annotations changed** from `MockPodcastService` to `IPodcastService` — views are now service-implementation-agnostic.

**Why This Design:** `makeWebRequest()` is async but Menu2 builds items in constructor and can't update after. Cache-first hybrid lets MockPodcastService work unchanged (data pre-loaded), PocketCastsPodcastService fetch in background and call `requestUpdate()`, and views call sync getters as usual.

**Open Questions:**
- Episode list shows "Loading..." on first visit with real API — needs view swap mechanism (Phase 2 polish).
- Token refresh doesn't queue original request during refresh — acceptable for v1 (1hr token lifetime).

---

### Revert to watch-app Type — AudioContentProviderApp Crash Fix (2026-04-14)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Status:** ⚠️ SUPERSEDED (see "Re-migrate to AudioContentProviderApp" below)  
**Affects:** Mal (Lead), all agents

Initial diagnosis: AudioContentProviderApp lifecycle incompatible with browse-only app. Reverted manifest to `watch-app` and YoCastsApp to AppBase until audio download implemented (Phase C). Media stubs preserved for future use.

**Root Cause (initially suspected):**
- `getContentDelegate()` → `getContentIterator()` → `get()` returning null caused native media player crash.

**Changes Made:**
- manifest.xml: type → watch-app
- YoCastsApp.mc: Base → AppBase, removed provider methods
- monkey.jungle: Excluded source/media

**Prerequisites to Switch Back:**
1. SyncDelegate must download real audio (makeWebRequest + HTTP_RESPONSE_CONTENT_TYPE_AUDIO)
2. ContentIterator.get() must return valid ContentObj via Media.getCachedContentObj()
3. ContentIterator.initializePlaylist() enumeration via Media.getContentRefIter()
4. Playback config view checks for content, shows "No episodes downloaded" when empty

---

### Re-migrate to AudioContentProviderApp (2026-04-14)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Affects:** Mal (Lead), Wash (API Dev), Jarod Aerts  
**Status:** Active

The earlier revert to watch-app was based on misdiagnosis. AudioContentProviderApp is the correct type; the crash was our bug, not a platform limitation.

**What Was Wrong Last Time:**
- Assumed ContentIterator.get() returning null caused crash — it doesn't. Native player shows "No Media" (expected).
- May have kept getInitialView() overridden, which conflicts with audio provider launch flow.
- Possible API 6.0 simulator bug (unrelated to Venu 4 target).

**Current Implementation:**
- manifest.xml: type="audio-content-provider-app"
- YoCastsApp.mc: extends AudioContentProviderApp with all provider methods
- getPlaybackConfigurationView() as entry point (not getInitialView())
- ContentIterator stubs return null safely
- Three-state auth gate: unauthenticated → LoginPromptView, authenticated → HomeMenuView
- All views, services, models unchanged

**How to Launch in Simulator:**
1. Build: monkeyc -d venu441mm -f monkey.jungle -o bin/YoCasts.prg -l 3
2. Start simulator: simulator.exe
3. Deploy: monkeydo bin/YoCasts.prg venu441mm
4. Navigate: Music Controls → Music Providers → YoCasts
5. System calls getPlaybackConfigurationView() → HomeMenuView (or LoginPromptView if not authed)

**Next Steps:**
- Verify music provider flow in simulator
- Implement SyncDelegate download logic (Phase C)
- Test on Venu 4 hardware

---

### Dual-Build Configuration for Simulator vs Device (2026-04-14)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Affects:** Jarod Aerts, Mal (Lead), all future Garmin builds  
**Status:** Approved (for future use post-Phase C)

The CIQ simulator cannot run `audio-content-provider-app` types, but watch-app can't play audio. Solution: dual-jungle build system with separate app entry points.

**Build Configuration:**
- **Simulator Build** (`monkey.simulator.jungle` + `manifest.simulator.xml`):
  - Type: watch-app (AppBase)
  - Entry: source/sim/YoCastsApp.mc
  - Media stubs: excluded
- **Device Build** (`monkey.jungle` + `manifest.xml`):
  - Type: audio-content-provider-app (AudioContentProviderApp)
  - Entry: source/app/YoCastsApp.mc
  - Media stubs: included (source/media/)

**Build Commands:**
```bash
# Simulator (UI development)
monkeyc -d venu441mm -f monkey.simulator.jungle -o bin/YoCasts.prg -l 3

# Device (hardware deployment)
monkeyc -d venu441mm -f monkey.jungle -o bin/YoCasts.prg -l 3
```

**Key Implementation Detail:**
Connect IQ `sourcePath` is recursive. Both jungle files define separate entry points in non-nested directories (source/app/ and source/sim/). Each jungle picks up only one YoCastsApp class.

**Status:**
✅ Both builds pass clean at `-l 3` strict. README updated. Ready for Phase C implementation when dual builds are needed.

---

### Phase C Readiness Assessment (2026-04-16)

**By:** Mal (Lead)  
**Affects:** Kaylee (Garmin Dev), Wash (API Dev), Jarod Aerts  
**Status:** Active

Phase C (audio download via SyncDelegate) is architecturally unblocked but has two prerequisites before implementation:

1. **Phase B (Sync Engine) must complete** — SyncEngine class needs to push/pull/reconcile successfully. ✅ **COMPLETE** (Kaylee)
2. **`Background` permission must be added to manifest.xml** — one-line change, blocking for SyncDelegate background execution.

**Phase C Gate — Current Status:**
- ChangeLog works ✅
- DownloadQueue works ✅
- ConnectivityManager works ✅
- SyncEngine pushes and pulls ✅
- Audio URL auth validated ✅ (Wash confirmed no auth needed)
- Venu 4 hardware available ❓ (needed)

**Top Risks (ordered by severity):**
1. **64 KB SyncDelegate memory limit** — only 15-24 KB usable. Mitigation: minimal imports, direct Storage reads.
2. **`HTTP_RESPONSE_CONTENT_TYPE_AUDIO` behavior** — only verified in MonkeyMusic sample. Must test on hardware immediately.
3. **CDN redirect chain handling** — all audio URLs redirect 1-6 times. Unknown if Garmin follows automatically.
4. **Interrupted download handling** — no resume in v1, partial downloads restart from scratch.
5. **Per-app storage quota** — unknown exact limit on Venu 4.

**Action Items:**
- [ ] Kaylee: Add `<iq:uses-permission id="Background"/>` to manifest.xml
- [ ] Kaylee: Resolve CacheManager API gap (addChangelogEntry/savePosition live in separate modules vs implementation plan)
- [ ] Jarod: Acquire/prepare Venu 4 hardware for Phase C testing
- [ ] All: Review `docs/hardware-testing-plan.md` for testing protocol

**Documents:**
- `docs/phase-c-readiness.md` — full codebase audit + risk assessment
- `docs/hardware-testing-plan.md` — 40+ test cases, 5-day execution plan

---

### Brand Color Tinting in All List Views (2026-04-19)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-19  
**Affects:** Wash (API Dev), Mal (Lead)  
**Status:** Complete

Implemented per-item brand color tinting in all three list views (Podcasts, Queue, Episodes) using `CustomMenuItem` with `artColor`/`artTint` from the proxy.

**Design Choices:**
1. **CustomMenuItem for all lists** — Podcasts, Queue, and Episodes now use custom-drawn menu items instead of plain `MenuItem`. Full control over background, text, and indicator rendering.

2. **Color lookup pattern** — `DataFormat.lookupPodcastColors(podcasts, podcastUuid)` resolves colors by UUID from the subscribed podcast cache. Queue episodes look up their parent podcast's colors. Episode list items inherit the parent podcast's colors uniformly.

3. **Contrast safety** — `DataFormat.ensureContrast(fg, bg)` checks luminance difference. If text would be unreadable (diff < 0.25), it falls back to white (on dark bg) or black (on light bg).

4. **Dim factors per context:**
   - Podcast list: 20% unfocused, 35% focused
   - Queue: 15% unfocused, 30% focused (subtler since queue has mixed podcasts)
   - Episode list: 10% unfocused, 22% focused (subtlest — single podcast context)

5. **Zero memory cost** — Colors are integer values. No bitmaps, no additional storage.

**Implications:**
- **Wash:** Proxy must continue serving `artColor` and `artTint` as hex strings or pre-parsed integers per podcast in `/user/podcast/list`.
- **Mal:** CustomMenuItem is now the standard pattern for all branded list UIs. Future screens should follow the same pattern.

---

### Phase A Changelog + Position Tracking Implementation (2026-07-16)

**By:** Kaylee (Garmin Dev)  
**Affects:** Wash (API Dev), Mal (Lead)  
**Status:** Complete

Enhanced `ChangeLog.mc` and created `PositionTracker.mc` as the foundation for Phase B sync engine.

**Key Design Decisions:**

1. **Enhanced existing ChangeLog module** — Added convenience methods (`logPositionUpdate`, `logStatusChange`, `logQueueAction`, `getChangelog`, `clearChangelog`) on top of existing `addEntry` API.

2. **PositionTracker is a class, not a module** — Timer callbacks require `method(:symbol)` which needs class instance context (`self`). Modules can't provide this.

3. **Dual-write pattern** — PositionTracker writes to both ChangeLog (for eventual sync push) and CacheManager (for instant offline resume).

4. **Reduced MAX_ENTRIES from 100 to 50** — Design doc's 8 KB budget. With coalescing, 50 entries sufficient for typical session.

5. **Battery-adaptive intervals** — 15s normal, 30s when battery < 20%. Checked via `System.getSystemStats().battery`.

**Files Changed:**
- `YoCastsGarmin/source/services/ChangeLog.mc` — Enhanced with convenience API + new types
- `YoCastsGarmin/source/services/PositionTracker.mc` — **NEW** — Timer-based position logger
- `YoCastsGarmin/source/views/NowPlayingView.mc` — Integrated PositionTracker lifecycle

**For Wash (Phase B):** Sync engine should call `ChangeLog.getChangelog()` and `ChangeLog.clearChangelog()` only after confirmed server push.

---

### SyncEngine Architecture (Phase B) (2026-07-18)

**By:** Kaylee (Garmin Dev)  
**Affects:** Mal (Lead), Wash (API Dev), Zoe (Testing)  
**Status:** Complete

Implemented the 7-step sync engine as a **class** (not module) in `source/services/SyncEngine.mc`.

**Key Decisions:**

1. **Class, not module:** SyncEngine must be a class because `method(:callback)` for async `makeWebRequest` requires a class instance context.

2. **Own auth flow:** SyncEngine manages its own login/token independently of PocketCastsPodcastService. Reads same credentials from `Application.Properties`.

3. **Changelog snapshot at step 2:** Solves the race condition flagged by Zoe. Snapshot entry IDs tracked in a Dictionary set. Cleanup selectively removes only snapshot entries — new entries added by PositionTracker during sync are preserved.

4. **Hybrid server fetch:** Uses `/user/in_progress` bulk endpoint first (covers ~95% of cases in 1 request), then individual `/user/episode` only for changelog episodes not found in bulk response.

5. **Aggregation before reconciliation:** Multiple changelog entries per episode (e.g., POSITION_UPDATE + EPISODE_COMPLETED) are aggregated to a single local state using `max(position)`, `max(status)`, `max(duration)`.

6. **Partial push success:** If some pushes fail and others succeed, only entries for successfully-pushed episodes are cleared. Failed episodes' changelog entries preserved for next sync cycle.

7. **Refresh via service.fetchAll():** Step 6 triggers the existing service pipeline rather than doing its own cache refresh.

**Files Changed:**
- **Created:** `YoCastsGarmin/source/services/SyncEngine.mc`
- **Modified:** `YoCastsGarmin/source/app/YoCastsApp.mc` (lifecycle integration)

**Open Questions:**
- Should sync display a UI indicator ("Syncing..." toast)? Currently logs to console.
- Should we add a manual "Sync Now" action in the settings menu?
- The `/user/in_progress` response format needs verification with live API testing (Wash).

---

### Audio URL Auth Confirmed + AudioInfo Proxy Enhanced (2026-04-19)

**By:** Wash (API Dev)  
**Affects:** Kaylee (Garmin Dev), Mal (Lead)  
**Status:** Complete

**Audio URL Auth Validation — DEFINITIVELY CONFIRMED**

Live testing on 5 episodes from 5 podcasts across 4 CDNs:

| Podcast | CDN | Auth Required? | Range Support? | File Size |
|---------|-----|:-:|:-:|-----------|
| The Vergecast: Ad-Free | supportingcast.fm | NO | YES (206) | 69.6 MB |
| The Vergecast | megaphone.fm | NO | YES (206) | 84.9 MB |
| Acquired | transistor.fm | NO | YES (206) | 242.5 MB |
| Timesuck | simplecastaudio.com | NO | YES (206) | 102.2 MB |
| 99% Invisible | simplecastaudio.com | NO | YES (206) | 30.4 MB |

**Conclusion:** Garmin SyncDelegate can download audio directly from CDN URLs. No PocketCasts auth headers needed. All CDNs support Range (resumable).

**AudioInfo Proxy Endpoint — Enhanced & Deployed**

**Endpoint:** `GET https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts/episode/{uuid}/audio-info`

**Response shape:**
```json
{
  "uuid": "episode-uuid",
  "audioUrl": "https://cdn.example.com/episode.mp3",
  "fileSize": 88844501,
  "duration": 5428,
  "contentType": "audio/mpeg",
  "requiresAuth": false,
  "title": "Episode Title",
  "podcastTitle": "Podcast Name",
  "podcastUuid": "podcast-uuid"
}
```

**Enhancements:**
1. `requiresAuth` field — flags SupportingCast premium URLs so Garmin client can re-fetch before download
2. `podcastTitle` field — from episode metadata
3. In-memory caching — 2hr TTL for standard, 30min for premium URLs
4. SupportingCast detection via `IsPremiumUrl()` pattern matching
5. Response ~515 bytes typical — well under 2 KB Garmin per-value limit

**For Kaylee:** SyncDelegate should call this endpoint before each download to get audioUrl, fileSize, requiresAuth, and contentType.

---

### Sync Engine Test Plan Published (2026-04-14)

**By:** Zoe (Tester)  
**Affects:** Kaylee (Garmin Dev), Mal (Lead), Wash (API Dev)  
**Document:** `docs/test-plan-sync-engine.md`  
**Status:** Complete

Published comprehensive test plan covering Phase A (Changelog + Position Tracker) and Phase B (Sync Engine) with 48 structured test scenarios:
- 18 ChangeLog tests (CL-01 through CL-18)
- 10 PositionTracker tests (PT-01 through PT-10)
- 14 SyncEngine tests (SE-01 through SE-14)
- 6 Cross-Cutting tests (CC-01 through CC-06)

**Key Decisions:**

1. **Tests written against spec, not implementation** — Position tracker and sync engine weren't built yet at test time. Test IDs and expected values may need revision once Kaylee's implementation is final.

2. **MAX_ENTRIES = 100** — Task brief mentioned 50, but `ChangeLog.mc` and design spec both say 100. Tests use 100.

3. **Input validation deferred to sync layer** — Recommend `addEntry()` does NOT validate inputs (empty UUIDs, negative positions). Keep logging fast. Validation happens at reconciliation time. ✅ Kaylee implemented this pattern.

4. **Concurrent modification flagged as risk** — `addEntry()` does a read-modify-write. If position tracker timer fires during sync engine `clearEntries()`, entries could be lost. ✅ Kaylee fixed via changelog snapshot pattern.

**Test Breakdown:**
- Phase A tests (18 of 18) run fully in the simulator
- Phase B tests need mocked API responses
- Cross-cutting tests (BT disconnect, Wi-Fi fallback, memory pressure, app kill) require hardware

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
