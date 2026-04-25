# Decision Log

## Azure Function Proxy for PocketCasts API (2026-04-14)

**By:** Wash (API Dev)  
**Date:** 2026-04-14  
**Affects:** Kaylee (Garmin Dev), Mal (Lead)

### Context

Garmin Connect IQ's `Communications.makeWebRequest()` has a hard ~32-44 KB response limit (error `-402 NETWORK_RESPONSE_TOO_LARGE`). Our `/user/podcast/list` response is 43 KB for just 15 podcasts because of huge `description` and `descriptionHtml` fields the watch doesn't need.

### Decision

Created `YoCastsProxy/` — a .NET 8 isolated worker Azure Function that acts as a transparent strip-and-forward proxy between the Garmin watch and PocketCasts API.

**Key design choices:**
1. **Stateless** — no credentials stored. Bearer token comes from the watch and is forwarded.
2. **Whitelist approach for podcast list** — only 11 fields kept (uuid, title, author, etc.). This is more aggressive than blacklist but guarantees size.
3. **Catch-all route** (`/api/pocketcasts/{*path}`) — mirrors PocketCasts paths so the Garmin app just changes base URL.
4. **No caching** — keep it simple for v1. Could add Azure Cache for Redis later if needed.
5. **Anonymous auth level** — the function itself has no auth gate; PocketCasts Bearer token provides access control.
6. **Consumption tier** — scales to zero, minimal cost for personal use.

### Impact on Garmin App

Kaylee needs to:
1. Add a configurable proxy base URL (could be an app property)
2. Route data requests through the proxy instead of directly to PocketCasts
3. Keep auth requests (`/user/login_pocket_casts`, `/user/token`) going directly to PocketCasts — the proxy is only for data endpoints

### Alternatives Considered

- **Client-side field filtering in Monkey C** — not possible, the response is too large to even receive
- **Garmin companion app** — too complex, requires Android/iOS development
- **Cloudflare Worker** — viable but .NET matches our stack

---

## Azure Function Proxy Integration — Garmin Side (2026-04-14)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Affects:** Wash (API Dev), Mal (Lead), Jarod Aerts

### Decision

Garmin app now routes all data-fetching API calls through an Azure Function proxy (`PROXY_BASE` constant in `PocketCastsPodcastService.mc`). Login and token refresh remain direct to `api.pocketcasts.com`.

### Rationale

PocketCasts API responses (especially `/user/podcast/list` with full descriptions) can exceed the CIQ ~32KB `makeWebRequest()` response limit. The proxy strips heavy fields (`description`, `descriptionHtml`, etc.) before forwarding to the watch.

### What Changed

- Added `PROXY_BASE` constant alongside existing `API_BASE` in `PocketCastsPodcastService.mc`
- `_makeAuthPost()` now uses `PROXY_BASE` for all data calls
- Removed `:maxLength => 65536` option from proxy calls (proxy guarantees small responses)
- Login (`_login()`) and token refresh (`_doTokenRefresh()`) still use `API_BASE` directly
- Class docstring updated with proxy architecture explanation

### Dependencies

- **Wash/Jarod:** Azure Function must be deployed and `PROXY_BASE` URL updated in the code before real API testing
- Proxy must forward `Authorization: Bearer {token}` header as-is
- Proxy endpoints must mirror PocketCasts API paths (e.g., `/user/podcast/list`, `/up_next/list`, `/user/episode`)

### Build Verification

Build passes `monkeyc.bat -d venu441mm -f monkey.simulator.jungle -o bin\YoCasts.prg -l 3` (strict mode, zero errors).

---

## AudioContentProviderApp Migration Complete — SDK Constraints & Implementation (2026-04-14)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Phase:** Phase 0  
**Status:** COMPLETED

### Key Findings (SDK 9.1.0)

1. **No `Media` Permission in Manifest** — The SDK rejects `<iq:uses-permission id="Media"/>` as invalid. The Media module is implicitly available for `audio-content-provider-app` types. Only `Communications` permission is needed. Confirmed by Garmin's MonkeyMusic sample.

2. **Communications.SyncDelegate Required** — SDK 9.1.0 enforces `Null or Communications.SyncDelegate` as the return type for `getSyncDelegate()`. Media.SyncDelegate is fully deprecated at the type system level. All future sync code must extend Communications.SyncDelegate.

3. **Inlined View Construction** — The strict type checker requires AudioContentProviderApp view methods to return specific tuple types. A shared helper method returning untyped Array causes type errors. Each method (`getInitialView`, `getPlaybackConfigurationView`, `getSyncConfigurationView`) must construct views inline.

4. **SyncConfigView Deferred to Phase C** — For Phase 0, `getSyncConfigurationView()` returns HomeMenuView. A dedicated SyncConfigView with episode download selection UI will be built in Phase C.

5. **Settings Unchanged** — PocketCastsPassword uses `alphaNumeric` type (no `password` type exists in CIQ). Settings XML works identically in audio-content-provider-app.

### Files Changed
- `manifest.xml` — type changed to audio-content-provider-app
- `YoCastsApp.mc` — base class changed, 5 new methods added
- `source/media/YoCastsContentDelegate.mc` — NEW stub
- `source/media/YoCastsContentIterator.mc` — NEW stub (includes PlaybackProfile)
- `source/media/YoCastsSyncDelegate.mc` — NEW stub extending Communications.SyncDelegate
- `monkey.jungle` — added source/media to sourcePath

### Build Status
- Monkey C Compiler: PASS at `-l 3` (strict)
- All tuple returns properly typed

---

## Migrate to AudioContentProviderApp (2026-04-14)

**By:** Mal (Lead)  
**Date:** 2026-04-14  
**Affects:** Kaylee (Garmin Dev), Wash (API Dev)  
**Status:** APPROVED  
**Document:** `docs/app-type-migration-evaluation.md`

### Summary

YoCasts must migrate from `AppBase` (device app) to `AudioContentProviderApp` (audio content provider) to enable audio playback on Garmin. This is not optional — there is no alternative for playing audio through Bluetooth headphones on Garmin watches.

### Key Findings

1. **AudioContentProviderApp inherits from AppBase** — all View/UI code survives. Custom drawing, Menu2, WatchUi.pushView(), InputDelegate — all work identically.
2. **Migration is small** — 2 files rewritten (YoCastsApp.mc, manifest.xml), 1 new file (SyncConfigView.mc), 12+ files completely unchanged.
3. **Every successful audio app on Garmin uses this pattern** — Spotify, Deezer, Amazon Music all use AudioContentProviderApp.
4. **The manifest changes to `type="audio-content-provider-app"`** and gains a `Media` permission.
5. **NowPlayingView changes role** — from playback controller to episode info display. Garmin's native media player handles playback UI.
6. **HomeMenuView survives intact** — served from `getPlaybackConfigurationView()` instead of `getInitialView()`.

### Architecture Changes

- **App class:** `extends AppBase` → `extends AudioContentProviderApp`
- **New required methods:** `getContentDelegate()`, `getSyncDelegate()`, `getPlaybackConfigurationView()`, `getSyncConfigurationView()`, `getProviderIconInfo()`
- **New files (migration-specific):** `SyncConfigView.mc`, `StubContentDelegate.mc` (temporary)
- **Phase plan update:** New Phase 0 (1 day) prepends the existing 5-phase plan. Phases A–E unchanged.

### Risk Assessment

**Confidence: HIGH (8/10).** Confirmed via Garmin API docs, MonkeyMusic sample, developer blog, community forums, and web research. Remaining 2 points require simulator/hardware validation (Phase 0).

### Impact on Existing Decisions

- **Menu2 for all list UIs** — still valid. Menu2 works in AudioContentProviderApp.
- **No text input on watch** — still valid. Application.Properties unchanged.
- **Dictionaries, not classes** — still valid. Data model layer unchanged.
- **Cache strategy** — still valid. Application.Storage works identically.
- **Audio download elevated to Phase 3** — now ENABLED by this migration. Phase 0 is the gate.

### What This Supersedes

- `audio-download-implementation-plan.md` Task D1 (YoCastsContentProvider) — no separate ContentProvider class. App IS the provider.
- `audio-download-implementation-plan.md` manifest change listed as Phase C — now Phase 0.
- `garmin-media-and-background-research.md` Option A concern about "limited UI" — debunked. Full UI available.

---

## Split-Dock Home Menu Implementation (2026-04-13)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-13  
**Affects:** Mal (Lead), Jarod (Owner)

### What Changed

Completely rewrote `HomeMenuView.mc` to implement the split-dock design from `docs/garmin-layout-reference.md` v2.0 Section 5. The old 4-pill scrollable layout (Queue, Podcasts, Now Playing, Settings) is replaced with a two-zone design:

1. **Zone 1 (Y=0–260):** Scrollable menu with 3 adaptive-width pills (Queue, Podcasts, Settings). Pill widths computed from round screen circle geometry at each Y position. Scrolling supported for future items but not needed for 3 items (204px content fits in 220px viewport).

