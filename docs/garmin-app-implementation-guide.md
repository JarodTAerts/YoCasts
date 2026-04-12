# YoCasts — Garmin Connect IQ Implementation Guide

> Blueprint for building a PocketCasts client on Garmin wearables.
> Written for Kaylee (implementation) and Wash (API/comms layer).
>
> **Last Updated:** 2026-04-14  
> **v2.0 changes:** Updated architecture to reflect actual implementation — IPodcastService interface, CachedPodcastService decorator, CacheManager module. Corrected connectivity model (Wi-Fi direct + BT, no proxy needed). Updated build phases with completion status. Updated file structure to match actual source tree.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Garmin Connect IQ Constraints](#2-garmin-connect-iq-constraints)
3. [Required API Surface](#3-required-api-surface)
4. [Data Flow Architecture](#4-data-flow-architecture)
5. [UI Screens & Navigation](#5-ui-screens--navigation)
6. [Offline & Caching Strategy](#6-offline--caching-strategy)
7. [Build Phases](#7-build-phases)

---

## 1. Architecture Overview

### 1.1 Platform Summary

YoCasts is a **Garmin Connect IQ app** written in **Monkey C**. It runs on the **Garmin Venu 4 41mm** (390×390, round AMOLED, 768 KB memory) and communicates with the PocketCasts API directly via `Communications.makeWebRequest()` — over Wi-Fi (direct to internet) or Bluetooth (proxied through the paired phone).

The existing Tizen/Xamarin app in `PodcastApp/` serves as the functional reference. The Garmin app will replicate its core feature set — login, view subscribed podcasts, browse episodes, and manage a queue — adapted for Garmin's hardware and interaction model.

### 1.2 App Type

Use a **Connect IQ App** (not a widget, watch face, or data field). Apps have the richest UI and lifecycle capabilities and are the only app type that supports multi-screen navigation and sustained network communication.

### 1.3 Core Architecture Components

```
┌──────────────────────────────────────────────┐
│  YoCastsApp (extends Application.AppBase)    │
│  ─ Lifecycle: onStart, getInitialView, onStop│
│  ─ Owns global state (service instance)      │
│  ─ Selects service via useMockData property  │
└──────────┬───────────────────────────────────┘
           │ returns initial View + Delegate
           ▼
┌──────────────────────────────────────────────┐
│  Views (extend WatchUi.View or WatchUi.Menu2)│
│  ─ HomeMenuView (custom split-dock design)   │
│  ─ QueueView (Menu2 — episode queue)         │
│  ─ SubscribedView (Menu2 — podcast list)     │
│  ─ EpisodeListView (Menu2 — per-podcast)     │
│  ─ NowPlayingView (custom full-screen view)  │
│  ─ SettingsView (account status, demo toggle)│
│  ─ LoginPromptView (login + skip/demo mode)  │
└──────────┬───────────────────────────────────┘
           │ calls service via IPodcastService
           ▼
┌──────────────────────────────────────────────┐
│  IPodcastService (interface)                 │
│  ─ Sync getters: getQueue, getPodcasts, etc. │
│  ─ Async: fetchAll, requestEpisodesForPodcast│
│  ─ State: isAuthenticated, isDataReady       │
├──────────────────────────────────────────────┤
│  Implementations:                            │
│  ┌─ MockPodcastService (demo data)           │
│  ┌─ CachedPodcastService (decorator)         │
│  │  └─ wraps PocketCastsPodcastService       │
│  │     ─ Real API via makeWebRequest         │
│  │     ─ Auth token lifecycle management     │
│  │     ─ JSON → Dictionary parsing           │
│  └─ CacheManager (Application.Storage module)│
│     ─ "yc_" key prefix                       │
│     ─ cachedAt timestamps                    │
│     ─ TTL-based revalidation hints           │
└──────────────────────────────────────────────┘
```

### 1.4 App Lifecycle

| Event | Method | What YoCasts Does |
|---|---|---|
| App launch | `onStart(state)` | Load cached auth token and data from `Application.Storage` |
| Initial UI | `getInitialView()` | Return `MainMenuView` + delegate if authenticated; `LoginPromptView` + delegate if not |
| App exit | `onStop(state)` | Persist any dirty cache to `Application.Storage` |
| Settings changed | `onSettingsChanged()` | Re-read any app settings (future use) |

### 1.5 File / Module Organization

```
YoCastsGarmin/
├── source/
│   ├── YoCastsApp.mc                      # AppBase subclass, lifecycle, service toggle
│   ├── models/
│   │   └── DataModels.mc                  # Dictionary keys / constants for podcast/episode data
│   ├── services/
│   │   ├── IPodcastService.mc             # Interface — sync getters + async fetch methods
│   │   ├── MockPodcastService.mc          # Demo data (useMockData = true)
│   │   ├── PocketCastsPodcastService.mc   # Real API via makeWebRequest
│   │   ├── CachedPodcastService.mc        # Cache-first decorator (TTL revalidation)
│   │   └── CacheManager.mc               # Application.Storage wrapper ("yc_" prefix)
│   └── views/
│       ├── HomeMenuView.mc                # Custom View — split-dock (pills + Now Playing dock)
│       ├── MainMenuView.mc                # (legacy — being replaced by HomeMenuView)
│       ├── QueueView.mc                   # Menu2 — episode queue
│       ├── SubscribedView.mc              # Menu2 — subscribed podcasts
│       ├── EpisodeListView.mc             # Menu2 — episodes for a podcast
│       ├── NowPlayingView.mc              # Custom View — full-screen playback
│       ├── LoginPromptView.mc             # Auth prompt + skip button (demo mode)
│       └── SettingsView.mc                # In-app settings (account, demo toggle)
├── resources/
│   ├── strings/strings.xml                # User-facing strings
│   ├── settings/settings.xml              # Phone-side settings definitions
│   ├── settings/properties.xml            # Property definitions
│   └── drawables/                         # Icons, launcher icon
├── manifest.xml
└── monkey.jungle                          # Build configuration
```

---

## 2. Garmin Connect IQ Constraints

### 2.1 Memory Limits (Venu 4 41mm)

| Constraint | Value | Impact |
|---|---|---|
| App runtime memory | 768 KB | Generous — room for richer features |
| Background memory | 64 KB | For background service / temporal events |
| Storage per value | 32 KB max per key | Break large data into multiple keys |
| Total app storage | ~128–256 KB estimated | Cache essential data with `CacheManager` |

### 2.2 HTTP via makeWebRequest

Garmin watches use `Communications.makeWebRequest()` for all HTTP requests. On the **Venu 4**, this works over **two** transports:

1. **Wi-Fi Direct** — The watch connects directly to the internet via a known Wi-Fi network (no phone needed).
2. **Bluetooth Proxy** — The phone's Garmin Connect Mobile app proxies the request over the phone's internet connection.

```
Watch App  ──Wi-Fi──►  Internet  ──►  PocketCasts API
                   OR
Watch App  ──BLE──►  Phone (GCM)  ──►  Internet  ──►  PocketCasts API
```

Implications:

- **Phone is NOT required when Wi-Fi is available.** The watch can sync, fetch data, and download episodes independently.
- **HTTPS only** — `http://` URLs return error `-1001` (`SECURE_CONNECTION_REQUIRED`).
- **Response must be JSON** — HTML responses cause parse errors. The API returns JSON, so this is fine.
- **Asynchronous only** — `makeWebRequest` is callback-based, not blocking.
- **Rate limits** — Garmin may throttle excessive requests. Batch when possible.
- **Three connectivity states** — Wi-Fi direct, Phone BT, Fully offline. See `offline-sync-design.md` for detection logic.

### 2.3 Monkey C Data Types

| Type | Notes |
|---|---|
| `Number` | 32-bit integer |
| `Long` | 64-bit integer (not all devices) |
| `Float` | 32-bit IEEE 754 |
| `Double` | 64-bit IEEE 754 (not all devices) |
| `String` | Immutable, UTF-8 |
| `Boolean` | `true` / `false` |
| `Array` | Dynamic, mixed-type. Watch memory limits apply. |
| `Dictionary` | String keys → any value. Primary way to handle JSON. |
| `ByteArray` | For binary data |
| `Symbol` | Enum-like identifiers (`:mySymbol`) |

**No classes for data models** in the Java/C# sense. Use `Dictionary` instances with well-known string keys. This is how `makeWebRequest` delivers parsed JSON anyway.

### 2.4 Execution Model

- **Single-threaded.** No background threads. All work happens in callbacks.
- **No blocking operations.** Long-running work will be killed by the system.
- **Timer-based periodic work** via `Timer.Timer` for polling or refresh.

### 2.5 Screen Sizes

Garmin watches have round or rectangular displays, typically 240×240 to 454×454 pixels. Use `Menu2` for lists — it handles layout and scrolling for all screen shapes automatically.

---

## 3. Required API Surface

Based on the existing Tizen app's `PocketCastsApiAccessorcs.cs`, the following PocketCasts API endpoints are needed:

### 3.1 Authentication

There are **two** login endpoints. YoCasts uses the modern one:

**Primary — `POST /user/login_pocket_casts`** (recommended)

| | |
|---|---|
| **Endpoint** | `POST https://api.pocketcasts.com/user/login_pocket_casts` |
| **Headers** | `Content-Type: application/json`, `Origin: https://play.pocketcasts.com` |
| **Body** | `{ "email": "<email>", "password": "<password>" }` |
| **Response** | `{ "accessToken": "<jwt>", "refreshToken": "<jwt>", "expiresIn": 3600, "tokenType": "Bearer", "uuid": "<user-uuid>", "email": "<email>" }` |
| **On Garmin** | Credentials entered via Garmin Connect Mobile settings (phone-side). Tokens stored in `Application.Storage`. |

**Token Refresh — `POST /user/token`**

| | |
|---|---|
| **Endpoint** | `POST https://api.pocketcasts.com/user/token` |
| **Headers** | `Content-Type: application/json` (NO Authorization header) |
| **Body** | `{ "grantType": "refresh_token", "refreshToken": "<saved_refresh_token>" }` |
| **Response** | Same as login — returns new `accessToken` + new `refreshToken` |

> ⚠️ **Token refresh was initially broken** because we sent an empty body `{}` with a Bearer header. The fix: send `grantType` + `refreshToken` in the body, no Authorization header.

**Legacy — `POST /user/login`** (still works, returns only a simple `token` field — no refresh token)

**Important:** Users should NOT type credentials on the watch. Use `Application.Properties` to accept email/password from the Garmin Connect Mobile app's settings page.

### 3.2 Get Subscribed Podcasts

| | |
|---|---|
| **Endpoint** | `POST https://api.pocketcasts.com/user/podcast/list` |
| **Headers** | `Authorization: Bearer <token>`, `Content-Type: application/json` |
| **Body** | `{}` |
| **Response** | `{ "podcasts": [ { "uuid", "title", "author", "description", "url", "lastEpisodePublished", "unplayed", "lastEpisodeUuid" }, ... ] }` |
| **Watch needs** | `uuid`, `title`, `author` (display only). Cache the list. |

### 3.3 Get Episodes for a Podcast

| | |
|---|---|
| **Endpoint** | `POST https://api.pocketcasts.com/user/podcast/episodes` |
| **Headers** | `Authorization: Bearer <token>`, `Content-Type: application/json` |
| **Body** | `{ "uuid": "<podcast-uuid>" }` |
| **Response** | `{ "episodes": [ { "uuid", "playingStatus", "playedUpTo", "isDeleted", "starred", "duration" }, ... ] }` |
| **Watch needs** | `uuid`, `duration`, `playedUpTo`. **Note:** This endpoint returns a **minimal** schema — no titles, URLs, or dates. Full metadata requires per-episode `POST /user/episode` calls. |

### 3.4 Get Queue (Up Next)

| | |
|---|---|
| **Endpoint** | `POST https://api.pocketcasts.com/up_next/list` |
| **Headers** | `Authorization: Bearer <accessToken>`, `Content-Type: application/json` |
| **Body** | `{}` |
| **Response** | `{ "serverModified": "<timestamp>", "order": ["<uuid>", ...], "episodes": { "<uuid>": { "title": "...", "url": "...", "podcast": "<podcast-uuid>" } } }` |
| **Watch needs** | Iterate `order` array, look up each UUID in `episodes` map. The queue is a **map keyed by episode UUID**, not an array. |

> ⚠️ **`/user/new_releases`** returns new/unplayed episodes from subscriptions — this is NOT the user's curated queue. The real queue is `/up_next/list`.

### 3.5 Data We Do NOT Need on Watch (MVP)

- Episode audio URLs (no playback on watch in MVP)
- Episode file sizes / file types
- Podcast descriptions (too much text for watch screen)
- Download queue management (Tizen feature, not needed for MVP)

### 3.6 API Notes

- All endpoints use `POST` with JSON bodies.
- The `Origin` header (`https://play.pocketcasts.com`) is required — include it via `makeWebRequest` options.
- Auth tokens are JWT with OAuth2-style refresh. Handle `401` responses by attempting token refresh via `/user/token`, then re-login as fallback.
- These endpoints were reverse-engineered and may change. Build the API layer so endpoint URLs and parsing logic are isolated in `PocketCastsService.mc`.

---

## 4. Data Flow Architecture

### 4.1 Request Flow

```
┌─────────┐        ┌──────────────────┐        ┌──────────────────┐
│  View   │───────▶│ IPodcastService  │───────▶│  PocketCasts API │
│ Delegate│ calls  │ (CachedPodcast   │ makes  │  (HTTPS)         │
│         │ sync   │  Service wraps   │ Web    │                  │
│         │ getter │  PocketCasts     │ Req    │                  │
│         │        │  PodcastService) │ via    │                  │
│         │        │                  │ Wi-Fi  │                  │
│         │        │                  │ or BT  │                  │
└─────────┘        └──────┬──────────┘        └──────────────────┘
                          │                           │
                          │◀──── callback ────────────┘
                          │
                   ┌──────▼──────┐
                   │ Parse JSON  │
                   │ Update Cache│ (via CacheManager)
                   │ Notify View │ (requestUpdate)
                   └─────────────┘
```

### 4.2 makeWebRequest Call Pattern

```monkeyc
function fetchQueue() {
    var url = "https://api.pocketcasts.com/up_next/list";
    var params = {};  // query params (none needed)
    var options = {
        :method => Communications.HTTP_REQUEST_METHOD_POST,
        :headers => {
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
            "Authorization" => "Bearer " + _accessToken,
            "Origin" => "https://play.pocketcasts.com"
        },
        :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
    };
    var body = {};  // POST body

    Communications.makeWebRequest(url, body, options, method(:onQueueResponse));
}

function onQueueResponse(responseCode, data) {
    if (responseCode == 200 && data != null) {
        // Up Next uses map structure: { order: [...], episodes: { uuid: {...} } }
        var order = data["order"];
        var episodes = data["episodes"];
        CacheManager.saveQueue(data);
        WatchUi.requestUpdate();
    } else if (responseCode == 401) {
        // Token expired — try refresh, then re-login
        refreshToken();
    } else {
        // Network error — fall back to cached data
    }
}
```

### 4.3 Authentication Flow

```
1. User installs app via Connect IQ Store
2. User opens Garmin Connect Mobile → App Settings → YoCasts
3. User enters PocketCasts email and password in settings fields
4. App reads credentials via Application.Properties on next launch
5. App calls POST /user/login_pocket_casts → receives accessToken + refreshToken + expiresIn
6. Tokens stored in Application.Storage (persists across app restarts)
7. On subsequent launches, app loads tokens from Storage — no re-login needed
8. Before API calls, check if token is near expiry → proactive refresh via POST /user/token
9. If token refresh fails (invalid_grant), re-login with stored credentials
10. If 401 received on any API call, attempt refresh → fallback to re-login
```

### 4.4 State Management

| State | Storage | Lifetime |
|---|---|---|
| Access + refresh tokens | `Application.Storage` via `CacheManager` (`"yc_auth"`) | Until expiry/logout; refreshed proactively |
| Subscribed podcasts (cached) | `Application.Storage` via `CacheManager` (`"yc_podcasts"`) | TTL 30 min; revalidated in background |
| Queue episodes (cached) | `Application.Storage` via `CacheManager` (`"yc_queue"`) | TTL 5 min; revalidated in background |
| Episode list per podcast | `Application.Storage` via `CacheManager` (`"yc_ep_<uuid>"`) | TTL 1 hr; evict LRU if storage full |
| User credentials | `Application.Properties` (phone settings) | Managed by user via GCM |
| Service mode (mock/real) | `Application.Properties` (`useMockData`) | Toggleable via Settings view |
| Current view state | In-memory only | Lost on app exit (acceptable) |

---

## 5. UI Screens & Navigation

### 5.1 Screen Map

```
                    ┌─────────────────┐
                    │ LoginPromptView  │  (shown if no auth token)
                    │ "Sign in via     │
                    │  Garmin Connect" │
                    │ [Skip → demo]   │
                    └────────┬────────┘
                             │ (after auth or skip)
                             ▼
                    ┌─────────────────────────┐
                    │  HomeMenuView            │  (Custom View — split-dock)
                    │  ┌─ Upper (scrollable) ─┐│
                    │  │ Queue                ││
                    │  │ Podcasts             ││
                    │  │ Settings             ││
                    │  └──────────────────────┘│
                    │  ┌─ Bottom (fixed) ─────┐│
                    │  │ Now Playing Dock     ││
                    │  └──────────────────────┘│
                    └──┬──────┬──────┬─────────┘
                       │      │      │
             ┌─────────▼┐  ┌─▼──────────┐  ┌──▼───────┐
             │ QueueView │  │ Subscribed │  │ Settings │
             │ (Menu2)   │  │ View       │  │ View     │
             └─────┬─────┘  │ (Menu2)    │  └──────────┘
                   │        └─────┬──────┘
                   │              │ select podcast
                   ▼              ▼
             ┌──────────┐  ┌────────────────┐
             │ Now      │  │ EpisodeListView│
             │ Playing  │  │ (Menu2)        │
             │ View     │  └───────┬────────┘
             └──────────┘          │ select episode
                                   ▼
                            ┌──────────┐
                            │ Now      │
                            │ Playing  │
                            └──────────┘
```

### 5.2 Navigation Model

Garmin uses a **view stack** managed by the system:

- `WatchUi.pushView(view, delegate, transition)` — push a new screen onto the stack
- `WatchUi.popView(transition)` — go back (also triggered by the hardware back button)
- The system handles the back button automatically when using `BehaviorDelegate.onBack()`

**Transitions:** Use `WatchUi.SLIDE_UP` when drilling down, `WatchUi.SLIDE_DOWN` when going back.

### 5.3 Screen Details

#### LoginPromptView
- **Type:** `WatchUi.View` (custom drawn)
- **Content:** Text: "Open Garmin Connect on your phone and enter your PocketCasts credentials in YoCasts settings."
- **Interaction:** None needed. App polls `Application.Properties` on a timer or checks on next `onShow()`.

#### MainMenuView / HomeMenuView
- **Type:** Custom `WatchUi.View` with `InputDelegate` (split-dock layout)
- **Upper Region:** Scrollable pills — Queue, Podcasts, Settings
- **Bottom Region:** Fixed Now Playing dock with progress bar + play/pause
- **On show:** Serve cached data immediately; trigger background refresh if connected
- **Navigation:** Tap Queue → `QueueView`, Tap Podcasts → `SubscribedView`, Tap Settings → `SettingsView`, Tap Now Playing dock → `NowPlayingView`

#### QueueView
- **Type:** `WatchUi.Menu2`
- **Items:** One `MenuItem` per episode: title, podcast name as subtitle
- **On show:** Fetch queue from API. On failure, load from cache. Show "Loading..." initially.
- **On select:** (MVP: no action. Future: episode detail / playback control)
- **Empty state:** Show "No new episodes" message

#### SubscribedView
- **Type:** `WatchUi.Menu2`
- **Items:** One `MenuItem` per podcast: title, author as subtitle
- **On show:** Fetch podcast list from API. On failure, load from cache.
- **On select:** Push `EpisodeListView` for that podcast's UUID

#### EpisodeListView
- **Type:** `WatchUi.Menu2`
- **Items:** One `MenuItem` per episode: title, duration as subtitle
- **On show:** Fetch episodes for the selected podcast UUID. On failure, load from cache.
- **On select:** (MVP: no action. Future: episode detail)
- **Limit:** Show only the 20 most recent episodes to conserve memory

### 5.4 Loading & Error States

Every view that fetches data should handle three states:

1. **Loading** — Show a simple View with "Loading..." text while the request is in flight
2. **Success** — Replace with Menu2 populated with data
3. **Error (no cache)** — Show "Could not connect. Ensure phone is nearby."
4. **Error (has cache)** — Show cached data with a subtle indicator that data may be stale

Use `WatchUi.switchToView()` to swap between loading and loaded states without adding to the view stack.

---

## 6. Offline & Caching Strategy

### 6.1 What to Cache

| Data | Cache Key | Max Size | TTL |
|---|---|---|---|
| Auth token | `"authToken"` | ~1 KB | Until 401 or user clears |
| Subscribed podcasts list | `"podcasts"` | ~5–15 KB (depending on count) | Refresh on every app open; serve stale if offline |
| Queue (new episodes) | `"queue"` | ~5–10 KB | Refresh on every app open; serve stale if offline |
| Episodes for podcast X | `"ep_<uuid>"` | ~5–10 KB (cap at 20 episodes) | Refresh when user views; evict oldest cached podcast if storage pressure |

### 6.2 Cache Format

Store data as Monkey C `Dictionary` / `Array` values via `Application.Storage.setValue()`. The SDK handles serialization.

```monkeyc
// Writing cache
function saveQueue(episodes) {
    // episodes is an Array of Dictionaries from makeWebRequest
    // Trim to essential fields to save space
    var trimmed = [];
    for (var i = 0; i < episodes.size() && i < 30; i++) {
        trimmed.add({
            "uuid" => episodes[i]["uuid"],
            "title" => episodes[i]["title"],
            "duration" => episodes[i]["duration"],
            "podcastTitle" => episodes[i]["podcastTitle"]
        });
    }
    Application.Storage.setValue("queue", trimmed);
}

// Reading cache
function loadQueue() {
    return Application.Storage.getValue("queue");
}
```

### 6.3 Storage Budget

With a 32 KB per-value limit and a device-dependent total, budget approximately:

| Key | Budget |
|---|---|
| `authToken` | 1 KB |
| `podcasts` | 10 KB |
| `queue` | 10 KB |
| Episode caches (3–5 podcasts) | 5 × 8 KB = 40 KB |
| **Total** | ~61 KB |

If the total exceeds device limits, implement LRU eviction: track which `ep_<uuid>` keys were accessed most recently and delete the oldest when a new one is needed.

### 6.4 Connectivity Loss Handling

```
Request initiated
    │
    ▼
connectionAvailable?  ──No──▶  Load from cache (CacheManager)
    │                           │
   Yes (Wi-Fi or BT)       Cache exists?
    │                      │         │
    ▼                     Yes        No
API responds?              │         │
    │                      ▼         ▼
   Yes ──▶ Update cache  Show data  Show error:
    │      via CacheManager(stale) "No connection,
   No      + serve fresh           no cached data"
    │
    ▼
Load from cache (same as above)
```

### 6.5 Sync Strategy

- **Cache-first with stale-while-revalidate.** Serve cached data immediately, refresh in background when connected (Wi-Fi or BT). TTL-based revalidation: queue 5min, podcasts 30min, episodes 1hr.
- **On-demand episode fetch.** Episodes loaded per-podcast when user navigates, not bulk at startup.
- **Three connectivity states.** Wi-Fi direct (best), Phone BT (good), Fully offline (cache-only). See `offline-sync-design.md` for full sync reconciliation architecture.
- **Phase 1 caching IS BUILT** — `CacheManager.mc` + `CachedPodcastService.mc` implement the cache-first pattern. Phase 2 (changelog, sync reconciliation) is planned but not yet built.

---

## 7. Build Phases

### Phase 1 — Skeleton & Auth ✅ COMPLETE

**Goal:** App launches, authenticates, shows the main menu.

- [x] Set up Connect IQ project (manifest, resources, jungle file)
- [x] Target device: Venu 4 41mm (390×390, round AMOLED, 768 KB)
- [x] Implement `YoCastsApp.mc` with lifecycle methods
- [x] Implement `LoginPromptView` — auth prompt with skip button for demo mode
- [x] Implement credential input via `Application.Properties` (settings.xml)
- [x] Implement `PocketCastsPodcastService` — login via `/user/login_pocket_casts`, token refresh via `/user/token`
- [x] Store auth tokens (accessToken + refreshToken) in `Application.Storage`
- [x] Implement `HomeMenuView` with split-dock design (Queue, Podcasts, Settings pills + Now Playing dock)
- [x] `IPodcastService` interface + `MockPodcastService` for demo mode
- [x] Service toggle via `useMockData` Application.Property
- [x] Navigation: home menu → list views and back

### Phase 2 — Queue & Subscribed Podcasts ✅ COMPLETE

**Goal:** Core browsing functionality works end-to-end.

- [x] Implement `PocketCastsPodcastService` — full async fetch with callback-based `makeWebRequest`
- [x] Implement `QueueView` — Menu2 populated from `/up_next/list` (map structure: iterate `order`, lookup in `episodes`)
- [x] Implement `SubscribedView` — Menu2 populated from `/user/podcast/list`
- [x] Implement `CacheManager` module — `Application.Storage` wrapper with `"yc_"` key prefix and `cachedAt` timestamps
- [x] Implement `CachedPodcastService` decorator — cache-first with TTL-based revalidation (queue 5min, podcasts 30min, episodes 1hr)
- [x] Stale-while-revalidate: serve cached data immediately, refresh in background
- [x] Error handling: 401 → token refresh → re-login fallback
- [x] Build passes `-l 3` strict mode

### Phase 3 — Episode Browsing ✅ COMPLETE

**Goal:** User can drill into a podcast and see its episodes.

- [x] Implement on-demand episode fetch per podcast via `requestEpisodesForPodcast(uuid)`
- [x] Implement `EpisodeListView` — Menu2 with episodes for selected podcast
- [x] Episode caching via CacheManager with TTL-based revalidation (1 hour)
- [x] Duration formatting and text truncation
- [x] NowPlayingView — custom full-screen playback view

### Phase 4 — Polish & Device Testing 🔄 IN PROGRESS

**Goal:** App is stable and tested on real hardware.

- [x] Scrolling viewport for HomeMenuView with increased touch targets
- [x] Pixel-based text truncation via `getTextWidthInPixels`
- [x] Fixed 20+ strict-mode type errors across service layer
- [x] SettingsView with account status and demo mode toggle
- [ ] Test on physical Garmin Venu 4 device
- [ ] Memory profiling — verify app stays within 768 KB limit
- [ ] Handle edge cases: empty lists, very long titles
- [ ] Test Wi-Fi direct vs BT connectivity transitions
- [ ] Handle token expiry gracefully in all views

### Phase 5 — Offline Sync & Audio Download 📋 PLANNED

**Goal:** Full offline capability with playback sync and episode downloads.

See [`offline-sync-design.md`](offline-sync-design.md) for the comprehensive architecture. The offline design has its own 4-phase implementation plan:

- [ ] **Offline Phase 1 (Metadata Caching):** ✅ Built — CacheManager + CachedPodcastService
- [ ] **Offline Phase 2 (Position Tracking + Sync):** Changelog, position tracking, sync state machine, push/pull reconciliation
- [ ] **Offline Phase 3 (Audio Download):** Media.ContentProvider, SyncDelegate, Wi-Fi auto-download
- [ ] **Offline Phase 4 (Full Reconciliation):** Queue merge, subscription sync, conflict resolution

---

## Appendix A: Key Garmin API References

| API | Docs URL |
|---|---|
| Application.AppBase | https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html |
| Application.Storage | https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html |
| Application.Properties | https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Properties.html |
| Communications | https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html |
| WatchUi | https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi.html |
| WatchUi.Menu2 | https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/Menu2.html |
| WatchUi.BehaviorDelegate | https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/BehaviorDelegate.html |
| Connect IQ SDK | https://developer.garmin.com/connect-iq/overview/ |

## Appendix B: PocketCasts API Quick Reference

| Operation | Method | URL | Auth |
|---|---|---|---|
| Login (modern) | POST | `/user/login_pocket_casts` | None (returns accessToken + refreshToken) |
| Login (legacy) | POST | `/user/login` | None (returns token only) |
| Token Refresh | POST | `/user/token` | None (refreshToken in body) |
| Subscribed Podcasts | POST | `/user/podcast/list` | Bearer accessToken |
| Episodes for Podcast | POST | `/user/podcast/episodes` | Bearer accessToken |
| Episode Detail | POST | `/user/episode` | Bearer accessToken |
| Queue (Up Next) | POST | `/up_next/list` | Bearer accessToken |
| New Releases | POST | `/user/new_releases` | Bearer accessToken |
| Sync Position | POST | `/sync/update_episode` | Bearer accessToken |

Base URL: `https://api.pocketcasts.com`

**Required headers on all authenticated requests:**
```
Authorization: Bearer <accessToken>
Content-Type: application/json
Origin: https://play.pocketcasts.com
```

> See [`pocketcasts-api-reference.md`](pocketcasts-api-reference.md) for the full 25+ endpoint reference with live-tested schemas.

## Appendix C: Mapping from Tizen App to Garmin App

| Tizen (C#/Xamarin) | Garmin (Monkey C) | Notes |
|---|---|---|
| `App.xaml.cs` → `App` class | `YoCastsApp.mc` → `AppBase` | Lifecycle management |
| `LoginPage.xaml` | `LoginPromptView.mc` | No text input on watch — use phone settings |
| `MainPage.xaml` | `HomeMenuView.mc` (Custom View, split-dock) | Split-dock design with scrollable pills + Now Playing dock |
| `QueuePage.xaml` | `QueueView.mc` (Menu2) | Episodes as MenuItems |
| `SubscribedPodcastsPage.xaml` | `SubscribedView.mc` (Menu2) | Podcasts as MenuItems |
| `NavigationService.cs` | `WatchUi.pushView/popView` | Built-in view stack — no custom nav needed |
| `SettingsService.cs` | `Application.Storage` | Key-value persistence |
| `PocketCastsApiService.cs` | `PocketCastsPodcastService.mc` | Uses `makeWebRequest` via Wi-Fi or BT. Wrapped by `CachedPodcastService`. |
| `PocketCastsApiAccessorcs.cs` | Merged into `PocketCastsPodcastService.mc` | No need for separate accessor on Garmin |
| `DownloadService.cs` | Planned for offline sync Phase 3 | `Media` module + Wi-Fi direct download |
| `Models/*.cs` (Episode, Podcast) | Dictionary keys in `DataModels.mc` | No class instances — use Dictionary |
