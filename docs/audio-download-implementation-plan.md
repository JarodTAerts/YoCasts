# Audio Download & Offline Sync — Implementation Plan

> **Version:** 1.0  
> **Author:** Mal (Lead)  
> **Date:** 2026-04-13  
> **Status:** Implementation-ready  
> **Audience:** Kaylee (primary implementer), Wash (API support)  
> **Parent design:** `docs/offline-sync-design.md` v1.1  
> **Target device:** Venu 4 41mm (390×390, 768 KB app memory, 64 KB background)

---

## How to Use This Document

This is a **step-by-step implementation blueprint**. Each phase has numbered tasks with dependencies, file paths, exact Monkey C API calls, and pseudocode. Build in order. Don't skip phases. Every task has explicit exit criteria.

**Conventions in this document:**
- `[FILE: path]` = file to create or modify
- `[DEPENDS: task]` = must complete the dependency first
- `[API: endpoint]` = PocketCasts API endpoint (see `docs/pocketcasts-api-reference.md`)
- Pseudocode uses Monkey C syntax unless noted otherwise
- Storage keys use the `"yc_"` prefix established by CacheManager

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Phase A: Changelog & Position Tracking](#2-phase-a-changelog--position-tracking)
3. [Phase B: Sync Engine](#3-phase-b-sync-engine)
4. [Phase C: Audio Download Infrastructure](#4-phase-c-audio-download-infrastructure)
5. [Phase D: Media Playback Integration](#5-phase-d-media-playback-integration)
6. [Phase E: Full Reconciliation & Polish](#6-phase-e-full-reconciliation--polish)
7. [Usage Scenarios — Walkthrough](#7-usage-scenarios--walkthrough)
8. [Power Efficiency Contract](#8-power-efficiency-contract)
9. [Storage Management Plan](#9-storage-management-plan)
10. [Error Handling Matrix](#10-error-handling-matrix)
11. [Integration Map — Existing Code](#11-integration-map--existing-code)
12. [File Inventory](#12-file-inventory)

---

## 1. System Overview

### 1.1 What We're Building

An offline-capable podcast player for Garmin. The user's primary workflow:

1. **At home (Wi-Fi):** Watch auto-downloads queued episodes. No phone needed.
2. **On a run (offline):** Watch plays downloaded episodes, tracks position locally.
3. **Back home (Wi-Fi reconnects):** Watch syncs positions, downloads new episodes.

### 1.2 Component Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YoCastsApp                                  │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────────────┐ │
│  │ Views        │  │ IPodcastService  │  │ ConnectivityManager   │ │
│  │ (UI layer)   │  │ (data contract)  │  │ (poll connectivity)   │ │
│  └──────┬───────┘  └────────┬─────────┘  └───────────┬───────────┘ │
│         │                   │                         │             │
│         ▼                   ▼                         ▼             │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              CachedPodcastService (decorator)                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │   │
│  │  │ CacheManager │  │ ChangeLog    │  │ SyncEngine       │   │   │
│  │  │ (storage)    │  │ (mutations)  │  │ (reconciliation) │   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Media Module Integration                        │   │
│  │  ┌──────────────────┐  ┌──────────────┐  ┌───────────────┐  │   │
│  │  │ YoCastsProvider   │  │ YoCastsSync  │  │ YoCastsContent│  │   │
│  │  │ (ContentProvider) │  │ (SyncDelegate│  │ (Iterator +   │  │   │
│  │  │                   │  │  + download) │  │  Delegate)    │  │   │
│  │  └──────────────────┘  └──────────────┘  └───────────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.3 Phase Dependencies

```
Phase A: Changelog & Position Tracking
    │
    ▼
Phase B: Sync Engine  ──────────────────────────────┐
    │                                                │
    ▼                                                │
Phase C: Audio Download Infrastructure               │
    │                                                │
    ▼                                                │
Phase D: Media Playback Integration                  │
    │                                                │
    ▼                                                ▼
Phase E: Full Reconciliation & Polish  ◄─────────────┘
```

Phases A and B are pure Application.Storage and HTTP — no Media module. Phase C introduces Media but with no playback yet. Phase D wires playback. Phase E adds edge case handling and stress testing.

---

## 2. Phase A: Changelog & Position Tracking

**Goal:** Every playback mutation is persisted locally. No data loss on crash or reboot. This is the foundation everything else builds on.

**Estimated effort:** 2–3 days

### Task A1: Add Changelog to CacheManager

**[FILE: `YoCastsGarmin/source/services/CacheManager.mc`]**

Add changelog storage alongside existing cache keys. The changelog is an array of mutation entries that survives app restarts. It must never be wiped by `clearCache()`.

**Add these constants and methods:**

```monkeyc
// ---- New storage key constants ----
const KEY_CHANGELOG = "yc_changelog";
const KEY_CHANGELOG_SEQ = "yc_cl_seq";       // monotonic sequence number
const KEY_POSITIONS = "yc_positions";         // consolidated positions map
const KEY_DL_MANIFEST = "yc_dl_manifest";     // downloaded episode UUIDs
const KEY_SYNC_STATE = "yc_sync_state";       // sync state machine position
const KEY_AUTH = "yc_auth";                   // persisted auth tokens

// ================================================================
// Changelog
// ================================================================

//! Add a changelog entry with per-episode coalescing for POSITION_UPDATE.
//! Coalescing: If the same episode already has a POSITION_UPDATE in the log,
//! replace it (don't append). This bounds changelog growth.
function addChangelogEntry(type as String, episodeUuid as String,
                           podcastUuid as String, data as Dictionary) as Void {
    var log = loadChangelog();

    // Coalesce: replace existing POSITION_UPDATE for same episode
    if (type.equals("POSITION_UPDATE")) {
        var filtered = [] as Array<Dictionary>;
        for (var i = 0; i < log.size(); i++) {
            var entry = log[i] as Dictionary;
            var entryType = entry.get("type") as String;
            var entryEp = entry.get("episodeUuid") as String;
            if (!(entryType.equals("POSITION_UPDATE") &&
                  entryEp.equals(episodeUuid))) {
                filtered.add(entry);
            }
        }
        log = filtered;
    }

    // Get next sequence number
    var seqVal = Application.Storage.getValue(KEY_CHANGELOG_SEQ);
    var seq = (seqVal != null && seqVal instanceof Number)
              ? (seqVal as Number) + 1 : 1;

    log.add({
        "id" => seq as Application.Storage.ValueType,
        "type" => type as Application.Storage.ValueType,
        "episodeUuid" => episodeUuid as Application.Storage.ValueType,
        "podcastUuid" => podcastUuid as Application.Storage.ValueType,
        "data" => data as Application.Storage.ValueType,
        "timestamp" => Time.now().value() as Application.Storage.ValueType
    } as Dictionary);

    // Safety cap: 100 entries max
    if (log.size() > 100) {
        log = log.slice(log.size() - 100, null) as Array<Dictionary>;
    }

    Application.Storage.setValue(KEY_CHANGELOG_SEQ,
                                seq as Application.Storage.ValueType);
    Application.Storage.setValue(KEY_CHANGELOG,
                                log as Application.Storage.ValueType);
}

//! Load the changelog. Returns empty array if none exists.
function loadChangelog() as Array<Dictionary> {
    var val = Application.Storage.getValue(KEY_CHANGELOG);
    if (val != null && val instanceof Array) {
        return val as Array<Dictionary>;
    }
    return [] as Array<Dictionary>;
}

//! Remove specific changelog entries by ID after successful sync push.
function removeChangelogEntries(ids as Array<Number>) as Void {
    var log = loadChangelog();
    var remaining = [] as Array<Dictionary>;
    for (var i = 0; i < log.size(); i++) {
        var entry = log[i] as Dictionary;
        var entryId = entry.get("id") as Number;
        var found = false;
        for (var j = 0; j < ids.size(); j++) {
            if (ids[j] == entryId) {
                found = true;
                break;
            }
        }
        if (!found) {
            remaining.add(entry);
        }
    }
    Application.Storage.setValue(KEY_CHANGELOG,
                                remaining as Application.Storage.ValueType);
}

//! Check if there are unsynced changes.
function hasUnsyncedChanges() as Boolean {
    return loadChangelog().size() > 0;
}
```

**Critical: Update `clearCache()` to be selective:**

```monkeyc
//! Wipe cached data but PRESERVE changelog, auth, sync state, download manifest.
function clearCache() as Void {
    Application.Storage.deleteValue(KEY_PODCASTS);
    Application.Storage.deleteValue(KEY_QUEUE);
    Application.Storage.deleteValue(KEY_POSITIONS);
    // Delete all episode caches (we don't track which keys exist,
    // so clearValues() followed by re-saving protected keys is safer)
    // Alternatively, track known episode cache keys in a separate key.
    // For v1: iterate known podcast UUIDs from cached podcasts list.
}
```

> **Design note:** `clearValues()` is no longer safe because changelog and auth must survive a cache clear. Switch to selective `deleteValue()`.

**Exit criteria:** `addChangelogEntry()` round-trips through `loadChangelog()`. Coalescing removes old POSITION_UPDATE entries. Cap at 100 works. `clearCache()` doesn't touch changelog.

---

### Task A2: Positions Map in CacheManager

**[FILE: `YoCastsGarmin/source/services/CacheManager.mc`]**
**[DEPENDS: A1]**

Replace the current per-episode position keys (`yc_pos_<uuid>`) with a consolidated positions map. One key, one read, bounded size. This is critical for efficiency — the sync engine reads all positions at once.

```monkeyc
// ================================================================
// Consolidated Positions Map
// ================================================================

//! Save a position to the consolidated map.
//! The map is: { episodeUuid => { "position", "status", "duration",
//!               "podcastUuid", "updatedAt", "dirty" } }
function savePosition(episodeUuid as String, podcastUuid as String,
                      position as Number, status as Number,
                      duration as Number) as Void {
    var positions = loadPositions();

    positions.put(episodeUuid, {
        "position" => position as Application.Storage.ValueType,
        "status" => status as Application.Storage.ValueType,
        "duration" => duration as Application.Storage.ValueType,
        "podcastUuid" => podcastUuid as Application.Storage.ValueType,
        "updatedAt" => Time.now().value() as Application.Storage.ValueType,
        "dirty" => true as Application.Storage.ValueType
    } as Dictionary);

    // Cap at 50 entries — evict oldest clean entries first
    if (positions.size() > 50) {
        _evictPositions(positions);
    }

    Application.Storage.setValue(KEY_POSITIONS,
                                positions as Application.Storage.ValueType);
}

//! Load all positions. Returns empty Dictionary if none exist.
function loadPositions() as Dictionary {
    var val = Application.Storage.getValue(KEY_POSITIONS);
    if (val != null && val instanceof Dictionary) {
        return val as Dictionary;
    }
    return {} as Dictionary;
}

//! Get position for a single episode, or null.
function getPosition(episodeUuid as String) as Dictionary? {
    var positions = loadPositions();
    var pos = positions.get(episodeUuid);
    if (pos != null && pos instanceof Dictionary) {
        return pos as Dictionary;
    }
    return null;
}

//! Mark all positions as clean (dirty: false) after sync.
function markPositionsClean(uuids as Array<String>) as Void {
    var positions = loadPositions();
    for (var i = 0; i < uuids.size(); i++) {
        var pos = positions.get(uuids[i]);
        if (pos != null && pos instanceof Dictionary) {
            (pos as Dictionary).put("dirty",
                false as Application.Storage.ValueType);
        }
    }
    Application.Storage.setValue(KEY_POSITIONS,
                                positions as Application.Storage.ValueType);
}

//! Evict oldest clean entries until under cap.
private function _evictPositions(positions as Dictionary) as Void {
    // Collect clean entries sorted by updatedAt
    var keys = positions.keys();
    var oldestCleanKey = null as String?;
    var oldestCleanTime = 2147483647; // max int

    while (positions.size() > 50) {
        oldestCleanKey = null;
        oldestCleanTime = 2147483647;
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i] as String;
            var val = positions.get(key) as Dictionary;
            var dirty = val.get("dirty");
            if (dirty != null && dirty instanceof Boolean && !(dirty as Boolean)) {
                var updatedAt = val.get("updatedAt") as Number;
                if (updatedAt < oldestCleanTime) {
                    oldestCleanTime = updatedAt;
                    oldestCleanKey = key;
                }
            }
        }
        if (oldestCleanKey != null) {
            positions.remove(oldestCleanKey);
        } else {
            break; // all entries are dirty — can't evict
        }
    }
}
```

**Migration note:** The existing `savePlaybackPosition()` / `loadPlaybackPosition()` methods using `KEY_POSITION_PREFIX` stay until Phase E cleanup. The new consolidated methods are used by all new code. Old methods are deprecated but not removed (no breaking changes to existing views).

**Exit criteria:** Save 55 positions. Verify 5 oldest clean entries are evicted. Dirty entries survive eviction. `getPosition()` returns correct data after round-trip.

---

### Task A3: PositionTracker Module

**[FILE: `YoCastsGarmin/source/services/PositionTracker.mc`]** (NEW)
**[DEPENDS: A1, A2]**

Encapsulates the "save position every N seconds during playback" logic. Owns the Timer. Handles battery-aware frequency adjustment.

```monkeyc
import Toybox.Lang;
import Toybox.Timer;
import Toybox.System;
import Toybox.Time;

//! Tracks playback position at configurable intervals.
//! Writes to CacheManager positions map AND changelog.
//! Adjusts frequency based on battery level.
module PositionTracker {

    // ---- State ----
    var _timer as Timer.Timer? = null;
    var _episodeUuid as String = "";
    var _podcastUuid as String = "";
    var _duration as Number = 0;
    var _lastSavedPosition as Number = -1;
    var _isTracking as Boolean = false;

    // ---- Configuration ----
    const SAVE_INTERVAL_NORMAL = 15000;    // 15 seconds (ms)
    const SAVE_INTERVAL_LOW_BATT = 60000;  // 60 seconds when battery < 20%
    const BATTERY_LOW_THRESHOLD = 20;      // percent

    //! Begin tracking position for an episode.
    //! Call this when playback starts or resumes.
    function startTracking(episodeUuid as String, podcastUuid as String,
                           duration as Number, initialPosition as Number) as Void {
        stopTracking(); // clean up any existing tracker

        _episodeUuid = episodeUuid;
        _podcastUuid = podcastUuid;
        _duration = duration;
        _lastSavedPosition = initialPosition;
        _isTracking = true;

        _timer = new Timer.Timer();
        var interval = _getSaveInterval();
        _timer.start(method(:onPositionTick), interval, true);
    }

    //! Stop tracking. Persists final position.
    function stopTracking() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        _isTracking = false;
    }

    //! Called by the timer. Reads current position from the Media player
    //! and persists it.
    //! @param currentPosition — the caller must provide the current position
    //!        since PositionTracker doesn't own the media player reference.
    function savePosition(currentPosition as Number) as Void {
        if (!_isTracking || _episodeUuid.equals("")) {
            return;
        }

        // Don't write if position hasn't changed
        if (currentPosition == _lastSavedPosition) {
            return;
        }

        _lastSavedPosition = currentPosition;

        // Determine status
        var status = DataKeys.STATUS_IN_PROGRESS;
        if (currentPosition >= _duration && _duration > 0) {
            status = DataKeys.STATUS_COMPLETED;
        }

        // Write to positions map
        CacheManager.savePosition(
            _episodeUuid, _podcastUuid,
            currentPosition, status, _duration
        );

        // Write to changelog
        CacheManager.addChangelogEntry(
            status == DataKeys.STATUS_COMPLETED
                ? "EPISODE_COMPLETED" : "POSITION_UPDATE",
            _episodeUuid,
            _podcastUuid,
            {
                "position" => currentPosition
                    as Application.Storage.ValueType,
                "status" => status as Application.Storage.ValueType,
                "duration" => _duration as Application.Storage.ValueType
            } as Dictionary
        );
    }

    //! Mark the current episode as completed.
    function markCompleted() as Void {
        if (_episodeUuid.equals("")) { return; }

        CacheManager.savePosition(
            _episodeUuid, _podcastUuid,
            _duration, DataKeys.STATUS_COMPLETED, _duration
        );

        CacheManager.addChangelogEntry(
            "EPISODE_COMPLETED",
            _episodeUuid,
            _podcastUuid,
            {
                "position" => _duration as Application.Storage.ValueType,
                "status" => DataKeys.STATUS_COMPLETED
                    as Application.Storage.ValueType,
                "duration" => _duration as Application.Storage.ValueType
            } as Dictionary
        );

        stopTracking();
    }

    //! Get save interval based on battery level.
    private function _getSaveInterval() as Number {
        var stats = System.getSystemStats();
        if (stats.battery < BATTERY_LOW_THRESHOLD) {
            return SAVE_INTERVAL_LOW_BATT;
        }
        return SAVE_INTERVAL_NORMAL;
    }

    //! Timer callback stub — the actual position must be provided externally.
    //! The ContentDelegate will call savePosition(currentPos) from its
    //! onPosition callback.
    function onPositionTick() as Void {
        // Position updates come from ContentDelegate.onPosition(),
        // not from this timer. The timer exists to ensure periodic saves
        // even if onPosition isn't called frequently enough.
        // In practice, the ContentDelegate should call savePosition()
        // on each onPosition event AND this timer acts as a safety net.
    }
}
```

**Design decision — why 15 seconds?**
- **Data loss on crash:** At most 15s of progress. Acceptable — user rewinds 15s, no big deal.
- **Battery impact:** `Application.Storage.setValue()` is a flash write. At 15s intervals during a 1-hour episode, that's 240 writes. Garmin flash is rated for millions of cycles. Negligible.
- **Low battery mode:** At < 20%, drops to 60s. 4x fewer writes. Max 30s data loss — still acceptable.
- **Alternative considered:** 30s interval. Rejected — 30s of lost progress feels too much after a crash. 15s is the sweet spot.

**Exit criteria:** PositionTracker starts, saves at 15s intervals, coalesces in changelog, stops cleanly. Low battery detection adjusts interval to 60s.

---

### Task A4: ConnectivityManager Module

**[FILE: `YoCastsGarmin/source/services/ConnectivityManager.mc`]** (NEW)
**[DEPENDS: none — can be built in parallel with A1-A3]**

Centralized connectivity monitoring with state transition detection. Replaces the scattered `_isConnected()` checks.

```monkeyc
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

//! Centralized connectivity state management.
//! Polls System.getDeviceSettings() on a timer and detects transitions.
//! When connectivity returns after being offline, triggers sync and downloads.
module ConnectivityManager {

    // Connectivity states
    const STATE_OFFLINE = 0;
    const STATE_PHONE_BT = 1;
    const STATE_WIFI_DIRECT = 2;

    // ---- State ----
    var _currentState as Number = STATE_OFFLINE;
    var _previousState as Number = STATE_OFFLINE;
    var _timer as Timer.Timer? = null;
    var _listeners as Array = [] as Array;

    // ---- Configuration ----
    const POLL_INTERVAL_NORMAL = 30000;     // 30s when app is active
    const POLL_INTERVAL_BACKGROUND = 300000; // 5min for background service

    //! Start polling connectivity.
    function start() as Void {
        _currentState = _detectState();
        _previousState = _currentState;
        _timer = new Timer.Timer();
        _timer.start(method(:onPoll), POLL_INTERVAL_NORMAL, true);
    }

    //! Stop polling.
    function stop() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    //! Register a listener. Listener must implement:
    //!   onConnectivityChanged(oldState, newState) as Void
    function addListener(listener as Object) as Void {
        _listeners.add(listener);
    }

    //! Get current connectivity state.
    function getState() as Number {
        return _currentState;
    }

    //! Convenience: can we make HTTP requests?
    function isConnected() as Boolean {
        return _currentState != STATE_OFFLINE;
    }

    //! Convenience: are we on Wi-Fi (best for downloads)?
    function isWiFi() as Boolean {
        return _currentState == STATE_WIFI_DIRECT;
    }

    //! Timer callback — detect state changes.
    function onPoll() as Void {
        var newState = _detectState();
        if (newState != _currentState) {
            _previousState = _currentState;
            _currentState = newState;
            _notifyListeners(_previousState, _currentState);
        }
    }

    //! Read device settings and determine connectivity state.
    private function _detectState() as Number {
        var settings = System.getDeviceSettings();
        if (!settings.connectionAvailable) {
            return STATE_OFFLINE;
        }
        if (!settings.phoneConnected) {
            return STATE_WIFI_DIRECT;
        }
        return STATE_PHONE_BT;
    }

    //! Notify all registered listeners of state change.
    private function _notifyListeners(oldState as Number,
                                       newState as Number) as Void {
        for (var i = 0; i < _listeners.size(); i++) {
            var listener = _listeners[i];
            if (listener has :onConnectivityChanged) {
                listener.onConnectivityChanged(oldState, newState);
            }
        }
    }
}
```

**State transition table — what each transition triggers:**

```
OFFLINE → WIFI_DIRECT:
  1. Trigger SyncEngine (push changelog, pull server state)
  2. After sync: trigger DownloadManager (auto-download queued episodes)
  
OFFLINE → PHONE_BT:
  1. Trigger SyncEngine (push changelog, pull server state)
  2. NO auto-downloads (BT too slow for audio files)
  
PHONE_BT → WIFI_DIRECT:
  1. Trigger DownloadManager (now on fast network)
  
WIFI_DIRECT → OFFLINE:
  1. Cancel any in-progress downloads
  2. Set all services to offline mode
  
PHONE_BT → OFFLINE:
  1. Set all services to offline mode
  
WIFI_DIRECT → PHONE_BT:
  1. Cancel downloads (dropping to slow network)
  2. Continue metadata sync if in progress
```

**Exit criteria:** ConnectivityManager detects all three states correctly in simulator. Transition callbacks fire. No false transitions during stable connectivity.

---

### Task A5: Update CachedPodcastService for Connectivity

**[FILE: `YoCastsGarmin/source/services/CachedPodcastService.mc`]**
**[DEPENDS: A4]**

Replace the private `_isConnected()` method with `ConnectivityManager.isConnected()`. This is a small but important change — it means the entire app uses a single source of truth for connectivity.

```monkeyc
// BEFORE (line 191):
private function _isConnected() as Boolean {
    return System.getDeviceSettings().phoneConnected;
}

// AFTER:
private function _isConnected() as Boolean {
    return ConnectivityManager.isConnected();
}
```

**Also update `fetchAll()` to use `connectionAvailable` instead of just `phoneConnected`** — the current code only fetches when the phone is BT-connected, missing the Wi-Fi-direct case entirely. This is a bug in the current implementation.

**Exit criteria:** `fetchAll()` works over Wi-Fi-direct (no phone). Existing BT-proxy path still works.

---

### Task A6: Auth Token Persistence

**[FILE: `YoCastsGarmin/source/services/CacheManager.mc`]**
**[DEPENDS: A1]**

Persist auth tokens in `Application.Storage` so the sync engine can re-auth after app restart without requiring the user to re-enter credentials.

```monkeyc
// ================================================================
// Auth Token Persistence
// ================================================================

//! Save auth tokens after successful login or refresh.
function saveAuth(accessToken as String, refreshToken as String,
                  expiresAt as Number) as Void {
    Application.Storage.setValue(KEY_AUTH, {
        "accessToken" => accessToken as Application.Storage.ValueType,
        "refreshToken" => refreshToken as Application.Storage.ValueType,
        "expiresAt" => expiresAt as Application.Storage.ValueType,
        "savedAt" => Time.now().value() as Application.Storage.ValueType
    } as Application.Storage.ValueType);
}

//! Load saved auth tokens. Returns null if not saved.
function loadAuth() as Dictionary? {
    var val = Application.Storage.getValue(KEY_AUTH);
    if (val != null && val instanceof Dictionary) {
        return val as Dictionary;
    }
    return null;
}

//! Clear auth (on logout or credential change).
function clearAuth() as Void {
    Application.Storage.deleteValue(KEY_AUTH);
}
```

**Also update `PocketCastsPodcastService`** to:
1. Try loading saved tokens on init before attempting login.
2. Save tokens after successful login and refresh.
3. On 401, try refresh → re-login → fail gracefully.

**Exit criteria:** App restarts, loads saved token, skips login if token is valid. Expired token triggers refresh. Failed refresh triggers re-login.

---

### Phase A Summary

After Phase A, the app:
- Tracks playback position every 15s (60s on low battery)
- Persists a coalesced changelog in Application.Storage
- Detects connectivity state (Wi-Fi / BT / Offline) via polling
- Uses a single connectivity source of truth
- Persists auth tokens for automatic re-auth

**No sync yet. No downloads yet.** Changelog just accumulates.

---

## 3. Phase B: Sync Engine

**Goal:** Push local changes to server. Pull server state. Reconcile conflicts. The changelog goes from accumulating to flushing.

**Estimated effort:** 4–5 days

### Task B1: SyncEngine Module — State Machine

**[FILE: `YoCastsGarmin/source/services/SyncEngine.mc`]** (NEW)
**[DEPENDS: A1, A2, A4, A6]**

The sync engine is a state machine that processes one step at a time, chaining via `makeWebRequest()` callbacks. It is **fully asynchronous** and **idempotent** — safe to restart at any point.

```
STATE MACHINE:

    ┌──────┐
    │ IDLE │◄──────────────────────────────────────────────┐
    └──┬───┘                                               │
       │ triggerSync()                                     │
       ▼                                                   │
    ┌──────────┐                                           │
    │ CHECKING │─── no connectivity ──► IDLE               │
    │ AUTH     │                                            │
    └──┬───────┘                                           │
       │ token valid                                       │
       ▼                                                   │
    ┌──────────┐                                           │
    │ PUSHING  │─── push all done ──────────────┐          │
    │ CHANGES  │                                │          │
    │          │─── push failed (retryable) ──► RETRY_WAIT │
    └──────────┘                                │          │
                                                ▼          │
    ┌──────────┐                           ┌─────────┐     │
    │ PULLING  │◄──────────────────────────│ (merge) │     │
    │ SERVER   │                           └─────────┘     │
    └──┬───────┘                                           │
       │ pull complete                                     │
       ▼                                                   │
    ┌──────────────┐                                       │
    │ RECONCILING  │                                       │
    └──┬───────────┘                                       │
       │ reconciliation complete                           │
       ▼                                                   │
    ┌──────────┐                                           │
    │ CLEANING │─── done ──────────────────────────────────┘
    │ UP       │
    └──────────┘

    RETRY_WAIT: Wait 30s, then re-enter PUSHING. Max 3 retries, then → IDLE (error).
```

**Core implementation:**

```monkeyc
import Toybox.Lang;
import Toybox.Communications;
import Toybox.Time;
import Toybox.System;
import Toybox.WatchUi;

//! Sync engine — pushes local changelog to PocketCasts, pulls server state,
//! reconciles conflicts. Fully async, idempotent, safe to retry.
class SyncEngine {

    // ---- Sync States ----
    enum {
        SYNC_IDLE,
        SYNC_AUTH,
        SYNC_PUSHING,
        SYNC_PULLING_IN_PROGRESS,
        SYNC_PULLING_EPISODES,
        SYNC_PULLING_QUEUE,
        SYNC_RECONCILING,
        SYNC_CLEANUP,
        SYNC_RETRY_WAIT,
        SYNC_ERROR
    }

    // ---- State ----
    private var _state as Number = SYNC_IDLE;
    private var _accessToken as String = "";
    private var _refreshToken as String = "";
    private var _tokenExpiresAt as Number = 0;

    // Push pipeline state
    private var _pushQueue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _pushIndex as Number = 0;
    private var _pushedIds as Array<Number> = [] as Array<Number>;

    // Pull pipeline state
    private var _serverInProgress as Array<Dictionary> = [] as Array<Dictionary>;
    private var _serverQueue as Dictionary = {} as Dictionary;
    private var _serverEpisodeFetchQueue as Array<String> = [] as Array<String>;
    private var _serverEpisodeResults as Dictionary = {} as Dictionary;
    private var _serverEpisodeFetchIndex as Number = 0;

    // Retry state
    private var _retryCount as Number = 0;
    private const MAX_RETRIES = 3;
    private const RETRY_DELAY = 30000; // 30 seconds

    // Callback
    private var _onComplete as Method? = null;

    // ---- API ----
    private const API_BASE = "https://api.pocketcasts.com";

    //! Trigger a sync. No-op if already syncing.
    function triggerSync(onComplete as Method?) as Void {
        if (_state != SYNC_IDLE && _state != SYNC_ERROR) {
            return; // already syncing
        }

        _onComplete = onComplete;
        _retryCount = 0;
        _state = SYNC_AUTH;
        _stepAuth();
    }

    //! Is a sync currently in progress?
    function isSyncing() as Boolean {
        return _state != SYNC_IDLE && _state != SYNC_ERROR;
    }

    //! Get current state for UI display.
    function getState() as Number {
        return _state;
    }

    // ================================================================
    // Step 1: Auth Check
    // ================================================================

    private function _stepAuth() as Void {
        if (!ConnectivityManager.isConnected()) {
            _finish(false, "No connectivity");
            return;
        }

        // Try loading saved auth
        var auth = CacheManager.loadAuth();
        if (auth != null) {
            _accessToken = auth.get("accessToken") as String;
            _refreshToken = auth.get("refreshToken") as String;
            _tokenExpiresAt = auth.get("expiresAt") as Number;

            if (Time.now().value() < _tokenExpiresAt - 300) {
                // Token still valid — proceed to push
                _state = SYNC_PUSHING;
                _stepPushBegin();
                return;
            }

            // Token expired or expiring — try refresh
            _doTokenRefresh();
            return;
        }

        // No saved auth — try login
        _doLogin();
    }

    private function _doLogin() as Void {
        var email = "";
        var password = "";
        try {
            email = Application.Properties.getValue("PocketCastsEmail") as String;
            password = Application.Properties.getValue("PocketCastsPassword") as String;
        } catch (e) {
            _finish(false, "No credentials");
            return;
        }

        Communications.makeWebRequest(
            API_BASE + "/user/login_pocket_casts",
            {
                "email" => email,
                "password" => password,
                "scope" => "webplayer"
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onSyncLoginResponse)
        );
    }

    //! @hide
    function onSyncLoginResponse(responseCode as Number,
                                  data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            _accessToken = dict.get("accessToken") as String;
            _refreshToken = dict.get("refreshToken") as String;
            var expiresIn = dict.get("expiresIn") as Number;
            _tokenExpiresAt = Time.now().value() + expiresIn;
            CacheManager.saveAuth(_accessToken, _refreshToken, _tokenExpiresAt);

            _state = SYNC_PUSHING;
            _stepPushBegin();
        } else {
            _finish(false, "Login failed: " + responseCode);
        }
    }

    private function _doTokenRefresh() as Void {
        Communications.makeWebRequest(
            API_BASE + "/user/token",
            {
                "grantType" => "refresh_token",
                "refreshToken" => _refreshToken
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onSyncRefreshResponse)
        );
    }

    //! @hide
    function onSyncRefreshResponse(responseCode as Number,
                                    data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            _accessToken = dict.get("accessToken") as String;
            _refreshToken = dict.get("refreshToken") as String;
            var expiresIn = dict.get("expiresIn") as Number;
            _tokenExpiresAt = Time.now().value() + expiresIn;
            CacheManager.saveAuth(_accessToken, _refreshToken, _tokenExpiresAt);

            _state = SYNC_PUSHING;
            _stepPushBegin();
        } else {
            // Refresh failed — try full login
            _doLogin();
        }
    }

    // ================================================================
    // Step 2: Push Local Changes
    // ================================================================

    private function _stepPushBegin() as Void {
        var changelog = CacheManager.loadChangelog();
        if (changelog.size() == 0) {
            // Nothing to push — skip to pull
            _state = SYNC_PULLING_IN_PROGRESS;
            _stepPullInProgress();
            return;
        }

        // Build push queue from changelog
        _pushQueue = [] as Array<Dictionary>;
        _pushedIds = [] as Array<Number>;

        for (var i = 0; i < changelog.size(); i++) {
            var entry = changelog[i] as Dictionary;
            var type = entry.get("type") as String;
            if (type.equals("POSITION_UPDATE") || type.equals("EPISODE_COMPLETED")) {
                _pushQueue.add(entry);
            }
            // QUEUE_REMOVE doesn't need a push — server handles queue cleanup
            // when we push EPISODE_COMPLETED for the same episode
        }

        _pushIndex = 0;
        _pushNextChange();
    }

    private function _pushNextChange() as Void {
        if (_pushIndex >= _pushQueue.size()) {
            // All changes pushed — remove from changelog
            CacheManager.removeChangelogEntries(_pushedIds);
            _state = SYNC_PULLING_IN_PROGRESS;
            _stepPullInProgress();
            return;
        }

        var entry = _pushQueue[_pushIndex] as Dictionary;
        var data = entry.get("data") as Dictionary;

        Communications.makeWebRequest(
            API_BASE + "/sync/update_episode",
            {
                "uuid" => entry.get("episodeUuid") as String,
                "podcast" => entry.get("podcastUuid") as String,
                "position" => data.get("position") as Number,
                "status" => data.get("status") as Number,
                "duration" => data.get("duration") as Number
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onPushResponse)
        );
    }

    //! @hide
    function onPushResponse(responseCode as Number,
                             data as Dictionary or String or Null) as Void {
        if (responseCode == 200) {
            var entry = _pushQueue[_pushIndex] as Dictionary;
            _pushedIds.add(entry.get("id") as Number);
            _pushIndex++;
            _pushNextChange();
        } else if (responseCode == 401) {
            // Token expired mid-sync — refresh and retry
            _state = SYNC_AUTH;
            _stepAuth();
        } else if (_retryCount < MAX_RETRIES) {
            // Retryable error — wait and retry from current position
            _retryCount++;
            _state = SYNC_RETRY_WAIT;
            var retryTimer = new Timer.Timer();
            retryTimer.start(method(:onRetryTimer), RETRY_DELAY, false);
        } else {
            // Max retries exhausted — push what we have, keep the rest
            CacheManager.removeChangelogEntries(_pushedIds);
            _finish(false, "Push failed after " + MAX_RETRIES + " retries");
        }
    }

    //! @hide
    function onRetryTimer() as Void {
        _state = SYNC_PUSHING;
        _pushNextChange();
    }

    // ================================================================
    // Step 3: Pull Server State
    // ================================================================

    private function _stepPullInProgress() as Void {
        // Fetch all in-progress episodes from server (bulk — 1 request)
        Communications.makeWebRequest(
            API_BASE + "/user/in_progress",
            {},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onPullInProgressResponse)
        );
    }

    //! @hide
    function onPullInProgressResponse(responseCode as Number,
                                       data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var episodes = dict.get("episodes");
            if (episodes != null && episodes instanceof Array) {
                _serverInProgress = episodes as Array<Dictionary>;
            }
        }
        // Proceed regardless — missing in-progress data is not fatal
        _state = SYNC_PULLING_QUEUE;
        _stepPullQueue();
    }

    private function _stepPullQueue() as Void {
        Communications.makeWebRequest(
            API_BASE + "/up_next/list",
            {},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onPullQueueResponse)
        );
    }

    //! @hide
    function onPullQueueResponse(responseCode as Number,
                                  data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            _serverQueue = data as Dictionary;
        }

        // Now fetch individual episode details for any episodes in our
        // local positions map that weren't covered by in_progress.
        _state = SYNC_PULLING_EPISODES;
        _buildEpisodeFetchQueue();
        _fetchNextServerEpisode();
    }

    private function _buildEpisodeFetchQueue() as Void {
        // Episodes we need server state for: any dirty positions
        // that aren't in the in_progress response
        var positions = CacheManager.loadPositions();
        var inProgressUuids = {} as Dictionary;
        for (var i = 0; i < _serverInProgress.size(); i++) {
            var ep = _serverInProgress[i] as Dictionary;
            var uuid = ep.get("uuid");
            if (uuid != null) {
                inProgressUuids.put(uuid as String, ep);
                _serverEpisodeResults.put(uuid as String, ep);
            }
        }

        _serverEpisodeFetchQueue = [] as Array<String>;
        var keys = positions.keys();
        for (var i = 0; i < keys.size(); i++) {
            var uuid = keys[i] as String;
            var posEntry = positions.get(uuid) as Dictionary;
            var dirty = posEntry.get("dirty");
            if (dirty != null && dirty instanceof Boolean && (dirty as Boolean)) {
                if (!inProgressUuids.hasKey(uuid)) {
                    _serverEpisodeFetchQueue.add(uuid);
                }
            }
        }

        _serverEpisodeFetchIndex = 0;
    }

    private function _fetchNextServerEpisode() as Void {
        if (_serverEpisodeFetchIndex >= _serverEpisodeFetchQueue.size()) {
            // All server episodes fetched — proceed to reconcile
            _state = SYNC_RECONCILING;
            _stepReconcile();
            return;
        }

        var uuid = _serverEpisodeFetchQueue[_serverEpisodeFetchIndex];
        Communications.makeWebRequest(
            API_BASE + "/user/episode",
            { "uuid" => uuid },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onServerEpisodeResponse)
        );
    }

    //! @hide
    function onServerEpisodeResponse(responseCode as Number,
                                      data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var uuid = dict.get("uuid");
            if (uuid != null) {
                _serverEpisodeResults.put(uuid as String, dict);
            }
        }
        _serverEpisodeFetchIndex++;
        _fetchNextServerEpisode();
    }

    // ================================================================
    // Step 4: Reconcile
    // ================================================================

    private function _stepReconcile() as Void {
        var positions = CacheManager.loadPositions();
        var keys = positions.keys();
        var reconciledUuids = [] as Array<String>;

        for (var i = 0; i < keys.size(); i++) {
            var uuid = keys[i] as String;
            var local = positions.get(uuid) as Dictionary;
            var dirty = local.get("dirty");
            if (dirty == null || !(dirty instanceof Boolean) || !(dirty as Boolean)) {
                continue; // already clean
            }

            var localPos = local.get("position") as Number;
            var localStatus = local.get("status") as Number;

            // Get server state
            var serverEp = _serverEpisodeResults.get(uuid);
            if (serverEp != null && serverEp instanceof Dictionary) {
                var sEp = serverEp as Dictionary;
                var serverPos = sEp.get("playedUpTo") != null
                    ? sEp.get("playedUpTo") as Number : 0;
                var serverStatus = sEp.get("playingStatus") != null
                    ? sEp.get("playingStatus") as Number : 0;

                // Resolve: max(status), max(position)
                var resolvedStatus = _resolveStatus(localStatus, serverStatus);
                var resolvedPos = localPos > serverPos ? localPos : serverPos;

                if (resolvedStatus == DataKeys.STATUS_COMPLETED) {
                    var dur = local.get("duration") as Number;
                    resolvedPos = resolvedPos > dur ? resolvedPos : dur;
                }

                // Update local position with resolved values
                local.put("position", resolvedPos as Application.Storage.ValueType);
                local.put("status", resolvedStatus as Application.Storage.ValueType);
            }

            reconciledUuids.add(uuid);
        }

        // Mark reconciled positions as clean
        CacheManager.markPositionsClean(reconciledUuids);

        // Save updated positions back
        Application.Storage.setValue(CacheManager.KEY_POSITIONS,
                                    positions as Application.Storage.ValueType);

        // Refresh cached queue with server queue
        if (_serverQueue.size() > 0) {
            CacheManager.saveQueue(_normalizeServerQueue(_serverQueue));
        }

        _state = SYNC_CLEANUP;
        _stepCleanup();
    }

    //! Status hierarchy: COMPLETED > IN_PROGRESS > NOT_PLAYED
    private function _resolveStatus(localStatus as Number,
                                     serverStatus as Number) as Number {
        if (localStatus == DataKeys.STATUS_COMPLETED ||
            serverStatus == DataKeys.STATUS_COMPLETED) {
            return DataKeys.STATUS_COMPLETED;
        }
        if (localStatus == DataKeys.STATUS_IN_PROGRESS ||
            serverStatus == DataKeys.STATUS_IN_PROGRESS) {
            return DataKeys.STATUS_IN_PROGRESS;
        }
        return DataKeys.STATUS_NOT_PLAYED;
    }

    //! Convert server queue response to cached Array<Dictionary> format.
    private function _normalizeServerQueue(raw as Dictionary) as Array<Dictionary> {
        var order = raw.get("order");
        var episodesMap = raw.get("episodes");
        var result = [] as Array<Dictionary>;

        if (order != null && order instanceof Array &&
            episodesMap != null && episodesMap instanceof Dictionary) {
            var orderArr = order as Array;
            var epsMap = episodesMap as Dictionary;

            for (var i = 0; i < orderArr.size() && i < 20; i++) {
                var uuid = orderArr[i] as String;
                var epRaw = epsMap.get(uuid);
                if (epRaw != null && epRaw instanceof Dictionary) {
                    var ep = epRaw as Dictionary;
                    result.add({
                        DataKeys.E_UUID => uuid,
                        DataKeys.E_TITLE => ep.get("title") != null
                            ? ep.get("title") as String : "Unknown",
                        DataKeys.E_DURATION => ep.get("duration") != null
                            ? ep.get("duration") as Number : 0,
                        DataKeys.E_PLAYED_UP_TO => ep.get("playedUpTo") != null
                            ? ep.get("playedUpTo") as Number : 0,
                        DataKeys.E_PLAYING_STATUS => ep.get("playingStatus") != null
                            ? ep.get("playingStatus") as Number : 0,
                        DataKeys.E_PODCAST_UUID => ep.get("podcast") != null
                            ? ep.get("podcast") as String : "",
                        DataKeys.E_URL => ep.get("url") != null
                            ? ep.get("url") as String : "",
                        DataKeys.E_FILE_TYPE => ep.get("fileType") != null
                            ? ep.get("fileType") as String : ""
                    } as Dictionary);
                }
            }
        }
        return result;
    }

    // ================================================================
    // Step 5: Cleanup
    // ================================================================

    private function _stepCleanup() as Void {
        // Request UI refresh
        WatchUi.requestUpdate();
        _finish(true, "Sync complete");
    }

    private function _finish(success as Boolean, message as String) as Void {
        _state = success ? SYNC_IDLE : SYNC_ERROR;
        System.println("YoCasts Sync: " + message);

        if (_onComplete != null) {
            // We can't call method references with args easily in Monkey C.
            // Instead, callers check isSyncing() / getState().
        }
        _onComplete = null;
    }
}
```

**Exit criteria:** Sync engine pushes 5 changelog entries, pulls in-progress + queue, reconciles "furthest position wins" correctly, cleans up changelog. Retry logic works — 3 retries with 30s backoff. Auth refresh mid-sync works.

---

### Task B2: Wire SyncEngine to ConnectivityManager

**[FILE: `YoCastsGarmin/source/YoCastsApp.mc`]**
**[DEPENDS: B1, A4]**

The app needs to own the SyncEngine instance and trigger syncs on connectivity transitions.

```monkeyc
// Add to YoCastsApp class:
private var _syncEngine as SyncEngine? = null;

function onStart(state) {
    _service = createService();
    _syncEngine = new SyncEngine();

    // Start connectivity monitoring
    ConnectivityManager.start();
    ConnectivityManager.addListener(self);

    // Kick off async data fetch
    var svc = _service as IPodcastService;
    svc.fetchAll();

    // If already connected at launch, trigger sync
    if (ConnectivityManager.isConnected() && CacheManager.hasUnsyncedChanges()) {
        _syncEngine.triggerSync(null);
    }
}

function onStop(state) {
    ConnectivityManager.stop();
    PositionTracker.stopTracking();
}

//! ConnectivityManager listener callback
function onConnectivityChanged(oldState as Number, newState as Number) as Void {
    if (oldState == ConnectivityManager.STATE_OFFLINE &&
        newState != ConnectivityManager.STATE_OFFLINE) {
        // Just came online — trigger sync
        if (CacheManager.hasUnsyncedChanges()) {
            (_syncEngine as SyncEngine).triggerSync(null);
        }
    }
}
```

**Exit criteria:** App launches, detects connectivity, syncs if changelog has entries. Going offline → online triggers sync automatically.

---

### Task B3: Sync Status UI

**[FILE: `YoCastsGarmin/source/views/HomeMenuView.mc`]**
**[DEPENDS: B1]**

Show a subtle sync indicator when syncing. This is a small addition to the existing HomeMenuView.

**Options (pick one based on screen real estate):**
1. Small text "Syncing..." below the menu title
2. A rotating icon in the status area
3. A status line at bottom of screen

The simplest approach: add a text element that shows when `_syncEngine.isSyncing()` is true.

**Exit criteria:** User sees "Syncing..." during sync, it disappears when done. "Sync failed" shows briefly on error.

---

### Phase B Summary

After Phase B:
- Changelog entries are pushed to PocketCasts server via `/sync/update_episode`
- Server state is pulled via `/user/in_progress` and `/user/episode`
- Conflicts are resolved: `max(status)`, `max(position)` — deterministic, no prompts
- Sync triggers automatically on connectivity transitions
- Retry logic handles transient failures
- UI shows sync status

---

## 4. Phase C: Audio Download Infrastructure

**Goal:** Download podcast audio files to the watch. Store them via the Garmin Media module. Track download state. Auto-download queued episodes on Wi-Fi.

**Estimated effort:** 5–7 days (most complex phase)

### Task C1: Manifest Changes

**[FILE: `YoCastsGarmin/manifest.xml`]**
**[DEPENDS: none]**

The current manifest only has `Communications` permission. Audio download and playback require the `Background` and `Media` permissions, and the app type needs to support audio content.

```xml
<?xml version="1.0"?>
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="4">
    <iq:application
        id="a3421feed75247efa2a683e6e5152865"
        type="audio-content-provider"
        name="@Strings.AppName"
        entry="YoCastsApp"
        launcherIcon="@Drawables.LauncherIcon"
        minSdkVersion="4.2.0">

        <iq:permissions>
            <iq:uses-permission id="Communications"/>
            <iq:uses-permission id="Background"/>
        </iq:permissions>

        <iq:products>
            <iq:product id="venu441mm"/>
        </iq:products>

        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>

        <iq:barrels/>
    </iq:application>
</iq:manifest>
```

> **Critical change:** `type="watch-app"` → `type="audio-content-provider"`. This is what makes the app show up in Garmin's music source selection and enables the Media module APIs. The app still functions as a regular app but now also participates in the audio content provider system.

**Exit criteria:** App compiles with new manifest. Shows up in simulator's music sources. No runtime errors.

---

### Task C2: Download Manifest in CacheManager

**[FILE: `YoCastsGarmin/source/services/CacheManager.mc`]**
**[DEPENDS: A1]**

Track which episodes are downloaded, in-progress, or failed. This is separate from the Media module's internal storage — it's our metadata about download state.

```monkeyc
// ================================================================
// Download Manifest
// ================================================================

// Download states
const DL_STATE_QUEUED = 0;
const DL_STATE_DOWNLOADING = 1;
const DL_STATE_COMPLETE = 2;
const DL_STATE_FAILED = 3;

//! The download manifest tracks download state for each episode:
//! { episodeUuid => { "state", "url", "podcastUuid", "fileType",
//!                    "queuedAt", "completedAt", "bytesTotal",
//!                    "errorCount", "refId" } }
//! refId is the Media.ContentRef.id assigned by Garmin when stored.

function saveDownloadManifest(manifest as Dictionary) as Void {
    Application.Storage.setValue(KEY_DL_MANIFEST,
                                manifest as Application.Storage.ValueType);
}

function loadDownloadManifest() as Dictionary {
    var val = Application.Storage.getValue(KEY_DL_MANIFEST);
    if (val != null && val instanceof Dictionary) {
        return val as Dictionary;
    }
    return {} as Dictionary;
}

//! Mark an episode as queued for download.
function queueDownload(episodeUuid as String, podcastUuid as String,
                       url as String, fileType as String) as Void {
    var manifest = loadDownloadManifest();
    manifest.put(episodeUuid, {
        "state" => DL_STATE_QUEUED as Application.Storage.ValueType,
        "url" => url as Application.Storage.ValueType,
        "podcastUuid" => podcastUuid as Application.Storage.ValueType,
        "fileType" => fileType as Application.Storage.ValueType,
        "queuedAt" => Time.now().value() as Application.Storage.ValueType,
        "errorCount" => 0 as Application.Storage.ValueType
    } as Dictionary);
    saveDownloadManifest(manifest);
}

//! Update download state for an episode.
function updateDownloadState(episodeUuid as String, state as Number,
                             refId as String?) as Void {
    var manifest = loadDownloadManifest();
    var entry = manifest.get(episodeUuid);
    if (entry != null && entry instanceof Dictionary) {
        var dict = entry as Dictionary;
        dict.put("state", state as Application.Storage.ValueType);
        if (state == DL_STATE_COMPLETE) {
            dict.put("completedAt",
                     Time.now().value() as Application.Storage.ValueType);
        }
        if (refId != null) {
            dict.put("refId", refId as Application.Storage.ValueType);
        }
        if (state == DL_STATE_FAILED) {
            var count = dict.get("errorCount");
            var ec = (count != null && count instanceof Number)
                     ? (count as Number) + 1 : 1;
            dict.put("errorCount", ec as Application.Storage.ValueType);
        }
        saveDownloadManifest(manifest);
    }
}

//! Check if an episode is downloaded.
function isEpisodeDownloaded(episodeUuid as String) as Boolean {
    var manifest = loadDownloadManifest();
    var entry = manifest.get(episodeUuid);
    if (entry != null && entry instanceof Dictionary) {
        var dict = entry as Dictionary;
        return dict.get("state") as Number == DL_STATE_COMPLETE;
    }
    return false;
}

//! Remove a downloaded episode from the manifest (after cleanup).
function removeFromDownloadManifest(episodeUuid as String) as Void {
    var manifest = loadDownloadManifest();
    manifest.remove(episodeUuid);
    saveDownloadManifest(manifest);
}

//! Get all episodes pending download.
function getPendingDownloads() as Array<Dictionary> {
    var manifest = loadDownloadManifest();
    var pending = [] as Array<Dictionary>;
    var keys = manifest.keys();
    for (var i = 0; i < keys.size(); i++) {
        var uuid = keys[i] as String;
        var entry = manifest.get(uuid) as Dictionary;
        var state = entry.get("state") as Number;
        if (state == DL_STATE_QUEUED || state == DL_STATE_FAILED) {
            var errCount = entry.get("errorCount");
            var ec = (errCount != null && errCount instanceof Number)
                     ? errCount as Number : 0;
            if (ec < 3) { // max 3 retry attempts
                var d = {} as Dictionary;
                d.put("uuid", uuid);
                d.put("url", entry.get("url") as String);
                d.put("podcastUuid", entry.get("podcastUuid") as String);
                d.put("fileType", entry.get("fileType") as String);
                pending.add(d);
            }
        }
    }
    return pending;
}
```

**Exit criteria:** Queue 5 episodes for download. Verify state transitions (queued → downloading → complete/failed). `isEpisodeDownloaded()` returns correct values. Failed downloads cap at 3 retries.

---

### Task C3: DownloadManager Module

**[FILE: `YoCastsGarmin/source/services/DownloadManager.mc`]** (NEW)
**[DEPENDS: C2, A4]**

Manages the download queue. Downloads episodes one at a time to stay within memory limits. Enforces battery guards for app-initiated downloads.

```monkeyc
import Toybox.Lang;
import Toybox.Communications;
import Toybox.System;
import Toybox.Media;
import Toybox.Time;

//! Manages downloading podcast episodes to the watch.
//! Downloads one episode at a time. Enforces battery guards for
//! non-charger downloads. Uses Communications.makeWebRequest()
//! which works over both Wi-Fi and BT (Wi-Fi preferred for speed).
class DownloadManager {

    // ---- State ----
    private var _isDownloading as Boolean = false;
    private var _currentUuid as String = "";
    private var _downloadQueue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _downloadedThisSession as Number = 0;
    private var _accessToken as String = "";

    // ---- Configuration ----
    private const MAX_EPISODES_NON_CHARGER = 3;
    private const BATTERY_MIN_START = 30;     // don't start downloads below 30%
    private const BATTERY_MIN_CONTINUE = 20;  // pause downloads if drops below 20%
    private const MAX_DOWNLOAD_CAP = 10;      // max episodes to keep downloaded

    //! Set auth token for download requests.
    function setAccessToken(token as String) as Void {
        _accessToken = token;
    }

    //! Check if downloads are in progress.
    function isDownloading() as Boolean {
        return _isDownloading;
    }

    //! Trigger download of pending episodes.
    //! Checks battery, connectivity, and builds download queue.
    function triggerDownloads() as Void {
        if (_isDownloading) { return; }

        // Check connectivity — need Wi-Fi for audio downloads
        if (!ConnectivityManager.isWiFi()) {
            System.println("YoCasts DL: skipping — not on Wi-Fi");
            return;
        }

        // Battery guard (only for non-charger downloads)
        if (!_isCharging()) {
            var stats = System.getSystemStats();
            if (stats.battery < BATTERY_MIN_START) {
                System.println("YoCasts DL: skipping — battery too low ("
                    + stats.battery.toNumber() + "%)");
                return;
            }
        }

        // Build download queue from pending downloads
        _downloadQueue = CacheManager.getPendingDownloads();

        // Filter to supported formats
        var filtered = [] as Array<Dictionary>;
        for (var i = 0; i < _downloadQueue.size(); i++) {
            var ep = _downloadQueue[i] as Dictionary;
            var ft = ep.get("fileType") as String;
            if (ft.equals("audio/mp3") || ft.equals("audio/mpeg") ||
                ft.equals("audio/aac") || ft.equals("audio/mp4") ||
                ft.equals("audio/x-m4a")) {
                filtered.add(ep);
            }
        }
        _downloadQueue = filtered;

        // Apply non-charger cap
        if (!_isCharging() && _downloadQueue.size() > MAX_EPISODES_NON_CHARGER) {
            _downloadQueue = _downloadQueue.slice(0, MAX_EPISODES_NON_CHARGER)
                             as Array<Dictionary>;
        }

        // Apply total download cap
        var manifest = CacheManager.loadDownloadManifest();
        var downloadedCount = 0;
        var keys = manifest.keys();
        for (var i = 0; i < keys.size(); i++) {
            var entry = manifest.get(keys[i]) as Dictionary;
            if ((entry.get("state") as Number) == CacheManager.DL_STATE_COMPLETE) {
                downloadedCount++;
            }
        }
        var slotsAvailable = MAX_DOWNLOAD_CAP - downloadedCount;
        if (slotsAvailable <= 0) {
            System.println("YoCasts DL: at cap (" + MAX_DOWNLOAD_CAP + ")");
            return;
        }
        if (_downloadQueue.size() > slotsAvailable) {
            _downloadQueue = _downloadQueue.slice(0, slotsAvailable)
                             as Array<Dictionary>;
        }

        _downloadedThisSession = 0;
        _downloadNext();
    }

    //! Cancel all in-progress downloads.
    function cancelDownloads() as Void {
        _isDownloading = false;
        _downloadQueue = [] as Array<Dictionary>;
        if (!_currentUuid.equals("")) {
            CacheManager.updateDownloadState(
                _currentUuid, CacheManager.DL_STATE_QUEUED, null);
            _currentUuid = "";
        }
    }

    //! Auto-queue episodes from Up Next that aren't downloaded yet.
    //! Call after sync pulls fresh queue.
    function autoQueueFromUpNext() as Void {
        var queue = CacheManager.loadQueue();
        if (queue == null) { return; }
        var queueArr = queue;
        for (var i = 0; i < queueArr.size(); i++) {
            var ep = queueArr[i] as Dictionary;
            var uuid = ep.get(DataKeys.E_UUID) as String;
            var url = ep.get(DataKeys.E_URL);
            var fileType = ep.get(DataKeys.E_FILE_TYPE);
            var podUuid = ep.get(DataKeys.E_PODCAST_UUID);

            if (url == null || fileType == null || podUuid == null) { continue; }

            if (!CacheManager.isEpisodeDownloaded(uuid)) {
                CacheManager.queueDownload(
                    uuid, podUuid as String,
                    url as String, fileType as String
                );
            }
        }
    }

    // ================================================================
    // Internal Download Pipeline
    // ================================================================

    private function _downloadNext() as Void {
        if (_downloadQueue.size() == 0) {
            _isDownloading = false;
            System.println("YoCasts DL: complete (" +
                _downloadedThisSession + " episodes)");
            return;
        }

        // Battery check before each download (non-charger only)
        if (!_isCharging()) {
            var stats = System.getSystemStats();
            if (stats.battery < BATTERY_MIN_CONTINUE) {
                System.println("YoCasts DL: pausing — battery dropped to "
                    + stats.battery.toNumber() + "%");
                _isDownloading = false;
                return;
            }
        }

        // Connectivity check
        if (!ConnectivityManager.isWiFi()) {
            System.println("YoCasts DL: pausing — lost Wi-Fi");
            _isDownloading = false;
            return;
        }

        var ep = _downloadQueue[0] as Dictionary;
        _currentUuid = ep.get("uuid") as String;
        var url = ep.get("url") as String;
        _downloadQueue = _downloadQueue.slice(1, null) as Array<Dictionary>;

        _isDownloading = true;
        CacheManager.updateDownloadState(
            _currentUuid, CacheManager.DL_STATE_DOWNLOADING, null);

        // Download the audio file
        // NOTE: makeWebRequest() has a ~100KB response limit for JSON,
        // but for binary content downloaded via the Media module,
        // we use Media.ContentRef and the system handles the download.
        // See Task C4 for the actual Media.SyncDelegate implementation.
        _startMediaDownload(ep);
    }

    //! Start a media download using the Garmin Media module.
    //! This is the bridge to the SyncDelegate / ContentProvider system.
    private function _startMediaDownload(ep as Dictionary) as Void {
        // The actual download is done through the Media module's
        // sync mechanism. See YoCastsSyncDelegate (Task C4).
        // DownloadManager tells the SyncDelegate what to download,
        // the SyncDelegate uses the system-level download APIs.

        // For app-initiated downloads (Path B), we use
        // Communications.makeWebRequest() with the audio URL directly
        // and pipe the response to Media.ContentRef.
        //
        // Implementation in Task C4.
        System.println("YoCasts DL: starting download for " + _currentUuid);
    }

    //! Called by the download completion callback.
    function onDownloadComplete(uuid as String, refId as String,
                                 success as Boolean) as Void {
        if (success) {
            CacheManager.updateDownloadState(uuid, CacheManager.DL_STATE_COMPLETE,
                                              refId);
            _downloadedThisSession++;
            System.println("YoCasts DL: completed " + uuid);
        } else {
            CacheManager.updateDownloadState(uuid, CacheManager.DL_STATE_FAILED,
                                              null);
            System.println("YoCasts DL: failed " + uuid);
        }
        _currentUuid = "";
        _downloadNext();
    }

    // ================================================================
    // Auto-Cleanup
    // ================================================================

    //! Remove downloaded episodes that have been completed AND synced.
    //! Also removes episodes no longer in the Up Next queue.
    function cleanupDownloads() as Void {
        var manifest = CacheManager.loadDownloadManifest();
        var queue = CacheManager.loadQueue();
        var queueUuids = {} as Dictionary;
        if (queue != null) {
            for (var i = 0; i < queue.size(); i++) {
                var ep = queue[i] as Dictionary;
                queueUuids.put(ep.get(DataKeys.E_UUID) as String, true);
            }
        }

        var positions = CacheManager.loadPositions();
        var toRemove = [] as Array<String>;
        var keys = manifest.keys();

        for (var i = 0; i < keys.size(); i++) {
            var uuid = keys[i] as String;
            var entry = manifest.get(uuid) as Dictionary;
            var state = entry.get("state") as Number;

            if (state != CacheManager.DL_STATE_COMPLETE) { continue; }

            // Remove if: completed + synced + not in queue
            var pos = positions.get(uuid);
            if (pos != null && pos instanceof Dictionary) {
                var posDict = pos as Dictionary;
                var status = posDict.get("status") as Number;
                var dirty = posDict.get("dirty");
                var isDirty = (dirty != null && dirty instanceof Boolean &&
                               (dirty as Boolean));

                if (status == DataKeys.STATUS_COMPLETED &&
                    !isDirty && !queueUuids.hasKey(uuid)) {
                    toRemove.add(uuid);
                }
            }
        }

        for (var i = 0; i < toRemove.size(); i++) {
            var uuid = toRemove[i];
            // Delete the media content
            var entry = manifest.get(uuid) as Dictionary;
            var refId = entry.get("refId");
            if (refId != null) {
                // Delete from Media storage
                // Media.ContentRef.deleteContent(refId) — exact API TBD
                // during Phase D when we have the ContentProvider wired up
            }
            CacheManager.removeFromDownloadManifest(uuid);
        }

        System.println("YoCasts DL: cleaned up " + toRemove.size() + " episodes");
    }

    // ================================================================
    // Helpers
    // ================================================================

    private function _isCharging() as Boolean {
        var stats = System.getSystemStats();
        return stats.charging;
    }
}
```

**Exit criteria:** DownloadManager queues episodes from Up Next, filters unsupported formats, enforces battery guards (< 30% = don't start, < 20% = pause), caps at 10 downloaded, cleans up completed + synced episodes.

---

### Task C4: YoCastsSyncDelegate

**[FILE: `YoCastsGarmin/source/media/YoCastsSyncDelegate.mc`]** (NEW)
**[DEPENDS: C2, C3]**

The `SyncDelegate` is called by the Garmin system when the watch is on the charger and connected to Wi-Fi. This is the "Path A" download trigger — the same mechanism Spotify uses.

```monkeyc
import Toybox.Lang;
import Toybox.Media;
import Toybox.Communications;
import Toybox.System;

//! Called by Garmin system when charger + Wi-Fi are available.
//! Downloads queued podcast episodes to media storage.
//! Runs in background service context (64 KB memory limit).
class YoCastsSyncDelegate extends Media.SyncDelegate {

    private var _downloadQueue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _currentIndex as Number = 0;

    function initialize() {
        SyncDelegate.initialize();
    }

    //! System asks: do we need to sync? Return true if there are pending downloads.
    function isSyncNeeded() as Boolean {
        var pending = CacheManager.getPendingDownloads();
        return pending.size() > 0;
    }

    //! System triggers sync — begin downloading.
    function onStartSync() as Void {
        System.println("YoCasts Sync Delegate: starting system sync");

        // First, auto-queue any Up Next episodes that aren't downloaded
        var queue = CacheManager.loadQueue();
        if (queue != null) {
            for (var i = 0; i < queue.size(); i++) {
                var ep = queue[i] as Dictionary;
                var uuid = ep.get(DataKeys.E_UUID) as String;
                var url = ep.get(DataKeys.E_URL);
                var fileType = ep.get(DataKeys.E_FILE_TYPE);
                var podUuid = ep.get(DataKeys.E_PODCAST_UUID);

                if (url != null && fileType != null && podUuid != null &&
                    !CacheManager.isEpisodeDownloaded(uuid)) {
                    CacheManager.queueDownload(
                        uuid, podUuid as String,
                        url as String, fileType as String);
                }
            }
        }

        _downloadQueue = CacheManager.getPendingDownloads();
        _currentIndex = 0;
        _downloadNextSyncItem();
    }

    //! System asks us to stop syncing.
    function onStopSync() as Void {
        System.println("YoCasts Sync Delegate: stop requested");
        _downloadQueue = [] as Array<Dictionary>;
    }

    private function _downloadNextSyncItem() as Void {
        if (_currentIndex >= _downloadQueue.size()) {
            // All done
            Media.notifySyncComplete();
            return;
        }

        var ep = _downloadQueue[_currentIndex] as Dictionary;
        var uuid = ep.get("uuid") as String;
        var url = ep.get("url") as String;

        CacheManager.updateDownloadState(uuid,
            CacheManager.DL_STATE_DOWNLOADING, null);

        // Use Media module to download
        // The exact API depends on SDK version:
        //   - Media.ContentRef for creating content references
        //   - Communications.makeWebRequest for raw download
        //
        // Approach: makeWebRequest with responseType = HTTP_RESPONSE_CONTENT_TYPE_FIT
        // or use the Media download helpers.
        //
        // For audio files, the pattern is:
        //   1. Create a ContentRef for the episode
        //   2. Use makeWebRequest to download to that ref
        //   3. On completion, update manifest

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_URL
        };

        // Download the audio file
        Communications.makeWebRequest(url, null, options,
            method(:onSyncDownloadResponse));
    }

    //! @hide
    function onSyncDownloadResponse(responseCode as Number,
                                     data as Dictionary or String or Null) as Void {
        var ep = _downloadQueue[_currentIndex] as Dictionary;
        var uuid = ep.get("uuid") as String;

        if (responseCode == 200) {
            // Create media content ref and store the downloaded file
            var contentRef = new Media.ContentRef(uuid, Media.CONTENT_TYPE_AUDIO);
            CacheManager.updateDownloadState(uuid,
                CacheManager.DL_STATE_COMPLETE, uuid);
            System.println("YoCasts Sync: downloaded " + uuid);
        } else {
            CacheManager.updateDownloadState(uuid,
                CacheManager.DL_STATE_FAILED, null);
            System.println("YoCasts Sync: download failed " + uuid +
                " (" + responseCode + ")");
        }

        _currentIndex++;
        _downloadNextSyncItem();
    }
}
```

> **⚠️ Important implementation note:** The exact Media download API varies by SDK version and device. The pseudocode above shows the *pattern*. Kaylee will need to prototype against the Venu 4 simulator to find the exact `Media.ContentRef` / download flow. The Connect IQ SDK documentation for `Media.SyncDelegate` is the definitive reference. Key questions to resolve during prototyping:
> 1. How to pipe `makeWebRequest` response data to Media storage
> 2. Whether `Media.ContentRef` requires a file path or handles download internally
> 3. Memory impact of buffering audio data in the background service (64 KB limit!)

**64 KB background memory constraint:**
- The SyncDelegate runs in the background service context
- 64 KB total — must be very lean
- No in-memory buffering of audio data — stream directly to Media storage
- Minimal Dictionary allocations — reuse where possible
- Track at most 1 download at a time (sequential, not parallel)

**Exit criteria:** SyncDelegate reports `isSyncNeeded() == true` when episodes are queued. `onStartSync()` begins downloading. Downloads complete and update manifest. `onStopSync()` halts cleanly.

---

### Task C5: Wire Downloads to Sync Engine

**[FILE: `YoCastsGarmin/source/services/SyncEngine.mc`]**
**[DEPENDS: B1, C3]**

After the sync engine finishes reconciliation, trigger downloads if Wi-Fi is available. This is the DOWNLOAD? step in the state machine.

Add after `_stepReconcile()` completes:

```monkeyc
// In _stepReconcile(), after reconciliation:
private function _stepReconcile() as Void {
    // ... existing reconciliation code ...

    // After reconciliation, check if we should download
    _state = SYNC_DOWNLOAD_CHECK;
    _stepDownloadCheck();
}

// New state
// Add SYNC_DOWNLOAD_CHECK to the enum

private function _stepDownloadCheck() as Void {
    if (ConnectivityManager.isWiFi()) {
        // Auto-queue episodes from the freshly-synced queue
        var dlManager = _getDownloadManager();
        dlManager.autoQueueFromUpNext();
        dlManager.setAccessToken(_accessToken);
        dlManager.triggerDownloads();
    }
    _state = SYNC_CLEANUP;
    _stepCleanup();
}
```

**Exit criteria:** Sync completes, checks Wi-Fi, auto-queues and starts downloading. BT-only connections skip downloads.

---

### Phase C Summary

After Phase C:
- Episodes download via Wi-Fi (system-triggered on charger OR app-initiated)
- Download state tracked in manifest (queued → downloading → complete/failed)
- Battery guards enforced (30% minimum to start, 20% to continue, 3 ep cap off charger)
- Auto-download Up Next episodes on Wi-Fi
- Auto-cleanup completed + synced episodes
- 64 KB background memory respected

---

## 5. Phase D: Media Playback Integration

**Goal:** Play downloaded episodes through Garmin's built-in media player. Wire playback events to position tracking.

**Estimated effort:** 4–5 days

### Task D1: YoCastsContentProvider

**[FILE: `YoCastsGarmin/source/media/YoCastsContentProvider.mc`]** (NEW)
**[DEPENDS: C2, C4]**

The ContentProvider is the entry point for Garmin's media player. It tells the system what content is available, how to browse it, and how to play it.

```monkeyc
import Toybox.Lang;
import Toybox.Media;

//! Content provider for YoCasts podcast playback.
//! Exposes downloaded episodes to Garmin's media player.
class YoCastsContentProvider extends Media.ContentProvider {

    function initialize() {
        ContentProvider.initialize();
    }

    //! Return the content iterator for browsing downloaded episodes.
    function getContentIterator() as Media.ContentIterator {
        return new YoCastsContentIterator();
    }

    //! Return the playback delegate for handling play/pause/skip events.
    function getContentDelegate() as Media.ContentDelegate {
        return new YoCastsContentDelegate();
    }

    //! Return the sync delegate for system-triggered downloads.
    function getSyncDelegate() as Media.SyncDelegate {
        return new YoCastsSyncDelegate();
    }
}
```

### Task D2: YoCastsContentIterator

**[FILE: `YoCastsGarmin/source/media/YoCastsContentIterator.mc`]** (NEW)
**[DEPENDS: D1, C2]**

Provides the playlist to Garmin's media player. Built from downloaded episodes in Up Next order.

```monkeyc
import Toybox.Lang;
import Toybox.Media;

//! Iterates over downloaded episodes for playback.
//! Order follows the Up Next queue.
class YoCastsContentIterator extends Media.ContentIterator {

    private var _items as Array<Media.ContentRef> = [] as Array<Media.ContentRef>;
    private var _currentIndex as Number = 0;

    function initialize() {
        ContentIterator.initialize();
        _buildPlaylist();
    }

    //! Build playlist from downloaded episodes in queue order.
    private function _buildPlaylist() as Void {
        _items = [] as Array<Media.ContentRef>;

        var queue = CacheManager.loadQueue();
        if (queue == null) { return; }

        var manifest = CacheManager.loadDownloadManifest();

        for (var i = 0; i < queue.size(); i++) {
            var ep = queue[i] as Dictionary;
            var uuid = ep.get(DataKeys.E_UUID) as String;
            var dlEntry = manifest.get(uuid);

            if (dlEntry != null && dlEntry instanceof Dictionary) {
                var dl = dlEntry as Dictionary;
                if ((dl.get("state") as Number) == CacheManager.DL_STATE_COMPLETE) {
                    var refId = dl.get("refId");
                    if (refId != null) {
                        var ref = new Media.ContentRef(
                            refId as String,
                            Media.CONTENT_TYPE_AUDIO
                        );
                        _items.add(ref);
                    }
                }
            }
        }
    }

    //! Get the current content item.
    function get() as Media.ContentRef? {
        if (_currentIndex >= 0 && _currentIndex < _items.size()) {
            return _items[_currentIndex];
        }
        return null;
    }

    //! Move to next item. Returns the next ContentRef or null.
    function next() as Media.ContentRef? {
        _currentIndex++;
        return get();
    }

    //! Move to previous item.
    function previous() as Media.ContentRef? {
        _currentIndex--;
        if (_currentIndex < 0) { _currentIndex = 0; }
        return get();
    }

    //! Get content by specific ID.
    function getById(id as String) as Media.ContentRef? {
        for (var i = 0; i < _items.size(); i++) {
            if (_items[i].getId().equals(id)) {
                _currentIndex = i;
                return _items[i];
            }
        }
        return null;
    }

    //! Number of items in playlist.
    function size() as Number {
        return _items.size();
    }
}
```

### Task D3: YoCastsContentDelegate

**[FILE: `YoCastsGarmin/source/media/YoCastsContentDelegate.mc`]** (NEW)
**[DEPENDS: D2, A3]**

Handles playback events from Garmin's media player. The critical piece: wiring position updates to PositionTracker.

```monkeyc
import Toybox.Lang;
import Toybox.Media;
import Toybox.System;

//! Handles media playback events from Garmin's media player.
//! Wires position updates to PositionTracker for persistence.
class YoCastsContentDelegate extends Media.ContentDelegate {

    private var _currentEpisodeUuid as String = "";
    private var _currentPodcastUuid as String = "";
    private var _currentDuration as Number = 0;

    function initialize() {
        ContentDelegate.initialize();
    }

    //! Called when playback starts for a content item.
    function onSong(contentRefId as String,
                     metadata as Media.SongMetadata) as Void {
        _currentEpisodeUuid = contentRefId;

        // Look up podcast UUID and duration from download manifest
        var manifest = CacheManager.loadDownloadManifest();
        var entry = manifest.get(contentRefId);
        if (entry != null && entry instanceof Dictionary) {
            var dict = entry as Dictionary;
            _currentPodcastUuid = dict.get("podcastUuid") as String;
        }

        // Get duration from cached queue or episode data
        var queue = CacheManager.loadQueue();
        if (queue != null) {
            for (var i = 0; i < queue.size(); i++) {
                var ep = queue[i] as Dictionary;
                if (contentRefId.equals(ep.get(DataKeys.E_UUID) as String)) {
                    _currentDuration = ep.get(DataKeys.E_DURATION) as Number;
                    break;
                }
            }
        }

        // Start position tracking
        var pos = CacheManager.getPosition(contentRefId);
        var initialPos = 0;
        if (pos != null) {
            initialPos = pos.get("position") as Number;
        }

        PositionTracker.startTracking(
            _currentEpisodeUuid, _currentPodcastUuid,
            _currentDuration, initialPos
        );

        System.println("YoCasts: playing " + contentRefId);
    }

    //! Called periodically with current playback position.
    function onPosition(position as Number) as Void {
        PositionTracker.savePosition(position);
    }

    //! Called when playback reaches the end of an episode.
    function onComplete() as Void {
        PositionTracker.markCompleted();

        // Log queue removal
        CacheManager.addChangelogEntry(
            "QUEUE_REMOVE",
            _currentEpisodeUuid,
            _currentPodcastUuid,
            {} as Dictionary
        );

        System.println("YoCasts: completed " + _currentEpisodeUuid);
    }

    //! Called when playback is paused.
    function onPause() as Void {
        // Save current position immediately on pause
        // (don't wait for next timer tick)
        // Position already saved via last onPosition call
    }

    //! Called when playback stops.
    function onStop() as Void {
        PositionTracker.stopTracking();
    }
}
```

### Task D4: Update App Entry Point

**[FILE: `YoCastsGarmin/source/YoCastsApp.mc`]**
**[DEPENDS: D1]**

Register the ContentProvider with the app.

```monkeyc
// Add to YoCastsApp:

//! Return the content provider for the media module.
//! Called by Garmin system when this app is selected as audio source.
function getContentProvider() as Media.ContentProvider? {
    return new YoCastsContentProvider();
}
```

### Task D5: Update NowPlayingView for Downloaded Content

**[FILE: `YoCastsGarmin/source/views/NowPlayingView.mc`]**
**[DEPENDS: D3, C2]**

The NowPlayingView needs to:
1. Check if the current episode is downloaded
2. If downloaded + offline: play from Media module (not stream)
3. If online: still play from Media module if downloaded (better UX)
4. Show download status indicator

**Key behavior changes:**
- Offline + downloaded → enable play button
- Offline + not downloaded → show "Not available offline"
- Online + downloaded → play locally (faster, no buffering)
- Online + not downloaded → cannot play (streaming not supported in v1)

**Exit criteria:** User can play downloaded episodes through Garmin media player. Position saves every 15s. Episode completion logs to changelog. Offline playback works.

---

### Task D6: Crash Recovery — Position Persistence

**[DEPENDS: A3, D3]**

On app start, check if there's a saved position for the last-playing episode. If so, resume from that position.

```monkeyc
// In YoCastsApp.onStart():
function _restorePlaybackState() as Void {
    // Check all positions for any that are IN_PROGRESS
    var positions = CacheManager.loadPositions();
    var keys = positions.keys();
    for (var i = 0; i < keys.size(); i++) {
        var uuid = keys[i] as String;
        var pos = positions.get(uuid) as Dictionary;
        var status = pos.get("status") as Number;
        if (status == DataKeys.STATUS_IN_PROGRESS) {
            // This episode was playing when app last closed
            // Set it as "now playing" so the UI can show it
            var position = pos.get("position") as Number;
            System.println("YoCasts: restoring position for " + uuid +
                " at " + position + "s");
            // The media player will seek to this position when the user
            // taps play. We just need to make sure the UI shows the
            // right episode.
            break;
        }
    }
}
```

**Exit criteria:** Kill app during playback. Relaunch. Episode shows at correct position (within 15s accuracy). No data loss.

---

### Phase D Summary

After Phase D:
- Downloaded episodes play through Garmin's native media player
- Position tracked every 15s during playback (60s on low battery)
- Episode completion triggers changelog + queue removal
- Crash recovery restores last position within 15s
- Offline playback works for downloaded episodes
- Playback events wire through to existing position tracking

---

## 6. Phase E: Full Reconciliation & Polish

**Goal:** Handle all edge cases, queue reconciliation, storage pressure, and stress testing.

**Estimated effort:** 3–4 days

### Task E1: Queue Reconciliation

**[FILE: `YoCastsGarmin/source/services/SyncEngine.mc`]**
**[DEPENDS: B1]**

Implement the full queue merge algorithm from the design doc. Currently, the sync engine just overwrites the local queue with the server queue. This task adds proper merge logic.

```monkeyc
//! Reconcile local and server queues.
//! Server order is base. Local completions are removed.
//! Server additions are merged in.
private function _reconcileQueue(serverQueue as Dictionary) as Array<Dictionary> {
    var localQueue = CacheManager.loadQueue();
    var changelog = CacheManager.loadChangelog();

    // Build set of locally completed episodes
    var localCompleted = {} as Dictionary;
    for (var i = 0; i < changelog.size(); i++) {
        var entry = changelog[i] as Dictionary;
        var type = entry.get("type") as String;
        if (type.equals("EPISODE_COMPLETED") || type.equals("QUEUE_REMOVE")) {
            localCompleted.put(entry.get("episodeUuid") as String, true);
        }
    }

    // Build resolved queue from server order, minus local completions
    var resolved = _normalizeServerQueue(serverQueue);
    var filtered = [] as Array<Dictionary>;
    for (var i = 0; i < resolved.size(); i++) {
        var ep = resolved[i] as Dictionary;
        var uuid = ep.get(DataKeys.E_UUID) as String;
        if (!localCompleted.hasKey(uuid)) {
            filtered.add(ep);
        }
    }

    return filtered;
}
```

### Task E2: Storage Pressure Monitoring

**[DEPENDS: C2, C3]**

Monitor storage usage and trigger cleanup when pressure is high. Since Garmin doesn't expose exact storage metrics, we estimate based on our own data.

```monkeyc
// Add to CacheManager:

//! Estimate current Application.Storage usage in bytes.
//! This is a rough estimate — we know the shape of our data.
function estimateStorageUsage() as Number {
    var total = 0;
    // Changelog: ~50 bytes per entry
    total += loadChangelog().size() * 50;
    // Positions: ~80 bytes per entry
    total += loadPositions().size() * 80;
    // Download manifest: ~120 bytes per entry
    total += loadDownloadManifest().size() * 120;
    // Queue: ~200 bytes per entry
    var queue = loadQueue();
    if (queue != null) { total += queue.size() * 200; }
    // Podcasts: ~200 bytes per entry
    var pods = loadPodcasts();
    if (pods != null) { total += pods.size() * 200; }
    // Auth: ~1KB
    if (loadAuth() != null) { total += 1024; }
    // Episode caches: not tracked here — tracked separately
    return total;
}

//! Check if storage pressure is high (> 80% of estimated budget).
function isStoragePressureHigh() as Boolean {
    var usage = estimateStorageUsage();
    var budget = 200 * 1024; // 200 KB conservative estimate
    return usage > (budget * 8 / 10);
}
```

### Task E3: Long Offline Period Handling

**[DEPENDS: B1, E1]**

When the watch has been offline for days (e.g., camping trip), the changelog can grow large and the queue can diverge significantly. The sync engine must handle this gracefully.

**Changes to SyncEngine:**
1. Before pushing, check changelog size. If > 50 entries, show "Large sync — this may take a moment" in UI.
2. Process pushes in batches of 10 with progress updates to the UI.
3. After pull, the queue reconciliation may remove many episodes — show summary ("Synced: 12 episodes completed, 3 new queued").

### Task E4: IPodcastService Interface Updates

**[FILE: `YoCastsGarmin/source/services/IPodcastService.mc`]**
**[DEPENDS: B1, C2]**

Add new methods to the interface for download and sync awareness.

```monkeyc
// Add to IPodcastService:

//! Whether an episode has been downloaded for offline playback.
function isEpisodeDownloaded(episodeUuid as String) as Boolean {
    return false;
}

//! Get download state for an episode (queued, downloading, complete, failed).
function getDownloadState(episodeUuid as String) as Number {
    return -1; // not tracked
}

//! Whether a sync is currently in progress.
function isSyncing() as Boolean {
    return false;
}

//! Get connectivity state.
function getConnectivityState() as Number {
    return ConnectivityManager.STATE_OFFLINE;
}
```

Then implement in `CachedPodcastService`:

```monkeyc
function isEpisodeDownloaded(episodeUuid as String) as Boolean {
    return CacheManager.isEpisodeDownloaded(episodeUuid);
}

function getDownloadState(episodeUuid as String) as Number {
    var manifest = CacheManager.loadDownloadManifest();
    var entry = manifest.get(episodeUuid);
    if (entry != null && entry instanceof Dictionary) {
        return (entry as Dictionary).get("state") as Number;
    }
    return -1;
}
```

### Task E5: Error Handling Hardening

**[DEPENDS: B1, C3, D3]**

Systematic error handling for every failure mode. See [Error Handling Matrix](#10-error-handling-matrix) for the full table.

Key areas:
1. **Download interrupted (Wi-Fi drops):** `ConnectivityManager` fires listener, `DownloadManager.cancelDownloads()` called. Episode stays in manifest as QUEUED. Retried on next Wi-Fi connection.
2. **Storage full during download:** Catch exception from Media storage write. Mark as FAILED. Trigger `cleanupDownloads()` to free space. Retry.
3. **Changelog corruption:** Wrap `loadChangelog()` in try/catch. If corrupted, clear and log. Data loss is accepted — it's better than a stuck sync.
4. **Concurrent modifications:** Handled by "max wins" policy. No locking needed.

### Task E6: Battery-Aware Behavior

**[DEPENDS: A3, C3]**

Implement graduated battery response:

```
Battery Level    │ Position Save    │ Downloads    │ Sync          │ Connectivity Poll
─────────────────┼──────────────────┼──────────────┼───────────────┼──────────────────
> 30%            │ Every 15s        │ Allowed      │ Full          │ Every 30s
20-30%           │ Every 30s        │ Not started  │ Full          │ Every 60s
10-20%           │ Every 60s        │ Paused       │ Push only     │ Every 120s
< 10%            │ On pause only    │ Cancelled    │ Deferred      │ Every 300s
```

---

## 7. Usage Scenarios — Walkthrough

### Scenario 1: At Home on Wi-Fi (No Phone Needed)

```
1. Watch connects to home Wi-Fi
2. ConnectivityManager detects STATE_WIFI_DIRECT
3. If app is open:
   a. CachedPodcastService.fetchAll() fetches fresh data over Wi-Fi
   b. SyncEngine.triggerSync() pushes any changelog, pulls server state
   c. After sync: DownloadManager.autoQueueFromUpNext()
   d. DownloadManager.triggerDownloads() starts downloading episodes
4. If app is not open (background):
   a. YoCastsSyncDelegate.isSyncNeeded() returns true
   b. System triggers onStartSync() when charging
   c. Episodes download in background
```

### Scenario 2: Out on a Run (Fully Offline)

```
1. Watch leaves Wi-Fi range
2. ConnectivityManager detects STATE_OFFLINE
3. DownloadManager.cancelDownloads() (if any were in progress)
4. User opens YoCasts:
   a. CachedPodcastService serves cached data
   b. Queue shows only downloaded episodes as playable
   c. Non-downloaded episodes grayed out
5. User plays an episode:
   a. YoCastsContentDelegate.onSong() starts PositionTracker
   b. Position saved every 15s to positions map + changelog
6. Episode completes:
   a. PositionTracker.markCompleted() logs to changelog
   b. QUEUE_REMOVE added to changelog
   c. Auto-advance to next downloaded episode
7. Low battery during run:
   a. PositionTracker detects battery < 20%
   b. Save interval drops to 60s
   c. At < 10%, saves only on pause
```

### Scenario 3: Phone Connected via Bluetooth (No Wi-Fi)

```
1. ConnectivityManager detects STATE_PHONE_BT
2. SyncEngine.triggerSync() pushes changelog, pulls server state
3. DownloadManager does NOT trigger (not on Wi-Fi)
4. CachedPodcastService.fetchAll() works via BT proxy
5. User sees fresh data but cannot download new episodes
6. Browse and queue management work normally
```

### Scenario 4: Returning Home After a Run

```
1. Watch reconnects to home Wi-Fi
2. ConnectivityManager detects OFFLINE → WIFI_DIRECT transition
3. SyncEngine.triggerSync() fires:
   a. AUTH: load saved token, refresh if needed
   b. PUSHING: push changelog entries (position updates, completions)
   c. PULLING: fetch /user/in_progress + /up_next/list + individual episodes
   d. RECONCILING: max(position), max(status) for each episode
   e. DOWNLOAD_CHECK: auto-queue new Up Next episodes
   f. CLEANUP: clear synced changelog, refresh caches
4. DownloadManager starts downloading newly queued episodes
5. UI refreshes with synced data
```

### Scenario 5: Phone + Wi-Fi Both Available

```
1. ConnectivityManager detects STATE_PHONE_BT
   (connectionAvailable=true, phoneConnected=true)
2. Full API access — best of both worlds
3. makeWebRequest uses best available transport (system decides)
4. Downloads trigger (Wi-Fi likely available alongside BT)
5. Same flow as Scenario 1 but with phone as fallback transport
```

### Scenario 6: Long Offline Period (Multi-Day Camping)

```
Day 1: Listen to 3 episodes, complete 2
  - Changelog: 2 EPISODE_COMPLETED + 2 QUEUE_REMOVE + ~180 POSITION_UPDATEs
  - After coalescing: 2 EPISODE_COMPLETED + 2 QUEUE_REMOVE + 3 POSITION_UPDATEs = 7 entries
  
Day 2: Listen to 2 more episodes
  - Changelog grows to: ~12 entries (coalescing keeps it bounded)
  
Day 3: Return to Wi-Fi
  1. SyncEngine pushes 12 entries sequentially
  2. Server has new episodes added by phone — queue diverged
  3. Queue reconciliation: remove 4 completed locally, merge 3 new from server
  4. Positions reconcile: max() for all touched episodes
  5. Download new episodes
  
Key: Changelog stays bounded due to per-episode coalescing.
     12 entries ≈ 600 bytes. Well within limits.
```

### Scenario 7: Battery Critically Low During Run

```
1. Battery hits 20%:
   - PositionTracker interval changes to 60s
   - Any downloads in progress: paused
   - ConnectivityManager poll interval: 120s
   
2. Battery hits 10%:
   - PositionTracker saves only on pause/stop events
   - Downloads: cancelled
   - Sync: deferred until charging
   - ConnectivityManager poll interval: 300s
   - Show low battery indicator in NowPlayingView
   
3. Battery hits 5% (system may kill app):
   - Last saved position is at most 60s stale
   - Changelog is persisted to Storage — survives app kill
   - On next launch (after charge): sync resumes normally
```

### Scenario 8: Watch Reboot / Crash During Playback

```
1. App is killed (crash, reboot, system OOM)
2. Last position was saved ≤15s ago (worst case 60s on low battery)
3. On next launch:
   a. CacheManager.loadPositions() finds IN_PROGRESS episode
   b. NowPlayingView shows "Resume: Episode Name at 23:45?"
   c. User taps play → ContentDelegate.onSong() seeks to saved position
   d. Changelog preserved — all mutations safe
```

### Scenario 9: Auth Token Expires While Offline

```
1. Token expires after 1 hour (typical PocketCasts token lifetime)
2. Watch is offline — no API calls possible anyway
3. On reconnect:
   a. SyncEngine.triggerSync() enters AUTH state
   b. Checks saved token → expired
   c. Tries refresh: POST /user/token with refreshToken
   d. If refresh works: new token saved, proceed with sync
   e. If refresh fails (400): full re-login using saved credentials
   f. If re-login fails: show "Auth error" to user, defer sync
   g. Changelog is preserved regardless — nothing lost
```

---

## 8. Power Efficiency Contract

### 8.1 Connectivity Polling

**Decision:** Timer-based polling, NOT event-based.

**Why:** Garmin Connect IQ does not provide connectivity change events. `System.getDeviceSettings()` must be polled. This is the same approach Garmin's own apps use.

**Polling frequency by state:**

| App State | Poll Interval | Rationale |
|---|---|---|
| App foreground, good battery | 30s | Fast detection matters when user is interacting |
| App foreground, low battery (< 20%) | 120s | Reduce overhead |
| Background service | 300s (5 min) | Temporal events run infrequently anyway |
| Critical battery (< 10%) | 300s | Absolute minimum |

**Cost analysis:** `System.getDeviceSettings()` is a lightweight system call. At 30s intervals, that's 2 calls/minute. Negligible CPU/battery impact.

### 8.2 Wi-Fi Radio Management

**We don't control the Wi-Fi radio.** Garmin manages it. Our responsibility:
1. Don't make unnecessary network requests — check connectivity before every request
2. Don't download when not on Wi-Fi — `ConnectivityManager.isWiFi()` guard
3. Batch downloads sequentially (one at a time) — avoids concurrent radio contention
4. Don't poll APIs while offline — complete no-op in offline state

### 8.3 Position Save Frequency Trade-offs

| Interval | Battery Impact | Data Loss on Crash | Recommendation |
|---|---|---|---|
| 5s | High — 720 writes/hr | 5s | Too aggressive |
| **15s** | **Moderate — 240 writes/hr** | **15s** | **Default — best balance** |
| 30s | Low — 120 writes/hr | 30s | Acceptable for low battery |
| 60s | Minimal — 60 writes/hr | 60s | Low battery mode |
| On-pause only | Near zero | Entire session | Critical battery mode |

**Each write:** `Application.Storage.setValue()` → flash write. Garmin flash is rated for 100K+ write cycles per cell. At 240 writes/hr during 2 hours of daily playback, that's 480 writes/day, or ~175K writes/year. Within spec.

### 8.4 Background Service Memory Budget (64 KB)

The `YoCastsSyncDelegate` runs in the background service with 64 KB total memory. Budget:

| Component | Estimated Size | Notes |
|---|---|---|
| SyncDelegate class | ~2 KB | Instance variables, vtable |
| Download queue (10 entries) | ~3 KB | Array of Dictionaries |
| Current download metadata | ~0.5 KB | One active download |
| CacheManager function stack | ~2 KB | Method calls + locals |
| Communications callback | ~1 KB | System callback overhead |
| **Garmin runtime overhead** | **~40 KB** | OS, GC, stack |
| **Available for app** | **~15 KB** | Tight but workable |
| **Buffer** | **~0.5 KB** | Safety margin |

**Rules for background code:**
- No large arrays or strings
- No in-memory audio buffering (stream directly to Media storage)
- Minimal Dictionary allocations
- No unnecessary imports
- Keep download queue references lean (UUID + URL only)

---

## 9. Storage Management Plan

### 9.1 Application.Storage Budget

```
Total estimated budget: 200 KB (conservative for Venu 4)
Per-value limit: 32 KB

Key                  │ Max Size  │ Priority  │ Evictable?
─────────────────────┼───────────┼───────────┼───────────
yc_auth              │ 1 KB      │ P0        │ Never
yc_changelog         │ 5 KB      │ P0        │ Never (cleared after sync)
yc_cl_seq            │ 0.1 KB    │ P0        │ Never
yc_positions         │ 4 KB      │ P0        │ Oldest clean entries
yc_queue             │ 5 KB      │ P0        │ Never
yc_podcasts          │ 6 KB      │ P1        │ As last resort
yc_dl_manifest       │ 2 KB      │ P0        │ Completed+synced entries
yc_sync_state        │ 0.1 KB    │ P1        │ Safe to reset
yc_episodes_<uuid>   │ 3 KB each │ P2        │ LRU (max 10 caches)
                     │ (30 KB)   │           │
─────────────────────┼───────────┼───────────┤
TOTAL                │ ~53 KB    │           │
```

**Headroom:** ~147 KB for future features, unexpected growth, and Garmin system keys.

### 9.2 Media Storage (Audio Files)

```
Venu 4 storage: ~8 GB shared with music, maps, apps
Podcast budget: ~500 MB (configurable, default)

Episode average: 30 MB (30 min @ 128 kbps MP3)
Max episodes: 10 (default cap, configurable)
Actual usage: ~300 MB typical
```

**Auto-cleanup triggers:**
1. Episode completed + synced + not in queue → delete
2. Episode not in queue for > 7 days → delete (future enhancement)
3. Storage pressure detected → delete oldest completed episodes
4. User manually deletes from UI (future enhancement)

### 9.3 Download Tracking State Machine

```
                ┌─────────────────┐
                │    NOT_TRACKED   │  (episode not in manifest)
                └────────┬────────┘
                         │ User queues or auto-queue from Up Next
                         ▼
                ┌─────────────────┐
           ┌───▶│    QUEUED        │◄──── retry (errorCount < 3)
           │    └────────┬────────┘
           │             │ Download starts (Wi-Fi available)
           │             ▼
           │    ┌─────────────────┐
           │    │   DOWNLOADING   │
           │    └────────┬────────┘
           │             │
           │     ┌───────┴───────┐
           │     │               │
           │     ▼               ▼
           │  ┌──────┐    ┌─────────┐
           │  │FAILED│────▶│ QUEUED  │  (if errorCount < 3)
           │  └──────┘    └─────────┘
           │     │
           │     │ errorCount >= 3
           │     ▼
           │  ┌───────────────────┐
           │  │  PERMANENTLY_FAILED│  (user must retry manually)
           │  └───────────────────┘
           │
           │  ┌─────────────────┐
           └──│   COMPLETE       │
              └────────┬────────┘
                       │ Episode completed + synced + not in queue
                       ▼
              ┌─────────────────┐
              │    DELETED       │  (removed from manifest + media storage)
              └─────────────────┘
```

### 9.4 Handling Partial Downloads

**No resume support in v1.** If a download is interrupted:
1. Mark as FAILED in manifest
2. Increment errorCount
3. On next Wi-Fi connection, restart from scratch
4. Podcast episodes are typically 20-50 MB — full re-download takes seconds on Wi-Fi

**Why no resume?** `Communications.makeWebRequest()` doesn't support Range headers. The Media module doesn't expose partial file access. Implementing resume would require a custom chunked download system — not worth the complexity for v1.

---

## 10. Error Handling Matrix

| Failure Mode | Detection | Recovery | Data Safety |
|---|---|---|---|
| **Wi-Fi drops mid-download** | ConnectivityManager fires listener | DownloadManager.cancelDownloads(). Episode marked QUEUED. | ✅ Partial file discarded. Full retry on reconnect. |
| **Wi-Fi drops mid-sync push** | makeWebRequest returns error code | SyncEngine retries 3x with 30s backoff. Unpushed entries stay in changelog. | ✅ Changelog preserved. Idempotent push. |
| **Server returns 401** | Response code check | Refresh token → re-login → fail with error. | ✅ Auth refreshes automatically. |
| **Server returns 4xx (other)** | Response code check | Skip this entry, continue with next. Log error. | ⚠️ Entry stays in changelog for manual retry. |
| **Server returns 5xx** | Response code check | Retry 3x with backoff. If persistent, defer sync. | ✅ Changelog preserved for next sync. |
| **Storage full during download** | Exception from Media write | Cancel download. Trigger cleanupDownloads(). Retry after cleanup. | ✅ Manifest updated, no corruption. |
| **Application.Storage full** | Exception from setValue() | Evict LRU episode caches. Retry write. | ⚠️ May lose cached episode lists. Changelog is small and safe. |
| **Changelog corruption** | JSON parse error in loadChangelog() | Clear changelog. Log error. Accept data loss. | ❌ Unsynced changes lost. Acceptable — positions map is separate backup. |
| **Concurrent modification (phone + watch)** | Detected during reconciliation | max(position), max(status) — deterministic merge. No prompt. | ✅ "Furthest wins" resolves all conflicts. |
| **App killed during playback** | No detection — crash | On restart: load last saved position (≤15s old). Resume. | ✅ Position persisted every 15s. |
| **App killed during sync** | No detection — crash | On restart: changelog still has unpushed entries. Sync re-triggers. | ✅ Idempotent sync protocol. |
| **Token expires while offline** | Checked on reconnect in SyncEngine | Refresh → re-login → fail gracefully. | ✅ Credentials in Properties survive. |
| **Rate limited (429)** | Response code check | Exponential backoff: 5s → 10s → 20s → 40s. Max 4 retries. | ✅ Changelog preserved. |
| **Network timeout** | makeWebRequest returns -1 or similar | Retry logic same as server errors. | ✅ Safe to retry. |
| **Garmin OOM in background** | System kills background service | SyncDelegate state is transient — no corruption. Re-triggered next wake. | ✅ Download manifest in Storage survives. |

---

## 11. Integration Map — Existing Code

### 11.1 CacheManager.mc Changes

| What Changes | Why |
|---|---|
| Add changelog methods (A1) | Foundation for offline mutation tracking |
| Add consolidated positions map (A2) | Replace per-episode position keys |
| Add auth persistence (A6) | Survive app restarts |
| Add download manifest (C2) | Track download state |
| Update clearCache() to be selective | Don't wipe changelog/auth |
| Add storage estimation (E2) | Monitor pressure |

### 11.2 CachedPodcastService.mc Changes

| What Changes | Why |
|---|---|
| Replace `_isConnected()` with ConnectivityManager (A5) | Single source of truth |
| Add `isEpisodeDownloaded()` method (E4) | Views need download state |
| Add `getDownloadState()` method (E4) | Download progress indicator |
| fetchAll() uses `connectionAvailable` not `phoneConnected` (A5) | Fix: Wi-Fi-direct was broken |

### 11.3 IPodcastService.mc Changes

| What Changes | Why |
|---|---|
| Add `isEpisodeDownloaded(uuid)` (E4) | Interface contract for download awareness |
| Add `getDownloadState(uuid)` (E4) | Download status for UI |
| Add `isSyncing()` (E4) | Sync status for UI |
| Add `getConnectivityState()` (E4) | Connectivity for UI |

### 11.4 PocketCastsPodcastService.mc Changes

| What Changes | Why |
|---|---|
| Load saved auth tokens on init (A6) | Skip login if token valid |
| Save tokens after login/refresh (A6) | Persist for sync engine |
| Add new IPodcastService methods (E4) | Default implementations return false/0 |

### 11.5 YoCastsApp.mc Changes

| What Changes | Why |
|---|---|
| Own SyncEngine instance (B2) | Centralized sync management |
| Start ConnectivityManager (B2) | Connectivity polling |
| Implement onConnectivityChanged listener (B2) | Trigger sync on reconnect |
| Add getContentProvider() (D4) | Media module integration |
| Add crash recovery (D6) | Resume after reboot |

### 11.6 manifest.xml Changes

| What Changes | Why |
|---|---|
| type → audio-content-provider (C1) | Enable Media module |
| Add Background permission (C1) | Enable SyncDelegate |

---

## 12. File Inventory

### New Files

| File | Phase | Purpose |
|---|---|---|
| `source/services/PositionTracker.mc` | A | Position tracking with timer + battery awareness |
| `source/services/ConnectivityManager.mc` | A | Connectivity polling and state transitions |
| `source/services/SyncEngine.mc` | B | Sync state machine — push, pull, reconcile |
| `source/services/DownloadManager.mc` | C | Download queue management with battery guards |
| `source/media/YoCastsSyncDelegate.mc` | C | System-triggered downloads (charger + Wi-Fi) |
| `source/media/YoCastsContentProvider.mc` | D | Media module entry point |
| `source/media/YoCastsContentIterator.mc` | D | Playlist from downloaded episodes |
| `source/media/YoCastsContentDelegate.mc` | D | Playback events → position tracking |

### Modified Files

| File | Phase | Changes |
|---|---|---|
| `source/services/CacheManager.mc` | A, C, E | Changelog, positions map, auth, download manifest |
| `source/services/CachedPodcastService.mc` | A, E | ConnectivityManager, download state methods |
| `source/services/IPodcastService.mc` | E | Download/sync awareness methods |
| `source/services/PocketCastsPodcastService.mc` | A, E | Auth persistence, new interface methods |
| `source/YoCastsApp.mc` | B, D | SyncEngine, ConnectivityManager, ContentProvider |
| `source/views/HomeMenuView.mc` | B | Sync status indicator |
| `source/views/NowPlayingView.mc` | D | Download status, offline playback |
| `source/views/QueueView.mc` | D | Download badges per episode |
| `manifest.xml` | C | App type + permissions |

---

## Appendix: Key Garmin API Quick Reference

```
// Connectivity detection
System.getDeviceSettings().connectionAvailable  // true if Wi-Fi OR BT
System.getDeviceSettings().phoneConnected       // true if BT paired
System.getSystemStats().battery                 // float, 0-100
System.getSystemStats().charging                // boolean

// Storage
Application.Storage.setValue(key, value)         // persist (32 KB max per value)
Application.Storage.getValue(key)                // retrieve
Application.Storage.deleteValue(key)             // remove one key

// HTTP
Communications.makeWebRequest(url, params, options, callback)
// options: { :method, :headers, :responseType }
// callback: function(responseCode, data)

// Timer
var timer = new Timer.Timer();
timer.start(callback, intervalMs, repeat);
timer.stop();

// Media module
Media.ContentProvider       // base class for audio apps
Media.SyncDelegate          // system-triggered sync (charger + Wi-Fi)
Media.ContentIterator       // playlist navigation
Media.ContentDelegate       // playback event handling
Media.ContentRef            // reference to stored audio content
Media.CONTENT_TYPE_AUDIO    // content type constant

// Time
Time.now().value()           // Unix timestamp (seconds)
```

---

*This document is the implementation blueprint for the audio download and offline sync system. It was produced from `docs/offline-sync-design.md` v1.1 and represents Mal's architecture decisions for how Kaylee should build each component. Every task has explicit dependencies, pseudocode, and exit criteria. Build in phase order. Don't skip ahead.*
