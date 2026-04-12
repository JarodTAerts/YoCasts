# YoCasts — Garmin Connect IQ UX Specification

> **Version:** 2.0  
> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-04-14 (updated)  
> **Status:** Active  
> **See also:** [`garmin-layout-reference.md`](garmin-layout-reference.md) — pixel-perfect layout specs, geometry tables, font measurements, and touch target specs for all screens  
> **v2.0 changes:** Corrected connectivity model — watch makes direct HTTP requests over Wi-Fi and BT (no phone-only proxy). Rewrote Home Menu to split-dock design (scrollable pills + fixed Now Playing dock). Added Settings screen. Updated navigation flow, data architecture, and companion app section to reflect actual implementation.

---

## Table of Contents

1. [Target Device](#1-target-device)
2. [Screen Inventory](#2-screen-inventory)
3. [Navigation Flow](#3-navigation-flow)
4. [Data Requirements Per Screen](#4-data-requirements-per-screen)
5. [Garmin Connect IQ UI Patterns](#5-garmin-connect-iq-ui-patterns)
6. [Resource Constraints](#6-resource-constraints)
7. [Communication & Connectivity](#7-communication--connectivity)

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
| **Communications** | Wi-Fi direct + Phone BT proxy via `Communications.makeWebRequest()` |

### Design Philosophy

> **Build for 390×390 AMOLED.** No need to scale down or support smaller screens. Take full advantage of the high-resolution display, generous memory budget, and touch input. Design for this one device and make it great.

---

## 2. Screen Inventory

### Tizen → Garmin Screen Mapping

| # | Tizen Screen | Garmin Equivalent | CIQ Component | Priority |
|---|---|---|---|---|
| 1 | LoginPage (email/password form) | Settings-Based Auth | Garmin Connect Mobile settings + `Application.Properties` | P0 |
| 2 | MainPage (hub with Queue / Subscribed) | Home Menu | Custom `WatchUi.View` (split-dock design) | P0 |
| 3 | QueuePage (unplayed episodes list) | Queue View | `WatchUi.Menu2` with custom `MenuItem` | P0 |
| 4 | SubscribedPodcastsPage | Podcasts List | `WatchUi.Menu2` | P0 |
| 5 | *(not in Tizen app)* | Episode List (per podcast) | `WatchUi.Menu2` | P1 |
| 6 | *(not in Tizen app)* | Now Playing | Custom `WatchUi.View` | P0 |
| 7 | *(not in Tizen app)* | Settings | Custom `WatchUi.View` | P1 |
| 8 | *(not in Tizen app)* | Loading / Sync Indicator | `WatchUi.ProgressBar` or custom View | P1 |

### Screen Descriptions

#### 2.1 — Auth / Login (Settings-Based)

**Why no on-watch login form?** Garmin watches have no keyboard. Typing email/password on a watch screen with buttons is a non-starter. Instead, we use the **Garmin Connect Mobile settings page** to capture credentials.

- User opens YoCasts settings in Garmin Connect Mobile on their phone
- Enters PocketCasts email and password in settings fields
- Credentials are stored in `Application.Properties` on the watch
- On app launch, the watch reads stored credentials and authenticates via the companion

**First-run experience:** If no credentials are stored, the app shows `LoginPromptView` — a screen prompting the user to sign in. Includes a **skip button** to enter mock data / demo mode (controlled by the `useMockData` Application.Property).

#### 2.2 — Home Menu (Split-Dock Design)

Replaces the Tizen `MainPage`. A custom `WatchUi.View` with a **split-dock layout** — scrollable navigation pills in the upper region and a fixed Now Playing dock at the bottom. Uses `InputDelegate` (not `BehaviorDelegate`) for proper touch handling. See [`garmin-layout-reference.md` §5](garmin-layout-reference.md#5-home-menu-layout-spec) for pixel-perfect positioning.

**Upper Region (Y=0–260): Scrollable Pills**

| Pill | Height | Content | Action |
|---|---|---|---|
| **Queue** | 68 px | Episode count subtitle | Navigate to Queue screen |
| **Podcasts** | 68 px | Subscription count subtitle | Navigate to Subscribed Podcasts |
| **Settings** | 68 px | — | Navigate to Settings screen |

**Bottom Region (Y=260–390): Fixed Now Playing Dock**

| Element | Content | Action |
|---|---|---|
| **Now Playing Dock** | Episode title, progress bar, play/pause button | Tap dock → Navigate to Now Playing; Tap play button → toggle playback |

Pills use adaptive width based on their Y position within the 390px round screen (see layout reference §5.7). The upper pills scroll via swipe; the Now Playing dock is always visible.

#### 2.2a — Settings

In-app settings view accessible from the Settings pill on the Home Menu.

| Element | Detail |
|---|---|
| **View type** | Custom `WatchUi.View` |
| **Content** | Account status (logged-in email or "Not signed in"), Demo Mode toggle (`useMockData` property) |
| **Interaction** | Tap Demo Mode toggle to switch between `MockPodcastService` and `PocketCastsPodcastService` |

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

Shown while data is being fetched from the PocketCasts API (over Wi-Fi or BT).

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
│  Check Auth     │───────────────────►│  LoginPromptView     │
│  (Properties)   │                     │  (skip → demo mode)  │
└────────┬────────┘                     └──────────────────────┘
         │ Has credentials (or demo mode)
         ▼
┌─────────────────────────────────────┐
│          Home Menu (Split-Dock)     │◄─────────────────────────┐
│  ┌──────── Upper: Scrollable ─────┐ │                          │
│  │ Queue     │ Podcasts │ Settings │ │                          │
│  └───────────┴──────────┴─────────┘ │                          │
│  ┌──────── Bottom: Fixed ─────────┐ │                          │
│  │        Now Playing Dock        │ │                          │
│  └────────────────────────────────┘ │                          │
└───┬──────────┬──────────┬───────────┘                          │
    │          │          │                                      │
    ▼          ▼          ▼                                      │
Queue List  Podcast   Settings                                   │
    │       List       View                                      │
    │          │                                                 │
    ▼          ▼                                                 │
Now Playing  Episode List ──► Now Playing                        │
    │              │              │                              │
  BACK           BACK           BACK ───────────────────────────┘
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
                    ┌─── Wi-Fi Direct ───┐
PocketCasts API ◄───┤                    ├──► Watch App
                    └── BT via Phone ────┘    (Communications.makeWebRequest)
```

The watch makes HTTP requests via `Communications.makeWebRequest()`, which works over **both** Wi-Fi (direct to the internet, no phone needed) and Bluetooth (proxied through the paired phone's internet connection). Three connectivity states exist:

| State | Detection | Capability |
|---|---|---|
| **Wi-Fi direct** | `connectionAvailable && !phoneConnected` | Full HTTP access, fast downloads, no phone needed |
| **Phone BT** | `connectionAvailable && phoneConnected` | Full HTTP access via BLE proxy, slower for large payloads |
| **Fully offline** | `!connectionAvailable` | Cache-only mode, serve stored data |

See [`offline-sync-design.md` — Connectivity Model](offline-sync-design.md#connectivity-model) for detailed detection logic.

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
| Episode list (title, uuid, podcastTitle, duration, playedUpTo) | `IPodcastService.getQueue()` via API or cache | Cache in `Application.Storage` (persist across sessions) |
| Episode count | Derived from list | N/A |

**Fetch strategy:** Stale-while-revalidate — serve cached data immediately, refresh via `makeWebRequest()` in background when connected (Wi-Fi or BT). TTL-based revalidation: queue refreshes after 5 minutes.

**Cache format:**
```
Storage key: "queue"
Value: Array of { uuid, title, podcastTitle, duration, playedUpTo }
Max entries: 20
```

#### 4.3 — Subscribed Podcasts

| Data | Source | Cache Strategy |
|---|---|---|
| Podcast list (title, uuid, unplayed flag) | `IPodcastService.getSubscribedPodcasts()` via API or cache | Cache in `Application.Storage` |

**Fetch strategy:** Stale-while-revalidate — serve cached data immediately, refresh in background. TTL: 30 minutes.

**Cache format:**
```
Storage key: "podcasts"
Value: Array of { uuid, title, unplayed }
Max entries: 30
```

#### 4.4 — Episode List

| Data | Source | Cache Strategy |
|---|---|---|
| Episodes for a specific podcast | `IPodcastService.getEpisodesForPodcast(uuid)` via API or cache | Cache per podcast UUID, evict LRU when > 5 podcasts cached |

**Fetch strategy:** On-demand — episodes loaded per-podcast when user navigates. TTL: 1 hour. Stale data always served, refresh in background when connected.

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
| Playback position | Local (on-watch media player) | Sync back to server via `/sync/update_episode` when connected |
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

**Component:** Custom `WatchUi.View` + `WatchUi.InputDelegate`

> **Note:** Uses `InputDelegate` (not `BehaviorDelegate`) — critical for correct touch event handling on the Venu 4. `InputDelegate` provides `onTap()`, `onSwipe()`, and `onHold()` methods that properly handle touch coordinates.

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
- **Home Menu:** Upper pills scroll via swipe gesture; the Now Playing dock at Y=260–390 is fixed. See [`garmin-layout-reference.md` §5.10](garmin-layout-reference.md#510--scroll-behavior)
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
3. **Limit list sizes.** Hard caps: Queue = 20, Podcasts = 30, Episodes per podcast = 15. The `CachedPodcastService` enforces these limits when caching data.
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

- Minimize API request frequency — don't poll; use stale-while-revalidate with TTL-based refresh
- Use `Application.Storage` for persistent cache to avoid re-fetching on every app open
- Keep Now Playing view updates to 1/second (timer-based `requestUpdate()`)
- Avoid continuous animations — only animate during active user interaction

---

## 7. Communication & Connectivity

### 7.1 — Architecture

The watch communicates directly with the PocketCasts API using `Communications.makeWebRequest()`. **No custom companion app is needed.** The Garmin Connect Mobile app on the phone serves only as a transparent BLE proxy when Wi-Fi is unavailable.

```
┌─────────────┐     Wi-Fi Direct     ┌─────────────┐
│  Watch App  │◄────────────────────►│ PocketCasts  │
│  (Monkey C) │                      │    API       │
│             │     BLE → Phone      │              │
│             │◄── (GCM proxy) ────►│              │
└─────────────┘                      └─────────────┘
```

### 7.2 — Service Architecture

The app uses an interface-based service architecture with runtime switching:

| Component | Role |
|---|---|
| **`IPodcastService`** | Interface defining sync getters + async fetch methods |
| **`MockPodcastService`** | Returns hardcoded demo data (for testing and demo mode) |
| **`PocketCastsPodcastService`** | Real API calls via `Communications.makeWebRequest()` |
| **`CachedPodcastService`** | Decorator wrapping the real service — cache-first, TTL-based revalidation |
| **`CacheManager`** | Module handling `Application.Storage` persistence with `"yc_"` key prefix |

Service toggle via `useMockData` Application.Property — switches between `MockPodcastService` and the `CachedPodcastService`-wrapped `PocketCastsPodcastService`.

### 7.3 — Communication Protocol

**Transport:** `Communications.makeWebRequest()` — works over both Wi-Fi (direct) and Bluetooth (proxied via phone's Garmin Connect Mobile).

The watch calls the PocketCasts API directly. No proxy service, no custom companion code. This means:
- No additional infrastructure to host or maintain
- The watch handles auth tokens itself (stored in `Application.Storage`)
- `makeWebRequest()` handles the transport layer transparently
- All API calls use HTTPS with JSON request/response bodies

**Message size limits:**
- Keep responses reasonable for watch memory — limit list sizes and truncate strings
- Queue: max 20 episodes, Podcasts: max 30, Episodes per podcast: max 15

### 7.4 — Auth Flow

```
1. User installs YoCasts on watch from Connect IQ Store
2. User opens Garmin Connect Mobile → YoCasts settings
3. User enters PocketCasts email + password
4. Settings are synced to watch via Application.Properties
5. On first app launch, watch reads credentials from Properties
6. Watch calls POST /user/login_pocket_casts directly
7. Receives accessToken + refreshToken + expiresIn
8. Tokens stored in Application.Storage on-watch
9. Token refresh via POST /user/token with {grantType, refreshToken}
10. If refresh fails, fallback to re-login with stored credentials
```

**Alternative:** User can skip login and use demo mode (MockPodcastService) via the `LoginPromptView` skip button.

### 7.5 — Offline Behavior

| Scenario | Behavior |
|---|---|
| Wi-Fi available, no phone | Full API access. Sync, browse, download episodes. |
| Phone connected via BT | Full API access via proxy. Metadata sync works well; large downloads are slower. |
| Fully offline (no Wi-Fi, no phone) | Show cached data. All screens usable with stale data. Mutations logged to changelog for later sync. |
| Connection lost during playback | Continue playback uninterrupted. Position sync on reconnect. |

See [`offline-sync-design.md`](offline-sync-design.md) for the complete offline mode and sync reconciliation architecture.

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
| `HttpClient` / direct HTTP | `Communications.makeWebRequest()` (direct over Wi-Fi or BT proxy) |
| `DownloadService` (file download) | `Media` module + `Communications.makeWebRequest()` over Wi-Fi (Phase 3) |

## Appendix B: File Structure (Actual)

```
YoCastsGarmin/
├── source/
│   ├── YoCastsApp.mc                      # AppBase — lifecycle, Properties init, service toggle
│   ├── models/
│   │   └── DataModels.mc                  # Dictionary keys / constants for podcast/episode data
│   ├── services/
│   │   ├── IPodcastService.mc             # Interface — sync getters + async fetch methods
│   │   ├── MockPodcastService.mc          # Demo data (useMockData = true)
│   │   ├── PocketCastsPodcastService.mc   # Real API via makeWebRequest
│   │   ├── CachedPodcastService.mc        # Cache-first decorator (TTL revalidation)
│   │   └── CacheManager.mc               # Application.Storage wrapper ("yc_" prefix)
│   └── views/
│       ├── HomeMenuView.mc                # Custom View — split-dock design (pills + Now Playing)
│       ├── MainMenuView.mc                # (legacy — being replaced by HomeMenuView)
│       ├── QueueView.mc                   # Menu2 — episode queue
│       ├── SubscribedView.mc              # Menu2 — subscribed podcasts
│       ├── EpisodeListView.mc             # Menu2 — episodes for a podcast
│       ├── NowPlayingView.mc              # Custom View — full-screen playback
│       ├── LoginPromptView.mc             # Auth prompt with skip button for demo mode
│       └── SettingsView.mc                # In-app settings (account status, demo toggle)
├── resources/
│   ├── strings/
│   │   └── strings.xml                    # User-facing strings
│   ├── settings/
│   │   ├── settings.xml                   # Phone-side settings (email, password, useMockData)
│   │   └── properties.xml                 # Property definitions
│   └── drawables/
│       ├── drawables.xml                  # Drawable definitions
│       └── launcher_icon.png              # App icon
├── manifest.xml                           # App manifest, device compatibility, permissions
└── monkey.jungle                          # Build configuration
```

## Appendix C: Open Questions

1. **Audio playback on Garmin:** ✅ **Resolved.** Garmin's `Media` module (CIQ 3.1+) supports audio playback. Episodes must be downloaded to watch storage first — no streaming. Download can happen over Wi-Fi directly (no phone needed). See `offline-sync-design.md` Phase 3 for the download architecture.

2. **PocketCasts API stability:** The API is reverse-engineered. 20/25 endpoints confirmed working via live testing. See `pocketcasts-api-reference.md` for the current state. The service layer (`IPodcastService` interface) abstracts the API so endpoint changes only affect `PocketCastsPodcastService.mc`.

3. **Proxy hosting:** ✅ **Resolved — not needed.** The watch calls the PocketCasts API directly via `Communications.makeWebRequest()` over Wi-Fi or BT. No proxy infrastructure required.

4. **Episode download vs. streaming:** ✅ **Resolved.** Download-only. Episodes download to watch storage over Wi-Fi (direct or via charger+sync). Planned for offline-sync Phase 3. See `offline-sync-design.md` §3.