2. **Zone 2 (Y=260–390):** Fixed Now Playing dock showing podcast name, episode title, progress bar, time display, and play/pause icon. Dock is drawn on top of scrollable content with `dc.setClip()` clipping at Y=260.

### Key Design Decisions

- **Now Playing moved from scrollable pill to fixed dock.** This gives always-visible playback status without scrolling.
- **Removed `hitTest()` method from View** — touch zone logic moved entirely to delegate's `onTap()` with fixed Y boundaries (365+ for play/pause, 260-365 for NP screen, <260 for pill hit testing).
- **Gear icon upgraded** to 6-tooth spec from Section 5.5.6 (was 4-tooth cardinal direction).
- **3 menu items instead of 4** — Now Playing is no longer a menu pill; it's always visible in the dock.
- **Physical button index cycles 0-2** (Queue, Podcasts, Settings) instead of 0-3.

### Build Status

Build passes `monkeyc -l 3` strict with zero errors/warnings.

---

## Audio Download & Offline Sync Implementation Architecture (2026-04-13)

**By:** Mal (Lead)  
**Date:** 2026-04-13  
**Affects:** Kaylee (Garmin Dev), Wash (API Dev)  
**Document:** `docs/audio-download-implementation-plan.md`

### Summary

Created comprehensive implementation plan for the audio download + offline sync system — the biggest remaining technical challenge for YoCasts. Translates the design-level `offline-sync-design.md` v1.1 into step-by-step build instructions.

### Key Decisions

#### 1. Five-Phase Implementation (A → E)

| Phase | What | Depends On |
|---|---|---|
| **A: Changelog & Position Tracking** | Persist mutations locally. PositionTracker, ConnectivityManager, auth persistence. | Existing code |
| **B: Sync Engine** | Push changelog to server, pull state, reconcile conflicts. State machine with retry logic. | Phase A |
| **C: Audio Download Infrastructure** | Download manager, SyncDelegate, download manifest tracking. Battery guards. | Phase A |
| **D: Media Playback Integration** | ContentProvider, ContentIterator, ContentDelegate. Wire to position tracking. | Phase C |
| **E: Full Reconciliation & Polish** | Queue merge algorithm, storage pressure monitoring, error hardening, interface updates. | Phases B-D |

#### 2. Position Save at 15s Intervals (Adaptive)

- 15s default → 30s at 20% battery → 60s at 10% → on-pause-only at 5%
- 240 writes/hr at normal — within Garmin flash spec (100K+ cycles/cell)
- Max 15s data loss on crash — acceptable tradeoff

#### 3. Consolidated Positions Map

Replace per-episode `yc_pos_<uuid>` keys with a single `yc_positions` map. One read fetches all positions for sync. Evicts oldest clean entries at 50-entry cap.

#### 4. clearCache() Now Selective

`Application.Storage.clearValues()` is no longer safe. Changelog, auth tokens, download manifest, and sync state must survive cache clears. Switched to selective `deleteValue()`.

#### 5. App Type → audio-content-provider

`manifest.xml` changes from `type="watch-app"` to `type="audio-content-provider"`. This enables the Media module APIs. Required for downloaded audio playback.

#### 6. CachedPodcastService Bug Fix Identified

Current `_isConnected()` only checks `phoneConnected`, missing Wi-Fi-direct. Must change to `ConnectivityManager.isConnected()` which checks `connectionAvailable`. This means `fetchAll()` works over Wi-Fi without phone.

#### 7. No Download Resume in v1

Partial downloads are discarded and restarted. `makeWebRequest()` doesn't support Range headers, Media module doesn't expose partial file access. Full re-download takes seconds on Wi-Fi. Not worth the complexity.

#### 8. 64 KB Background Memory Budget

SyncDelegate gets ~15 KB after Garmin runtime overhead. Rules: no large arrays, no audio buffering in memory, minimal Dictionary allocations, sequential downloads only.

### Open Questions

1. **Exact Media download API** — `Media.ContentRef` creation and audio file storage varies by SDK version. Kaylee needs to prototype against Venu 4 simulator.
2. **Application.Storage exact limit on Venu 4** — estimated 128-256 KB. Needs hardware testing.
3. **`Communications.makeWebRequest()` for binary audio** — need to verify response handling for non-JSON content types in the context of Media storage.

### Impact

- 8 new files, 9 modified files
- manifest.xml changes require re-deployment
- IPodcastService interface expands (4 new methods)
- MockPodcastService needs corresponding stubs

---

## Wi-Fi Direct Connectivity Model for Offline Sync (2026-04-13)

**By:** Mal (Lead)  
**Date:** 2026-04-13  
**Affects:** Kaylee (Garmin Dev), Wash (API Dev)  
**Document:** `docs/offline-sync-design.md` v1.1

### Decision

Updated the offline sync design from a two-state connectivity model (online/offline) to a three-state model (Wi-Fi / Phone BT / Fully Offline) based on the Venu 4's Wi-Fi direct capability.

### Key Changes

1. **Three connectivity states** — Wi-Fi connected (best, no phone needed), Phone connected via Bluetooth (full API but slower), Fully offline (cache only).
2. **`connectionAvailable` is the primary check** — `System.getDeviceSettings().connectionAvailable` returns `true` for either Wi-Fi or BT proxy. This replaces `phoneConnected` as the sync trigger.
3. **Phone companion is less critical** — The watch can sync metadata, push playback state, and download episodes directly over Wi-Fi. The phone is still useful but no longer a prerequisite.
4. **Two episode download paths** — Path A: system-triggered `SyncDelegate` (charger + Wi-Fi, traditional). Path B: app-initiated (Wi-Fi detected, no charger, with battery guards).
5. **Auto-download on Wi-Fi** — When Wi-Fi connects and Up Next has un-downloaded episodes, begin downloading automatically (max 3 episodes off-charger, skip if battery < 30%).
6. **Sync state machine updated** — New DOWNLOAD? step after PULL_SERVER to trigger episode downloads when Wi-Fi is available.
7. **Phase 3 simplified** — No phone intermediary needed for episode downloads. `makeWebRequest()` over Wi-Fi handles large files at full speed.

### Rationale

The Venu 4 has Wi-Fi hardware and `Communications.makeWebRequest()` transparently uses it. This dramatically simplifies the offline architecture — the user's typical flow of "come home, watch auto-syncs and downloads over Wi-Fi" works without the phone even being nearby. This is a better UX than requiring phone proximity or charger placement for sync.

### Impact

- Kaylee: `getConnectivityState()` helper needed in Phase 1. Phase 3 implementation is simpler — no companion app dependency for downloads.
- Wash: No API changes needed. `makeWebRequest()` abstracts the transport.
- All: The phone companion app (if we ever build one) is now a nice-to-have, not a requirement.

---

## Audio Download API Findings (2026-04-12)

**Author:** Wash (API Dev)  
**Date:** 2026-04-12  
**Affects:** Mal (Lead), Kaylee (Garmin Dev)  
**Document:** `docs/pocketcasts-audio-download-research.md`

### Summary

Completed live-tested research on how PocketCasts serves audio and what the Garmin watch needs to do for offline downloads. Tested 7 episodes across 7 different CDN providers.

### Critical Findings

#### 1. Audio is NOT proxied by PocketCasts

Episode URLs are original RSS feed URLs. PocketCasts just passes them through. The watch/phone downloads directly from podcast host CDNs (Megaphone, Simplecast, Transistor, SupportingCast, Podbean).

#### 2. No authentication needed for audio

All 7 CDNs returned `200 OK` without any Bearer token. PocketCasts auth is only for the metadata API, not for audio file access. **The phone companion can download audio without API credentials.**

#### 3. Range requests work everywhere

All 7 CDNs support `Range: bytes=X-Y` headers with `206 Partial Content` responses. Resumable downloads are fully supported — critical for unreliable BLE connections.

#### 4. URLs redirect heavily (1-6 hops)

Every audio URL goes through analytics/tracking redirectors before reaching the CDN. HTTP client must follow redirects. The phone's HTTP stack handles this natively.

#### 5. API `size` field is unreliable

Often `"0"` (string, not number). When non-zero, doesn't match actual Content-Length (10-20% discrepancy). **Must issue HEAD request for real file size.**

#### 6. Premium feed URLs may expire

SupportingCast (Verge ad-free, etc.) URLs contain embedded JWT tokens with timestamps. A 3.3-day-old URL still worked, but expiry is likely. **Always re-fetch episode URL from API immediately before download.**

### Decisions Needed

1. **Maximum download size/count** — Episodes range from 19 MB to 243 MB. Recommend capping at 3 episodes or 200 MB total. Need Kaylee's input on Garmin Media storage limits.

2. **Download timing** — Should downloads happen during Garmin Media sync (the standard approach) or via a custom background transfer? The Media module's ContentProvider/SyncDelegate pattern is the intended mechanism.

3. **URL refresh strategy** — Given possible SupportingCast expiry, should we cache URLs for max 1 hour? Or always call `/user/episode` right before download?

### Impact on Architecture

