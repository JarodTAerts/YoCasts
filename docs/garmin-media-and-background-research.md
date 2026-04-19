# Garmin Connect IQ — Media, Background Services & Power Management Research

> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-04-13  
> **Status:** Technical Reference — verified against Garmin API docs, SDK 9.1.0, forums, and sample code  
> **Target Device:** Venu 4 41mm (390×390 AMOLED, 8 GB storage, 768 KB app RAM, CIQ API 5.0+)  
> **Purpose:** Ground-truth reference for audio download + offline sync implementation

---

## Table of Contents

1. [Media Module Deep Dive](#1-media-module-deep-dive)
2. [Background Services](#2-background-services)
3. [Power Management](#3-power-management)
4. [Communications.makeWebRequest() for Large Files](#4-communicationsmakewebrequest-for-large-files)
5. [Application.Storage Limits](#5-applicationstorage-limits)
6. [Connectivity Detection](#6-connectivity-detection)
7. [Architecture Implications for YoCasts](#7-architecture-implications-for-yocasts)

---

## 1. Media Module Deep Dive

### 1.1 App Type: AudioContentProviderApp

**⚠️ CRITICAL ARCHITECTURAL DECISION:** Audio content provider apps are a **separate app type** from device apps. They are not regular "device apps" with audio bolted on — they are a fundamentally different app type with different lifecycle, manifest, and entry points.

| Property | Device App | Audio Content Provider |
|---|---|---|
| Manifest `type` | `device` | `audioContentProviderApp` |
| Base class | `Toybox.Application.AppBase` | `Toybox.Application.AudioContentProviderApp` |
| Media player integration | None | Full — provides content to native player |
| Launched from | App list | Music widget / music controls |
| Can download audio | No (no media cache access) | Yes (via SyncDelegate + media cache) |

**Source:** [AudioContentProviderApp API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html)

**Implication for YoCasts:** We CANNOT be a "device app that also plays audio." We must either:
1. Build as an `AudioContentProviderApp` (loses normal app launcher presence, lives in music widget only), OR
2. Build two apps — a device app for browsing/UI and an audio content provider for playback, OR
3. Build as a device app with NO native media player integration (handle our own playback UI entirely)

> **⚠️ UNVERIFIED:** Whether a single app can register as both app types simultaneously. Community consensus suggests NO — you must pick one. Needs hardware testing.

### 1.2 AudioContentProviderApp Lifecycle

The app class must override these methods:

```monkeyc
class YoCastsApp extends AudioContentProviderApp {
    // Returns the ContentDelegate for system media player interaction
    function getContentDelegate(args as PersistableType) as ContentDelegate

    // Returns the View for configuring what to sync (playlist selection)
    function getSyncConfigurationView() as [Views] or [Views, InputDelegates]

    // Returns the View for configuring playback options
    function getPlaybackConfigurationView() as [Views] or [Views, InputDelegates]

    // Returns the SyncDelegate for managing downloads
    // DEPRECATED after System 9 — use Communications.SyncDelegate instead
    function getSyncDelegate() as Communications.SyncDelegate or Null
}
```

**Source:** [AudioContentProviderApp API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html)

**Lifecycle flow:**
1. User selects YoCasts from the music widget
2. System calls `getSyncConfigurationView()` → shows UI for selecting episodes to download
3. User triggers sync → system enables Wi-Fi, calls `getSyncDelegate().onStartSync()`
4. App downloads episodes via chained `makeWebRequest()` calls with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO`
5. User starts playback → system calls `getContentDelegate()` → app returns iterator over downloaded content
6. System media player handles actual audio decoding and BT headphone output
7. System notifies app of playback events via `ContentDelegate.onSong()`

### 1.3 Media.ContentDelegate (✅ VERIFIED)

The delegate that responds to playback events from the native media player.

**Methods:**

| Method | Signature | Purpose |
|---|---|---|
| `getContentIterator()` | `() as ContentIterator or Null` | Return iterator for system to traverse tracks |
| `resetContentIterator()` | `() as ContentIterator or Null` | Reset iterator to beginning of playlist |
| `onSong()` | `(contentRefId as Object, songEvent as SongEvent, playbackPosition as Number or PlaybackPosition) as Void` | **THE key callback** — fired on every playback state change |
| `onShuffle()` | `() as Void` | User toggled shuffle |
| `onRepeat()` | `() as Void` | User toggled repeat |
| `onThumbsUp()` | `(contentRefId as Object) as Void` | User liked a track |
| `onThumbsDown()` | `(contentRefId as Object) as Void` | User disliked a track |
| `onCustomButton()` | `(button as CustomButton) as Void` | User pressed a custom button |
| `onAdAction()` | `(adContext as Object) as Void` | User clicked an ad |

**Source:** [ContentDelegate API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentDelegate.html)

**SongEvent values (all ✅ VERIFIED from API docs):**

| Event | Value | Since | Description |
|---|---|---|---|
| `SONG_EVENT_START` | 0 | 3.0.0 | Song started from beginning |
| `SONG_EVENT_SKIP_NEXT` | 1 | 3.0.0 | Skipped to next |
| `SONG_EVENT_SKIP_PREVIOUS` | 2 | 3.0.0 | Skipped to previous |
| `SONG_EVENT_PLAYBACK_NOTIFY` | 3 | 3.0.0 | Played for `playbackNotificationThreshold` seconds |
| `SONG_EVENT_COMPLETE` | 4 | 3.0.0 | Song finished naturally |
| `SONG_EVENT_STOP` | 5 | 3.0.0 | Song stopped mid-playback |
| `SONG_EVENT_PAUSE` | 6 | 3.0.0 | Song paused |
| `SONG_EVENT_RESUME` | 7 | 3.0.0 | Song resumed after pause |
| `SONG_EVENT_SKIP_FORWARD` | 8 | 4.2.4 | Skipped forward by `skipForwardTimeDelta` seconds |
| `SONG_EVENT_SKIP_BACKWARD` | 9 | 4.2.4 | Skipped backward by `skipBackwardTimeDelta` seconds |

**Position tracking via onSong():**
- The `playbackPosition` parameter gives current position in seconds
- Fired on EVERY event — so we get position on pause, skip, stop, complete
- This is how we sync `playedUpTo` back to PocketCasts

### 1.4 Media.ContentIterator (✅ VERIFIED)

A user-defined iterator the system uses to navigate through tracks.

**Methods:**

| Method | Returns | Purpose |
|---|---|---|
| `get()` | `Content or Null` | Current track |
| `next()` | `Content or Null` | Advance and get next track |
| `previous()` | `Content or Null` | Go back and get previous track |
| `peekNext()` | `Content or Null` | Preview next without advancing |
| `peekPrevious()` | `Content or Null` | Preview previous without going back |
| `canSkip()` | `Boolean` | Whether current track is skippable |
| `getPlaybackProfile()` | `PlaybackProfile or Null` | Playback rules for current content |
| `shuffling()` | `Boolean` | Whether shuffle is on |
| `repeatMode()` | `RepeatMode or Null` | Current repeat mode |

**Source:** [ContentIterator API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentIterator.html)

**For podcasts:** We'd implement this as a simple queue iterator. `canSkip()` always returns `true`. No shuffle. `REPEAT_MODE_OFF`. The iterator walks through the downloaded episode queue.

### 1.5 Media.Content and ContentMetadata (✅ VERIFIED)

**Content** wraps a ContentRef + metadata:

```monkeyc
var content = new Media.Content(
    contentRef,   // ContentRef — reference to cached audio
    metadata      // ContentMetadata — display info
);

// Optional: set playback start position (for resume)
content.getPlaybackStartPosition();  // Returns Number (seconds)
```

**ContentMetadata** fields:

| Field | Type | Purpose | Podcast mapping |
|---|---|---|---|
| `title` | `String` | Track title | Episode title |
| `artist` | `String` | Artist name | Podcast name |
| `album` | `String` | Album title | Podcast name (or "Podcasts") |
| `genre` | `String` | Genre | "Podcast" |
| `trackNumber` | `Number` | Track number | Episode index in queue |

**Source:** [ContentMetadata API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentMetadata.html)

### 1.6 Media.ContentRef (✅ VERIFIED)

A reference to a downloaded/cached audio file.

```monkeyc
var ref = new Media.ContentRef(
    id,   // Object — unique identifier (we'd use episode UUID string)
    type  // ContentType — CONTENT_TYPE_AUDIO (value: 1)
);

ref.getId();           // Returns the ID we passed in
ref.getContentType();  // Returns CONTENT_TYPE_AUDIO
```

**Source:** [ContentRef API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentRef.html)

**Key insight:** The `id` parameter is `Lang.Object` — so we can use PocketCasts episode UUIDs as strings directly.

### 1.7 Media.PlaybackProfile (✅ VERIFIED)

Controls the native media player's UI and behavior.

| Property | Type | Default | For Podcasts |
|---|---|---|---|
| `playbackControls` | `Array<PlaybackControl or CustomButton>` | — | `[SKIP_BACKWARD, PLAYBACK, SKIP_FORWARD]` |
| `skipForwardTimeDelta` | `Number or Null` | 30 | 30 (matches PocketCasts) |
| `skipBackwardTimeDelta` | `Number or Null` | 30 | 15 (PocketCasts default) |
| `playbackNotificationThreshold` | `Number or Null` | — | 30 (to record "started playing") |
| `requirePlaybackNotification` | `Boolean or Null` | — | `true` (need position tracking) |
| `skipPreviousThreshold` | `Number or Null` | device-dependent | 3 (quick double-back to go previous) |
| `playerColors` | `PlayerColors or Null` | device-dependent | Custom YoCasts branding colors |
| `attemptSkipAfterThumbsDown` | `Boolean or Null` | — | `false` (not relevant for podcasts) |

**Podcast-specific playback controls:**

```monkeyc
[
    Media.PLAYBACK_CONTROL_SKIP_BACKWARD,  // -30s or -15s
    Media.PLAYBACK_CONTROL_PLAYBACK,       // play/pause
    Media.PLAYBACK_CONTROL_SKIP_FORWARD,   // +30s
    Media.PLAYBACK_CONTROL_PREVIOUS,       // previous episode
    Media.PLAYBACK_CONTROL_NEXT            // next episode
]
```

**Source:** [PlaybackProfile API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/PlaybackProfile.html)

### 1.8 SyncDelegate — Audio Download Mechanism (✅ VERIFIED from Garmin sample code)

**⚠️ DEPRECATION NOTICE:** `Toybox.Media.SyncDelegate` is deprecated after System 9. Use `Toybox.Communications.SyncDelegate` instead. The interface is identical — same three methods.

**SyncDelegate interface:**

| Method | Purpose |
|---|---|
| `isSyncNeeded()` → `Boolean` | System asks if sync is needed. Return `true` if we have episodes queued for download |
| `onStartSync()` → `Void` | System starts sync (Wi-Fi enabled). Begin downloading. |
| `onStopSync()` → `Void` | User cancelled sync. Call `cancelAllRequests()` + `notifySyncComplete()` |

**How sync is triggered (✅ VERIFIED):**
1. System periodically checks `isSyncNeeded()` when the watch is charging or on Wi-Fi
2. User can manually trigger from the sync configuration view
3. **The app can programmatically trigger sync** via `Media.startSync()` — but this is ALSO deprecated after System 9

**⚠️ UNVERIFIED:** Whether there's a non-deprecated replacement for `Media.startSync()` after System 9. This needs SDK testing.

**How audio files are downloaded (✅ VERIFIED from MonkeyMusic sample):**

```monkeyc
// Inside onStartSync():
var options = {
    :method => Communications.HTTP_REQUEST_METHOD_GET,
    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
    :mediaEncoding => Media.ENCODING_MP3  // or ENCODING_M4A, ENCODING_WAV, ENCODING_ADTS
};

Communications.makeWebRequest(audioUrl, null, options, method(:onDownloaded));

// Callback:
function onDownloaded(responseCode, data) {
    // responseCode == 200 → success
    // data is a ContentRef — the system cached the file automatically!
    // data.getId() returns the system-assigned content ref ID
    
    Media.notifySyncProgress(percentComplete);
    // ... chain next download ...
    Media.notifySyncComplete(null);  // null = success, string = error
}
```

**Source:** [Garmin MonkeyMusic SyncDelegate.mc](https://github.com/garmin/connectiq-apps/blob/master/audio-provider/monkeymusic/source/SyncDelegate.mc)

**Key facts from the sample code:**
1. Downloads are **chained manually** — download one file, in the callback start the next
2. No parallel downloads — one at a time, sequentially
3. The `data` parameter in the callback IS a `ContentRef` — the system automatically caches the file encrypted on disk
4. You must call `notifySyncProgress()` periodically or the UI shows no progress
5. You must call `notifySyncComplete(null)` when done, or `notifySyncComplete(errorString)` on failure
6. Song metadata is stored separately in `Application.Properties` (not in the media cache)

### 1.9 Audio Storage (✅ VERIFIED)

| Property | Value | Source |
|---|---|---|
| Storage mechanism | Encrypted, sandboxed per-app | Garmin blog, API docs |
| Encryption | AES-128, written encrypted to disk | Garmin blog |
| Accessible by user via USB? | **No** — hidden, app-specific folders | Forums, blog |
| Accessible by other apps? | **No** — strict sandbox isolation | API docs |
| Total device storage | 8 GB (Venu 4) | Amazon product page |
| Usable for music/audio | ~3.5–4 GB after system files | Community testing |
| Can query cache size? | **Yes** — `Media.getCacheStatistics()` | API docs |
| Cache stats | `capacity` (Long, bytes) + `size` (Long, bytes) | CacheStatistics API |
| Delete individual items | `Media.deleteCachedItem(contentRef)` | API docs |
| Reset entire cache | `Media.resetContentCache()` | API docs |

**Source:** [CacheStatistics API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/CacheStatistics.html)

```monkeyc
var stats = Media.getCacheStatistics();
var capacityMB = stats.capacity / (1024 * 1024);  // Total available in MB
var usedMB = stats.size / (1024 * 1024);           // Currently used in MB
var freeMB = capacityMB - usedMB;
```

### 1.10 Supported Audio Formats (✅ VERIFIED from API docs)

| Format | Constant | Extension | Supported |
|---|---|---|---|
| MP3 | `Media.ENCODING_MP3` | .mp3 | ✅ Yes |
| M4A (AAC) | `Media.ENCODING_M4A` | .m4a | ✅ Yes |
| ADTS (AAC stream) | `Media.ENCODING_ADTS` | .aac, .adts | ✅ Yes |
| WAV | `Media.ENCODING_WAV` | .wav | ✅ Yes |
| OGG | — | .ogg | ❌ **Not supported** |
| M4B (audiobook) | — | .m4b | ✅ Supported by device, but no SDK constant |

**Source:** [Toybox.Media constants](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media.html)

**For PocketCasts:** Most podcast episodes are MP3. Some newer ones are M4A/AAC. We need our proxy to report the encoding type so we can set `:mediaEncoding` correctly.

### 1.11 How Spotify/Deezer/Amazon Music Work (✅ VERIFIED)

All three use the same pattern:
1. **AudioContentProviderApp** — registered in music widget
2. **OAuth via Garmin Connect Mobile** — user authenticates on phone, token stored on watch
3. **Sync over Wi-Fi only** — playlists selected via sync config view, downloaded when charger/Wi-Fi available
4. **SyncDelegate chains makeWebRequest()** calls for each track
5. **No live streaming** — all content must be pre-downloaded
6. **Encrypted storage** — files stored encrypted, only decrypted in memory during playback
7. **~500 MB cap** typically enforced (varies by provider agreement with Garmin)

**This confirms our architecture.** YoCasts would follow the exact same pattern.

### 1.12 Can makeWebRequest() Download Audio Outside SyncDelegate?

**⚠️ CRITICAL:** The `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` response type for `makeWebRequest()` is specifically designed for use within the sync flow. Using it:
- Causes the system to write the response directly to the encrypted media cache
- Returns a `ContentRef` (not raw data) in the callback
- Bypasses the normal ~32-100KB response size limit because the data streams to disk, not memory

**Outside of SyncDelegate context (e.g., in a regular device app):**
- Community reports indicate `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` may still work, but behavior is inconsistent
- Some devices return `-1002 UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE`
- The intended and reliable path is SyncDelegate

**Conclusion:** Audio downloads MUST go through the SyncDelegate mechanism for reliability.

---

## 2. Background Services

### 2.1 ServiceDelegate (✅ VERIFIED)

Background services use `System.ServiceDelegate`. The background process runs in a **separate, memory-constrained environment** from the main app.

```monkeyc
(:background)
class YoCastsServiceDelegate extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // Triggered by registered temporal event
        // Do work here (HTTP request, data processing)
        // MUST call Background.exit(data) when done
    }
}
```

**The app class must provide the delegate:**
```monkeyc
function getServiceDelegate() as Array<System.ServiceDelegate> {
    return [new YoCastsServiceDelegate()];
}
```

**Source:** [ServiceDelegate API](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/ServiceDelegate.html)

### 2.2 Memory Limits (✅ VERIFIED)

| Property | Value | Source |
|---|---|---|
| Background memory limit (Venu 4) | 64 KB | Device spec sheet |
| What counts toward limit | **Everything:** compiled code, global vars, AppBase overhead, static data, heap allocations | Forums |
| System overhead | ~4-6 KB reserved by VM (actual usable ~58-60 KB) | Forums |
| `(:background)` annotation | Required on classes/functions used in background | SDK docs |
| Global variables | ALL globals count, even if not used in background code | Forums (confirmed by Garmin engineers) |
| Peak memory matters | If a web request response temporarily spikes memory, that counts | Forums |

**Key optimization strategies:**
1. Mark background classes with `(:background)` annotation — only annotated code is loaded
2. Minimize global state — every global variable consumes background memory even if unused in background
3. Keep web request responses small — parse and discard immediately
4. Use `Background.exit(data)` to pass results to foreground — data must be serializable (String, Number, Float, Boolean, Array, Dictionary)

### 2.3 Temporal Events (✅ VERIFIED)

```monkeyc
// Register for periodic wake-up (in foreground app code):
Background.registerForTemporalEvent(new Time.Duration(5 * 60));  // Every 5 minutes

// Or at a specific time:
Background.registerForTemporalEvent(someMoment);
```

| Property | Value | Source |
|---|---|---|
| Minimum interval | **5 minutes** between temporal events | API docs (verified: "cannot be set to occur less than 5 minutes after the last temporal event") |
| Max simultaneous events | **1** — registering overwrites previous | API docs |
| Past-time behavior | Triggers immediately | API docs |
| Precision | Not guaranteed — may drift | Community reports |
| Persistence | Survives app exit; cleared on reboot | API docs |
| 5-minute restriction reset | Cleared on app startup (for Moment-based events only) | API docs |

**Source:** [Background.registerForTemporalEvent()](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)

### 2.4 What Can Background Services Do? (✅ VERIFIED)

| Capability | Available? | Notes |
|---|---|---|
| `makeWebRequest()` | ✅ Yes | But response must fit in 64KB memory |
| `Application.Storage` read/write | ✅ Yes | Shared with foreground app |
| `Application.Properties` read | ✅ Yes | Read-only from background |
| `Background.exit(data)` | ✅ Yes, required | Pass data to foreground |
| `Background.requestApplicationWake()` | ✅ Yes | Shows confirmation dialog to user |
| UI operations | ❌ No | No views, no drawing, no user interaction |
| Media module access | ❌ No | Cannot trigger sync or playback |
| Timer.Timer | ❌ No | Not available in background |
| Sensor access | ❌ No | Not available in background |

### 2.5 Background ↔ Foreground Communication (✅ VERIFIED)

```monkeyc
// BACKGROUND: Pass data when exiting
Background.exit({"newEpisodes" => 3, "lastSync" => Time.now().value()});

// FOREGROUND: Receive data
function onBackgroundData(data) as Void {
    // Called when background process exits
    // data is whatever was passed to Background.exit()
    var newEps = data["newEpisodes"];
    // Update UI, trigger refresh, etc.
}
```

**Data size limit:** There's an `ExitDataSizeLimitException` if the data passed to `exit()` is too large. Keep it small — metadata only, not full episode lists.

### 2.6 Can Background Services Trigger SyncDelegate?

**❌ NO.** Background services cannot access the Media module. They cannot call `Media.startSync()` or interact with the SyncDelegate. The sync flow is triggered by:
1. The system automatically (when charging + Wi-Fi)
2. The user manually via the sync configuration view
3. `Media.startSync()` from the foreground app (deprecated after System 9)

**For YoCasts:** Background services can be used for metadata sync (fetching new episode lists, pushing playback positions), but NOT for downloading audio.

---

## 3. Power Management

### 3.1 Battery Level API (✅ VERIFIED)

```monkeyc
var stats = System.getSystemStats();
stats.battery;       // Float — percentage (0.0–100.0)
stats.charging;      // Boolean — true if on charger (API 3.0.0+)
stats.batteryInDays; // Float — estimated days remaining (API 3.3.0+, device-dependent)
```

**Source:** [System.Stats API](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/Stats.html)

**Quirks:**
- Battery may report 97-99% immediately after removing from charger (Garmin intentionally doesn't show 100% to protect battery longevity)
- Newer devices may truncate decimal precision
- `batteryInDays` not available on all devices — check for `null`

### 3.2 Charging State Detection (✅ VERIFIED)

```monkeyc
var isCharging = System.getSystemStats().charging;
```

**Available since API 3.0.0.** This is reliable for our use case:
- When `charging == true` AND `connectionAvailable == true` → ideal time for large downloads
- Use this as a trigger condition in the sync configuration view

### 3.3 Power Impact of Periodic Operations

| Operation | Battery Impact | Recommendation |
|---|---|---|
| Wi-Fi scan + connect | **High** (~1-2% per connection cycle) | Only connect when needed |
| Wi-Fi data transfer | **Medium** while active | Batch operations, minimize connections |
| Bluetooth proxy HTTP | **Low-Medium** | Good for small metadata syncs |
| Background temporal event | **Very Low** | 5-minute minimum interval is fine |
| `Application.Storage` read/write | **Negligible** | No concerns |
| GPS | **Very High** | Not relevant for our app |
| Always-On Display | **High** | Not under app control |

### 3.4 Best Practices for Power-Efficient Syncing

1. **Prefer charging + Wi-Fi for audio downloads** — check `charging && connectionAvailable && !phoneConnected` (Wi-Fi direct)
2. **Use temporal events sparingly** — 15-30 minute intervals for metadata polling, not 5 minutes
3. **Batch metadata syncs** — push all position changes in one request, not per-episode
4. **Abort early if battery low** — check `battery < 20.0` before starting downloads
5. **Wi-Fi is a finite resource** — the system may disable it after a timeout; complete downloads promptly

### 3.5 Does Garmin Kill Power-Hungry Apps?

**No explicit kill mechanism documented** for power usage, BUT:
- Garmin's Connect IQ app review guidelines will reject apps with excessive battery drain
- The 5-minute minimum for temporal events is itself a power guardrail
- Background services that don't call `exit()` within a reasonable time will be killed
- Users can uninstall apps; Garmin's support page specifically mentions "uninstall recent CIQ apps" as a battery troubleshooting step

---

## 4. Communications.makeWebRequest() for Large Files

### 4.1 Response Size Limits (✅ VERIFIED from forums + testing)

| Context | Response Size Limit | Source |
|---|---|---|
| Normal `makeWebRequest()` (JSON/text) | **~16-100 KB** device-dependent | Forums, community testing |
| Epix 2 Pro | ~44 KB | Forum report |
| Fenix 7 Pro | ~32 KB | Forum report |
| Older devices | ~16 KB | Forum report |
| Venu 4 (estimated) | ~32-64 KB | Extrapolated from similar gen devices |
| Error code when exceeded | `-402 (RESPONSE_SIZE_EXCEEDED)` | API docs |
| During SyncDelegate (audio) | **No practical limit** (streams to disk) | Verified from MonkeyMusic sample |

**Source:** [Garmin Forums — makeWebRequest limits](https://forums.garmin.com/developer/connect-iq/i/bug-reports/request-for-documentation-and-simulator-accuracy-on-makewebrequest-limits)

### 4.2 Can We Download MP3s (20-50MB) Directly?

**Via normal makeWebRequest():** ❌ **Absolutely not.** Response size limit is 16-100KB.

**Via SyncDelegate with HTTP_RESPONSE_CONTENT_TYPE_AUDIO:** ✅ **Yes!** This is the designed mechanism. The response streams directly to the encrypted media cache on disk, bypassing the normal response size limit. This is exactly how Spotify, Deezer, etc. download tracks.

### 4.3 Chunked/Streaming Downloads

| Feature | Supported? | Notes |
|---|---|---|
| HTTP chunked transfer encoding | ❌ Not reliably | May cause errors on some devices |
| HTTP Range requests (resume) | ❌ Not supported by SDK | No way to specify Range headers reliably |
| Resume interrupted downloads | ❌ Not supported | Must restart from beginning |
| Parallel downloads | ❌ Not supported | Must chain sequentially |
| Download timeout | ⚠️ Undocumented | System may cancel long-running syncs |

### 4.4 Response Content Types Available

| Constant | Value | Purpose |
|---|---|---|
| `HTTP_RESPONSE_CONTENT_TYPE_JSON` | — | Parse response as JSON Dictionary |
| `HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN` | — | Return response as String |
| `HTTP_RESPONSE_CONTENT_TYPE_URL_ENCODED` | — | Parse URL-encoded form data |
| `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` | — | Stream to media cache, return ContentRef |
| `HTTP_RESPONSE_CONTENT_TYPE_FIT` | — | FIT file format (activity data) |

### 4.5 Critical: mediaEncoding Option

When using `HTTP_RESPONSE_CONTENT_TYPE_AUDIO`, you MUST specify the encoding:

```monkeyc
var options = {
    :method => Communications.HTTP_REQUEST_METHOD_GET,
    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
    :mediaEncoding => Media.ENCODING_MP3  // REQUIRED!
};
```

If `:mediaEncoding` doesn't match the actual file format, playback will fail silently or the download will error.

---

## 5. Application.Storage Limits

### 5.1 Verified Limits

| Property | Value | Source |
|---|---|---|
| Total storage per app | **Device-dependent, ~128-256 KB estimated** for Venu 4 | Garmin docs (not published exactly) |
| Per-key size limit | **Not strictly documented** | API docs say "varies" |
| Community-reported per-key max | ~32 KB on most modern devices | Forum testing |
| Persists across app updates? | ✅ **Yes** (unless app uninstalled or data cleared) | API docs |
| Persists across reboots? | ✅ **Yes** | API docs |
| Persists across firmware updates? | ✅ **Yes** (usually) | Community reports |
| Accessible from background? | ✅ **Yes** — both read and write | API docs |
| Thread safety | ✅ Cooperative multitasking — no race conditions | API docs |

**Source:** [Application.Storage API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)

### 5.2 Performance Characteristics

- Storage operations are synchronous and blocking
- Read/write speed is fast enough for frequent position saves (multiple times per second if needed)
- No performance concerns for our use case (position saves every 5-30 seconds)
- Large values (approaching 32KB) may take slightly longer to read/write

### 5.3 Value Types Supported

Storage accepts `Application.Storage.ValueType`:
- `String`, `Number`, `Float`, `Boolean`, `Long`, `Double`, `Char`
- `Array` containing any of the above
- `Dictionary<KeyType, ValueType>` where KeyType is `String`, `Number`, or `Symbol`

> **⚠️ GOTCHA (from our own experience):** Unparameterized `Dictionary` values fail strict mode. Must cast with `as Application.Storage.ValueType`.

---

## 6. Connectivity Detection

### 6.1 DeviceSettings Properties (✅ VERIFIED)

```monkeyc
var settings = System.getDeviceSettings();
```

| Property | Type | Meaning |
|---|---|---|
| `connectionAvailable` | `Boolean` | `true` if ANY internet path exists (Wi-Fi OR BT proxy) |
| `phoneConnected` | `Boolean` | `true` if phone paired and reachable via Bluetooth |
| `connectionInfo` | `Dictionary<Symbol, ConnectionInfo>` | Per-connection-type state details |

**Source:** [DeviceSettings API](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/DeviceSettings.html)

### 6.2 connectionInfo Deep Dive (✅ VERIFIED)

The `connectionInfo` dictionary contains entries keyed by `:bluetooth`, `:wifi`, and `:lte` (if supported):

```monkeyc
var connInfo = settings.connectionInfo;

if (connInfo.hasKey(:wifi)) {
    var wifiInfo = connInfo[:wifi];
    // wifiInfo.state == CONNECTION_STATE_CONNECTED means Wi-Fi is active
}

if (connInfo.hasKey(:bluetooth)) {
    var btInfo = connInfo[:bluetooth];
    // btInfo.state == CONNECTION_STATE_CONNECTED means BT is active
}
```

**ConnectionState values:**

| Constant | Value | Meaning |
|---|---|---|
| `CONNECTION_STATE_NOT_INITIALIZED` | 0 | Connection not setup or inactive |
| `CONNECTION_STATE_NOT_CONNECTED` | 1 | Setup but not in range |
| `CONNECTION_STATE_CONNECTED` | 2 | Available for use |

**Source:** [System.ConnectionInfo API](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/ConnectionInfo.html), [ConnectionState constants](https://developer.garmin.com/connect-iq/api-docs/Toybox/System.html)

### 6.3 Wi-Fi vs Bluetooth Detection (✅ VERIFIED)

**Yes, we CAN distinguish Wi-Fi from Bluetooth!** Using `connectionInfo`:

```monkeyc
function getConnectivityState() as Symbol {
    var settings = System.getDeviceSettings();
    var connInfo = settings.connectionInfo;

    var wifiConnected = false;
    var btConnected = false;

    if (connInfo.hasKey(:wifi)) {
        wifiConnected = (connInfo[:wifi].state == System.CONNECTION_STATE_CONNECTED);
    }
    if (connInfo.hasKey(:bluetooth)) {
        btConnected = (connInfo[:bluetooth].state == System.CONNECTION_STATE_CONNECTED);
    }

    if (wifiConnected) {
        return :wifi;        // Best — can do large downloads
    } else if (btConnected && settings.connectionAvailable) {
        return :bluetooth;   // Good for metadata sync
    } else {
        return :offline;     // Cache only
    }
}
```

### 6.4 Connectivity Change Callbacks

**❌ NO system callback exists for connectivity changes.** You must poll.

**Polling strategies:**
1. **In views:** Check in `onUpdate()` (called every screen refresh) — essentially free
2. **Timer-based:** Use `Timer.Timer` to check every 30-60 seconds
3. **Before operations:** Check right before making any HTTP request
4. **In background service:** Check in `onTemporalEvent()` every 5-15 minutes

### 6.5 How Quickly Does connectionAvailable Update?

**⚠️ UNVERIFIED exact latency.** Community reports suggest:
- Wi-Fi connect/disconnect: reflects within 1-5 seconds
- Bluetooth connect/disconnect: reflects within 5-15 seconds
- Polling every 30 seconds is sufficient for our use case

---

## 7. Architecture Implications for YoCasts

### 7.1 The App Type Problem

**This is the biggest architectural decision.** We have three options:

#### Option A: Pure AudioContentProviderApp
- ✅ Full media player integration, native playback UI
- ✅ Proper SyncDelegate for reliable audio downloads
- ✅ How Spotify/Deezer do it
- ❌ App only accessible from music widget, not app list
- ❌ Limited UI options — sync config view + playback config view only
- ❌ Cannot have our custom home menu, queue browsing, etc.

#### Option B: Two Separate Apps
- ✅ Device app for full UI (queue, podcasts, browsing)
- ✅ Audio content provider for downloads and playback
- ❌ Complex — two apps to maintain, need inter-app communication
- ❌ User confusion — two separate app entries
- ❌ May not be possible to share data between apps reliably

#### Option C: Device App with Manual Audio (NO native media player)
- ✅ Full control over UI and UX
- ✅ Single app in app list
- ❌ Cannot use SyncDelegate — no reliable way to download large audio files
- ❌ Must implement our own playback UI (we already have NowPlayingView)
- ❌ Cannot use native media player's BT headphone routing
- ❌ May not be able to play audio at all without Media module (device app type doesn't have media permissions)

**⚠️ RECOMMENDATION: Option A is the most viable.** All successful podcast/music apps on Garmin use this pattern. The limited UI surface (sync config + playback config views) is actually sufficient for podcast apps — sync config IS our "select episodes to download" screen, and playback config IS our "now playing" options.

### 7.2 The SyncDelegate Deprecation Problem

`Media.SyncDelegate` and `Media.startSync()` are deprecated after System 9. The replacement `Communications.SyncDelegate` has the same interface but:
- It's unclear if `Media.startSync()` has a replacement for programmatic sync triggering
- The system may rely more on automatic sync (when charging + Wi-Fi)
- We should implement `Communications.SyncDelegate` now for future-proofing

### 7.3 Proposed Download Flow

```
User selects "Download" on an episode
    → App marks episode in sync list (Application.Storage key "sync_list")
    → isSyncNeeded() returns true
    → System enables Wi-Fi when conditions are right (charging, Wi-Fi available)
    → System calls onStartSync()
        → App fetches episode audio URL from PocketCasts API
        → makeWebRequest(url, null, {AUDIO, MP3}, callback)
        → Callback receives ContentRef
        → Store ContentRef ID + episode metadata in Application.Storage
        → notifySyncProgress(%)
        → Chain next download
        → notifySyncComplete(null)
    → Files are now in encrypted media cache
    → ContentIterator serves them for playback
```

### 7.4 Playback Position Sync Flow

```
System media player calls onSong(contentRefId, SONG_EVENT_PAUSE, position)
    → Map contentRefId back to episode UUID (via stored mapping)
    → Write position to Application.Storage
    → If connected, push to PocketCasts via /sync/update_episode
    → If offline, add to changelog for later sync
```

### 7.5 Storage Budget (Revised)

| Data | Key | Size | Purpose |
|---|---|---|---|
| Sync list | `"sync_list"` | ~2 KB | Episodes queued for download |
| Downloaded songs map | `"songs"` | ~5 KB | ContentRef ID → episode UUID mapping |
| Playback positions | `"positions"` | ~2 KB | UUID → position for all tracked episodes |
| Offline changelog | `"changelog"` | ~5 KB | Pending sync operations |
| Auth tokens | `"auth"` | ~1 KB | PocketCasts credentials |
| Podcast metadata cache | `"podcasts"` | ~6 KB | Subscription list |
| Queue cache | `"queue"` | ~5 KB | Up Next episodes |
| **Total** | | **~26 KB** | Well within limits |

Audio files stored separately in encrypted media cache (3.5-4 GB available).

---

## Sources

### Official Garmin Documentation
- [Toybox.Media Module](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media.html)
- [Media.ContentDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentDelegate.html)
- [Media.SyncDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/SyncDelegate.html)
- [Communications.SyncDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications/SyncDelegate.html)
- [Media.ContentIterator](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentIterator.html)
- [Media.ContentRef](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentRef.html)
- [Media.PlaybackProfile](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/PlaybackProfile.html)
- [Media.ContentMetadata](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentMetadata.html)
- [Media.CacheStatistics](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/CacheStatistics.html)
- [AudioContentProviderApp](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html)
- [Toybox.Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- [System.ServiceDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/ServiceDelegate.html)
- [System.Stats](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/Stats.html)
- [System.DeviceSettings](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/DeviceSettings.html)
- [System.ConnectionInfo](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/ConnectionInfo.html)
- [Application.Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)

### Garmin Sample Code
- [MonkeyMusic SyncDelegate.mc](https://github.com/garmin/connectiq-apps/blob/master/audio-provider/monkeymusic/source/SyncDelegate.mc) — canonical audio download implementation

### Garmin Blog / Articles
- [Creating Music Apps in Connect IQ 3](https://www.garmin.com/en-US/blog/developer/creating-music-apps-3x/)
- [How to Improve App Performance](https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/)
- [Audio File Type Support](https://support.garmin.com/en-US/?faq=JyNEOTsZaR3KMXqej3oQp5)

### Community / Forums
- [makeWebRequest Response Limits](https://forums.garmin.com/developer/connect-iq/i/bug-reports/request-for-documentation-and-simulator-accuracy-on-makewebrequest-limits)
- [Background Memory Discussion](https://forums.garmin.com/developer/connect-iq/f/discussion/308901/background-and-memory)
- [Connectivity Detection](https://forums.garmin.com/developer/connect-iq/f/discussion/359127/how-do-i-check-if-the-watch-is-connected-to-the-phone---watch-app)
- [HTTP_RESPONSE_CONTENT_TYPE_AUDIO Issues](https://forums.garmin.com/developer/connect-iq/f/discussion/292336/makewebrequest-with-http_response_content_type_audio-fails-with-unsupported_content_type_in_response)
