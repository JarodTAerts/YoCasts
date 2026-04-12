# YoCasts — Offline Mode & Sync Reconciliation Design

> **Version:** 1.2  
> **Author:** Mal (Lead)  
> **Date:** 2026-04-12 (updated 2026-04-14)  
> **Status:** Partially Implemented — Phase 1 caching is built  
> **Audience:** Kaylee (implementation), Wash (API layer)  
> **v1.1 change:** Revised for Venu 4 Wi-Fi direct connectivity. Three-state connectivity model replaces two-state.  
> **v1.2 change:** Updated status — Phase 1 metadata caching is implemented (`CacheManager.mc` + `CachedPodcastService.mc`). Phases 2–4 remain planned.

---

## Table of Contents

1. [Connectivity Model](#connectivity-model)
2. [Offline Capabilities Assessment](#1-offline-capabilities-assessment)
3. [Data Caching Strategy](#2-data-caching-strategy)
4. [Audio Download Strategy](#3-audio-download-strategy)
5. [Offline Playback Flow](#4-offline-playback-flow)
6. [Sync Reconciliation Algorithm](#5-sync-reconciliation-algorithm)
7. [Sync Protocol](#6-sync-protocol)
8. [PocketCasts API Integration for Sync](#7-pocketcasts-api-integration-for-sync)
9. [Implementation Phases](#8-implementation-phases)

---

## Connectivity Model

The Venu 4 has both Bluetooth and Wi-Fi radios. `Communications.makeWebRequest()` works over **either** transport — Bluetooth proxies through the paired phone, Wi-Fi connects directly. This gives us **three** connectivity states, not two:

### State 1: Wi-Fi Connected (Best)

The watch is connected to a known Wi-Fi network (typically at home). **No phone required.**

- Full HTTP access — `makeWebRequest()` works directly over Wi-Fi
- Can download podcast episodes at full speed (no BLE bottleneck)
- Can sync metadata, push playback state, refresh caches
- Best time for bulk operations: auto-download Up Next episodes, full cache refresh
- Detected via `System.getDeviceSettings().connectionAvailable == true` (may also be true for BT — see detection notes below)

### State 2: Phone Connected via Bluetooth

The phone is paired and in range. HTTP requests are proxied through the phone's internet connection.

- Full HTTP access — `makeWebRequest()` works via BLE proxy
- Slower than Wi-Fi, especially for large downloads (audio files)
- Metadata sync and position pushes work well (small payloads)
- Episode downloads are possible but slower and drain more battery
- Detected via `System.getDeviceSettings().phoneConnected == true`

### State 3: Fully Offline

No Wi-Fi, no phone. The watch is on its own.

- No HTTP requests possible
- Cache-only mode — serve stored data
- Local playback of downloaded episodes only
- All mutations logged to changelog for later sync
- Detected via `connectionAvailable == false && phoneConnected == false`

### Connectivity Preference

```
Wi-Fi > Bluetooth > Offline

When Wi-Fi is available, prefer it for all operations.
When only Bluetooth is available, sync metadata and positions;
  defer large downloads unless user explicitly requests.
When fully offline, serve cached data and log changes.
```

### Detection

`System.getDeviceSettings()` provides two relevant fields:

| Field | Meaning |
|---|---|
| `connectionAvailable` | `true` if **any** internet path exists (Wi-Fi OR Bluetooth proxy). Use this as the primary "can I make HTTP requests?" check. |
| `phoneConnected` | `true` if the phone is paired and reachable via Bluetooth. |

**Practical detection logic:**

| `connectionAvailable` | `phoneConnected` | Likely State | Action |
|---|---|---|---|
| `true` | `false` | **Wi-Fi direct** | Full sync + episode downloads |
| `true` | `true` | **Phone connected** (may also have Wi-Fi) | Sync metadata + positions; downloads if bandwidth allows |
| `false` | `false` | **Fully offline** | Cache-only mode |
| `false` | `true` | **Phone connected, no internet** | Rare edge case — treat as offline |

> **Note:** `connectionAvailable` is `true` for either Wi-Fi or BT proxy. We cannot currently distinguish "Wi-Fi only" from "Wi-Fi + BT" with certainty via the public API. However, `connectionAvailable && !phoneConnected` is a reliable signal for "Wi-Fi without phone," which is the key new capability.

---

## 1. Offline Capabilities Assessment

### 1.1 What the Garmin Watch CAN Do

| Capability | Mechanism | Notes |
|---|---|---|
| **Store structured data** | `Application.Storage` (key-value) | Persists across app restarts. 32 KB per-value limit. Total varies by device. |
| **Store audio files** | `Media` module / `ContentProvider` | Dedicated media storage separate from app memory. Garmin manages the file system. |
| **Play audio** | `Media.ContentDelegate` + system media player | Garmin's built-in media player handles playback, controls, BT headphone output. |
| **Track time** | `Time.now()`, `Timer.Timer` | Reliable wall-clock timestamps for change tracking. |
| **Run the app** | Full app lifecycle | App runs normally without phone. All Views, Menus, logic work. |
| **Detect connectivity** | `System.getDeviceSettings()` | `connectionAvailable` (any internet path) + `phoneConnected` (BLE to phone). See [Connectivity Model](#connectivity-model). |
| **Make HTTP requests over Wi-Fi** | `Communications.makeWebRequest()` | Works directly over Wi-Fi without phone. Same API as BLE proxy path. |
| **Download episodes over Wi-Fi** | `Communications.makeWebRequest()` + `Media` | Large file downloads feasible at Wi-Fi speeds, no BLE bottleneck. |

### 1.2 What the Garmin Watch CANNOT Do When Fully Offline

These limitations apply only when the watch has **no connectivity at all** (no Wi-Fi, no phone):

| Limitation | Impact |
|---|---|
| **No HTTP requests** | `Communications.makeWebRequest()` requires either Wi-Fi or phone-as-proxy. Neither available = no API calls. |
| **No new data** | Cannot fetch new episodes, updated queue, or subscription changes. |
| **No position sync** | Cannot push playback progress to PocketCasts server. |
| **No streaming** | Audio must be pre-downloaded. No on-demand streaming without connectivity. |
| **No auth refresh** | Token refresh requires HTTP. If token expires while fully offline, no API calls until connectivity returns. |

### 1.3 Venu 4 41mm Storage Constraints

| Resource | Limit | Notes |
|---|---|---|
| **App memory (runtime)** | 768 KB | Generous — but this is RAM, not storage |
| **Background memory** | 64 KB | For background service / temporal events |
| **Application.Storage** | ~128–256 KB estimated | Device-dependent, separate from runtime RAM. Garmin does not publish exact limits. |
| **Storage per value** | 32 KB max | Single key-value entry cannot exceed this |
| **Media storage** | ~2–8 GB (shared) | Venu 4 has internal storage shared with music, apps, maps. User-configurable. |
| **Media file formats** | MP3, AAC, WAV | Garmin supports common audio formats via the Media module |

### 1.4 Connectivity State Diagram

```
         WI-FI CONNECTED                PHONE CONNECTED (BT)              FULLY OFFLINE
    ┌─────────────────────┐         ┌─────────────────────┐         ┌─────────────────┐
    │  Watch ◄──Wi-Fi──► Router     │  Watch ◄──BLE──► Phone        │  Watch (solo)   │
    │    │                          │    │                          │    │            │
    │    ▼                          │    ▼                          │    ▼            │
    │  makeWebRequest()             │  makeWebRequest()             │  Storage.get()  │
    │    │                          │    │ (proxied via phone)      │  Media.play()   │
    │    ▼                          │    ▼                          │  ChangeLog.add()│
    │  PocketCasts API              │  PocketCasts API              │                 │
    │                               │                               │                 │
    │  ✦ Fast downloads             │  ✦ Full API access            │  ✦ Cache only   │
    │  ✦ Auto-sync episodes         │  ✦ Smaller payloads preferred │  ✦ Local play   │
    │  ✦ No phone needed            │  ✦ Downloads possible (slow)  │  ✦ Log changes  │
    └─────────────────────┘         └─────────────────────┘         └─────────────────┘

    Transition: connectionAvailable == false && phoneConnected == false → fully offline
    Transition: connectionAvailable == true  → can make HTTP requests (prefer Wi-Fi path)
    Transition: connectionAvailable == true && !phoneConnected → Wi-Fi direct (best for downloads)
```

---

## 2. Data Caching Strategy

### 2.1 What to Cache

Every piece of data the user might need while disconnected. We cache aggressively when connected because storage is cheap and connectivity is not guaranteed.

| Data | Cache Key | Max Items | Est. Size | Priority |
|---|---|---|---|---|
| Subscribed podcasts | `"podcasts"` | 30 | ~6 KB | P0 — needed for browse |
| Episode lists (per podcast) | `"ep_{podcastUuid}"` | 15 per podcast, 10 podcasts | ~27 KB | P0 — needed for browse |
| Up Next queue | `"queue"` | 20 | ~5 KB | P0 — primary play list |
| In-progress episodes | `"in_progress"` | 20 | ~5 KB | P1 — resume playback |
| Playback positions (all tracked) | `"positions"` | 50 | ~2 KB | P0 — must track locally |
| User preferences | `"prefs"` | 1 | ~0.5 KB | P2 — playback speed, etc. |
| Auth tokens | `"auth"` | 1 | ~1 KB | P0 — needed on reconnect |
| **Sync change log** | `"changelog"` | 100 entries | ~5 KB | P0 — core of reconciliation |
| **Total metadata budget** | | | **~51.5 KB** | Fits in Application.Storage |

### 2.2 Cache Data Shapes

Each cached item is a Monkey C Dictionary/Array stored via `Application.Storage.setValue()`.

**Podcast cache (`"podcasts"`):**
```
[
  {
    "uuid": "abc-123",
    "title": "Up First from NPR",  // truncated to 40 chars
    "author": "NPR",               // truncated to 30 chars
    "unplayed": true,
    "lastEpisodePublished": "2026-04-11T14:50:06Z",
    "cachedAt": 1744444800          // Unix timestamp of when cached
  },
  ...
]
```

**Episode cache (`"ep_{podcastUuid}"`):**
```
[
  {
    "uuid": "def-456",
    "title": "Wednesday April 11",   // truncated to 50 chars
    "duration": 781,                 // seconds
    "playedUpTo": 340,               // seconds
    "playingStatus": 2,              // 0=not played, 2=in progress, 3=complete
    "podcastUuid": "abc-123",
    "podcastTitle": "Up First",      // truncated to 30 chars
    "url": "https://...",            // audio URL — needed for download
    "fileType": "audio/mp3",
    "published": "2026-04-11T14:50:06Z",
    "cachedAt": 1744444800
  },
  ...
]
```

**Up Next queue (`"queue"`):**
```
{
  "order": ["def-456", "ghi-789", ...],  // episode UUIDs in play order
  "episodes": {
    "def-456": {
      "title": "Episode Title",
      "url": "https://...",
      "podcast": "abc-123",
      "podcastTitle": "Podcast Name",
      "duration": 781,
      "playedUpTo": 340,
      "playingStatus": 2
    },
    ...
  },
  "serverModified": "1775953728729",     // server timestamp for conflict detection
  "cachedAt": 1744444800
}
```

**Playback positions (`"positions"`):**
```
{
  "def-456": {
    "position": 340,          // seconds
    "status": 2,              // playingStatus
    "duration": 781,
    "podcastUuid": "abc-123",
    "updatedAt": 1744445000,  // local timestamp of last change
    "dirty": true             // true = not yet synced to server
  },
  ...
}
```

### 2.3 Cache Invalidation Strategy

We use **stale-while-revalidate** with **opportunistic refresh**:

| Trigger | Action |
|---|---|
| **App launch (connected — Wi-Fi or BT)** | Refresh podcasts + queue in background. Serve cached data immediately. |
| **View entry (connected)** | Refresh that view's data. Show cached, swap when fresh data arrives. |
| **App launch (fully offline)** | Serve cached data only. No refresh attempt. |
| **Wi-Fi connection detected** | Trigger full sync + episode auto-download (§3.2). Best opportunity for bulk operations. |
| **Phone reconnection detected** | Trigger metadata sync. Defer large downloads unless Wi-Fi also available. |
| **Manual refresh** | User long-presses on a list → force refresh (future feature). |

**No TTL expiry.** Cached data never expires — it's always better to show stale data than nothing on a watch. Freshness is indicated via `cachedAt` timestamp if we want to show a "Last synced: 2h ago" indicator.

### 2.4 Storage Pressure & Eviction

With ~51.5 KB of metadata, we're well within the estimated 128–256 KB Application.Storage limit. But if we approach limits:

1. **Episode caches evict LRU.** Track last-accessed time per `"ep_{uuid}"` key. When adding a new podcast's episodes and storage is tight, delete the oldest-accessed podcast's episode cache.
2. **Max 10 podcast episode caches.** Hard cap. Most users only actively browse 3–5 podcasts.
3. **Positions map caps at 50 entries.** Remove oldest `dirty: false` entries first.
4. **Never evict:** auth tokens, queue, podcasts list, changelog.

```
Storage Priority (never evict → first evict):
  1. auth          — can't function without it
  2. changelog     — losing this loses unsynced data
  3. positions     — active tracking data
  4. queue         — primary play list
  5. podcasts      — browse list
  6. in_progress   — nice to have
  7. ep_{uuid}     — LRU eviction candidates
```

---

## 3. Audio Download Strategy

### 3.1 Garmin Media Module Overview

Garmin Connect IQ provides a `Media` module for audio content apps. YoCasts would implement `Media.ContentProvider` — this is how apps like Spotify and Deezer work on Garmin.

```
┌──────────────────────────────────────────────────┐
│  YoCasts implements Media.ContentProvider         │
│                                                  │
│  ┌────────────────────┐  ┌─────────────────────┐ │
│  │ ContentIterator    │  │ ContentDelegate     │ │
│  │ - browseContent()  │  │ - onPlay/Pause/Skip │ │
│  │ - getContentById() │  │ - onPosition update │ │
│  └────────────────────┘  └─────────────────────┘ │
│                                                  │
│  ┌────────────────────────────────────────────┐   │
│  │ SyncDelegate                              │   │
│  │ - isSyncNeeded()                          │   │
│  │ - onStartSync() — download episodes       │   │
│  │ - onStopSync()  — clean up                │   │
│  └────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

**Key components:**
- **`ContentProvider`** — The main class. Registers the app as an audio source. Garmin's media player calls into it.
- **`SyncDelegate`** — Called by the system when Wi-Fi is available (typically while charging). This is where we download audio files. On the Venu 4, Wi-Fi availability is common at home, making this trigger more reliable than older devices.
- **`ContentIterator`** — Provides the playlist structure for browsing downloaded content.
- **`ContentDelegate`** — Receives playback events (play, pause, skip, position changes).

### 3.2 Download Triggers

Audio download can happen via **two paths**, both using Wi-Fi:

**Path A: System-triggered sync (primary)**

Garmin triggers `SyncDelegate.onStartSync()` when:
1. Watch is on charger AND connected to Wi-Fi
2. User manually triggers sync from Garmin Connect

This is the same flow Spotify uses. Users put the watch on the charger, it downloads podcasts over Wi-Fi.

**Path B: App-initiated download (new — Wi-Fi direct)**

When the app detects Wi-Fi connectivity (`connectionAvailable && !phoneConnected`), it can proactively download episodes using `Communications.makeWebRequest()`:
1. App detects Wi-Fi at home (e.g., user comes home from a run)
2. App checks Up Next queue for episodes not yet downloaded
3. Downloads episodes directly over Wi-Fi — no phone, no charger needed
4. This is faster than waiting for the user to put the watch on the charger

**Path comparison:**

| | System Sync (Path A) | App-Initiated (Path B) |
|---|---|---|
| **Trigger** | Charger + Wi-Fi | Wi-Fi detected (no charger needed) |
| **Battery impact** | Minimal (on charger) | Moderate — limit to 2-3 episodes per session |
| **Speed** | Full Wi-Fi speed | Full Wi-Fi speed |
| **Reliability** | Garmin-managed, proven | App-managed, needs careful battery management |
| **Use case** | Overnight/pre-planned sync | Opportunistic — grab latest episodes when home |

### 3.3 Which Episodes to Auto-Download

Priority order for download (applies to both Path A and Path B):
1. **All episodes in the Up Next queue** — These are what the user explicitly queued.
2. **In-progress episodes** — User was listening, probably wants to continue.
3. **Most recent episode from top 5 subscriptions** — Catch new releases.

**Download cap:** Configurable, default 10 episodes. At ~30 MB average per episode, that's ~300 MB — reasonable on the Venu 4's shared storage.

**Wi-Fi auto-download behavior:**
When Wi-Fi is detected and Up Next has un-downloaded episodes, automatically begin downloading in priority order. This acts like a "podcast sync job" — the watch keeps its local library current whenever it's on Wi-Fi, similar to how a phone podcast app auto-downloads new episodes on Wi-Fi.

**Battery guard for app-initiated downloads (Path B):**
- Maximum 3 episodes per non-charger Wi-Fi session
- Skip download if battery < 30%
- Pause downloads if battery drops below 20% during download

### 3.4 Audio Format Requirements

| Format | PocketCasts Serves | Garmin Supports | Status |
|---|---|---|---|
| MP3 | ✅ Most common (`audio/mp3`) | ✅ | Primary format |
| AAC/M4A | ✅ Some podcasts | ✅ | Supported |
| OGG | Rare | ❌ | Skip — don't download |
| WAV | Never | ✅ | N/A |

PocketCasts episode responses include `fileType` and `url`. We filter to MP3/AAC only. If an episode's `fileType` is unsupported, skip it and try the next in queue.

### 3.5 Storage Budget for Audio

| Item | Size | Notes |
|---|---|---|
| Average podcast episode | 20–50 MB | 30-60 min at 128 kbps |
| Venu 4 total storage | ~8 GB | Shared with music, maps, other apps |
| Realistic podcast budget | 500 MB–1 GB | User configurable |
| Episodes at 30 MB avg | 15–30 episodes | More than enough for a run |

### 3.6 Download Flow

```
┌──────────────────────────────────────────────────────────────┐
│  Episode Download Flow (Path A: SyncDelegate or Path B: App) │
│                                                              │
│  1. Determine trigger:                                       │
│     Path A: SyncDelegate.onStartSync() (charger + Wi-Fi)    │
│     Path B: Wi-Fi detected, app checks for pending downloads│
│                                                              │
│  2. Get current queue from cache (or fetch fresh over Wi-Fi) │
│  3. Get list of already-downloaded episode UUIDs             │
│  4. For each queued episode not yet downloaded:              │
│     a. Path B only: check battery guard (§3.3)              │
│     b. Check storage space                                  │
│     c. Fetch episode audio URL from cache/API               │
│     d. Download via Communications.makeWebRequest           │
│        (uses Wi-Fi directly — fast, no BLE bottleneck)      │
│     e. Store as Media content with episode UUID as ID       │
│     f. Update download status in cache                      │
│  5. Remove downloaded episodes no longer in queue           │
│  6. Path A: Call SyncDelegate.onStopSync() when done        │
│     Path B: Update UI with download status                  │
└──────────────────────────────────────────────────────────────┘
```

> **Wi-Fi direct advantage:** On the Venu 4, `makeWebRequest()` over Wi-Fi downloads at full network speed. A 30 MB episode takes seconds on a typical home Wi-Fi connection, compared to minutes over a BLE proxy. This makes opportunistic app-initiated downloads (Path B) practical — you can grab a few episodes in the time it takes to walk in the door.

---

## 4. Offline Playback Flow

### 4.1 User Scenario: Going for a Run

```
TIME ──────────────────────────────────────────────────────────────────────────►

  AT HOME (Wi-Fi)                ON A RUN (fully offline)        BACK HOME (Wi-Fi reconnects)
  ┌───────────────────┐          ┌───────────────────────┐       ┌─────────────────────────┐
  │ Wi-Fi auto-sync   │          │ Browse cached podcasts│       │ Wi-Fi detected          │
  │ Download episodes │          │ Play downloaded audio │       │ Auto-sync: push changes │
  │ (no phone needed!)│          │ Track position locally│       │ Auto-download new eps   │
  │ Cache everything  │          │ Log all changes       │       │ Refresh caches          │
  └───────────────────┘          └───────────────────────┘       └─────────────────────────┘

  Key insight: The phone companion is NOT required for the at-home sync steps.
  Wi-Fi direct means the watch handles its own sync whenever it's on the home network.
```

### 4.2 Detailed Playback Flow by Connectivity State

```
User opens YoCasts
    │
    ▼
App checks: System.getDeviceSettings()
    │
    ├── connectionAvailable == true && !phoneConnected ──► WI-FI DIRECT
    │     - Full API access, no phone needed
    │     - Sync metadata in background
    │     - Auto-download queued episodes (battery permitting)
    │     - No offline indicator shown
    │
    ├── connectionAvailable == true && phoneConnected ──► PHONE CONNECTED
    │     - Full API access via BLE proxy (or Wi-Fi if both available)
    │     - Sync metadata in background
    │     - Downloads possible but prefer Wi-Fi for large files
    │     - No offline indicator shown
    │
    └── connectionAvailable == false ──► FULLY OFFLINE
          │
          ▼
    Show offline indicator (subtle icon in header/status bar)
          │
          ▼
    Load Home Menu from cache
          │
          ├──► Queue → Load from cached "queue"
          │              Show only episodes that have audio downloaded
          │              Gray out episodes without downloaded audio
          │              Badge: "📥 Downloaded" vs "☁️ Not downloaded"
          │
          ├──► Podcasts → Load from cached "podcasts"
          │                 Show episode lists from cached "ep_{uuid}"
          │                 Gray out episode actions that need network
          │
          └──► Now Playing → Play from downloaded Media content
                              │
                              ▼
                        Track position locally every 15 seconds:
                          positions[episodeUuid] = {
                            position: currentPos,
                            status: 2 (in_progress),
                            updatedAt: Time.now(),
                            dirty: true
                          }
                              │
                              ▼
                        On episode complete:
                          positions[episodeUuid] = {
                            position: duration,
                            status: 3 (completed),
                            updatedAt: Time.now(),
                            dirty: true
                          }
                          changelog.add({
                            type: "EPISODE_COMPLETED",
                            episodeUuid: uuid,
                            podcastUuid: podUuid,
                            timestamp: Time.now()
                          })
                              │
                              ▼
                        Auto-advance to next episode in queue
                        Remove completed from local queue copy
                        Log queue change in changelog
```

### 4.3 UI Behavior by Connectivity State

| Element | Wi-Fi Connected | Phone Connected (BT) | Fully Offline |
|---|---|---|---|
| **Status indicator** | None (clean UI) | None (clean UI) | Small "⊘" or "OFFLINE" in status area |
| **Queue items** | All tappable; downloading in background | All tappable | Only downloaded episodes tappable; others grayed |
| **Podcast list** | Fetch fresh on view | Fetch fresh on view | Show cached list. Subtitle: "Cached" |
| **Episode list** | Fetch fresh on view | Fetch fresh on view | Show cached list. No "fetch more" option. |
| **Now Playing** | Stream or play local | Stream or play local | Play local only. "Sync" button hidden. |
| **Refresh action** | Pulls fresh data | Pulls fresh data | Shows toast: "No connection available" |
| **Download action** | Downloads over Wi-Fi (fast) | Downloads over BT (slow, warn user) | Disabled |
| **Subscription changes** | N/A | N/A | Disabled — read-only view of cached subs |

### 4.4 Local Change Log

Every mutation the user makes while offline is recorded in a structured change log:

```
Storage key: "changelog"
Value: [
  {
    "id": 1,                              // sequential ID
    "type": "POSITION_UPDATE",            // change type
    "episodeUuid": "def-456",
    "podcastUuid": "abc-123",
    "data": { "position": 450, "status": 2, "duration": 781 },
    "timestamp": 1744445200               // when this change happened
  },
  {
    "id": 2,
    "type": "EPISODE_COMPLETED",
    "episodeUuid": "def-456",
    "podcastUuid": "abc-123",
    "data": { "position": 781, "status": 3, "duration": 781 },
    "timestamp": 1744445600
  },
  {
    "id": 3,
    "type": "QUEUE_REMOVE",
    "episodeUuid": "def-456",
    "data": {},
    "timestamp": 1744445601
  },
  ...
]
```

**Change types:**
| Type | Data | When Logged |
|---|---|---|
| `POSITION_UPDATE` | position, status, duration | Every 60s during playback (coalesced — only keep latest per episode) |
| `EPISODE_COMPLETED` | position, status, duration | When episode finishes |
| `QUEUE_REMOVE` | (none) | When completed episode removed from local queue |
| `EPISODE_STARRED` | starred (bool) | User stars/unstars (future) |

**Coalescing rule:** Multiple `POSITION_UPDATE` entries for the same episode are collapsed to keep only the latest. This prevents the changelog from growing unboundedly during a long run.

---

## 5. Sync Reconciliation Algorithm

This is the heart of the offline design. When the watch reconnects, local changes and server state may conflict. The algorithm resolves conflicts deterministically without user intervention.

### 5.1 Core Principles

1. **No data loss.** Never discard listening progress. If in doubt, keep the furthest-ahead state.
2. **Completed wins.** If either side says an episode is complete, it's complete. You can't un-listen to something.
3. **Server is authoritative for metadata.** Subscription changes, episode metadata, podcast info — server wins.
4. **Watch is authoritative for local playback.** The watch knows exactly what the user listened to locally.
5. **Deterministic.** Same inputs always produce the same output. No randomness, no user prompts.
6. **Idempotent.** Running sync twice with the same data produces the same result.

### 5.2 Conflict Categories & Resolution

#### A. Playback Position Conflicts

The most common conflict. User listened on the watch offline, and may have also listened on their phone or another device.

```
SCENARIO: Watch offline at position 15:30 for episode X.
          Server says episode X is at 12:00 (user listened on phone to 12:00).

RESOLUTION: Furthest position wins.
            → Sync position to 15:30 (watch value).

SCENARIO: Watch offline at position 15:30 for episode X.
          Server says episode X is at 25:00 (user listened MORE on phone).

RESOLUTION: Furthest position wins.
            → Keep server position 25:00. Don't regress.
```

**Why "furthest position wins"?**
- Podcast listening is linear. You don't want to re-listen to content.
- This is the strategy used by PocketCasts itself across its own apps.
- Edge case: user rewinds intentionally. This is acceptable loss — rewinding is cheap, re-listening is annoying.

**Pseudocode:**
```
function resolvePosition(localPos, localTimestamp, serverPos, serverTimestamp):
    if localPos == serverPos:
        return serverPos  // no conflict

    // Furthest position wins
    resolvedPos = max(localPos, serverPos)
    return resolvedPos
```

#### B. Episode Completion Conflicts

```
SCENARIO: Watch says episode is COMPLETED (status=3).
          Server says episode is IN_PROGRESS (status=2) at position 12:00.

RESOLUTION: Completed ALWAYS wins.
            → Push status=3 to server with position=duration.

SCENARIO: Server says COMPLETED, watch says IN_PROGRESS at 5:00.
          (User started re-listening? Or server got a completion from another device?)

RESOLUTION: Completed wins. Mark local as completed.
            → Don't regress completion state.
```

**Status hierarchy (higher always wins):**
```
COMPLETED (3) > IN_PROGRESS (2) > NOT_PLAYED (0)

Exception: NOT_PLAYED can only win if BOTH sides agree on NOT_PLAYED.
```

**Pseudocode:**
```
function resolveStatus(localStatus, serverStatus):
    // Completed is terminal — highest priority
    if localStatus == COMPLETED or serverStatus == COMPLETED:
        return COMPLETED

    // In-progress beats not-played
    if localStatus == IN_PROGRESS or serverStatus == IN_PROGRESS:
        return IN_PROGRESS

    return NOT_PLAYED
```

#### C. Queue (Up Next) Conflicts

The queue can diverge in multiple ways while the watch is offline:

```
SCENARIO 1: User added episodes on phone while watch was offline.
RESOLUTION: Merge. New server episodes appended to end of resolved queue.

SCENARIO 2: User removed episodes on phone. Watch still has them.
RESOLUTION: If watch played them → keep COMPLETED status, remove from queue.
            If watch didn't play them → remove from queue (server wins).

SCENARIO 3: Watch completed an episode and auto-removed from local queue.
            Server still has it in queue.
RESOLUTION: Remove from queue + mark completed on server.

SCENARIO 4: Both sides reordered the queue.
RESOLUTION: Server order wins for episodes not played on watch.
            Played/completed episodes are removed from queue regardless.
```

**Queue merge algorithm:**

```
function reconcileQueue(localQueue, serverQueue, localChangelog):
    // Step 1: Build sets
    localCompleted = set of episodeUuids completed on watch (from changelog)
    localPlayed    = set of episodeUuids with position updates (from changelog)
    serverSet      = set of episodeUuids in server queue
    localSet       = set of episodeUuids in local queue

    // Step 2: Start with server order as base
    resolvedOrder = []

    // Step 3: Walk server queue order
    for uuid in serverQueue.order:
        if uuid in localCompleted:
            continue  // completed episodes leave the queue
        resolvedOrder.add(uuid)

    // Step 4: Check for episodes in local queue but NOT in server queue
    //         (removed on server while watch was offline)
    for uuid in localQueue.order:
        if uuid not in serverSet:
            if uuid in localCompleted:
                // Watch completed it, server removed it — both agree it's done
                continue
            elif uuid in localPlayed:
                // Watch was playing it but server removed it
                // Respect server removal but preserve position for sync
                continue
            else:
                // Server removed, watch never touched — drop it
                continue

    // Step 5: Episodes completed on watch that server didn't know about
    //         → will be synced via POSITION_UPDATE / EPISODE_COMPLETED in sync protocol

    return resolvedOrder
```

```
VISUAL: Queue Merge

Local Queue:     [A*, B, C, D]       (* = played/completed on watch)
Server Queue:    [B, C, E, F]        (A removed, E+F added on phone)

Step 1: A is completed locally → mark completed, remove from queue
Step 2: Server order base → [B, C, E, F]
Step 3: A was in local but not server → already handled
Step 4: D was in local but not server → server removed it, drop

Result:          [B, C, E, F]        + sync A as completed
```

#### D. Subscription Changes

```
RESOLUTION: Server wins. Always.

The watch is read-only for subscriptions. Users subscribe/unsubscribe
on their phone or desktop. The watch reflects server state.
```

On reconnect:
1. Fetch fresh `/user/podcast/list`
2. Replace local `"podcasts"` cache entirely
3. If a cached podcast was unsubscribed, delete its `"ep_{uuid}"` cache
4. If a new podcast was subscribed, it appears in the list (no episodes cached until user browses it)

#### E. Episode Metadata Changes

```
RESOLUTION: Server wins for metadata. Watch values are display-only.

On reconnect, any cached episode titles, durations, URLs, etc.
are replaced by server values. The only watch-authoritative fields
are playback position and status (handled in §5.2.A and §5.2.B).
```

### 5.3 The Full Reconciliation Algorithm

Combining all conflict categories into one unified flow:

```
function reconcile(localState, serverState, changelog):
    result = {
        positionsToSync: [],    // changes to push to server
        queueToSync: null,      // resolved queue (if changed)
        localUpdates: {}        // updates to apply to local cache
    }

    // ─── PHASE 1: Resolve Playback Positions ───

    for entry in changelog where entry.type in [POSITION_UPDATE, EPISODE_COMPLETED]:
        episodeUuid = entry.episodeUuid
        localPos    = entry.data.position
        localStatus = entry.data.status
        localTime   = entry.timestamp

        // Fetch current server state for this episode
        serverEp = serverState.getEpisode(episodeUuid)
        if serverEp == null:
            // Episode doesn't exist on server (deleted?) — skip
            continue

        serverPos    = serverEp.playedUpTo
        serverStatus = serverEp.playingStatus

        // Resolve status first (status determines position handling)
        resolvedStatus = resolveStatus(localStatus, serverStatus)

        // Resolve position
        if resolvedStatus == COMPLETED:
            resolvedPos = max(localPos, serverPos, serverEp.duration)
        else:
            resolvedPos = max(localPos, serverPos)

        // Only sync if our resolved value differs from server
        if resolvedPos != serverPos or resolvedStatus != serverStatus:
            result.positionsToSync.add({
                uuid: episodeUuid,
                podcast: entry.podcastUuid,
                position: resolvedPos,
                status: resolvedStatus,
                duration: entry.data.duration
            })

        // Update local cache regardless
        result.localUpdates[episodeUuid] = {
            position: resolvedPos,
            status: resolvedStatus
        }

    // ─── PHASE 2: Resolve Queue ───

    serverQueue = serverState.getQueue()
    localQueue  = localState.getQueue()

    result.queueToSync = reconcileQueue(localQueue, serverQueue, changelog)

    // ─── PHASE 3: Subscriptions ───

    // Server wins — no merge needed
    result.localUpdates["podcasts"] = serverState.getPodcasts()

    return result
```

### 5.4 Conflict Resolution Truth Table

Quick reference for all possible states:

| Local Status | Server Status | Local Pos | Server Pos | → Resolved Status | → Resolved Pos |
|---|---|---|---|---|---|
| NOT_PLAYED | NOT_PLAYED | 0 | 0 | NOT_PLAYED | 0 |
| IN_PROGRESS | NOT_PLAYED | 500 | 0 | IN_PROGRESS | 500 |
| NOT_PLAYED | IN_PROGRESS | 0 | 300 | IN_PROGRESS | 300 |
| IN_PROGRESS | IN_PROGRESS | 500 | 300 | IN_PROGRESS | 500 |
| IN_PROGRESS | IN_PROGRESS | 300 | 500 | IN_PROGRESS | 500 |
| COMPLETED | NOT_PLAYED | 781 | 0 | COMPLETED | 781 |
| COMPLETED | IN_PROGRESS | 781 | 300 | COMPLETED | 781 |
| IN_PROGRESS | COMPLETED | 300 | 781 | COMPLETED | 781 |
| COMPLETED | COMPLETED | 781 | 781 | COMPLETED | 781 |

**Rule summary:** `max(status)` for status, `max(position)` for position. Simple, predictable, no data loss.

### 5.5 Edge Cases

| Edge Case | Handling |
|---|---|
| **User re-listens to a completed episode** | Not supported in v1. COMPLETED is terminal. User must mark as unplayed on phone first. |
| **Episode deleted on server** | Skip sync for that episode. Remove from local cache. |
| **Extremely long offline period (days)** | Works fine — changelog entries have timestamps. Process all of them. |
| **Changelog grows very large** | Coalescing (§4.4) keeps it bounded. Only latest position per episode is kept. |
| **Auth token expired during offline** | On reconnect, re-authenticate before syncing. Store credentials securely for re-auth. |
| **Two episodes completed in different order** | Order doesn't matter — each episode is resolved independently. |
| **Watch battery dies mid-playback** | Last persisted position (every 15s) is used. At most 15s of progress lost. |

---

## 6. Sync Protocol

### 6.1 Sync Flow — Step by Step

```
┌──────────────────────────────────────────────────────────────────┐
│                    SYNC PROTOCOL                                 │
│                                                                  │
│  TRIGGER: connectionAvailable transitions false → true           │
│           (Wi-Fi connects at home, or phone comes in range)      │
│           OR app launch with connectionAvailable == true          │
│           OR user manually triggers sync                         │
│                                                                  │
│  NOTE: Sync works identically over Wi-Fi or Bluetooth.           │
│        makeWebRequest() abstracts the transport.                 │
│        Wi-Fi is preferred — faster, no phone dependency.         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 1: DETECT CONNECTION                                   │ │
│  │   if !System.getDeviceSettings().connectionAvailable:       │ │
│  │     return  // fully offline — no Wi-Fi or phone             │ │
│  │   syncState = "SYNCING"                                     │ │
│  │   show sync indicator on UI                                 │ │
│  └──────────────────────┬──────────────────────────────────────┘ │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 2: VALIDATE AUTH                                       │ │
│  │   if token expired:                                         │ │
│  │     try refresh via /user/token                             │ │
│  │     if refresh fails: re-login via /user/login_pocket_casts │ │
│  │     if login fails: abort sync, show auth error             │ │
│  └──────────────────────┬──────────────────────────────────────┘ │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 3: READ LOCAL CHANGELOG                                │ │
│  │   changelog = Storage.getValue("changelog")                 │ │
│  │   if changelog == null or changelog.size() == 0:            │ │
│  │     skip to STEP 6  // no local changes to reconcile        │ │
│  └──────────────────────┬──────────────────────────────────────┘ │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 4: FETCH SERVER STATE FOR AFFECTED EPISODES            │ │
│  │   affectedUuids = unique episodeUuids from changelog        │ │
│  │   for each uuid:                                            │ │
│  │     serverEpisode = POST /user/episode { uuid }             │ │
│  │     (batch if possible — up to 10 parallel requests)        │ │
│  │   serverQueue = POST /up_next/list                          │ │
│  └──────────────────────┬──────────────────────────────────────┘ │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 5: RECONCILE & PUSH                                   │ │
│  │   result = reconcile(localState, serverState, changelog)    │ │
│  │                                                             │ │
│  │   // Push position updates to server                        │ │
│  │   for each update in result.positionsToSync:                │ │
│  │     POST /sync/update_episode {                             │ │
│  │       uuid, podcast, position, status, duration             │ │
│  │     }                                                       │ │
│  │     Mark changelog entry as synced                          │ │
│  │                                                             │ │
│  │   // Queue changes handled by server state in next fetch    │ │
│  │   // (completed episodes will be auto-removed by server)    │ │
│  └──────────────────────┬──────────────────────────────────────┘ │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 6: REFRESH ALL CACHES                                  │ │
│  │   podcasts = POST /user/podcast/list                        │ │
│  │   queue = POST /up_next/list                                │ │
│  │   inProgress = POST /user/in_progress                       │ │
│  │                                                             │ │
│  │   // Update local caches                                    │ │
│  │   Storage.setValue("podcasts", trim(podcasts))               │ │
│  │   Storage.setValue("queue", normalize(queue))                │ │
│  │   Storage.setValue("in_progress", trim(inProgress))          │ │
│  │                                                             │ │
│  │   // Refresh episode caches for recently viewed podcasts    │ │
│  │   for each cached "ep_{uuid}":                              │ │
│  │     episodes = POST /user/podcast/episodes { uuid }         │ │
│  │     merge episode metadata (titles from /user/episode)      │ │
│  │     Storage.setValue("ep_{uuid}", trim(episodes))            │ │
│  └──────────────────────┬──────────────────────────────────────┘ │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ STEP 7: CLEAR CHANGELOG & UPDATE STATE                      │ │
│  │   // Only clear entries that were successfully synced        │ │
│  │   Storage.setValue("changelog", remainingEntries)            │ │
│  │   // Update positions — mark all as dirty: false             │ │
│  │   Storage.setValue("positions", updatedPositions)             │ │
│  │   syncState = "COMPLETE"                                    │ │
│  │   hide sync indicator                                       │ │
│  │   refresh active view                                       │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 6.2 Sync State Machine

```
                    ┌──────────┐
                    │  IDLE    │◄──────────────────────┐
                    └────┬─────┘                       │
                         │ connectionAvailable          │
                         │ (Wi-Fi or BT)               │
                         │ || app launch               │
                         ▼                             │
                    ┌──────────┐                       │
                    │  AUTH    │──── auth failed ───►IDLE (show error)
                    └────┬─────┘                       │
                         │ auth OK                     │
                         ▼                             │
                    ┌──────────────┐                   │
                    │  PUSH_LOCAL  │── push failed ──► RETRY (after 30s)
                    └────┬─────────┘                   │
                         │ push OK                     │
                         ▼                             │
                    ┌──────────────┐                   │
                    │  PULL_SERVER │── pull failed ──► RETRY (after 30s)
                    └────┬─────────┘                   │
                         │ pull OK                     │
                         ▼                             │
                    ┌──────────────┐                   │
                    │  DOWNLOAD?   │── Wi-Fi + pending episodes?
                    └────┬─────────┘   Yes → trigger episode downloads (§3.2)
                         │ done / skip │   No → skip to CLEANUP
                         ▼             │
                    ┌──────────────┐   │
                    │  CLEANUP     │───┘───────────────┘
                    └──────────────┘
```

> **New DOWNLOAD? step:** After pulling server state, if Wi-Fi is available and there are queued episodes not yet downloaded, trigger auto-download. This step is skipped on BT-only connections (downloads too slow) and when all episodes are already local.

### 6.3 Error Handling During Sync

| Failure Point | Recovery | Data Safety |
|---|---|---|
| **Auth fails** | Re-login. If still fails, abort sync. Changelog preserved. | ✅ No data lost — changelog persists |
| **Push fails (network)** | Retry up to 3 times with 10s backoff. If all fail, keep changelog for next sync. | ✅ Changelog entries not cleared until confirmed pushed |
| **Push partially completes** | Only clear successfully pushed changelog entries. Remaining entries retry next sync. | ✅ Each entry tracked independently |
| **Pull fails** | Use existing cached data. Try again next sync opportunity. | ✅ Stale cache is better than no cache |
| **Connection lost mid-sync** | Sync aborts gracefully. State machine returns to IDLE. Changelog preserved. Works the same whether Wi-Fi drops or phone disconnects. | ✅ Idempotent — safe to restart |
| **App killed mid-sync** | On next launch, sync resumes from IDLE with preserved changelog. | ✅ Changelog is persisted to Storage before sync starts |

### 6.4 Idempotency Guarantees

The sync protocol is safe to retry at any point:

1. **Position pushes are idempotent.** Calling `/sync/update_episode` with the same position twice has no side effects.
2. **Changelog entries are only cleared after confirmed push.** If push succeeds but clear fails, the entry will be pushed again — harmless due to idempotency.
3. **Cache refreshes are full replacements.** Pulling the same data twice just overwrites with the same values.
4. **No ordering dependencies between episodes.** Each episode's reconciliation is independent.

### 6.5 Connectivity Detection

```monkeyc
// Primary connectivity check — true for Wi-Fi OR Bluetooth proxy
function hasConnectivity() as Boolean {
    var settings = System.getDeviceSettings();
    return settings.connectionAvailable;
}

// Distinguish Wi-Fi-only from phone-connected
function getConnectivityState() as Number {
    var settings = System.getDeviceSettings();
    if (!settings.connectionAvailable) {
        return CONNECTIVITY_OFFLINE;       // 0 — no internet at all
    }
    if (!settings.phoneConnected) {
        return CONNECTIVITY_WIFI_DIRECT;   // 2 — Wi-Fi without phone (best for downloads)
    }
    return CONNECTIVITY_PHONE;             // 1 — phone connected (may also have Wi-Fi)
}

// Timer-based polling during app lifecycle
function onStart(state) {
    _connectivityTimer = new Timer.Timer();
    _connectivityTimer.start(method(:onConnectivityCheck), 30000, true);  // every 30s
}

function onConnectivityCheck() as Void {
    var state = getConnectivityState();
    if (state != CONNECTIVITY_OFFLINE && _wasOffline && hasUnsyncedChanges()) {
        triggerSync();
    }
    // Wi-Fi direct detected — opportunity for episode downloads
    if (state == CONNECTIVITY_WIFI_DIRECT && hasPendingDownloads()) {
        triggerEpisodeDownloads();
    }
    _wasOffline = (state == CONNECTIVITY_OFFLINE);
}
```

> **Key change from v1.0:** We now check `connectionAvailable` instead of `phoneConnected` as the primary connectivity signal. This means sync triggers whenever the watch has _any_ internet path — including Wi-Fi without the phone. The phone is no longer a prerequisite for sync.

---

## 7. PocketCasts API Integration for Sync

### 7.1 Endpoints Used in Sync

| Endpoint | Sync Phase | Direction | Purpose |
|---|---|---|---|
| `POST /user/login_pocket_casts` | Auth | Watch → Server | Re-authenticate if token expired |
| `POST /user/token` | Auth | Watch → Server | Refresh access token |
| `POST /user/episode` | Pull | Server → Watch | Get current server state per episode |
| `POST /sync/update_episode` | Push | Watch → Server | Push resolved position + status |
| `POST /user/podcast/list` | Pull | Server → Watch | Refresh subscriptions |
| `POST /up_next/list` | Pull | Server → Watch | Refresh queue |
| `POST /user/in_progress` | Pull | Server → Watch | Get all in-progress episodes |
| `POST /user/history` | Pull (optional) | Server → Watch | Check what was listened elsewhere |

### 7.2 Push: /sync/update_episode

This is the critical write endpoint. Used to push resolved playback state.

**Request:**
```json
{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid",
  "position": 450,
  "status": 2,
  "duration": 781
}
```

**Sync strategy:** Push one episode at a time, sequentially. Wait for 200 response before pushing next. This avoids rate limiting and makes error tracking simple.

**Timing:** On Garmin, `makeWebRequest` is asynchronous. Chain pushes via callbacks:

```monkeyc
function pushNextChange() as Void {
    if (_syncQueue.size() == 0) {
        onPushComplete();
        return;
    }

    var change = _syncQueue[0];
    var url = "https://api.pocketcasts.com/sync/update_episode";
    var body = {
        "uuid" => change["uuid"],
        "podcast" => change["podcastUuid"],
        "position" => change["position"],
        "status" => change["status"],
        "duration" => change["duration"]
    };

    Communications.makeWebRequest(url, body, _authOptions, method(:onPushResponse));
}

function onPushResponse(responseCode as Number, data as Dictionary?) as Void {
    if (responseCode == 200) {
        var pushed = _syncQueue[0];
        _syncQueue = _syncQueue.slice(1, null);
        markChangelogEntrySynced(pushed["changelogId"]);
        pushNextChange();  // chain to next
    } else if (responseCode == 401) {
        refreshTokenAndRetry();
    } else {
        // Network error — stop pushing, keep remaining in queue
        onPushFailed(responseCode);
    }
}
```

### 7.3 Pull: Server State Fetch

**Batch strategy for episode state:**

We can't batch `/user/episode` calls (one UUID per request). But we can use `/user/in_progress` to get all in-progress episodes in one call, which covers most reconciliation needs.

```
Optimization: Instead of fetching each affected episode individually,
              fetch /user/in_progress (gets all partially-played episodes)
              + /user/history (gets recently completed episodes).
              This covers 90%+ of sync cases in 2 requests instead of N.
```

| Strategy | Requests | Coverage |
|---|---|---|
| Individual `/user/episode` per UUID | N requests | 100% — but slow |
| `/user/in_progress` + `/user/history` | 2 requests | ~95% — misses never-played episodes |
| Hybrid: bulk first, individual for misses | 2 + M requests | 100% — optimal |

**Recommended: Hybrid approach.** Fetch bulk endpoints first, then individual requests only for episodes not covered.

### 7.4 Rate Limiting & Throttling

| Consideration | Approach |
|---|---|
| **Push rate** | Max 1 request per second. Sequential pushes with callback chaining. |
| **Pull rate** | Batch pulls. 2-3 requests max at sync start. |
| **429 handling** | Exponential backoff: 5s → 10s → 20s → 40s. Max 4 retries. |
| **Total sync requests** | Typical sync: 2–5 pulls + 1–10 pushes = under 15 requests total. |
| **Download rate (Wi-Fi)** | Sequential episode downloads. One at a time to manage memory. Wi-Fi bandwidth is not a concern — the bottleneck is device processing. |
| **Download rate (BT)** | Avoid large downloads over Bluetooth. Metadata sync only unless user explicitly requests. |
| **Background vs foreground** | Sync runs in foreground (user sees "Syncing..." indicator). Episode downloads can run in background via SyncDelegate. |

### 7.5 Server Timestamp Handling

PocketCasts uses various timestamp formats:

| Field | Format | Example |
|---|---|---|
| `serverModified` (Up Next) | Unix millis string | `"1775953728729"` |
| `published` | ISO 8601 | `"2026-04-11T14:50:06Z"` |
| `playedUpTo` | Integer seconds | `1491` |

**For conflict detection:** We use `serverModified` from the Up Next response to detect queue changes. For episodes, we compare `playedUpTo` and `playingStatus` values directly — no timestamp comparison needed because our rule is simply `max(position)` and `max(status)`.

---

## 8. Implementation Phases

### Phase 1: Metadata Caching (Browse Offline) ✅ IMPLEMENTED

**Goal:** User can browse podcasts and episodes while disconnected.

**Implementation:** `CacheManager.mc` (module) + `CachedPodcastService.mc` (decorator)

- [x] `CacheManager` wraps `Application.Storage` with `"yc_"` key prefixes and `cachedAt` timestamps
- [x] `CachedPodcastService` wraps `PocketCastsPodcastService` via constructor injection
- [x] Cache-first: loads cached data on init for instant UI
- [x] TTL-based revalidation hints: queue 5min, podcasts 30min, episodes 1hr
- [x] Stale data always served — freshness is a revalidation hint, not an expiry
- [x] `fetchAll()` delegates to wrapped service only when `connectionAvailable == true`
- [x] Read-through getters cache on each view cycle
- [x] Connectivity detection via `connectionAvailable` (not just `phoneConnected`)
- [ ] `getConnectivityState()` helper returning Wi-Fi / Phone / Offline (not yet implemented separately)
- [ ] Show offline indicator in UI only when fully offline (deferred to Phase 2)
- [ ] LRU eviction for episode caches (max 10 podcasts) (deferred — not hitting limits yet)

**Files:** `source/services/CacheManager.mc`, `source/services/CachedPodcastService.mc`

**Phase 2 readiness:** `savePlaybackPosition()` / `loadPlaybackPosition()` stubs exist in `CacheManager`. Phase 2 adds the changelog key and calls from NowPlayingView.

### Phase 2: Playback Position Tracking & Sync 📋 NEXT UP

**Goal:** Watch tracks playback position locally and syncs to server on reconnect.

**Tasks:**
- [ ] Implement `"positions"` cache with dirty tracking (§2.2)
- [ ] Implement change log (`"changelog"`) with coalescing (§4.4)
- [ ] Track playback position every 15s during playback → write to positions cache
- [ ] Log `POSITION_UPDATE` and `EPISODE_COMPLETED` to changelog
- [ ] Implement sync state machine (§6.2)
- [ ] Implement connectivity polling (30s interval) with reconnection detection
- [ ] Implement push flow: sequential `/sync/update_episode` calls (§7.2)
- [ ] Implement pull flow: fetch `/user/in_progress` + individual episode fallback (§7.3)
- [ ] Implement reconciliation algorithm (§5.3) — position + status resolution
- [ ] Implement changelog cleanup after successful push
- [ ] Add sync status UI ("Syncing...", "Sync complete", "Sync failed")
- [ ] Handle auth token expiry during sync

**Exit criteria:** User listens to episode on watch, goes offline, comes back. Position syncs to PocketCasts. Verified by checking position on web player.

**Dependencies:** Phase 1 (caching), existing Now Playing implementation.

### Phase 3: Audio Download & Offline Playback

**Goal:** User can download episodes to watch over Wi-Fi and play them without phone.

**Tasks:**
- [ ] Implement `Media.ContentProvider` for YoCasts (§3.1)
- [ ] Implement `SyncDelegate` for system-triggered downloads (Path A: charger + Wi-Fi) (§3.2)
- [ ] Implement app-initiated downloads (Path B: Wi-Fi detected, no charger needed) (§3.2)
- [ ] Battery guard for Path B downloads: max 3 episodes, skip if battery < 30% (§3.3)
- [ ] Download logic: prioritize Up Next queue, then in-progress, then recent (§3.3)
- [ ] Wi-Fi auto-download: when Wi-Fi connects and Up Next has un-downloaded episodes, begin downloading automatically
- [ ] File format filtering — only download MP3/AAC (§3.4)
- [ ] Storage management — track downloaded episode UUIDs, implement cleanup
- [ ] `ContentIterator` — expose downloaded episodes for browse/play
- [ ] `ContentDelegate` — handle play/pause/skip events, feed position back to position tracker
- [ ] UI: Show download status per episode (downloaded ✓, downloading ⟳, not downloaded ☁)
- [ ] UI: Only allow playing downloaded episodes when fully offline
- [ ] UI: Show download progress when Wi-Fi downloads are active
- [ ] Add DOWNLOAD? step to sync state machine — after pull, check for pending downloads on Wi-Fi (§6.2)

**Exit criteria:** User comes home, watch connects to Wi-Fi, episodes auto-download without phone. User goes for run without phone, plays downloaded episodes. Position tracked locally. Also works via charger + Wi-Fi (traditional Garmin sync flow).

**Dependencies:** Phase 2 (position tracking), Garmin Media SDK.

### Phase 4: Full Sync Reconciliation

**Goal:** Complete conflict resolution for all scenarios.

**Tasks:**
- [ ] Implement queue reconciliation algorithm (§5.2.C)
- [ ] Handle subscription changes — server wins, cache update (§5.2.D)
- [ ] Handle episode metadata refresh — server wins (§5.2.E)
- [ ] Implement hybrid pull strategy (bulk + individual) (§7.3)
- [ ] Rate limiting with exponential backoff (§7.4)
- [ ] Full error recovery — partial sync resume (§6.3)
- [ ] Stress test: simulate long offline period with many changes
- [ ] Stress test: simulate conflicting changes on phone + watch
- [ ] Edge case testing: auth expiry, network drops mid-sync, app kill
- [ ] Storage pressure testing — verify eviction works under load

**Exit criteria:** All scenarios in the conflict resolution truth table (§5.4) produce correct results. Sync is reliable across disconnections and failures.

**Dependencies:** Phases 1–3.

### Phase Summary Timeline

```
Phase 1 ████████████████████████████  ✅ DONE (CacheManager + CachedPodcastService)
Phase 2 ░░░░░░░░████████████░░░░░░░░  📋 NEXT (Position Tracking + Sync)
Phase 3 ░░░░░░░░░░░░░░░░████████░░░░  (Audio Download)
Phase 4 ░░░░░░░░░░░░░░░░░░░░████████  (Full Reconciliation)
```

Phases 1 and 2 can be implemented by Kaylee (on-device logic) with Wash supporting the API integration. Phase 3 requires deep Garmin Media SDK work + Wi-Fi download logic — primarily Kaylee. Phase 4 is integration testing — full team.

> **Wi-Fi impact on phasing:** Wi-Fi direct simplifies Phase 3 significantly — the phone companion app is no longer needed as a download intermediary. The watch can download episodes directly over Wi-Fi using the same `makeWebRequest()` API used for metadata. This removes a major complexity barrier from the original Phase 3 plan.

---

## Appendix A: Data Flow Diagram — Complete Lifecycle

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              COMPLETE DATA FLOW                                      │
│                                                                                      │
│   WI-FI CONNECTED            PHONE CONNECTED (BT)        FULLY OFFLINE               │
│   ───────────────            ────────────────────         ─────────────               │
│                                                                                      │
│   ┌──────────────┐           ┌──────────────┐            ┌──────────┐                │
│   │ Direct HTTP  │           │ Proxied HTTP │            │ Storage  │                │
│   │ via Wi-Fi    │           │ via phone    │            │ read     │                │
│   └────┬─────────┘           └────┬─────────┘            └────┬─────┘                │
│        │                          │                           │                      │
│        ▼                          ▼                           ▼                      │
│   ┌──────────────┐           ┌──────────────┐            ┌──────────┐                │
│   │ Update cache │           │ Update cache │            │ Serve    │                │
│   │ + serve      │           │ + serve      │            │ cached   │                │
│   │ + download   │           │ (skip large  │            │ data     │                │
│   │   episodes   │           │  downloads)  │            └────┬─────┘                │
│   └────┬─────────┘           └────┬─────────┘                 │                      │
│        │                          │                           ▼                      │
│        ▼                          ▼                      ┌──────────┐                │
│   ┌──────────┐               ┌──────────┐               │ User     │                │
│   │ User     │               │ User     │               │ plays    │                │
│   │ sees     │               │ sees     │               │ episode  │                │
│   │ fresh    │               │ fresh    │               └────┬─────┘                │
│   │ data     │               │ data     │                    │                      │
│   └──────────┘               └──────────┘                    ▼                      │
│                                                         ┌──────────┐                │
│   ──── RECONNECTION (Wi-Fi or BT) ────                  │ Write to │                │
│                                                         │ changelog│                │
│   ┌──────────┐                                          │ + cache  │                │
│   │ Sync     │                                          └──────────┘                │
│   │ Engine   │                                                                      │
│   └────┬─────┘                                                                      │
│        │                                                                            │
│        ▼                                                                            │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│   │ Read     │→ │ Fetch    │→ │ Reconcile│→ │ Push to  │→ │ Refresh  │             │
│   │ changelog│  │ server   │  │ conflicts│  │ server   │  │ caches   │             │
│   └──────────┘  └──────────┘  └──────────┘  └──────────┘  └────┬─────┘             │
│                                                                │                    │
│                                                                ▼                    │
│                                                           ┌──────────┐              │
│                                                           │ Download │ (Wi-Fi only) │
│                                                           │ episodes │              │
│                                                           └────┬─────┘              │
│                                                                │                    │
│                                                                ▼                    │
│                                                           ┌──────────┐              │
│                                                           │ Clear    │              │
│                                                           │ changelog│              │
│                                                           └──────────┘              │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Appendix B: Storage Key Reference

| Key | Type | Max Size | Description |
|---|---|---|---|
| `"auth"` | Dictionary | ~1 KB | accessToken, refreshToken, expiresIn, loginTimestamp |
| `"podcasts"` | Array<Dictionary> | ~6 KB | Subscribed podcast metadata |
| `"queue"` | Dictionary | ~5 KB | Up Next: order array + episodes map + serverModified |
| `"in_progress"` | Array<Dictionary> | ~5 KB | Episodes with playingStatus == 2 |
| `"positions"` | Dictionary | ~2 KB | Episode UUID → {position, status, updatedAt, dirty} |
| `"changelog"` | Array<Dictionary> | ~5 KB | Pending local changes to sync |
| `"ep_{uuid}"` | Array<Dictionary> | ~3 KB each | Cached episode list per podcast (max 10) |
| `"prefs"` | Dictionary | ~0.5 KB | User preferences (playback speed, etc.) |
| `"dl_manifest"` | Array<String> | ~1 KB | List of downloaded episode UUIDs |
| `"sync_state"` | String | ~0.1 KB | Current sync state machine position |

## Appendix C: Changelog Entry Schema

```
{
  "id": Number,           // monotonically increasing, unique per entry
  "type": String,         // "POSITION_UPDATE" | "EPISODE_COMPLETED" | "QUEUE_REMOVE" | "EPISODE_STARRED"
  "episodeUuid": String,  // episode this change affects
  "podcastUuid": String,  // parent podcast UUID
  "data": Dictionary,     // type-specific payload
  "timestamp": Number     // Unix timestamp (seconds) when change occurred
}
```

**Coalescing implementation:**
```monkeyc
function addChangelogEntry(type, episodeUuid, podcastUuid, data) {
    var log = Storage.getValue("changelog");
    if (log == null) { log = []; }

    // Coalesce: remove older POSITION_UPDATE for same episode
    if (type.equals("POSITION_UPDATE")) {
        var filtered = [];
        for (var i = 0; i < log.size(); i++) {
            if (!(log[i]["type"].equals("POSITION_UPDATE") &&
                  log[i]["episodeUuid"].equals(episodeUuid))) {
                filtered.add(log[i]);
            }
        }
        log = filtered;
    }

    // Append new entry
    var nextId = log.size() > 0 ? log[log.size()-1]["id"] + 1 : 1;
    log.add({
        "id" => nextId,
        "type" => type,
        "episodeUuid" => episodeUuid,
        "podcastUuid" => podcastUuid,
        "data" => data,
        "timestamp" => Time.now().value()
    });

    // Cap at 100 entries (safety valve)
    if (log.size() > 100) {
        log = log.slice(log.size() - 100, null);
    }

    Storage.setValue("changelog", log);
}
```

---

*This document supersedes the offline/caching section (§6) in `garmin-app-implementation-guide.md` and expands it into a full offline + sync architecture. v1.1 incorporates the Venu 4's Wi-Fi direct capability, which simplifies the architecture — the phone companion is no longer required for sync or episode downloads when Wi-Fi is available. The implementation guide's §6 remains valid as a quick reference for the simpler "cache-for-offline-browse" use case.*