- Mal's offline-sync-design.md Phase 3 (Audio Download) is now unblocked — all API mechanics documented
- The phone companion does all the heavy HTTP lifting (redirects, Range requests, downloads)
- Watch-side storage is through Garmin Media module, not `Application.Storage`
- Position sync after playback uses per-episode `POST /sync/update_episode` (no batch)
- `/user/in_progress` provides all data needed for bulk reconciliation

---

## Media Module Constraints Discovery (2026-04-13)

**From:** Kaylee (Garmin Dev)  
**Date:** 2026-04-13  
**Affects:** Mal (Lead), Wash (API Dev)  
**Urgency:** HIGH — affects core architecture

---

### Critical Constraint: App Type Must Change

**Discovery:** Audio download/playback on Garmin requires `AudioContentProviderApp` — a fundamentally different app type from our current `device` type. This is NOT a "feature we add" to our existing app. It changes the app's identity, lifecycle, entry points, and UI surface.

**Impact:**
- Our current app is a `device` type launched from the app list
- An `AudioContentProviderApp` is launched from the **music widget** only
- Different base class: `AudioContentProviderApp` instead of `AppBase`
- Different lifecycle: `getSyncConfigurationView()`, `getPlaybackConfigurationView()`, `getContentDelegate()` instead of `getInitialView()`
- Cannot have both types in a single app (unverified but strongly indicated by all documentation)

**Options for team discussion:**
1. **Convert entirely to AudioContentProviderApp** — lose app-list presence, gain full media integration
2. **Ship two apps** — device app for browsing, audio provider for playback (complex, data sharing problems)
3. **Stay as device app, no native audio** — can't reliably download or play audio

**My recommendation:** Option 1. All successful podcast/music apps on Garmin (Spotify, Deezer, Amazon Music) are AudioContentProviderApps. The sync config view can serve as our episode selection UI.

---

### SyncDelegate Deprecation

`Media.SyncDelegate` and `Media.startSync()` are deprecated after System 9. Must use `Communications.SyncDelegate` (same interface). But there may be no replacement for programmatic sync triggering — needs SDK testing.

---

### Audio Download Mechanism

