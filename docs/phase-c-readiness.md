# Phase C Readiness Review

> **Author:** Mal (Lead)  
> **Date:** 2026-04-16  
> **Status:** Assessment Complete  
> **Audience:** Jarod Aerts, Kaylee (Garmin Dev), Wash (API Dev)

---

## 1. Codebase Readiness Audit

### 1.1 AudioContentProviderApp Migration — SOLID ✅

The migration is properly implemented in `YoCastsGarmin/source/app/YoCastsApp.mc`:

- **`YoCastsApp extends Application.AudioContentProviderApp`** — correct base class.
- **`getPlaybackConfigurationView()`** — properly implemented as the primary entry point. Three-state auth gate: mock data → HomeMenuView, credentials → HomeMenuView, no creds → LoginPromptView. Returns `[View, InputDelegate]` tuple as required.
- **`getSyncConfigurationView()`** — delegates to `getPlaybackConfigurationView()`. Valid approach for v1 (user configures from the same home menu).
- **`getContentDelegate(arg)`** — returns `new YoCastsContentDelegate()`. Correct.
- **`getSyncDelegate()`** — returns `new YoCastsSyncDelegate()`. Correct.
- **`getProviderIconInfo()`** — returns `ProviderIconInfo` with launcher icon and accent color. Correct.

**No `getInitialView()` override** — good. The MonkeyMusic sample doesn't use it either. The audio provider lifecycle uses `getPlaybackConfigurationView()` as the entry point.

**Dual-build system** is in place:
- `monkey.jungle` → device build (audio-content-provider-app, includes `source/media/`)
- `monkey.simulator.jungle` → simulator build (watch-app, excludes media stubs)

### 1.2 SyncDelegate Skeleton — IN PLACE, NEEDS BUILD-OUT ⚠️

`YoCastsGarmin/source/media/YoCastsSyncDelegate.mc` exists with correct structure:

```
class YoCastsSyncDelegate extends Communications.SyncDelegate
```

Current state:
- ✅ `initialize()` — calls `SyncDelegate.initialize()`
- ✅ `isSyncNeeded()` — returns `false` (correct stub)
- ✅ `onStartSync()` — calls `Media.notifySyncComplete(null)` immediately
- ✅ `onStopSync()` — calls `Communications.cancelAllRequests()` + `Media.notifySyncComplete(null)`

