# Garmin CIQ Audio Architecture Options

> **Author:** Wash (API Dev)
> **Date:** 2026-04-14
> **Status:** Research Complete — Recommendation Ready

## Executive Summary

There is exactly **one viable architecture** for YoCasts: a single `AudioContentProviderApp`. This is not a compromise — it's the only path that delivers all three requirements (browse, download, play). The "crash on first launch" problem is solvable and has been solved by existing open-source apps.

---

## Research Findings

### 1. Can a watch-app play audio?

**No.** Full stop.

- `Media.startPlayback()` and the entire `Toybox.Media` module are **exclusive to AudioContentProviderApp**. A watch-app attempting to use them will error.
- `Attention.playTone()` is available in watch-apps but only produces short beeps/vibrations — not usable for podcast audio.
- There is **no workaround**, no hidden API, no hack. The Media subsystem is gated by app type at the OS level.

**Sources:** [Toybox.Media docs](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media.html), [Garmin Forums](https://forums.garmin.com/developer/connect-iq/f/discussion/375976/)

### 2. Two-app pattern (watch-app + audio provider)

**Not viable on-device.**

- `Application.Storage` is **sandboxed per-app**. Two CIQ apps cannot share storage, files, or any on-device state.
- There is **no inter-app launch mechanism** — you cannot open one CIQ app from another.
- Monkey Barrels (shared libraries) share code at build time, not data at runtime.
- The only workaround is syncing through a cloud service (both apps log into PocketCasts independently), but this means:
  - User enters credentials twice
  - No shared download state
  - No way to hand off "play this episode" from the browse app to the audio app
  - Terrible UX

**Verdict:** Dead end. Don't pursue.

### 3. App type capabilities matrix

| Capability | watch-app | audio-content-provider | widget | data-field |
|---|---|---|---|---|
| Custom Views/UI | ✅ Full | ✅ Via config views | ⚠️ Limited | ❌ |
| `getInitialView()` | ✅ | ❌ | ✅ | ✅ |
| `getPlaybackConfigurationView()` | ❌ | ✅ | ❌ | ❌ |
| `getSyncConfigurationView()` | ❌ | ✅ | ❌ | ❌ |
| HTTP requests | ✅ | ✅ | ✅ | ❌ |
| `Application.Storage` | ✅ | ✅ | ✅ | ❌ |
| `Application.Properties` | ✅ | ✅ | ✅ | ✅ |
| Background service | ✅ | ❌ | ❌ | ❌ |
| Audio playback (Media API) | ❌ | ✅ | ❌ | ❌ |
| Audio download (SyncDelegate) | ❌ | ✅ | ❌ | ❌ |
| GPS/Sensors | ✅ | ❌ | ✅ | ✅ |
| Launched from app list | ✅ | ❌ | ✅ | N/A |
| Launched from music controls | ❌ | ✅ | ❌ | ❌ |

**Key insight:** AudioContentProviderApp has HTTP + Storage + custom views (via config methods) + audio. It only lacks `getInitialView()` and app-list presence — but it doesn't need them.

### 4. Can AudioContentProviderApp show custom views before content exists?

**Yes. This is the designed pattern.**

- `getPlaybackConfigurationView()` and `getSyncConfigurationView()` are the app's entry points. They return `[View, InputDelegate]` arrays — identical to `getInitialView()` in a watch-app.
- From the initial view, you can `WatchUi.pushView()` to create arbitrarily complex multi-screen navigation (Menu2, CustomMenu, custom Views).
- **The "crash on first launch" is caused by the ContentDelegate/ContentIterator**, not the config views. When the native player asks for content and the iterator returns invalid data, it crashes.
- **The fix is defensive ContentDelegate implementation:**
  - `ContentIterator.get()` → return `null` when no content
  - `ContentIterator.peekNext()`/`peekPrevious()` → return `null`
  - `ContentDelegate.getContentIterator()` → return an iterator that handles empty queue

The open-source **garmin-podcasts** app proves this works — it shows a full menu (Queue, Podcasts, Episodes, Settings) inside `getPlaybackConfigurationView()`, downloads episodes via sync, and only calls `Media.startPlayback(null)` when the user explicitly chooses to play.

**Sources:** [garmin-podcasts PodcastsApp.mc](https://github.com/lucasasselli/garmin-podcasts/blob/main/app/source/PodcastsApp.mc), [Garmin AudioContentProviderApp API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html)

### 5. Background service + audio

**ServiceDelegate cannot play audio.**

- `Toybox.Background` / `ServiceDelegate` can run temporal events, make network requests, and handle messages in the background.
- They have **zero access** to the Media subsystem. No audio playback, no media file management.
- `AudioContentProviderApp` is the **only** path to background audio. When the native player is active, your audio plays even when the user navigates away.

### 6. Communications.SyncDelegate

**Exclusive to audio-content-provider-app.**

- `Communications.SyncDelegate` (and the deprecated `Media.SyncDelegate`) handle system-initiated media sync workflows.
- Only AudioContentProviderApp can implement `getSyncDelegate()` — the system's music sync UI triggers it.
- Watch-apps can use `Communications.makeWebRequest()` for HTTP but **cannot** use `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` to download audio files — that response type requires the media sandbox.
- In SDK 9.1.0+, `Communications.SyncDelegate` replaces the deprecated `Media.SyncDelegate`. Use `getSyncDelegate()` on the app class.

### 7. AudioContentProviderApp lifecycle

```
USER FLOW:
┌──────────────────────────────────────────────────────────┐
│  User opens Music Controls (hold DOWN or swipe)          │
│  → Selects "YoCasts" as provider                         │
│  → System calls getPlaybackConfigurationView()           │
│     └→ Your custom UI: browse, configure, login          │
│        ├→ User browses podcasts (pushView for submenus)  │
│        ├→ User selects "Play Queue"                      │
│        │  └→ Media.startPlayback(null)                   │
│        │     └→ Native player takes over                 │
│        │        └→ ContentDelegate.onSong() for events   │
│        └→ User selects "Sync" (or system auto-syncs)     │
│           └→ getSyncConfigurationView()                  │
│              └→ Your sync config UI                      │
│              └→ SyncDelegate.onStartSync()               │
│                 └→ Download episodes via makeWebRequest   │
│                    (HTTP_RESPONSE_CONTENT_TYPE_AUDIO)     │
│                 └→ notifySyncComplete()                   │
└──────────────────────────────────────────────────────────┘

KEY LIFECYCLE METHODS:
  getPlaybackConfigurationView()  — user wants to browse/configure/play
  getSyncConfigurationView()      — user wants to sync/download
  getSyncDelegate()               — system needs sync delegate instance
  getContentDelegate(arg)         — system needs content for playback
  getProviderIconInfo()           — system needs your icon for music UI
  onSettingsChanged()             — GCM settings changed
```

**Important:** There is **no `getInitialView()`** — the app never appears in the main app list. Users access it exclusively through the device's Music Controls.

### 8. Open source CIQ audio apps

#### garmin-podcasts (lucasasselli) — **Primary Reference**

A fully functional podcast app for Garmin. Architecture:

```
PodcastsApp.mc          — extends AudioContentProviderApp
├── getPlaybackConfigurationView() → MainMenu (browse, queue, settings)
├── getSyncConfigurationView()     → MainMenu (same entry point)
├── getContentDelegate()           → ContentDelegate (playback events)
├── getSyncDelegate()              → SyncDelegate (downloads episodes)
│
MainMenu.mc             — Queue (with play count), Podcasts, Episodes, Settings
ContentDelegate.mc      — Handles onSong events (progress, skip, complete)
ContentIterator.mc      — Iterates downloaded episodes for playback
SyncDelegate.mc         — Downloads artwork + audio via makeWebRequest
EpisodeManager.mc       — Manage downloaded episodes
SubscriptionManager.mc  — Manage podcast subscriptions
Queue.mc                — Playback queue management
Providers/              — Podcast feed providers (Podcast Index, gpodder)
UI/                     — Custom UI components
```

**Key patterns from garmin-podcasts:**
1. Both config views return the **same MainMenu** — single entry point for all flows
2. Uses `Communications.SyncDelegate` (not deprecated `Media.SyncDelegate`)
3. Downloads audio with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` + `mediaEncoding`
4. Tracks episode progress in `Application.Storage`
5. `Media.startPlayback(null)` kicks off native player after user confirms
6. ContentIterator returns `null` when no episodes queued (prevents crash)
7. SyncDelegate handles both artwork and audio downloads sequentially

#### garmin/connectiq-apps/audio-provider/monkeymusic — **Official Sample**

Garmin's official skeleton audio provider. Simpler than garmin-podcasts but shows the basic wiring.

---

## Architecture Options Matrix

### Option A: Single AudioContentProviderApp (RECOMMENDED)

Convert YoCasts to `AudioContentProviderApp`. All browse, download, and playback in one app.

| Dimension | Assessment |
|---|---|
| **Browse podcasts/episodes** | ✅ Full Menu2/custom views via getPlaybackConfigurationView(). Proven by garmin-podcasts. |
| **Download episodes** | ✅ SyncDelegate with HTTP_RESPONSE_CONTENT_TYPE_AUDIO. Our CDN research confirms all PocketCasts CDNs support this. |
| **Background audio playback** | ✅ Native media player handles playback. ContentDelegate receives events. |
| **PocketCasts login** | ✅ Credentials via Application.Properties (GCM settings). API calls via makeWebRequest. |
| **Offline caching** | ✅ Application.Storage available. CachedPodcastService pattern works unchanged. |
| **UX entry point** | ⚠️ Users access via Music Controls, not app list. This is how Spotify/Deezer work on Garmin — users expect it for audio apps. |
| **Migration effort** | 🟡 Medium. Change manifest type, replace getInitialView() with getPlaybackConfigurationView()/getSyncConfigurationView(), add ContentDelegate + ContentIterator + SyncDelegate. Existing views/services reusable. |
| **First-launch crash** | ✅ Solvable. Defensive ContentIterator (return null when empty) + show "No episodes — sync first" message. |
| **Existing code reuse** | ✅ High. HomeMenuView, all browse views, PocketCastsPodcastService, CachedPodcastService — all reusable. Only app shell and media delegates are new. |

### Option B: Watch-app only (current state)

Keep YoCasts as a watch-app. Browse and cache, but no audio playback.

| Dimension | Assessment |
|---|---|
| **Browse podcasts/episodes** | ✅ Works today. |
| **Download episodes** | ❌ Cannot use SyncDelegate. Cannot download audio files. |
| **Background audio playback** | ❌ Impossible. No Media API access. |
| **UX entry point** | ✅ Standard app list. |
| **Value to user** | ❌ Minimal. A podcast app that can't play podcasts. |

### Option C: Two apps (watch-app + audio provider)

Ship two separate apps: watch-app for browsing, audio provider for playback.

| Dimension | Assessment |
|---|---|
| **Browse podcasts/episodes** | ✅ Watch-app handles this. |
| **Download episodes** | ✅ Audio provider handles sync. |
| **Background audio playback** | ✅ Audio provider plays. |
| **Data sharing** | ❌ No shared storage. User must configure/login in BOTH apps separately. |
| **Episode handoff** | ❌ Cannot pass "play this" from browse app to audio app. |
| **User experience** | ❌ Terrible. Two app icons, two logins, no coordination. |
| **Maintenance** | ❌ Two codebases, two CIQ store listings, two review cycles. |
| **Precedent** | ❌ No known CIQ apps use this pattern. |

### Option D: Watch-app + Background ServiceDelegate

Use ServiceDelegate for background audio.

| Dimension | Assessment |
|---|---|
| **Background audio playback** | ❌ ServiceDelegate has NO access to Media API. Cannot play audio. |
| **Verdict** | ❌ Non-starter. |

---

## Recommendation

### **Go with Option A: Single AudioContentProviderApp.**

This is not a close call. Options B, C, and D are all dead ends. Every shipping podcast/music app on Garmin (Spotify, Deezer, Amazon Music, garmin-podcasts) uses this exact architecture.

### Migration path from current watch-app:

1. **Change manifest.xml:** `type="watch-app"` → `type="audio-content-provider-app"`
2. **Change app class:** `AppBase` → `AudioContentProviderApp`
3. **Replace entry points:**
   - Remove `getInitialView()` (doesn't exist on AudioContentProviderApp)
   - Add `getPlaybackConfigurationView()` → return `[HomeMenuView, HomeMenuDelegate]`
   - Add `getSyncConfigurationView()` → return same or a sync-specific view
4. **Add media delegates:**
   - `ContentDelegate` (extends `Media.ContentDelegate`) — handles playback events
   - `ContentIterator` (extends `Media.ContentIterator`) — iterates downloaded episodes
   - `SyncDelegate` (extends `Communications.SyncDelegate`) — handles episode downloads
5. **Add provider icon:** `getProviderIconInfo()` → return icon for music controls
6. **Fix first-launch crash:** Defensive null returns in ContentIterator when no episodes downloaded
7. **Reuse everything else:** HomeMenuView, browse views, PocketCastsPodcastService, CachedPodcastService, all models — unchanged.

### What changes for the user:

- YoCasts disappears from the main app list
- YoCasts appears in Music Controls → Music Providers
- User holds DOWN button (or swipes to music) → selects YoCasts → full browse/play experience
- This is identical to how Spotify, Deezer, and every other audio app works on Garmin

### What doesn't change:

- All existing browse views
- All existing API service code
- All existing caching logic
- Settings/properties flow via GCM

---

## References

| Source | URL |
|---|---|
| Toybox.Media API | https://developer.garmin.com/connect-iq/api-docs/Toybox/Media.html |
| AudioContentProviderApp API | https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html |
| Toybox.Attention (tones only) | https://developer.garmin.com/connect-iq/api-docs/Toybox/Attention.html |
| Communications.SyncDelegate | https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html |
| Garmin Blog: Creating Music Apps | https://www.garmin.com/en-US/blog/developer/creating-music-apps-3x/ |
| garmin-podcasts (open source) | https://github.com/lucasasselli/garmin-podcasts |
| Official audio-provider sample | https://github.com/garmin/connectiq-apps/tree/master/audio-provider |
| CIQ FAQ: Audio Provider | https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-an-audio-content-provider/ |
| Garmin Forum: Audio app crashes | https://forums.garmin.com/developer/connect-iq/i/bug-reports/audio-apps-on-api-6-0-devices-crash-simulator-on-start |
| Garmin Forum: Return to native player | https://forums.garmin.com/developer/connect-iq/f/discussion/413352/ |