- Audio downloads MUST go through SyncDelegate → `makeWebRequest()` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO`
- This bypasses the ~32-100KB response size limit by streaming to disk
- Downloads are sequential (one at a time), cannot be parallelized
- Cannot resume interrupted downloads
- OGG format NOT supported — MP3 and M4A/AAC only

---

### Background Services Cannot Trigger Audio Sync

Background `ServiceDelegate` (64KB memory) can make small HTTP requests for metadata but CANNOT:
- Access the Media module
- Trigger SyncDelegate
- Download audio files

Background services are useful for: metadata polling, position sync pushes, new episode checks.

---

### Connectivity: We CAN Distinguish Wi-Fi from Bluetooth

`System.getDeviceSettings().connectionInfo` has `:wifi` and `:bluetooth` keys with `ConnectionState` values. This means we can implement smart sync: audio over Wi-Fi only, metadata over either.

No connectivity change callbacks exist — must poll.

---

**Decision needed from Mal:** Which app type path do we take? This affects every file in the project.

---

## User Directive: Home Menu Redesign (2026-04-12)

**By:** Jarod Aerts (via Copilot)  
**Timestamp:** 2026-04-12T14:54:11Z

Redesign the home menu with a split layout:
1. **Bottom 1/3** = static "Now Playing" dock. Play/pause button at very bottom (rounded area), time elapsed/total + progress bar above it, podcast name + episode title above that (in the widest part of the section). Text scrolls/marquees. Tap play/pause = toggle playback, tap elsewhere = open full Now Playing screen.
2. **Upper 2/3** = scrollable section with Queue, Podcasts, Settings buttons. These scroll UNDER the Now Playing dock (dock stays fixed on top, visually).
3. **Add a Settings button** and a simple placeholder settings page for future items (playback speed, auto-download, etc.).

**Rationale:** User request — captured for team memory and layout reference

---

## PocketCasts Auth Strategy — Use Two-Token OAuth Flow (2026-04-12)

**Author:** Wash (API Dev)  
**Status:** Proposed  
**Affects:** Mal (Lead), Kaylee (Garmin Dev)

### Context

Live API testing showed `POST /user/token` returning 400 Bad Request. Investigation of 6 community PocketCasts API clients revealed the root issue: **wrong request format and wrong login endpoint**.

### Root Cause

1. We logged in via `/user/login`, which returns `{ "token": "..." }` — a simple access token with **no refresh token**
2. We sent `POST /user/token` with empty body `{}` and a `Bearer` auth header
3. The endpoint actually requires: `{ "grantType": "refresh_token", "refreshToken": "<token>" }` in JSON body, with NO Authorization header
4. The refresh token is only available from `/user/login_pocket_casts`, which returns full OAuth2-style response

### Key Discovery: Two Login Endpoints, Two Token Systems

| Endpoint | Response Fields | Refresh Capable |
|----------|----------------|-----------------|
| `/user/login` | `token`, `uuid`, `email` | ❌ No refresh token |
| `/user/login_pocket_casts` | `accessToken`, `refreshToken`, `expiresIn`, `tokenType`, `uuid`, `email` | ✅ Full OAuth2 |

### Recommended Auth Strategy

**Primary: Proactive Token Refresh**

1. Login via `POST /user/login_pocket_casts` with `{ email, password }`
2. Store `accessToken`, `refreshToken`, and `expiresIn`
3. Track expiry — before each API call, check if token is near expiry
4. Refresh proactively via `POST /user/token` with `{ "grantType": "refresh_token", "refreshToken": "<saved>" }`
5. Save new tokens — refresh response returns NEW `accessToken` AND NEW `refreshToken` (token rotation)
6. Fallback — if refresh fails with `invalid_grant`, re-login with stored credentials

### Evidence Base

All 6 community clients that implement token refresh use `/user/login_pocket_casts` + `/user/token` with `grantType`/`refreshToken` format:
- `yfhyou/api_pocketcasts` (Python, Dec 2025)
- `rudiedirkx/pocketcasts-api-client` (PHP, 2024)

Others use `/user/login` only (no refresh capability).

### Garmin-Specific Implementation

- Credentials stored in `Application.Properties` (set via Garmin Connect Mobile)
- Tokens stored in `Application.Storage` with expiry timestamp
- On app start: check stored tokens → refresh if near expiry → re-login if refresh fails
- On 401 response: attempt refresh → re-login → show error if both fail

### Action Items

- [ ] **Wash:** Update C# test tool to validate `/user/login_pocket_casts` and correct `/user/token` format
- [ ] **Mal:** Update `PocketCastsService.mc` to store both tokens + expiry
- [ ] **Kaylee:** Plan `Application.Storage` keys for token persistence

### Documentation

- Updated `docs/pocketcasts-api-reference.md` with corrected auth documentation and examples

---

## Target Venu 4 41mm Only (2026-04-12)

**Author:** Kaylee (Garmin Dev)  
**Status:** Implemented  
**Scope:** Device targeting, UX specification, build configuration

### Context

YoCasts is Jarod's personal project. Previous manifest targeted 16 devices across Venu, Forerunner, Fenix, Vivoactive, and epix lines. For a single user with one watch, this multi-device support is unnecessary overhead.

### Decision

Target exclusively the **Garmin Venu 4 41mm** (`venu441mm`).

### Device Specifications

- 390×390 AMOLED round display (capacitive touch + 2 buttons)
- 768 KB watch app memory
- 54×54 px launcher icon
- Connect IQ SDK 4.2+

### Changes Made

| File | Change |
|---|---|
| `YoCastsGarmin/manifest.xml` | Single `<iq:product>` entry: `venu441mm`. Bumped `minSdkVersion` to 4.2.0. |
| `YoCastsGarmin/monkey.jungle` | Added `base.device = venu441mm` build target. |
| `docs/garmin-ux-spec.md` | Rewrote §1 (Target Device) for single device. Updated input model to touch + 2-button. Updated Now Playing from 240×240 to 390×390. Updated memory budget from 128 KB to 768 KB. |

### Design Implications

- **Touch-first design** — touchscreen is primary input; buttons secondary
- **Memory-generous** — 768 KB available enables richer caching, larger lists, future artwork support
- **Modern SDK** — no backward-compatibility constraint, can use SDK 4.2+ APIs freely
- **Simplified testing** — one simulator device, one physical device to deploy to

### Impact

- **Mal (Architecture):** Can assume 768 KB memory budget for caching and feature design
- **Wash (API):** Device constraints confirmed; API surface targets align with Venu 4 specs
- **Team:** Single-device focus allows optimized UX instead of lowest-common-denominator design

### Verification

All files updated and internally consistent. Ready for development phase.

---

## User Directive: Venu 4 41mm Personal Watch (2026-04-12)

**Requestor:** Jarod Aerts  
**Timestamp:** 2026-04-12T00:56Z

The Garmin app should be built specifically for the Venu 4 41mm. This app is mainly just for Jarod, so it will pretty much only run on that watch. No need to support a wide range of devices.

---

## Garmin App MVP Scaffolding (2026-04-12)

**Author:** Kaylee (Garmin Dev)  
**Status:** Approved (implementation complete)

Created the full `YoCastsGarmin/` Connect IQ project with mock data service. The app has 5 screens, Menu2 navigation, and an `IPodcastService` interface that `MockPodcastService` implements. The mock data uses Dictionary keys matching PocketCasts API field names for easy swap to real service.

### Key Implementation Decisions

1. **Menu2 returned directly from `getInitialView()`** — no wrapper View for the home screen. Cleaner and avoids view stack issues.
2. **NowPlayingView uses delegate-holds-view-reference pattern** — delegate calls `setView()` to get a reference for controlling playback. This is the standard CIQ pattern since delegates can't access the view stack.
3. **Mock data normalizes the Up Next structure** — real API returns `{order: [...], episodes: {...}}` but mock uses a simple array. The real PocketCastsService should normalize this in its `getQueue()` method.
4. **No `static` functions used** — Monkey C supports them but they cause issues in some SDK versions. Instance methods throughout.
5. **`getInitialView()` has no explicit return type annotation** — SDK will reject override if typed.

### Impact

- **Mal (Architecture):** IPodcastService interface ready for service implementation. Dictionary models align with API response structure.
- **Zoe (Testing):** Fixtures available for UI logic testing without live API.
- **Team:** Scaffolding complete and ready for real API integration.

---

## Phase 1 Offline Caching — Decorator Pattern with Read-Through Cache (2026-04-12)

**Author:** Kaylee (Garmin Dev)  
**Status:** Implemented  
**Affects:** Mal (Lead), Wash (API Dev)

### Context

Mal's `docs/offline-sync-design.md` defines a 4-phase offline strategy. Phase 1 is metadata caching — enabling users to browse podcasts, episodes, and the queue even when the phone is out of range.

### What Was Built

1. **`CacheManager.mc` (module):** Wraps `Application.Storage` with typed save/load methods. Keys prefixed `"yc_"` to avoid collisions with future changelog/auth data. Every entry stores a `cachedAt` timestamp for TTL decisions. `clearCache()` calls `clearValues()` — safe in Phase 1 since auth lives in Properties.

2. **`CachedPodcastService.mc` (decorator):** Wraps any `IPodcastService` via constructor injection. Loads cached data on init for instant UI. Delegates `fetchAll()` only when `phoneConnected == true`. Read-through getters cache fresh data on each view cycle. TTLs: queue 5min, podcasts 30min, episodes 1hr.

3. **App wiring:** Real API mode: `CachedPodcastService(PocketCastsPodcastService(email, password))`. Mock mode: unwrapped `MockPodcastService()`.

### Design Decisions

1. **Module vs class for CacheManager** — Module chosen. No instance state; all functions operate on Storage directly.
2. **Read-through caching** — Async callbacks impractical to intercept. Getters check wrapped service each view cycle, cache when new data detected. `_refreshPending` flag prevents redundant writes.
3. **TTLs are revalidation hints, not expiry** — Per Mal's design: stale data always served, TTLs only trigger network refresh.
4. **`clearValues()` for `clearCache()`** — Phase 1 only. Must become selective when changelog/auth tokens are added.

### Impact on Future Phases

- **Phase 2 (Position Tracking):** `savePlaybackPosition()` / `loadPlaybackPosition()` already implemented. Phase 2 adds changelog key and calls from Now Playing view.
- **Phase 3 (Audio Download):** No impact — audio uses separate Media module storage.
- **Phase 4 (Reconciliation):** Sync engine reads/writes through CacheManager. Key prefixes keep caching separate from sync data.

### Open Questions

- Exact `Application.Storage` size limit on Venu 4 41mm — needs hardware testing.
- Whether `clearValues()` needs to become selective once changelog/auth keys are added.

---

## Architecture Assessment: Podcast Art + Audio Playback Roadmap (2026-04-16)

**By:** Mal (Lead)  
**Date:** 2026-04-16  
**Requested by:** Jarod Aerts  
**Status:** Assessment — pending team review  
**Affects:** Kaylee (Garmin Dev), Wash (API Dev), Zoe (Tests)

### Item 1: Podcast Art Colors + Thumbnails

#### Feasibility Verdict: **FEASIBLE — but defer to Phase E (polish)**

#### CIQ Image Capabilities

CIQ provides `Communications.makeImageRequest()` — a first-class API for downloading images over the network. It returns a `BitmapResource` in the callback.

**Key options:**
- `:maxWidth` / `:maxHeight` — resize on-transit
- `:packingFormat` — supports JPG, PNG, YUV (since API 4.2.0, Venu 4 qualifies)
- `:dithering` — Floyd-Steinberg for palette-limited rendering
- `:palette` — constrain to specific color palette

#### Recommended Thumbnail Size

- **40×40px** is the sweet spot for 390×390 watch screen
- Uncompressed: 40 × 40 × 2 bytes = **3,200 bytes per image**
- With JPG packing: ~1-2 KB per image over-the-wire
- **Do NOT exceed 48×48px**

#### Color Tinting Works

In custom `HomeMenuView` and custom list views, setting per-item backgrounds via `Dc.setColor()` and `Dc.fillRoundedRectangle()` is trivial. Menu2-based views (Queue, Episodes) are harder — would need custom `MenuItem` subclasses.

**Recommendation:** Color tinting on home screen pills and Podcasts list only. NOT on Menu2 lists.

#### Memory Impact Analysis

Storing 15 thumbnails + 15 color values simultaneously:

| Item | Per-podcast | × 15 podcasts |
|---|---|---|
| Thumbnail (40×40, 16-bit) | 3,200 B | **48,000 B** (~47 KB) |
| Color value (Number) | 4 B | 60 B |
| BitmapResource overhead | ~100 B | 1,500 B |
| **Total** | ~3,304 B | **~49,560 B** (~48 KB) |

**48 KB is 6.3% of 768 KB budget.** Manageable IF lazy-loaded.

**Critical constraint:** Load thumbnails for visible items only (3-5 on screen). Evict off-screen to drop peak memory to ~16 KB — acceptable.

#### Where to Extract Colors: **Proxy (server-side)**

On-device color extraction is not viable (no pixel API). Proxy should:
1. Fetch podcast's art URL from PocketCasts API
2. Download image server-side
3. Extract dominant color (k-means or simple average)
4. Return hex color in podcast metadata JSON (e.g., `"artColor": "#2A4B8D"`)
5. Optionally: serve resized thumbnail via separate endpoint

#### What We'd Need

| Component | Owner | Effort |
|---|---|---|
| Proxy: `GET /art/{podcastUuid}` endpoint | Wash | 1 day |
| Proxy: Add `artColor` to `/user/podcast/list` | Wash | 0.5 day |
| Garmin: ArtworkManager module — lazy-load | Kaylee | 2 days |
| Garmin: Update custom list views | Kaylee | 1 day |
| Tests: Proxy art endpoint | Zoe | 0.5 day |
| **Total** | | **~5 days** |

#### Recommendation

**Defer to Phase E.** Rationale:
1. Audio download is the core feature — art is polish
2. 48 KB RAM may be needed for sync engine and download queue
3. No hard dependency — app works perfectly with text-only lists
4. Color extraction adds network dependency (failure mode)
5. When built: colors first → thumbnails second → per-item tinting last

### Item 2: Audio Download & Playback Roadmap

#### Current State

| Component | Status |
|---|---|
| App type: AudioContentProviderApp | ✅ Migrated, builds clean |
| Dual-build (sim vs device) | ✅ Configured |
| Media stubs | ✅ In source/media/ |
| CacheManager + CachedPodcastService | ✅ Phase 1 complete |
| Real Venu 4 hardware | ❌ Not available yet |
| Simulator audio testing | ❌ CIQ limitation |

#### What We Can Build NOW (Simulator-Testable)

**Phases A and B** are pure data-layer and HTTP — no Media module, fully simulator-testable.

##### Phase A: Changelog & Position Tracking (2-3 days)

All six tasks simulator-safe:

| Task | Description | Testable in Sim? |
|---|---|---|
| A1: Changelog in CacheManager | Coalesced mutation log, selective `clearCache()` | ✅ Yes |
| A2: Positions Map | Consolidated positions, eviction, dirty tracking | ✅ Yes |
| A3: PositionTracker module | Timer-based position saves, battery-aware frequency | ✅ Yes |
| A4: ConnectivityManager | Three-state polling, transition callbacks | ✅ Partial |
| A5: CachedPodcastService update | Fix `_isConnected()` bug | ✅ Yes |
| A6: Auth token persistence | Save/load/refresh tokens in Storage | ✅ Yes |

##### Phase B: Sync Engine (4-5 days)

Entirely HTTP + Storage. No Media module.

| Task | Description | Testable in Sim? |
|---|---|---|
| B1: SyncEngine state machine | 7-step sync: auth → push → pull → reconcile → clean | ✅ Yes |
| B2: Push pipeline | Batch changelog entries to `/sync/update_episode` | ✅ Yes |
| B3: Pull pipeline | Fetch `/user/in_progress`, queue, episodes | ✅ Yes |
| B4: Reconciliation logic | "Furthest position wins", status hierarchy | ✅ Yes |
| B5: Auto-sync trigger | ConnectivityManager listener → triggerSync() | ✅ Yes |

#### What MUST Wait for Real Hardware

| Component | Why It Needs Hardware | Phase |
|---|---|---|
| SyncDelegate downloads | `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` + Media cache | Phase C |
| ContentIterator | Needs `Media.getCachedContentObj()` | Phase D |
| ContentDelegate callbacks | Fired by native media player only | Phase D |
| Bluetooth audio output | Hardware-only | Phase D |
| Media.getCacheStatistics() | Real values only on device | Phase C |
| Wi-Fi direct detection (reliable) | Sim doesn't model `phoneConnected` vs `connectionAvailable` | Phase A (partial) |

#### Prioritized Work Breakdown

**Priority: Phase A → Phase B → Download Queue UI → Phase C (hardware)**

Sprint 1 Foundation (Week 1): 11 tasks (6 days)
Sprint 2 Sync Engine (Week 2): 8 tasks (5 days)
Sprint 3 Download Queue UI (Week 3): 7 tasks (5 days)

Total: ~3 weeks, all simulator-testable except Phase C/D components.

#### Key Risks

1. **`makeWebRequest()` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` unverified on Venu 4** — same mechanism Spotify/Deezer use. Mitigated by sample verification.