**What needs to be built for Phase C:**
1. `isSyncNeeded()` must check `DownloadQueue.getNextPending() != null`
2. `onStartSync()` must chain `makeWebRequest()` calls with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` + `Media.ENCODING_MP3`
3. Download completion callback must receive `ContentRef`, store `refId` in `StorageManager.markDownloaded()`, then chain next download
4. Must call `Media.notifySyncProgress()` between downloads for UI feedback
5. `onStopSync()` must update in-progress download to `STATUS_PENDING` (not `STATUS_FAILED`)

**IMPORTANT:** The implementation plan references `Media.SyncDelegate` but Kaylee's research confirms it's deprecated after System 9. The current code correctly uses `Communications.SyncDelegate`. The plan's Task C4 pseudocode needs updating.

### 1.3 ContentIterator Stubs — SAFE ✅

`YoCastsGarmin/source/media/YoCastsContentIterator.mc`:

- `get()` → returns `null` ✅ (system shows "No Media" — expected)
- `next()` → returns `null` ✅
- `previous()` → returns `null` ✅
- `peekNext()` → returns `null` ✅
- `peekPrevious()` → returns `null` ✅
- `canSkip()` → returns `true` ✅
- `shuffling()` → returns `false` ✅
- `getPlaybackProfile()` → returns configured profile with skip forward 30s, backward 15s ✅

All null-returning methods are safe. The native media player handles null gracefully by showing "No Media" or "No Content."

### 1.4 ContentDelegate Stub — SAFE ✅

`YoCastsGarmin/source/media/YoCastsContentDelegate.mc`:

- `getContentIterator()` → lazy-initializes and returns `YoCastsContentIterator` ✅
- `resetContentIterator()` → creates fresh iterator ✅
- `onSong()` → logs event, no-op (Phase D will wire to PositionTracker) ✅
- `onShuffle()`, `onRepeat()`, `onThumbsUp()`, `onThumbsDown()` → no-op stubs ✅

### 1.5 Media Directory — WELL-STRUCTURED ✅

`YoCastsGarmin/source/media/` contains exactly the three required files:
1. `YoCastsContentDelegate.mc` — playback event handler
2. `YoCastsContentIterator.mc` — track navigation
3. `YoCastsSyncDelegate.mc` — download orchestration

Correctly excluded from simulator build via `monkey.simulator.jungle` (no `source/media` in sourcePath).

### 1.6 Supporting Infrastructure — STRONG ✅

Several Phase C prerequisites are already built:

| Component | File | Status |
|---|---|---|
| ChangeLog | `source/services/ChangeLog.mc` | ✅ Implemented (coalescing, eviction, persistence) |
| DownloadQueue | `source/services/DownloadQueue.mc` | ✅ Implemented (FIFO, status tracking, retry logic) |
| StorageManager | `source/services/StorageManager.mc` | ✅ Implemented (download metadata, refId mapping) |
| ConnectivityManager | `source/services/ConnectivityManager.mc` | ✅ Implemented (3-state: Wi-Fi/Phone/Offline) |
| CacheManager | `source/services/CacheManager.mc` | ✅ Implemented (podcast/episode/queue/position caching) |
| DownloadsView | `source/views/DownloadsView.mc` | ✅ Implemented (download queue UI with status icons) |
| DataKeys | `source/models/DataModels.mc` | ✅ Implemented (E_URL, E_FILE_TYPE, E_SIZE fields) |

### 1.7 Manifest Permissions — NEEDS UPDATE ⚠️

Current `manifest.xml` permissions:
```xml
<iq:uses-permission id="Communications"/>
```

**Missing for Phase C:**
- **`Background`** — Required for SyncDelegate to run in background context. Without this, the system may not trigger background sync when the watch is charging.

**NOT needed:**
- **`Media`** — Kaylee's research confirmed the SDK rejects explicit `<iq:uses-permission id="Media"/>` for audio content provider apps. The Media permission is implicit in the `audio-content-provider-app` type.

**Action required:** Add `<iq:uses-permission id="Background"/>` to manifest.xml before Phase C.

---

## 2. Phase B→C Transition Checklist

### Prerequisites — What Must Be True

| # | Requirement | Owner | Status | Notes |
|---|---|---|---|---|
| 1 | ChangeLog is working (Phase A) | Kaylee | ✅ DONE | `ChangeLog.mc` with coalescing, eviction, persistence |
| 2 | DownloadQueue is working (Phase A) | Kaylee | ✅ DONE | `DownloadQueue.mc` with FIFO, retry, status tracking |
| 3 | ConnectivityManager is working (Phase A) | Kaylee | ✅ DONE | 3-state detection (Wi-Fi/Phone/Offline) |
| 4 | Sync engine pushes changelog to server (Phase B) | Kaylee | 🔨 IN PROGRESS | `SyncEngine` class spec'd in implementation plan |
| 5 | Sync engine pulls server state (Phase B) | Kaylee | 🔨 IN PROGRESS | `/user/in_progress` + `/up_next/list` |
| 6 | Audio URL auth validated | Wash | ✅ DONE | Confirmed: no auth needed for CDN audio URLs |
| 7 | SyncDelegate wired to DownloadQueue | Kaylee | ❌ NOT STARTED | Phase C Task C4 |
| 8 | `Background` permission in manifest | Kaylee | ❌ NOT DONE | One-line change |
| 9 | CacheManager: `addChangelogEntry()`, `savePosition()`, `loadPositions()` | Kaylee | ⚠️ PARTIAL | Spec'd in plan, ChangeLog module exists separately |

### Gate Criteria

**Phase B is DONE when:**
1. SyncEngine pushes ≥1 changelog entry to PocketCasts (`/sync/update_episode` returns 200)
2. SyncEngine pulls in-progress episodes and queue from server
3. "Furthest position wins" reconciliation resolves at least one conflict correctly
4. Connectivity transition (offline → online) triggers sync automatically
5. Auth token persistence survives app restart

**Phase C can START when:**
- Items 1-6 above are complete (items 7-9 are Phase C work itself)
- Venu 4 hardware is available for testing

### Smallest Possible Phase C MVP

**Goal: Download one episode, play it back.**

Minimum tasks:
1. Add `Background` permission to manifest
2. `YoCastsSyncDelegate.isSyncNeeded()` → check `DownloadQueue.getNextPending()`
3. `YoCastsSyncDelegate.onStartSync()` → `makeWebRequest(url, null, {responseType: HTTP_RESPONSE_CONTENT_TYPE_AUDIO, mediaEncoding: ENCODING_MP3}, callback)`
4. Callback receives `ContentRef` → store `refId` via `StorageManager.markDownloaded()` → `Media.notifySyncComplete(null)`
5. `YoCastsContentIterator.get()` → if downloaded episodes exist, return `new Media.Content(contentRef, metadata)`
6. Manually add one episode to DownloadQueue from the episode list view
7. Trigger sync (charger + Wi-Fi on real hardware)
8. Verify native media player plays the downloaded episode

**Estimated effort:** 2-3 days of focused implementation + 1-2 days hardware debugging.

---

## 3. Risk Assessment — Top 5 Phase C Risks

### Risk 1: 64 KB SyncDelegate Memory Limit — HIGH 🔴

**The problem:** SyncDelegate runs in a background service context with a 64 KB total memory budget. Garmin runtime overhead is ~40-49 KB, leaving only **15-24 KB** for our code + data. Each `makeWebRequest()` callback + state management + DownloadQueue loading consumes memory.

**Mitigations:**
- Keep SyncDelegate code minimal — no imports beyond what's needed
- Don't load full DownloadQueue in background; read one pending item at a time
- Don't import CacheManager (heavy); use direct `Application.Storage` reads for the single key needed
- Profile memory usage on hardware with `System.getSystemStats().freeMemory`
- If over budget: split into a "thin delegate" that reads a single URL from storage, downloads it, saves the refId, and exits

**Contingency:** If 64 KB is insufficient for even one download cycle, investigate whether the foreground app can trigger downloads via `Media.startSync()` (deprecated but possibly functional).

### Risk 2: CDN Redirect Handling on Garmin — MEDIUM 🟡

**The problem:** Every PocketCasts audio URL goes through 1-6 redirect hops (302s) before reaching the final CDN. Wash's research confirmed this. Garmin's `makeWebRequest()` documentation doesn't explicitly state whether it follows HTTP redirects automatically.

**Mitigations:**
- Test on hardware with a real PocketCasts audio URL that redirects
- If Garmin doesn't follow redirects: pre-resolve the URL by issuing a HEAD request first, then download from the final URL
- HEAD request approach adds one extra HTTP call per download but avoids the redirect problem entirely
- The SupportingCast premium feed URLs already contain embedded auth tokens — these MUST be fetched fresh from the API before each download attempt (URL may expire)

**Contingency:** If redirect following fails AND HEAD doesn't give us the final URL, use the phone BT proxy to resolve the URL chain (the phone's HTTP client definitely follows redirects).

### Risk 3: Audio File Storage Limits — MEDIUM 🟡

**The problem:** Venu 4 has ~3.5-4 GB usable for audio after system files. Podcast episodes average ~1 MB/minute, so a 1-hour episode is ~60 MB. 20 episodes (our `MAX_QUEUE_SIZE`) could be ~1-2 GB. The exact per-app storage quota is unknown — Garmin may enforce a per-app cap.

**Mitigations:**
- Use `Media.getCacheStatistics()` to check capacity and usage before each download
- Enforce our own 10-episode cap (`MAX_DOWNLOAD_CAP` in implementation plan)
- Implement cleanup: delete completed + synced episodes not in Up Next queue
- Prioritize shorter episodes in download order (better battery efficiency)
- Monitor actual storage consumption on hardware during testing

**Contingency:** If per-app cap is surprisingly low (< 500 MB), reduce MAX_DOWNLOAD_CAP to 5 and warn the user.

### Risk 4: Interrupted Download Handling — MEDIUM 🟡

**The problem:** Downloads can be interrupted by: user canceling sync, Wi-Fi dropping, watch being removed from charger, background service timeout. In v1, we have no resume — partial downloads restart from scratch.

**Mitigations:**
- `onStopSync()` already calls `Communications.cancelAllRequests()` — clean cancellation
- Set interrupted downloads back to `STATUS_PENDING` (not `STATUS_FAILED`) so they retry
- Track `errorCount` per download item — give up after 3 failures
- Prioritize smallest pending downloads first to maximize chance of completion
- Long episodes (>60 min / >60 MB) are risky — consider warning the user or capping at 45 min episodes in v1

**Contingency:** If interrupted downloads corrupt the media cache, call `Media.deleteCachedItem(contentRef)` to clean up before retrying.

### Risk 5: `makeWebRequest` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` Behavior — HIGH 🔴

