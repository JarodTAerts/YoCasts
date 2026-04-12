# YoCasts — Garmin Connect IQ UX Specification

> **Version:** 1.1  
> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-04-13 (updated)  
> **Status:** Active  
> **See also:** [`garmin-layout-reference.md`](garmin-layout-reference.md) — pixel-perfect layout specs, geometry tables, font measurements, and touch target specs for all screens

---

## Table of Contents

1. [Target Device](#1-target-device)
2. [Screen Inventory](#2-screen-inventory)
3. [Navigation Flow](#3-navigation-flow)
4. [Data Requirements Per Screen](#4-data-requirements-per-screen)
5. [Garmin Connect IQ UI Patterns](#5-garmin-connect-iq-ui-patterns)
6. [Resource Constraints](#6-resource-constraints)
7. [Companion App Requirements](#7-companion-app-requirements)

---

## 1. Target Device

### Garmin Venu 4 41mm — Single Target

This is a personal project for Jarod. We target exactly one device: the **Garmin Venu 4 41mm**.

| Attribute | Value |
|---|---|
| **Device ID** | `venu441mm` |
| **Connect IQ Version** | 4.2+ |
| **Screen Resolution** | 390 × 390 px (round, AMOLED) |
| **Screen Shape** | Round |
| **Display Colors** | 65,536 (16-bit) |
| **App Memory Limit** | 768 KB (watch app) |
| **Background Memory** | 64 KB |
| **Input** | Capacitive touchscreen + 2 buttons (Enter, Escape) |
| **Launcher Icon Size** | 54 × 54 px |
| **Communications** | Phone companion via Garmin Connect Mobile |

### Design Philosophy

> **Build for 390×390 AMOLED.** No need to scale down or support smaller screens. Take full advantage of the high-resolution display, generous memory budget, and touch input. Design for this one device and make it great.

---

## 2. Screen Inventory

### Tizen → Garmin Screen Mapping

| # | Tizen Screen | Garmin Equivalent | CIQ Component | Priority |
|---|---|---|---|---|
| 1 | LoginPage (email/password form) | Settings-Based Auth | Garmin Connect Mobile settings + `Application.Properties` | P0 |
| 2 | MainPage (hub with Queue / Subscribed) | Home Menu | `WatchUi.Menu2` | P0 |
| 3 | QueuePage (unplayed episodes list) | Queue View | `WatchUi.Menu2` with custom `MenuItem` | P0 |
| 4 | SubscribedPodcastsPage | Podcasts List | `WatchUi.Menu2` | P0 |
| 5 | *(not in Tizen app)* | Episode List (per podcast) | `WatchUi.Menu2` | P1 |
| 6 | *(not in Tizen app)* | Now Playing | Custom `WatchUi.View` | P0 |
| 7 | *(not in Tizen app)* | Loading / Sync Indicator | `WatchUi.ProgressBar` or custom View | P1 |

### Screen Descriptions

#### 2.1 — Auth / Login (Settings-Based)

**Why no on-watch login form?** Garmin watches have no keyboard. Typing email/password on a watch screen with buttons is a non-starter. Instead, we use the **Garmin Connect Mobile settings page** to capture credentials.

- User opens YoCasts settings in Garmin Connect Mobile on their phone
- Enters PocketCasts email and password in settings fields
- Credentials are stored in `Application.Properties` on the watch
- On app launch, the watch reads stored credentials and authenticates via the companion

**First-run experience:** If no credentials are stored, the app shows a single-screen message: *"Open YoCasts settings in Garmin Connect to sign in."*

#### 2.2 — Home Menu

Replaces the Tizen `MainPage`. A custom `WatchUi.View` with three tappable rounded-rectangle pills. See [`garmin-layout-reference.md` §5](garmin-layout-reference.md#5-home-menu-layout-spec) for pixel-perfect positioning.

| Pill | Height | Content | Action |
|---|---|---|---|
| **Queue** | 68 px | Episode count subtitle | Navigate to Queue screen |
| **Podcasts** | 68 px | Subscription count subtitle | Navigate to Subscribed Podcasts |
| **Now Playing** | 100 px | Episode title, progress bar, play/pause | Navigate to Now Playing (tap pill) or toggle playback (tap play button) |

Pills use adaptive width based on their Y position within the 390px round screen (see layout reference §5.7). All three pills fit in the viewport without scrolling (260px content in 290px viewport).

#### 2.3 — Queue (Unplayed Episodes)

Replaces the Tizen `QueuePage`. Shows episodes from `GetQueue()` (new/unplayed episodes).

| Element | Detail |
|---|---|
| **List type** | `Menu2` with custom `MenuItem` |
| **Per-item display** | Episode title (primary label), podcast name (sublabel) |
| **Item action** | SELECT → Navigate to Now Playing for that episode |
| **Empty state** | "No episodes in queue. Sync from your phone." |
| **Max items** | 20 episodes (memory constraint — see §6) |

The Tizen app had a play button embedded in each list item. On Garmin, tapping/selecting an episode goes straight to Now Playing — fewer taps, clearer intent.

#### 2.4 — Subscribed Podcasts List

Replaces the Tizen `SubscribedPodcastsPage`. Shows podcasts from `GetSubscribedPodcasts()`.

| Element | Detail |
|---|---|
| **List type** | `Menu2` |
| **Per-item display** | Podcast title (primary label), unplayed indicator (icon or sublabel) |
| **Item action** | SELECT → Navigate to Episode List for that podcast |
| **Empty state** | "No subscriptions found. Sync from your phone." |
| **Max items** | 30 podcasts |

#### 2.5 — Episode List (Per Podcast)

**New screen** not present in the Tizen app (the Tizen app had `GetEpisodesForPodcast()` in the API but no UI for it).

| Element | Detail |
|---|---|
| **List type** | `Menu2` |
| **Per-item display** | Episode title, duration (sublabel), played/unplayed indicator |
| **Item action** | SELECT → Navigate to Now Playing |
| **Max items** | 15 episodes per podcast |

#### 2.6 — Now Playing

**New screen.** The Tizen app added episodes to a download queue but had no playback UI. This is the most important screen for the Garmin version.

| Element | Detail |
|---|---|
| **View type** | Custom `WatchUi.View` (full-screen, not a menu) |
| **Layout** | Podcast name (top), episode title (center, scrolling if long), progress bar (bottom arc), play/pause icon (center) |
| **Controls** | SELECT = play/pause, UP = skip back 30s, DOWN = skip forward 30s, BACK = return to previous screen, MENU = playback options |
| **Playback options menu** | Speed (1×, 1.5×, 2×), Mark as played, Return to queue |
| **Progress display** | Elapsed / Total time, arc progress indicator around screen edge |

#### 2.7 — Loading / Sync Indicator

Shown while data is being fetched from the companion app.

| Element | Detail |
|---|---|
| **View type** | Simple `WatchUi.View` with spinner/progress |
| **Display** | "Syncing..." with animated dots or a circular progress indicator |
| **Timeout** | After 15 seconds, show "Sync failed. Press BACK to retry." |

---

## 3. Navigation Flow

### Input Model

The Venu 4 41mm has **2 physical buttons** and a **capacitive touchscreen**:

| Input | Standard Function | YoCasts Function |
|---|---|---|
| **Enter button** | Confirm / enter | Select menu item / play-pause |
| **Escape button** | Go back / cancel | Return to previous screen |
| **Tap** | Select item | Select menu item / play-pause |
| **Swipe up/down** | Scroll | Scroll lists |
| **Swipe right** | Go back | Return to previous screen |
| **Long press (Enter)** | Menu | Open context menu (playback options) |

Touch is the **primary input method** on the Venu 4. Buttons are secondary. Design touch-first.

### Navigation Graph

```
┌─────────────────┐
│   App Launch     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    No credentials    ┌──────────────────────┐
│  Check Auth     │───────────────────►│  "Set up in Garmin   │
│  (Properties)   │                     │   Connect" message   │
└────────┬────────┘                     └──────────────────────┘
         │ Has credentials
         ▼
┌─────────────────┐
│   Home Menu     │◄──────────────────────────────┐
│  ┌───────────┐  │                                │
│  │ Queue     │──┼───► Queue List ──► Now Playing │
│  ├───────────┤  │         │              │       │
│  │ Podcasts  │──┼───► Podcast List      BACK     │
│  └───────────┘  │         │              │       │
└─────────────────┘    Episode List ──► Now Playing │
                            │                      │
                          BACK ────────────────────┘
```

### Navigation Rules

1. **BACK always goes up one level.** No dead ends. From Home Menu, BACK exits the app.
2. **No circular navigation.** Every path has a clear parent.
3. **Now Playing is reachable from Queue OR Episode List.** Both paths lead to the same Now Playing view.
4. **Menu depth is max 3 levels:** Home → List → Now Playing. Users should never be more than 2 presses from the home screen.
5. **On resume:** If the app was backgrounded during playback, re-open directly to Now Playing (persist `PlayingEpisode` in `Application.Properties`).

---

## 4. Data Requirements Per Screen

### Data Flow Overview

```
PocketCasts API ◄──► Companion App (Phone) ◄──► Watch App
                     (HTTP requests)           (Communications API)
```

The watch **never** makes direct HTTP requests to the PocketCasts API. All network calls go through the phone companion.

### Per-Screen Data Requirements

#### 4.1 — Home Menu

| Data | Source | Cache Strategy |
|---|---|---|
| Menu items (static) | Hardcoded | N/A — built into the app |
| Auth status | `Application.Properties` | Persisted on-device |

No API calls needed for this screen.

#### 4.2 — Queue

| Data | Source | Cache Strategy |
|---|---|---|
| Episode list (title, uuid, podcastTitle, duration, playedUpTo) | Companion → `GetQueue()` | Cache in `Application.Storage` (persist across sessions) |
| Episode count | Derived from list | N/A |

**Fetch strategy:** Request fresh data from companion on screen entry. If companion is unavailable, fall back to cached data. Show loading indicator during fetch.

**Cache format:**
```
Storage key: "queue"
Value: Array of { uuid, title, podcastTitle, duration, playedUpTo }
Max entries: 20
```

#### 4.3 — Subscribed Podcasts

| Data | Source | Cache Strategy |
|---|---|---|
| Podcast list (title, uuid, unplayed flag) | Companion → `GetSubscribedPodcasts()` | Cache in `Application.Storage` |

**Fetch strategy:** Same as Queue — fetch on entry, fall back to cache.

**Cache format:**
```
Storage key: "podcasts"
Value: Array of { uuid, title, unplayed }
Max entries: 30
```

#### 4.4 — Episode List

| Data | Source | Cache Strategy |
|---|---|---|
| Episodes for a specific podcast | Companion → `GetEpisodesForPodcast(uuid)` | Cache per podcast UUID, evict LRU when > 5 podcasts cached |

**Fetch strategy:** Always fetch fresh — episode lists change frequently. Cache is fallback only.

**Cache format:**
```
Storage key: "episodes_{podcastUuid}"
Value: Array of { uuid, title, duration, playedUpTo }
Max entries: 15 per podcast, max 5 podcasts cached
```

#### 4.5 — Now Playing

| Data | Source | Cache Strategy |
|---|---|---|
| Current episode details | Passed from Queue/Episode List selection | Persist in `Application.Properties` as `PlayingEpisode` |
| Playback position | Local (on-watch media player) | Sync back to companion periodically |
| Playback state (playing/paused) | Local | Not persisted (always pause on exit) |

#### 4.6 — Data Size Budget

| Data | Estimated Size Per Item | Max Items | Total |
|---|---|---|---|
| Queue episodes | ~200 bytes | 20 | ~4 KB |
| Subscribed podcasts | ~150 bytes | 30 | ~4.5 KB |
| Episode list (per podcast) | ~180 bytes | 15 × 5 | ~13.5 KB |
| Current episode | ~200 bytes | 1 | ~0.2 KB |
| **Total cached data** | | | **~22 KB** |

This fits comfortably within the `Application.Storage` limits (typically 32–128 KB depending on device).

---

## 5. Garmin Connect IQ UI Patterns

### 5.1 — Menu Screens (Queue, Podcasts, Episodes)

**Component:** `WatchUi.Menu2`

`Menu2` is the standard Garmin pattern for scrollable lists. It handles:
- Scrolling with UP/DOWN buttons or touch swipe
- Item selection with SELECT
- Back navigation with BACK
- Round-screen adaptation automatically

**Home Menu uses Custom View** (not Menu2) for rich pill rendering. See [`garmin-layout-reference.md` §5](garmin-layout-reference.md#5-home-menu-layout-spec) and §9.3 for the decision guide.

**Menu2 configuration per screen:**

```
Home Menu:
  - NOT Menu2 — Custom View with adaptive-width pills
  - See garmin-layout-reference.md §5 for full spec

Queue:
  - Menu2 title: "Queue"
  - Items: Dynamic MenuItems
  - Primary label: episode.title (pixel-truncated via getTextWidthInPixels)
  - Sublabel: episode.podcastTitle (pixel-truncated)

Podcasts:
  - Menu2 title: "Podcasts"
  - Items: Dynamic MenuItems
  - Primary label: podcast.title (pixel-truncated)
  - Sublabel: "New episodes" or "" based on unplayed flag
  - Icon: dot indicator if unplayed

Episodes:
  - Menu2 title: podcast.title (pixel-truncated)
  - Items: Dynamic MenuItems
  - Primary label: episode.title (pixel-truncated)
  - Sublabel: formatted duration (e.g., "45 min")
```

### 5.2 — Now Playing (Custom View)

**Component:** Custom `WatchUi.View` + `WatchUi.BehaviorDelegate`

This is one of two custom-drawn screens (along with Home Menu). See [`garmin-layout-reference.md` §7](garmin-layout-reference.md#7-now-playing-screen-layout-spec) for pixel-perfect positioning.

Layout targets the 390×390 AMOLED display:

```
Layout (390×390 round, AMOLED):
┌──────────────────────────┐
│    ╭─── progress arc ───╮│   ← drawArc(), r=185, pen=6, 0x55AAFF
│    │                    ││
│    │  Podcast Name      ││   ← Y=80, FONT_XTINY (33px), 0xAAAAAA
│    │                    ││
│    │  Episode Title     ││   ← Y=135, FONT_MEDIUM (56px), white
│    │  (2 lines max)     ││   ← Y=185, FONT_MEDIUM (line 2)
│    │                    ││
│    │  [⏮]  [▶]  [⏭]    ││   ← Y=245, circles r=24/32/24
│    │                    ││
│    │  12:34 / 45:00     ││   ← Y=300, FONT_TINY (41px), 0xAAAAAA
│    │                    ││
│    ╰────────────────────╯│
└──────────────────────────┘
```

**Font choices (verified pixel heights for 390×390 — see [`garmin-layout-reference.md` §2](garmin-layout-reference.md#2-font-reference)):**

| Element | Font | Height | Color |
|---|---|---|---|
| Podcast name | `FONT_XTINY` | 33 px | 0xAAAAAA (gray) |
| Episode title | `FONT_MEDIUM` | 56 px | White |
| Time display | `FONT_TINY` | 41 px | 0xAAAAAA (gray) |
| Play/pause icon | Custom drawable | ~32 px radius | 0x55AAFF (accent) |

**Progress arc:** Draw using `Dc.drawArc()` — a colored arc around the screen edge showing playback progress. This is a natural fit for round Garmin displays.

### 5.3 — Loading/Sync View

**Component:** Custom `WatchUi.View`

- Center the text "Syncing..." with `FONT_SMALL`
- Use a simple animated spinner (rotating arc, redrawn via `WatchUi.requestUpdate()` on a timer)
- Keep it minimal — this screen should be visible for < 5 seconds in normal conditions

### 5.4 — Empty States

Every list screen must handle the empty case:

| Screen | Empty Message |
|---|---|
| Queue | "Queue is empty" |
| Podcasts | "No subscriptions" |
| Episodes | "No episodes" |
| Auth missing | "Sign in via\nGarmin Connect" |

Display empty messages centered, `FONT_SMALL`, light gray. Don't use `Menu2` for empty states — switch to a simple `View`.

### 5.5 — Font Size Guidelines

Targeting 390×390 AMOLED. Actual pixel heights verified via `getFontHeight()` (full table in [`garmin-layout-reference.md` §2.1](garmin-layout-reference.md#21--system-font-pixel-heights-venu-4-41mm--390390)):

| Element | Font | Pixel Height |
|---|---|---|
| Screen title | `FONT_MEDIUM` | 56 px |
| Pill label | `FONT_SMALL` | 46 px |
| Subtitle / secondary | `FONT_XTINY` | 33 px |
| Body text (lists) | `FONT_SMALL` | 46 px |
| Numbers / time | `FONT_TINY` | 41 px |

For `Menu2` screens, Garmin handles font sizing automatically. Custom views use the measured values above.

### 5.6 — Scrolling and List Behavior

- `Menu2` handles scrolling natively — no custom scroll logic needed for list screens
- Lists wrap around (scrolling past the last item goes to the first)
- On touch devices, swipe momentum scrolling is handled by the framework
- **Home Menu:** No scrolling needed — 3 pills (260px total) fit in the 290px viewport. See [`garmin-layout-reference.md` §5.10](garmin-layout-reference.md#510--scroll-behavior)
- **Now Playing:** No scrolling — all content is visible at once. Long episode titles use marquee animation (3-phase: pause→scroll→pause→reset at 150ms intervals)
- For custom views that do need scrolling: use `onSwipe()` with 80px step, `dc.setClip()` viewport, instant snap (no animation). See layout reference §4.5

---

## 6. Resource Constraints

### 6.1 — Memory Budget

**Target: The Venu 4 41mm provides 768 KB for watch apps — generous headroom.**

| Component | Estimated Memory | Notes |
|---|---|---|
| App code (PRG) | ~40 KB | Monkey C compiled bytecode |
| Active View/Menu | ~8 KB | Current screen's objects |
| Cached data (Storage) | ~22 KB | See §4.6 — loaded on demand |
| Drawables/Icons | ~5 KB | Minimal icon set |
| Communications buffers | ~10 KB | Message serialization |
| Monkey C runtime overhead | ~10 KB | VM, stack, GC |
| **Total estimated peak** | **~95 KB** | Well under 768 KB limit |

With 768 KB available, there's room for richer features in future iterations (podcast artwork, larger caches, etc.).

### 6.2 — Memory Management Rules

1. **Load data lazily.** Don't load Queue AND Podcasts AND Episodes into memory simultaneously. Load the active screen's data only.
2. **Release on view exit.** When navigating away from a list, set the data array to `null` so the GC can reclaim it.
3. **Limit list sizes.** Hard caps: Queue = 20, Podcasts = 30, Episodes per podcast = 15. The companion app should enforce these limits before sending data.
4. **No images in v1.** Podcast artwork is expensive in transfer time. Use text-only lists with icon indicators. Artwork is a v2 feature — memory is not the bottleneck on the Venu 4.
5. **String truncation.** Truncate all user-facing strings before storing. Episode titles: max 50 chars. Podcast titles: max 40 chars.

### 6.3 — Maximum List Sizes

| List | Max Items | Rationale |
|---|---|---|
| Queue | 20 | 20 episodes × ~200 bytes = 4 KB — reasonable for a watch queue |
| Subscribed Podcasts | 30 | Most users have < 30 subscriptions |
| Episodes per Podcast | 15 | Recent episodes only — nobody scrolls through hundreds on a watch |
| Cached podcast episode lists | 5 | LRU eviction — only cache the 5 most recently viewed podcasts |

### 6.4 — Icon and Image Strategy

**v1: Text and system glyphs only.**

- Use Unicode characters or Garmin's built-in icon set for indicators (play, pause, unplayed dot)
- Custom drawables only for the app icon (launcher) — single PNG, sized per device
- No podcast artwork, no album art, no thumbnails

**v2 (future):**
- Podcast artwork as 48×48 bitmaps in `Menu2` items
- Downloaded from companion, stored in `Application.Storage`
- 768 KB budget makes this feasible

### 6.5 — Battery Considerations

- Minimize companion communication frequency — don't poll; fetch on user action only
- Use `Application.Storage` for persistent cache to avoid re-fetching on every app open
- Keep Now Playing view updates to 1/second (timer-based `requestUpdate()`)
- Avoid continuous animations — only animate during active user interaction

---

## 7. Companion App Requirements

### 7.1 — Architecture

The Garmin Connect IQ companion runs as part of the Garmin Connect Mobile app on the user's phone. It communicates with the watch via the `Communications` API.

```
┌─────────────┐     BLE/Wi-Fi      ┌─────────────────┐     HTTPS     ┌─────────────┐
│  Watch App  │◄──────────────────►│  Companion App  │◄────────────►│ PocketCasts  │
│  (Monkey C) │  Communications    │  (Phone-side)   │   REST API   │    API       │
│             │  API               │                 │              │              │
└─────────────┘                    └─────────────────┘              └─────────────┘
```

### 7.2 — Companion Responsibilities

| Function | Description | Watch → Phone Message | Phone → Watch Response |
|---|---|---|---|
| **Authenticate** | Login to PocketCasts with stored credentials | `{ "action": "login" }` | `{ "status": "ok", "token": "..." }` or `{ "status": "error", "message": "..." }` |
| **Fetch Queue** | Get unplayed episodes | `{ "action": "getQueue" }` | `{ "episodes": [...] }` (max 20, truncated fields) |
| **Fetch Podcasts** | Get subscribed podcast list | `{ "action": "getPodcasts" }` | `{ "podcasts": [...] }` (max 30) |
| **Fetch Episodes** | Get episodes for a podcast | `{ "action": "getEpisodes", "uuid": "..." }` | `{ "episodes": [...] }` (max 15) |
| **Sync Playback** | Report playback position back | `{ "action": "syncPosition", "uuid": "...", "position": 1234 }` | `{ "status": "ok" }` |

### 7.3 — Communication Protocol

**Transport:** `Communications.transmit()` (watch → phone) and `Communications.registerForPhoneAppMessages()` (phone → watch).

Alternatively, for simpler implementation, use `Communications.makeWebRequest()` where the companion acts as a transparent proxy. This avoids building a custom companion app — the watch calls a small web service or serverless function that wraps the PocketCasts API.

**Recommended approach for v1:** Use `Communications.makeWebRequest()` with a lightweight proxy service. This means:
- No custom companion app needed (less code to maintain)
- The proxy handles auth token management
- The watch sends HTTP requests through the phone's internet connection
- Garmin Connect Mobile handles the BLE/Wi-Fi transport transparently

**Message size limits:**
- Keep individual messages under 16 KB (Garmin's practical limit for `Communications` payloads)
- This is why we truncate strings and limit list sizes — a queue of 20 episodes at ~200 bytes each = ~4 KB, well under the limit

### 7.4 — Auth Flow (Settings-Based)

```
1. User installs YoCasts on watch from Connect IQ Store
2. User opens Garmin Connect Mobile → YoCasts settings
3. User enters PocketCasts email + password
4. Settings are synced to watch via Application.Properties
5. On first app launch, watch reads credentials from Properties
6. Watch sends auth request through Communications API
7. Companion/proxy authenticates with PocketCasts API
8. Auth token is returned and stored on-watch for session
```

**Security note:** Credentials in `Application.Properties` are stored in Garmin's device storage — not encrypted, but only accessible to the app. For v2, consider OAuth or token-only storage where the password never leaves the phone.

### 7.5 — Offline Behavior

| Scenario | Behavior |
|---|---|
| Phone not connected | Show cached data with "Offline" indicator. All screens usable except Sync. |
| Phone connected, API error | Show cached data + toast "Sync failed" |
| No cached data, no connection | Show empty state message per screen (see §5.4) |
| Playback in progress, connection lost | Continue playback uninterrupted. Queue position sync on reconnect. |

### 7.6 — Companion Implementation Options

| Option | Pros | Cons | Recommendation |
|---|---|---|---|
| **makeWebRequest + Proxy** | No companion app code, simpler, faster to ship | Requires hosting a proxy service | ✅ **v1 — start here** |
| **Custom Companion (Android)** | Full control, richer features, offline phone-side caching | More code, two codebases to maintain | v2 if needed |
| **Custom Companion (Android + iOS)** | Full platform coverage | Significant effort, two mobile codebases | v3 / future |

---

## Appendix A: Tizen → Garmin Translation Reference

| Tizen Concept | Garmin Equivalent |
|---|---|
| `CirclePage` | `WatchUi.View` |
| `CircleListView` | `WatchUi.Menu2` |
| `CircleStackLayout` | Manual layout in `View.onUpdate(dc)` |
| `Label` | `Dc.drawText()` |
| `Button` | `BehaviorDelegate` button handler |
| `Entry` (text input) | `Application.Properties` (settings on phone) |
| `Tizen.Applications.Preference` | `Application.Storage` / `Application.Properties` |
| `NavigationService` (push/pop pages) | `WatchUi.pushView()` / `WatchUi.popView()` |
| `HttpClient` / direct HTTP | `Communications.makeWebRequest()` via phone |
| `DownloadService` (file download) | Not applicable in v1 — stream or proxy through companion |

## Appendix B: File Structure (Proposed)

```
YoCasts-Garmin/
├── source/
│   ├── YoCastsApp.mc              # AppBase — lifecycle, Properties init
│   ├── HomeMenuView.mc            # Menu2 — Queue / Podcasts
│   ├── HomeMenuDelegate.mc        # Menu2InputDelegate
│   ├── QueueView.mc               # Menu2 — episode queue
│   ├── QueueDelegate.mc           # Menu2InputDelegate
│   ├── PodcastsView.mc            # Menu2 — subscribed podcasts
│   ├── PodcastsDelegate.mc        # Menu2InputDelegate
│   ├── EpisodesView.mc            # Menu2 — episodes for a podcast
│   ├── EpisodesDelegate.mc        # Menu2InputDelegate
│   ├── NowPlayingView.mc          # Custom View — playback screen
│   ├── NowPlayingDelegate.mc      # BehaviorDelegate — playback controls
│   ├── LoadingView.mc             # Sync/loading indicator
│   ├── AuthPromptView.mc          # "Set up in Garmin Connect" message
│   └── DataManager.mc             # Storage, caching, companion communication
├── resources/
│   ├── strings.xml                # All user-facing strings
│   ├── settings.xml               # Phone-side settings (email, password)
│   ├── menus/                     # Menu XML definitions (if using declarative menus)
│   └── drawables/                 # App icon per device resolution
├── manifest.xml                   # App manifest, device compatibility, permissions
└── monkey.jungle                  # Build configuration
```

## Appendix C: Open Questions

1. **Audio playback on Garmin:** Connect IQ has limited audio support (`Media` module, CIQ 3.1+). Need to investigate whether we can stream audio or if we must download episodes to watch storage first. This significantly impacts the companion app requirements.

2. **PocketCasts API stability:** The existing Tizen app uses a reverse-engineered API. If endpoints change, the proxy/companion needs updating. Consider abstracting the API layer.

3. **Proxy hosting:** If we go the `makeWebRequest` route, where does the proxy live? Options: Cloudflare Worker, AWS Lambda, self-hosted. This is a decision for Wash (backend).

4. **Episode download vs. streaming:** Garmin watches with music support (Venu, Forerunner Music editions) can store audio files. Should we download episodes to the watch for offline playback? This is a v2 feature but impacts architecture decisions now.