2. **PocketCasts audio URLs may require auth or redirect** — validate during Sprint 1. If auth needed, proxy must be authenticated intermediary.

3. **64 KB background memory for SyncDelegate** — ~15 KB usable after Garmin overhead. Keep delegate lean.

4. **No download resume in v1** — full re-download on failure. Acceptable for 20-50 MB episodes on Wi-Fi.

#### Recommendation

**Start Sprints 1-3 immediately.** Everything is simulator-testable. By the time Venu 4 arrives, we'll have complete data layer and download code written — waiting for hardware validation only.

**Highest-risk unknown:** Task 7 (audio URL resolution). Wash prioritize this — if PocketCasts audio requires special auth, we need to know early.

### Summary of Calls

| Decision | Verdict |
|---|---|
| Podcast art colors + thumbnails | **Feasible. Defer to Phase E.** Colors first, thumbnails second. Server-side extraction. |
| Audio download — what to build now | **Phases A + B + download queue UI.** All simulator-testable. ~3 weeks. |
| Audio download — what waits | **Phases C + D.** Needs Venu 4 hardware. |
| Highest priority task | **A1 (changelog), audio URL resolution for Wash, tests for Zoe.** |
| Highest risk | **PocketCasts audio URL auth — Wash validates first.** |

---

## Podcast Art Color & Thumbnail Feasibility — Artwork is GO (2026-04-16)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-16  
**Affects:** Mal (Lead), Wash (API Dev), Jarod Aerts

### Summary

Completed full API research on CIQ image loading and custom colors. **Both are feasible on Venu 4 41mm.**

### Key Findings

1. **`makeImageRequest()`** loads PNG/JPG from URLs at runtime. 30×30px JPG = 1-3 KB per image, well under 32 KB response limit.

2. **768 KB memory** on Venu 4 means 15 thumbnails at 30×30px = ~27 KB (16-bit), trivially within budget. The "no artwork in v1" decision was based on 128 KB devices — no longer applicable for Venu 4-only build.

3. **Custom hex colors** like `0xFF5500` work directly in `dc.setColor()`. `Graphics.createColor(alpha, r, g, b)` enables semi-transparent overlays.

4. **`CustomMenuItem`** (API 3.2.0+) or custom View can render per-item brand-color backgrounds and thumbnails.

### Recommendation

**Option A — brand colors first.** Highest visual impact for zero cost. Defer thumbnails to Phase E.

### Impact on Proxy

Wash: proxy already whitelists `artwork_url` and `author_color`. If `author_color` comes as hex string, consider pre-parsing to integer for watch efficiency.

---

## Design: Podcast Art Color & Thumbnail Support (2026-04-16)

**By:** Wash (API Dev)  
**Date:** 2026-04-16  
**Affects:** Kaylee (Garmin Dev), Mal (Lead), Jarod Aerts  
**Status:** Proposal — needs team review

### Executive Summary

PocketCasts already provides pre-computed color metadata and server-side resized artwork. **No image processing library is needed.** The proxy enriches the podcast list with colors by fetching a lightweight JSON endpoint. Thumbnails load natively via CIQ's `makeImageRequest()`.

### Research Findings

#### 1. PocketCasts Art URLs — Confirmed

Artwork served from `static.pocketcasts.com` as WebP only:

| URL Pattern | Status | Size |
|---|---|---|
| `/discover/images/webp/200/{uuid}.webp` | ✅ Working | ~3.1 KB |
| `/discover/images/webp/480/{uuid}.webp` | ✅ Working | ~7.1 KB |
| `/discover/images/webp/960/{uuid}.webp` | ✅ Working | ~14.7 KB |

No authentication required. Cache: `max-age=604800` (7 days), ETag supported.

#### 2. PocketCasts Color Metadata — The Goldmine

PocketCasts pre-computes dominant colors for every podcast:

```
GET https://static.pocketcasts.com/discover/images/metadata/{uuid}.json
```

Returns (231 bytes, no auth, 7-day cache):

```json
{
  "colors": {
    "background": "#1d2b38",
    "tintForDarkBg": "#eaefa9",
    "tintForLightBg": "#257bbb",
    "fabForLightBg": "#61c6c7",
    "fabForDarkBg": "#61c6c7",
    "linkForLightBg": "#61c6c7",
    "linkForDarkBg": "#61c6c7"
  }
}
```

Eliminates need for SkiaSharp, ImageSharp, or custom color extraction. **Tested with multiple UUIDs — all return valid colors.**

#### 3. Image Processing Libraries — NOT NEEDED

| Library | Azure Fit | Cold Start | Notes |
|---|---|---|---|
| **SkiaSharp** | ⚠️ Needs native libs | +200-500ms | ~25 MB, unsupported on Linux consumption |
| **ImageSharp** | ✅ Pure .NET | +50-100ms | ~5 MB, best choice if needed |
| **System.Drawing** | ❌ Not supported | N/A | GDI+ unsupported on Azure |

#### 4. Size Budget Analysis

| Approach | Per-podcast | 15 podcasts | Under 32 KB? |
|---|---|---|---|
| Color hex only (`artColor`) | ~7 bytes | ~105 bytes | ✅ Trivial |
| Color + artUrl | ~75 bytes | ~1.1 KB | ✅ Easy |
| Base64 40×40 JPEG | ~1,500 bytes | **~22.5 KB** | ⚠️ Tight |

Current stripped list: ~3-5 KB for 15. Colors add negligible overhead.

#### 5. CIQ `makeImageRequest()` — Native Solution

```monkey-c
Communications.makeImageRequest(
    "https://static.pocketcasts.com/discover/images/webp/200/" + uuid + ".webp",
    {},
    { :maxWidth => 48, :maxHeight => 48 },
    method(:onArtReceived)
);
```

**Key properties:**
- Native image decoding (PNG, JPEG, BMP, WebP varies)
- Automatic resizing via `:maxWidth`/`:maxHeight`
- Returns `BitmapResource` directly usable in views
- Async callback — fits CIQ's event model
- Memory: 48×48 ARGB = ~9.2 KB per image

### Recommended Design: Option C (Initial) → Option A (Phase E)

#### Immediate (Phase E prep)

**Proxy changes:**
1. When handling `/user/podcast/list`, fetch color metadata for each podcast UUID
2. Add `artColor` (background hex) and `artTint` to each podcast
3. In-memory cache with 7-day TTL, matching PocketCasts cache headers

**CIQ changes:**
1. Read `artColor` from podcast data — use as background tint
2. Prepare for `artUrl` loading later

#### Proxy Implementation Sketch

```csharp
private static readonly ConcurrentDictionary<string, ArtMetadata> _artCache = new();

private async Task<string> EnrichPodcastList(string json)
{
    var doc = JsonNode.Parse(json);
    if (doc is not JsonObject root) return json;
    
    var podcasts = root["podcasts"]?.AsArray();
    if (podcasts == null) return json;
    
    var colorTasks = new List<Task>();
    foreach (var podcast in podcasts)
    {
        if (podcast is not JsonObject podObj) continue;
        var uuid = podObj["uuid"]?.GetValue<string>();
        if (uuid == null) continue;
        
        colorTasks.Add(Task.Run(async () =>
        {
            var colors = await GetArtColors(uuid);
            if (colors != null)
            {
                podObj["artColor"] = colors.Background;
                podObj["artTint"] = colors.Tint;
            }
        }));
    }
    
    await Task.WhenAll(colorTasks);
    return root.ToJsonString();
}
```

#### Caching Strategy (v1)