**The problem:** The implementation plan's Task C4 uses `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` with `makeWebRequest()`. Kaylee's research confirms this is the correct approach (MonkeyMusic sample does exactly this), BUT it's only verified for use within `SyncDelegate.onStartSync()`. Community reports suggest it may fail outside the sync context.

**Mitigations:**
- Phase C MVP must test this on real hardware immediately — it's the single biggest unknown
- Verify the callback receives a `ContentRef` (not null or error code)
- Verify the `ContentRef.getId()` is usable to construct a `Media.Content` object
- Test with both MP3 and M4A audio files (MP3 is most common, M4A is the edge case)
- Verify that `Media.ENCODING_MP3` is correct for `audio/mpeg` content type

**Contingency:** If `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` doesn't work, investigate `HTTP_RESPONSE_CONTENT_TYPE_URL` as an alternative (returns the final URL after redirects, which could then be passed to a different download mechanism).

---

## 4. Key Findings Summary

### What's Working Well
- AudioContentProviderApp migration is clean and complete
- All three media stubs (ContentDelegate, ContentIterator, SyncDelegate) are properly structured
- DownloadQueue, StorageManager, ChangeLog, ConnectivityManager — all Phase C prerequisites are built
- Dual-build system works correctly (simulator vs device)
- Audio URL auth is confirmed not required (Wash validated this)

### What Needs Attention Before Phase C
1. **Add `Background` permission to manifest** — blocking, simple fix
2. **SyncEngine (Phase B) must be completed** — blocking, in progress
3. **`CacheManager` needs `addChangelogEntry()`, `savePosition()`, `loadPositions()`** — the implementation plan describes these but ChangeLog.mc was built as a separate module instead. Either CacheManager needs these methods or the SyncDelegate must import ChangeLog directly. Resolve the API contract.
4. **Real hardware is required** — SyncDelegate download behavior, Media module storage, and ContentRef lifecycle cannot be validated in the simulator

### Open Questions
1. Does `makeWebRequest` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` follow 302 redirects automatically?
2. What is the per-app media storage quota on Venu 4?
3. Does `Communications.SyncDelegate` (non-deprecated) work identically to `Media.SyncDelegate` for audio downloads?
4. Is there a non-deprecated replacement for `Media.startSync()` to programmatically trigger sync?
