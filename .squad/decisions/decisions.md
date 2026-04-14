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