**In-Memory Cache:**
- **Pros:** Zero latency after cold start, zero cost
- **Cons:** Lost on cold start, first request pays ~100-150ms for 15 parallel fetches
- **Mitigation:** PocketCasts metadata endpoint is fast (~50ms), parallelized
- **Cold start impact:** ~100-150ms on initial `/user/podcast/list` call

### Impact Assessment

| Concern | Impact |
|---|---|
| Response size | +1.8 KB for 15 podcasts. Still ~5-7 KB total, under 32 KB |
| Proxy latency | +100-150ms on cold start. ~0ms on warm requests |
| Cold start time | No new NuGet packages. No change. |
| CIQ memory | 48×48 bitmap = ~9.2 KB. 15 loaded = ~138 KB. Within budget. |
| Azure cost | $0.00 — metadata from PocketCasts CDN |

### Open Questions for Team

1. **Kaylee:** Does `makeImageRequest()` support WebP on Venu 4 41mm SDK 9.1.0? If not, need proxy-side PNG conversion (Option B).
2. **Kaylee:** Target thumbnail size for Menu2 items? UX spec mentions 48×48 — confirm?
3. **Mal:** Option C now (colors only) or jump to Option A (colors + URLs)? Option C aligns with "no artwork in v1."
4. **All:** Include `tintForDarkBg` for text accent colors?

### Recommendation

**Implement Option C now (colors only), prepare for Option A later.**

1. Add `artColor` and `artTint` to proxy response — ~15 lines of code
2. Zero new dependencies, zero cold start impact
3. CIQ uses colors for tinted UI immediately
4. Phase E: add `artUrl` and `makeImageRequest()` handling
5. If WebP unsupported: add conversion endpoint (Option B) at that time

**Key insight: PocketCasts already did the hard work.** We forward their metadata, no image processing needed.

---

## Download Data Layer — Storage-Backed Queue + Proxy Audio Info (2026-04-16)

**By:** Wash (API Dev)  
**Date:** 2026-04-16  
**Affects:** Kaylee (Garmin Dev), Mal (Lead)

### What Was Built

Three components forming the data layer for episode audio downloads (Phase B/C):

#### 1. DownloadQueue Module (Garmin)

**File:** `YoCastsGarmin/source/services/DownloadQueue.mc`

Replaced mock stub with real Application.Storage persistence. Queue survives app restarts.

**Design:**
- Storage key: `yc_dl_queue` — array of download item dictionaries
- Max queue size: 20 episodes
- Status flow: PENDING → DOWNLOADING → DOWNLOADED or FAILED
- Retry policy: Failed items retry up to 3 times, then ignored by `getNextPending()`
- Backward compatible: All existing constants (DL_UUID, DL_STATUS, etc.) and methods preserved

#### 2. StorageManager Module (Garmin)

**File:** `YoCastsGarmin/source/services/StorageManager.mc`

Tracks downloaded episode metadata separately from Media module.

**Design:**
- Storage key: `yc_downloads` — dictionary mapping episodeUuid → metadata
- No Media imports — works in simulator (source/media/ excluded)
- `refId` field: Will hold Media.ContentRef on hardware, string placeholder now
- `getTotalDownloadSize()`: Enforce storage budget

#### 3. AudioInfo Proxy Endpoint (Azure)

**File:** `YoCastsProxy/AudioInfoProxy.cs`

New endpoint: `GET /api/pocketcasts/episode/{uuid}/audio-info`

**Features:**
- Fetches episode metadata from PocketCasts (audio URL, duration, title)
- Issues HEAD request to CDN for real file size (API `size` field unreliable)
- Returns final URL after redirect chain resolution
- 15-second timeout on HEAD requests
- Watch uses this to check storage before downloading

### Decisions Made

1. **DownloadQueue owns UI contract** — DL_* constants and methods preserved for DownloadsView compatibility
2. **StorageManager separate from DownloadQueue** — queue tracks intent (what to download), storage tracks outcome (what's downloaded)
3. **No Media module references** — both modules compile in simulator build
4. **HEAD-based size resolution in proxy** — Garmin's `makeWebRequest()` doesn't support HEAD. Proxy does HEAD and returns size in JSON

### Build Status

✅ Garmin simulator build passes  
✅ All existing tests pass  
⚠️ Proxy deployment pending (`func azure functionapp publish`)

### What's Next

- **Phase C4 (Kaylee):** Wire `YoCastsSyncDelegate` to use `DownloadQueue.getNextPending()` and `StorageManager.markDownloaded()`
- **Phase D:** ContentIterator reads from StorageManager to enumerate downloaded episodes
- **Proxy deployment:** AudioInfoProxy needs publish to go live

---

## Download UI Architecture & DownloadQueue Interface Contract (2026-04-16)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-16  
**Affects:** Wash (API Dev), Mal (Lead)

### Summary

Implemented download management UI screens with DownloadQueue module. Interface contract defined and ready for Wash's real implementation.

### Decisions Made

#### 1. DownloadQueue Module Interface

Module-level singleton pattern with in-memory state. Real implementation persists to `Application.Storage`.

**Module functions:**
- `addToQueue(episodeDict)` — append to queue
- `removeFromQueue(uuid)` — remove by UUID
- `getStatus(uuid)` — query current state
- `getProgress(uuid)` — get percent complete
- `getDownloads()` — return all download items
- `getDownloadCount()` — count pending+downloading
- `getNextPending()` — get next queued episode for SyncDelegate
- `markDownloading(uuid)` — update status
- `markDownloaded(uuid, refId)` — mark complete with Media ref
- `toEpisodeDict()` — convert for NowPlayingView compatibility

#### 2. Download Status Constants

Four states: `STATUS_PENDING (0)`, `STATUS_DOWNLOADING (1)`, `STATUS_DOWNLOADED (2)`, `STATUS_FAILED (3)`

#### 3. Episode Action Menu Pattern

EpisodeListView shows Menu2 action popup on episode select:
- Play (existing — navigates to NowPlayingView)
- Download (new — calls `DownloadQueue.addToQueue()`)

Extensible for future actions (Star, Mark Played, etc.).

#### 4. Downloads Pill Placement

Added between Podcasts and Settings in HomeMenuView:
- Queue → Podcasts → Downloads → Settings
- TOTAL_MENU_HEIGHT: 382 → 478px
- Touch zone: Y < 260 for scrollable area

#### 5. Download Item Dictionary Keys

Separate from DataKeys.E_* to avoid coupling:
- `DL_UUID`, `DL_TITLE`, `DL_PODCAST_TITLE`, `DL_STATUS`, `DL_PROGRESS`, `DL_SIZE`, `DL_STATUS_TEXT`

`toEpisodeDict()` converts for NowPlayingView compatibility.

### Open Questions Resolved

- **Failed downloads auto-retry:** Yes, up to 3 times per Wash's implementation
- **Maximum downloads:** Capped at 20 episodes or storage budget
- **Sort order:** By status (downloading first) then by add order

### Build Status

✅ Simulator build passes  
✅ Device build passes (Venu 4 41mm)  
✅ Strict linting enabled (`-l 3`)  

### What's Next

- **Wash (DownloadQueue real impl):** Persist to `Application.Storage`, implement queue state machine
- **Kaylee (Phase C):** Wire SyncDelegate to use `DownloadQueue.getNextPending()` for actual downloads

---

## YoCastsProxy: Art Colors + Audio Info Deployed to Azure (2026-04-16)

**By:** Wash (API Dev)  
**Date:** 2026-04-16  
**Status:** DEPLOYED

### Summary

Extended YoCastsProxy to enrich podcast metadata with brand colors, tints, and artwork URLs. Also added audio metadata endpoint for download planning.

### Deployed URL

```
https://yocasts-proxy.azurewebsites.net/api/pocketcasts/{*path}
```

### Changes Made

#### 1. Podcast List Enrichment

**Endpoint:** `GET /api/pocketcasts/user/podcast/list`

**Added fields per podcast:**
- `artColor` — background hex (e.g., `#1d2b38`)
- `artTint` — tint for dark backgrounds (e.g., `#eaefa9`)
- `artUrl` — 200px WebP image URL (not yet loaded by watch, prepared for Phase E)

**Implementation:**
- Parallel fetch of color metadata for each podcast UUID
- Source: `https://static.pocketcasts.com/discover/images/metadata/{uuid}.json`
- In-memory cache with 7-day TTL (matching PocketCasts headers)
- `ConcurrentDictionary<string, ArtMetadata>` storage

#### 2. Audio Info Endpoint

**Endpoint:** `GET /api/pocketcasts/episode/{uuid}/audio-info`

**Returns:**
```json
{
  "audioUrl": "https://...",
  "duration": 3600,
  "fileSize": 52428800,
  "title": "Episode Title"
}
```

**Features:**
- Fetches episode metadata from PocketCasts
- Issues HEAD request to CDN for real file size (API field unreliable)
- Follows redirect chain to final CDN URL
- 15-second timeout on slow CDNs
- Watch uses this before downloading to verify storage availability

### Implementation Details

**File:** `YoCastsProxy/PocketCastsProxy.cs`

- **Color fetch strategy:** Parallel Task.WhenAll() for 15 UUIDs
- **Fallback:** If color fetch fails, podcast returned unchanged (graceful degradation)
- **Response size:** +1.8 KB for 15 podcasts (still ~5-7 KB total, under 32 KB limit)
- **Dependencies:** Zero new NuGet packages — uses existing System.Text.Json
- **Latency:** ~100-150ms cold start, ~0ms warm cache
- **Cost:** Free — metadata fetched from PocketCasts CDN

### Deployment Verification

✅ HTTP 401 on unauthenticated `/user/podcast/list` (correct — Bearer token required)  
✅ Color metadata fetches successfully for all podcasts  
✅ Response size within budget  
✅ Endpoint available at: `https://yocasts-proxy.azurewebsites.net/api/pocketcasts/user/podcast/list`

### Caching Strategy (v1 — In-Memory)

**Pros:**
- Zero latency after cold start
- Zero cost
- Simple implementation

**Cons:**
- Lost on cold start
- First request pays ~100-150ms for parallel metadata fetches

**Mitigation:** PocketCasts metadata endpoint is fast (~50ms per request). Total cold start impact: ~100-150ms on initial podcast list fetch.

**Future (v2):** If cold start latency becomes a problem, migrate to Azure Table Storage persistence (eliminates cold start penalty, costs ~$0.001/month).

### Action Items for Team

- **Kaylee:** Update Garmin app to read `artColor`/`artTint` from proxy and use for UI tinting
- **Kaylee:** Prepare for `artUrl` loading via `makeImageRequest()` in Phase E
- **Mal:** Verify CachedPodcastService routes through proxy URL
- **Zoe:** Add tests for color metadata endpoint

### Open Questions

1. **Kaylee:** Does `makeImageRequest()` support WebP on Venu 4 SDK 9.1.0? If not, proxy may need PNG conversion endpoint.
2. **Team:** Should we implement in-memory OR Table Storage caching for v1? Current choice: in-memory (simpler, cold start trade-off acceptable).

---

## PowerShell Deploy Script: deploy-sim.ps1 Conversion (2026-04-19)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-19  
**Affects:** Jarod Aerts, all agents running builds

### Decision

Created `YoCastsGarmin/deploy-sim.ps1` — a PowerShell rewrite of `deploy-sim.bat` with automatic simulator launch.

### Key Changes

1. **Auto-start simulator** — Checks for running `simulator` process; launches `simulator.exe` from SDK bin with 5s init wait if absent. No more "is the simulator running?" failures.
2. **Idiomatic PowerShell** — Uses `$ErrorActionPreference`, `$LASTEXITCODE`, `Write-Host` with colors, `Start-Process` for the simulator.
3. **Old .bat preserved** — `deploy-sim.bat` still works if anyone prefers it.

### Recommendation

Use `.\deploy-sim.ps1` as the default build+deploy command going forward. Update any docs referencing `deploy-sim.bat` to mention both options.

---

## Phase C Audio Download Implementation — SyncDelegate & ContentIterator (2026-04-19)

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-19  
**Status:** Implemented  
**Affects:** Wash (API Dev), Mal (Lead), Zoe (Tester)

### Context

Phase C implements the core audio download pipeline — the SyncDelegate that runs in background when the watch is on charger+WiFi, and the ContentIterator that feeds downloaded episodes to the native Garmin media player.

### Decisions Made

#### 1. PersistedContent.Iterator for Audio Downloads
`makeWebRequest` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` returns `PersistedContent.Iterator`, not `Media.ContentRef` directly. We call `iter.next()` to extract the ContentRef. This required adding `PersistedContent` permission to manifest.xml.

#### 2. Background Token Management
The SyncDelegate authenticates independently by reading PocketCasts email/password from `Application.Properties` and caching the token in `Application.Storage` (keys: `yc_bg_token`, `yc_bg_token_exp`). Token is reused across sync cycles with 5-minute expiry buffer.

#### 3. Sequential Downloads Only
One episode at a time within the 64KB background memory limit. After each download completes (or fails), we move to the next pending item. Failed downloads get up to 3 retry attempts across sync cycles.

#### 4. Cancel-Safe Design
`onStopSync()` resets in-progress downloads to PENDING status so they retry on the next sync cycle. No partial state is left behind.

#### 5. StorageManager Cleanup on UI Remove
Added `StorageManager.removeDownload(uuid)` call in DownloadsView when removing episodes, ensuring both the queue entry AND the persisted content metadata are cleaned up.

### Files Changed

- `YoCastsGarmin/manifest.xml` — Added Background, PersistedContent permissions
- `YoCastsGarmin/source/media/YoCastsSyncDelegate.mc` — Full implementation (~300 lines)
- `YoCastsGarmin/source/media/YoCastsContentIterator.mc` — Full implementation (~125 lines)
- `YoCastsGarmin/source/views/DownloadsView.mc` — StorageManager cleanup on remove
- `YoCastsGarmin/source/sim/LocalCredentials.mc` — Created stub for simulator build

### Build Verification

- ✅ Device build passes (default type check level)
- ✅ Simulator build passes (media/ excluded from sim build)

### Technical Findings

**PersistedContent.Iterator Pattern:**  
`makeWebRequest(options)` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` returns `PersistedContent.Iterator`.  
Call `iter.next()` to extract `Media.ContentRef`.  
Requires `PersistedContent` permission in manifest.

### Open Items for Hardware Testing

- ContentRef ID type: stored as String via `.toString()`. May need exact type if constructor expects Number.
- 64KB memory limit: cannot validate in simulator, requires real Venu 4 hardware.
- `mediaEncoding` option: not set in makeWebRequest — system should auto-detect from HTTP Content-Type. May need explicit `Media.ENCODING_MP3` if hardware testing reveals issues.

### Impact

Phase C audio download pipeline complete and ready for hardware integration testing. Prerequisite: Background permission + Venu 4 hardware (Mal's gating conditions met). No additional API changes needed from Wash — proxy already provides audio URLs.



---

# Decision: Brand Color Brightening Strategy

**Author:** Kaylee (Garmin Dev)
**Date:** 2026-04-19
**Status:** Applied

## Context

PocketCasts proxy returns `artColor` and `artTint` hex strings per podcast. The `artColor` values represent the dominant dark color from artwork — many are extremely dark (e.g., `#1d2b38` = RGB 29,43,56). When used with the original `dimColor()` at 10–35% factor for AMOLED backgrounds, the resulting RGB values (e.g., 5,8,11) were invisible against the black Menu2 background.

## Decision

Added `DataFormat.brightenColor(color, targetMax)` — a hue-preserving proportional scaler that boosts a color so its brightest channel reaches `targetMax`. Applied throughout all CustomMenuItem subclasses:

| Element | Before | After |
|---------|--------|-------|
| Background (unfocused) | dimColor @ 0.10–0.20 | brighten(80) then dim @ 0.25–0.35 |
| Background (focused) | dimColor @ 0.22–0.35 | brighten(80) then dim @ 0.50–0.60 |
| Circles/dots | raw brandColor | brighten(140–160) |
| Accent bars | raw brandColor | brighten(160) |
| Title text | tintColor (unchanged) | tintColor (unchanged) |

Also added explicit `{:height => 80}` to all `CustomMenuItem.initialize()` calls as a safety measure — omitting the height option may prevent `draw()` from being called in certain CIQ SDK versions.

## Impact

- **Wash (Proxy Dev):** No changes needed — proxy artColor/artTint format is correct.
- **Team:** If we add new CustomMenuItem subclasses in future views, always pass `{:height => N}` and use `brightenColor()` for any artColor-derived visual elements.


---

# Brand Color Tinting Extended to All Views

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-07-15  
**Affects:** Mal (Lead), all agents

## Decision

Extended podcast brand color tinting from the three CustomMenu list views (QueueView, SubscribedView, EpisodeListView) to the two remaining custom Views:

1. **DownloadsView** — pill backgrounds, selection borders, title text, progress bars, and subtitle text now use the parent podcast's artColor/artTint via `DataFormat.lookupPodcastColors()`. Status indicator colors (green/red/blue) kept as-is for semantic clarity.

2. **NowPlayingView** — progress arc, play/pause button, skip button backgrounds/icons, podcast name text, and a subtle background wash all use brand colors. The episode title stays white for maximum readability.

**Pattern used:** `CacheManager.loadPodcasts()` for the podcast list (no service reference needed), `DataFormat.lookupPodcastColors()` for lookup, `brightenColor()` + `dimColor()` for tinting, `ensureContrast()` for text legibility.

## Podcast Art Status

artUrl values confirmed present in podcast dicts. Implementation plan for `Communications.makeImageRequest()` thumbnails documented as comments in SubscribedView's `PodcastMenuItem.draw()`. Memory budget: ~64KB for 10 cached 40x40 images. Not yet implemented — needs a dedicated pass with phone-connected testing.

## Build Status

Build passes at `-l 3` (strict) on Venu 4 41mm target.


---

# CustomMenuItem Requires CustomMenu, Not Menu2

**By:** Kaylee (Garmin Dev)
**Date:** 2026-07-15
**Affects:** All agents working on Garmin views

## Problem

`CustomMenuItem.draw()` was never called by the CIQ runtime. All three list screens (Podcasts, Queue, Episodes) showed plain text labels instead of custom-drawn items with brand colors, initial circles, accent bars, and author subtitles.

## Root Cause

**CustomMenuItem is designed for CustomMenu, not Menu2.** The Garmin CIQ API docs explicitly state:

> "A CustomMenuItem is a element of a CustomMenu View"
> "A CustomMenuItem can be added to a CustomMenu using the addItem() method"

`CustomMenu` extends `Menu2` but adds the custom rendering pipeline that calls `draw()`. When CustomMenuItems are added to a plain `Menu2`, it ignores their draw() override and falls back to rendering the label text from `setLabel()`.

## Fix Applied

Converted all three list views from `extends WatchUi.Menu2` to `extends WatchUi.CustomMenu`:

- **SubscribedView** — podcasts list
- **QueueView** — up next episodes
- **EpisodeListView** — episodes per podcast

Key API differences:
| | Menu2 | CustomMenu |
|---|---|---|
| Initialize | `Menu2.initialize({:title => "Text"})` | `CustomMenu.initialize(80, Graphics.COLOR_BLACK, {:titleItemHeight => 50})` |
| Title | String passed in options | Override `drawTitle(dc)` method |
| Item height | Per-item `{:height => N}` (not in API) | Menu-level `itemHeight` param |
| addItem() accepts | MenuItem | CustomMenuItem |
| draw() called? | ❌ No | ✅ Yes |

## Impact

- All CustomMenuItem subclasses (PodcastMenuItem, QueueEpisodeMenuItem, EpisodeMenuItem) now have their `draw()` method invoked
- Empty/loading states use new `EmptyStateMenuItem` (extends CustomMenuItem) since CustomMenu.addItem() only accepts CustomMenuItem
- `Menu2InputDelegate` still works as the delegate for CustomMenu (it extends Menu2)
- Build passes `-l 3` strict

## Decision

**All future CIQ list screens that need custom rendering MUST use `CustomMenu`, not `Menu2`.** Use plain `Menu2` only for simple text-only menus (like the episode action menu with Play/Download options).


---

# Episode Detail View — Navigation Flow Change

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-07-16  
**Affects:** Mal (Lead), all agents

## Decision

Changed the episode selection navigation flow from a simple Menu2 action menu to a full-screen Episode Detail View.

**OLD flow:** EpisodeListView → tap episode → Menu2 with "Play" / "Download" options  
**NEW flow:** EpisodeListView → tap episode → EpisodeDetailView (full info) → tap Play or Download button

## What Changed

1. **Created `EpisodeDetailView.mc`** — Custom `WatchUi.View` + `InputDelegate` pair showing:
   - Podcast name (brand-tinted), episode title (marquee), duration/progress with progress bar, download status (color-coded), play status, and two circular action buttons (Play + Download).

2. **Modified `EpisodeListView.mc`** — `EpisodeListDelegate.onSelect()` now pushes `EpisodeDetailView` instead of creating a Menu2. Removed `showEpisodeActionMenu()` and `EpisodeActionDelegate` (dead code).

3. **Navigation preserved** — Back (swipe right / ESC) pops the detail view. SELECT physical button maps to Play. All existing play+download logic ported from the old action delegate.

## Rationale

- Full layout control for the 390×390 AMOLED display (Menu2 is too constrained)
- Shows episode context (duration, status, download state) before requiring user action
- Consistent design language with NowPlayingView and DownloadsView (brand-tinted, circular buttons, InputDelegate for tap hit-testing)
- Matches Garmin UX patterns (Spotify, native music player show detail before playback)

## Technical Notes

- `const` in Monkey C classes can't be accessed statically across classes — delegate uses hardcoded button coordinates (same pattern as NowPlayingDelegate)
- Brand colors loaded via `CacheManager.loadPodcasts()` + `DataFormat.lookupPodcastColors()` (no service reference needed)
- Build passes `-l 3` strict linting


---

# HomeMenuView Rewritten to CustomMenu

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-07-15  
**Affects:** All agents (UI architecture change)

## Decision

Rewrote HomeMenuView from a manual `WatchUi.View` with hand-rolled scrolling to `WatchUi.CustomMenu` with native smooth scrolling. This is a significant architectural change to the app's primary screen.

## Approach Chosen: Full CustomMenu (Option A)

Evaluated three options:
1. **Option A (chosen):** Full CustomMenu — all nav items + Now Playing as CustomMenuItems
2. **Option B:** Keep View, improve scroll physics — less disruptive but still manual
3. **Option C:** Hybrid CustomMenu with overlay dock — hacky, and Menu2InputDelegate can't handle raw taps for the dock area

Option A was chosen because:
- Native smooth scrolling matches the Podcasts/Queue/Episodes lists
- Menu2InputDelegate handles item selection cleanly (no coordinate math)
- CustomMenu handles focus states, physical button navigation, and touch natively
- The Now Playing dock becomes a compact card item — tapping it opens the full NowPlayingView

## What Changed

- `HomeMenuView` now extends `WatchUi.CustomMenu` (was `WatchUi.View`)
- `HomeMenuDelegate` now extends `WatchUi.Menu2InputDelegate` (was `WatchUi.InputDelegate`)
- Now Playing is a `NowPlayingMenuItem` (CustomMenuItem) reading from `PlaybackState` module
- Marquee animation removed — replaced with `DataFormat.truncateText()` (consistent with all other list views)
- Constructor signatures unchanged — no caller modifications needed

## Trade-offs

- Now Playing is no longer a fixed dock — it's the 5th item in the scrollable list. With 4 nav items (320px) + title (50px) = 370px on 390px screen, there's minimal scrolling needed and the NowPlaying card is always close to visible.
- Marquee animation for long text is gone — truncated with "..." instead. The full NowPlayingView shows complete text.


---

# List View Rounded Pill Redesign

**By:** Kaylee (Garmin Dev)
**Date:** 2026-07-15
**Affects:** All agents (UI pattern)

## Decision

All CustomMenu list views (Subscribed Podcasts, Queue, Episode List) now use **rounded pill-shaped items** instead of edge-to-edge flat rectangles. This is the standard layout pattern going forward for any new CustomMenu screens.

## Design Constants

- **Horizontal margin:** 20px unfocused, 12px focused (expansion effect)
- **Vertical margin:** 4px top and bottom
- **Corner radius:** 14px
- **Background:** True AMOLED black (`COLOR_BLACK`) outside pills
- **Focus indicator:** Bright `drawRoundedRectangle` border + wider pill

## Pattern for New Views

```
dc.clear() with COLOR_BLACK  →  fillRoundedRectangle(marginX, marginY, itemW, itemH, 14)  →  draw content inside margins
```

All X/Y coordinates for content (text, dots, bars, circles) must be relative to `marginX`, not screen edge.

## Cover Art

Still using styled initial circles (larger, FONT_TINY, outer ring border). Actual cover art via `Communications.makeImageRequest()` is future work — TODO comment marks the spot in PodcastMenuItem.draw().


---

# Phase D: Media Playback Integration Decisions

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-19  
**Affects:** Mal (Lead), Wash (API Dev), Zoe (QA)

## Decision: PlaybackState Shared Module Pattern

ContentDelegate (device native events) and NowPlayingView (sim/supplementary UI) both need to publish what's currently playing. Rather than two separate state stores, a single `PlaybackState` module with mutable module-level vars serves as the shared state. Writers: ContentDelegate or NowPlayingView. Readers: HomeMenuView dock, any future widget.

**Rationale:** Modules are singletons in CIQ — no instantiation overhead. Module-level vars persist for the app lifetime. This avoids passing state through constructor chains or Application.Storage round-trips for ephemeral playback info.

## Decision: ContentDelegate Singleton

`getContentDelegate()` in YoCastsApp now returns a cached instance instead of creating a new delegate on each call. This preserves the position-logging timer, current track context, and playing state between system calls.

**Rationale:** The system may call `getContentDelegate()` multiple times during a playback session. Recreating the delegate each time would reset timers and lose track state.

## Decision: Song Event Numeric Constants

Used numeric constants (0=start, 1=pause, 2=resume, 3=complete, 4=stop) for `onSong()` event handling rather than relying on `Media.SONG_EVENT_*` symbol names. Extensive println logging included for hardware verification.

**Rationale:** SDK symbol names for song events are not documented with certainty. Numeric values are stable across SDK versions. The logging will let us validate on real hardware and adjust if needed.

## Open for Mal/Zoe

- Hardware testing needed: onSong() event values must be verified on Venu 4
- Position logging frequency: currently 15s timer + every onSong event. May need tuning based on battery impact.
- NowPlayingView is supplementary — native Garmin music player is the primary playback UI. Do we want to invest in making our NowPlayingView control real playback in Phase E?

