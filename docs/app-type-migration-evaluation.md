# App Type Migration Evaluation: AppBase → AudioContentProviderApp

> **Version:** 1.0  
> **Author:** Mal (Lead)  
> **Date:** 2026-04-14  
> **Status:** Architecture Decision — APPROVED  
> **Audience:** All team members  
> **Input artifacts:**  
> - `docs/garmin-media-and-background-research.md` (Kaylee's 39KB research)  
> - `docs/audio-download-implementation-plan.md` (5-phase implementation plan)  
> - `docs/pocketcasts-audio-download-research.md` (Wash's CDN research)  
> - `docs/offline-sync-design.md` (v1.2, offline architecture)  
> - Garmin API documentation, MonkeyMusic sample, developer blog, community forums

---

## Executive Summary

**Recommendation: MIGRATE to AudioContentProviderApp.** This is not optional — it's the only path to audio playback on Garmin. The migration is lower-risk than initially feared because AudioContentProviderApp inherits from AppBase and preserves full View/InputDelegate capabilities. Our existing UI code survives almost entirely intact.

**Key finding:** Kaylee's research was right — every successful audio app on Garmin (Spotify, Deezer, Amazon Music) uses this pattern. There is no alternative for playing audio through Bluetooth headphones on Garmin watches. A "device app that also plays audio" does not exist in the Connect IQ SDK.

**Scope of migration:** 2 files rewritten, 1 new file, 6 files modified, 12+ files unchanged. The core app entry point (`YoCastsApp.mc`) and manifest are rewritten. The entire service layer, cache layer, and most views survive untouched.

---

## Table of Contents

1. [What is AudioContentProviderApp?](#1-what-is-audiocontentproviderapp)
2. [What MUST Change](#2-what-must-change)
3. [What CAN Stay the Same](#3-what-can-stay-the-same)
4. [Impact Assessment](#4-impact-assessment)
5. [Risk Assessment](#5-risk-assessment)
6. [Step-by-Step Migration Plan](#6-step-by-step-migration-plan)
7. [Updated Phase Plan](#7-updated-phase-plan)
8. [File-by-File Impact Matrix](#8-file-by-file-impact-matrix)
9. [Open Questions](#9-open-questions)

---

## 1. What is AudioContentProviderApp?

### 1.1 Technical Identity

`AudioContentProviderApp` is a specialized subclass of `AppBase` in the Garmin Connect IQ SDK. It extends AppBase with methods for integrating with the device's native media player.

```
Inheritance chain:
  Toybox.Lang.Object
    └── Toybox.Application.AppBase
          └── Toybox.Application.AudioContentProviderApp  ← our new base class
```

**Source:** [Garmin API — AudioContentProviderApp](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html)

### 1.2 How It Differs from AppBase

| Property | AppBase (current) | AudioContentProviderApp |
|---|---|---|
| Manifest `type` | `watch-app` | `audio-content-provider-app` |
| Launched from | App list on watch | Music app / music widget |
| `getInitialView()` | ✅ Required | ✅ Inherited, still available |
| Custom Views | ✅ Full support | ✅ Full support (same API) |
| `WatchUi.pushView()` | ✅ Works | ✅ Works — full view navigation |
| Media module access | ❌ No media cache, no playback | ✅ Full — downloads, playback, encrypted storage |
| SyncDelegate | ❌ Not available | ✅ System-triggered downloads |
| ContentDelegate | ❌ Not available | ✅ Playback event handling |
| Native media player | ❌ Cannot plug in | ✅ Acts as plug-in to native player |
| BT headphone audio | ❌ Cannot route audio | ✅ System handles BT audio routing |
| Background services | ✅ ServiceDelegate | ✅ ServiceDelegate (same) |
| Application.Storage | ✅ Full access | ✅ Full access (same) |
| Application.Properties | ✅ Full access | ✅ Full access (same) |
| Communications module | ✅ Full access | ✅ Full access (same) |
| Timer.Timer | ✅ Available | ✅ Available (same) |

### 1.3 App Lifecycle Differences

**Current lifecycle (AppBase/watch-app):**
```
User opens app from app list
  → onStart()
  → getInitialView() → HomeMenuView
  → User navigates views (pushView/popView)
  → onStop()
```

**New lifecycle (AudioContentProviderApp):**
```
User opens YoCasts from Music app
  → onStart()

  CONTEXT-DEPENDENT VIEW SELECTION:
  ├── Direct launch / "Browse" → getInitialView() → HomeMenuView
  ├── "Select what to play"    → getPlaybackConfigurationView() → HomeMenuView or QueueView
  ├── "Sync content"           → getSyncConfigurationView() → SyncConfigView (NEW)
  └── System needs content     → getContentDelegate() → YoCastsContentDelegate

  → User navigates views (pushView/popView — same as before)

  PLAYBACK:
  → System calls getContentDelegate() for playback events
  → Native media player handles audio decoding + BT headphone output
  → ContentDelegate.onSong() fires on play/pause/skip/complete
  → We track position via PositionTracker

  SYNC (system-triggered, charger + Wi-Fi):
  → System calls getSyncDelegate()
  → SyncDelegate.isSyncNeeded() → true if episodes queued for download
  → SyncDelegate.onStartSync() → chain makeWebRequest(AUDIO) calls
  → Downloads stream to encrypted media cache
  → notifySyncComplete()
```

### 1.4 Critical Capability Confirmation

**✅ CONFIRMED: AudioContentProviderApp supports all View/UI capabilities of AppBase.**

Because it inherits from AppBase, every UI API we currently use is still available:
- `WatchUi.View` — custom drawing with `onUpdate(dc)`
- `WatchUi.BehaviorDelegate` / `WatchUi.InputDelegate` — input handling
- `WatchUi.Menu2` — list menus (Queue, Episodes, Subscribed)
- `WatchUi.pushView()` / `popView()` — view stack navigation
- `Graphics.Dc` — all drawing operations
- `Timer.Timer` — periodic updates (marquee scrolling, etc.)

**Sources:**
- [Garmin API docs](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html) — "extends AppBase"
- [MonkeyMusic sample](https://github.com/garmin/connectiq-apps/tree/master/audio-provider/monkeymusic) — uses Views, Menus, Delegates
- [Garmin blog](https://www.garmin.com/en-US/blog/developer/creating-music-apps-3x/) — "define your own sync/playback UI with WatchUi.Menu2 or WatchUi.CustomMenu"
- Web search results confirm custom views, WatchUi.pushView(), and full navigation work inside AudioContentProviderApp

### 1.5 What It Gives Us

1. **Audio playback through Bluetooth headphones** — the native media player handles decoding, volume, BT routing
2. **Encrypted media cache** — 3.5–4 GB of storage on Venu 4 for downloaded episodes
3. **System-managed sync** — automatic downloads when charging + Wi-Fi, no user intervention needed
4. **SyncDelegate** — reliable large-file downloads via `HTTP_RESPONSE_CONTENT_TYPE_AUDIO`
5. **ContentDelegate** — position tracking on every play/pause/skip/complete event
6. **PlaybackProfile** — customizable skip intervals (±15s/30s), playback controls
7. **Integration with Garmin's music ecosystem** — appears alongside Spotify/Deezer in music widget

### 1.6 What It Takes Away

1. **App list presence** — the app moves from the watch app list to the Music app provider list. Users access YoCasts through the Music menu, not the main app list. This is how ALL audio apps work on Garmin; users expect it.
2. **Custom Now Playing UI during playback** — when audio is playing, Garmin's native media player takes the foreground. Our `NowPlayingView` is superseded by the system player. (But we gain native skip/pause/volume controls, headphone routing, and lock-screen controls for free.)
3. **"Always running" background** — the app runs as a plug-in, not a standalone process. The system manages lifecycle more aggressively.

---

## 2. What MUST Change

### 2.1 YoCastsApp.mc — REWRITE

The app class changes from `extends AppBase` to `extends AudioContentProviderApp`. New methods must be implemented:

```monkeyc
import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Media;
import Toybox.Communications;

class YoCastsApp extends Application.AudioContentProviderApp {

    private var _service as IPodcastService?;

    function initialize() {
        AudioContentProviderApp.initialize();
    }

    function onStart(state) {
        _service = createService();
        var svc = _service as IPodcastService;
        svc.fetchAll();
    }

    // ================================================================
    // AppBase inherited — still works, called on direct app launch
    // ================================================================

    function getInitialView() {
        return _buildEntryView();
    }

    // ================================================================
    // AudioContentProviderApp — NEW required methods
    // ================================================================

    //! Called when user selects "Play" / browses content to play.
    //! This IS our main browsing entry point — maps to HomeMenuView.
    function getPlaybackConfigurationView() {
        return _buildEntryView();
    }

    //! Called when user selects "Sync" / "Download" from music app.
    //! Shows a view for selecting episodes to download.
    function getSyncConfigurationView() {
        var service = getService();
        var view = new SyncConfigView(service);
        return [view, new SyncConfigDelegate(view, service)];
    }

    //! Returns the ContentDelegate for playback event handling.
    function getContentDelegate(args) {
        return new YoCastsContentDelegate();
    }

    //! Returns the SyncDelegate for system-triggered downloads.
    //! Using Communications.SyncDelegate (not deprecated Media.SyncDelegate).
    function getSyncDelegate() {
        return new YoCastsSyncDelegate();
    }

    //! Provider icon for the music app.
    function getProviderIconInfo() {
        return new Media.ProviderIconInfo(
            Rez.Drawables.LauncherIcon, 0x55AAFF
        );
    }

    // ================================================================
    // Existing methods — unchanged
    // ================================================================

    function onStop(state) { }

    function onSettingsChanged() as Void {
        System.println("YoCasts: settings changed, recreating service");
        _service = createService();
        var svc = _service as IPodcastService;
        svc.fetchAll();
        WatchUi.requestUpdate();
    }

    function hasCredentials() as Boolean { /* unchanged */ }
    function shouldUseMockData() as Boolean { /* unchanged */ }
    private function createService() as IPodcastService { /* unchanged */ }
    function getService() as IPodcastService { /* unchanged */ }
    function buildHomeView(service as IPodcastService) as Array { /* unchanged */ }

    //! Shared entry point for both getInitialView and getPlaybackConfigurationView.
    private function _buildEntryView() as Array {
        if (hasCredentials() || shouldUseMockData()) {
            var service = getService();
            var view = new HomeMenuView(service);
            return [view, new HomeMenuDelegate(view, service)];
        } else {
            return [new LoginPromptView(), new LoginPromptDelegate()];
        }
    }
}
```

**Key design decision:** Both `getInitialView()` and `getPlaybackConfigurationView()` return the same HomeMenuView. This ensures consistent UX regardless of how the user enters the app. The `getSyncConfigurationView()` returns a dedicated download-selection view — a new screen.

### 2.2 manifest.xml — REWRITE

```xml
<?xml version="1.0"?>
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="4">
    <iq:application
        id="a3421feed75247efa2a683e6e5152865"
        type="audio-content-provider-app"
        name="@Strings.AppName"
        entry="YoCastsApp"
        launcherIcon="@Drawables.LauncherIcon"
        minSdkVersion="4.2.0">

        <iq:permissions>
            <iq:uses-permission id="Communications"/>
            <iq:uses-permission id="Media"/>
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

**Changes from current:**
1. `type` changes from `watch-app` to `audio-content-provider-app`
2. `Media` permission added
3. Everything else identical

### 2.3 New Files Required

#### 2.3.1 SyncConfigView.mc (NEW)

A new view for the sync configuration screen. Shows the Up Next queue with download toggles. This is what the user sees when they enter "Sync" mode from the Music app.

**Location:** `YoCastsGarmin/source/views/SyncConfigView.mc`

This view shows a list of Up Next episodes with checkboxes indicating which to download. The user selects episodes, presses "Sync," and the system triggers the SyncDelegate.

#### 2.3.2 YoCastsContentDelegate.mc (Phase D)

Already designed in the implementation plan (Task D3). Handles `onSong()` callbacks from the native media player. Wires playback events to PositionTracker.

**Location:** `YoCastsGarmin/source/media/YoCastsContentDelegate.mc`

#### 2.3.3 YoCastsSyncDelegate.mc (Phase C)

Already designed in the implementation plan (Task C1). Handles system-triggered sync: `isSyncNeeded()`, `onStartSync()`, `onStopSync()`.

**Location:** `YoCastsGarmin/source/media/YoCastsSyncDelegate.mc`

#### 2.3.4 YoCastsContentIterator.mc (Phase D)

Already designed in the implementation plan (Task D2). Provides playlist iteration to the native media player.

**Location:** `YoCastsGarmin/source/media/YoCastsContentIterator.mc`

### 2.4 NowPlayingView.mc — ROLE CHANGE

**Our NowPlayingView does NOT need to be deleted.** But its role changes:

| Before Migration | After Migration |
|---|---|
| Primary playback UI — shows progress arc, play/pause button, time display | Secondary "episode info" view — shows episode details while system handles actual playback |
| Handles play/pause/skip via BehaviorDelegate | System media player handles all playback controls natively |
| Manually tracks position via timer | ContentDelegate.onSong() provides position automatically |
| No actual audio playback (placeholder) | Real audio playback via native player |

**What happens:** When the user starts playback, the system's native media player takes over. The user sees Garmin's standard playback UI with our episode title, podcast name (via ContentMetadata), and our customized skip intervals (via PlaybackProfile). Our NowPlayingView becomes an "episode detail" screen the user can access from the queue/browsing views — it shows extended info but doesn't control playback directly.

**Practical impact:** NowPlayingView survives as-is for now. In Phase D, we'll either:
- Adapt it to show "currently playing" info pulled from ContentDelegate state, or
- Replace it with a simpler info view since the system handles playback UI

The existing code is not wasted — the progress arc rendering, marquee text, and layout logic may be reused for an episode detail view.

### 2.5 Service Architecture Integration

**How our service architecture connects to the Media module:**

```
                    ┌───────────────────────────────────┐
                    │     AudioContentProviderApp        │
                    │                                   │
                    │  getPlaybackConfigurationView()   │
                    │         ↓                         │
                    │  HomeMenuView → QueueView          │
                    │  (existing views, unchanged)       │
                    │                                   │
                    │  getContentDelegate()              │
                    │         ↓                         │
                    │  YoCastsContentDelegate            │
                    │    ↓ onSong()   ↓ onComplete()    │
                    │  PositionTracker  CacheManager     │
                    │                                   │
                    │  getSyncDelegate()                 │
                    │         ↓                         │
                    │  YoCastsSyncDelegate               │
                    │    ↓ onStartSync()                │
                    │  DownloadManager                   │
                    │    ↓ makeWebRequest(AUDIO)        │
                    │  CacheManager (download manifest)  │
                    │                                   │
                    │  getSyncConfigurationView()        │
                    │         ↓                         │
                    │  SyncConfigView (NEW)              │
                    │    reads IPodcastService.getQueue() │
                    └───────────────────────────────────┘
```

**IPodcastService stays as the data contract.** The Media module components (ContentDelegate, SyncDelegate, ContentIterator) sit alongside the service layer, not inside it. They read from CacheManager directly for downloaded content, and from IPodcastService for metadata.

---

## 3. What CAN Stay the Same

### 3.1 Service Layer — ALL UNCHANGED

| File | Status | Reason |
|---|---|---|
| `IPodcastService.mc` | ✅ Unchanged | Interface contract doesn't depend on app type |
| `MockPodcastService.mc` | ✅ Unchanged | Mock data doesn't depend on app type |
| `PocketCastsPodcastService.mc` | ✅ Unchanged | API calls work the same regardless of app type |
| `CachedPodcastService.mc` | ✅ Unchanged | Cache decorator doesn't depend on app type |
| `CacheManager.mc` | ✅ Unchanged | Application.Storage works identically in both app types |

### 3.2 Views — MOSTLY UNCHANGED

| File | Status | Notes |
|---|---|---|
| `HomeMenuView.mc` | ✅ Unchanged | Split-dock home menu works in AudioContentProviderApp. Full View/Graphics API available. Now served from `getPlaybackConfigurationView()` instead of `getInitialView()`. |
| `QueueView.mc` | ✅ Unchanged | Menu2 list — works identically |
| `SubscribedView.mc` | ✅ Unchanged | Menu2 list — works identically |
| `EpisodeListView.mc` | ✅ Unchanged | Menu2 list — works identically |
| `SettingsView.mc` | ✅ Unchanged | Menu2 list — works identically |
| `LoginPromptView.mc` | ✅ Unchanged | Simple view — works identically |
| `MainMenuView.mc` | ✅ Unchanged | If still used — works identically |
| `NowPlayingView.mc` | ⚠️ Role change | Code survives, but role shifts from "playback controller" to "episode info display." See Section 2.4. |

### 3.3 Models — UNCHANGED

| File | Status |
|---|---|
| `DataModels.mc` | ✅ Unchanged |

### 3.4 Resources — UNCHANGED

All string resources, drawables, properties, and layouts remain the same.

### 3.5 Build Configuration — UNCHANGED

| File | Status |
|---|---|
| `monkey.jungle` | ✅ Unchanged |
| `developer_key/` | ✅ Unchanged |

---

## 4. Impact Assessment

### 4.1 Code Change Summary

| Category | Files | Effort |
|---|---|---|
| **Rewritten** | 2 (YoCastsApp.mc, manifest.xml) | ~2 hours |
| **New (migration)** | 1 (SyncConfigView.mc) | ~3 hours |
| **New (already planned)** | 4 (ContentDelegate, SyncDelegate, ContentIterator, DownloadManager) | Already in Phase C/D plan |
| **Modified** | 1 (NowPlayingView — role change, Phase D) | ~1 hour |
| **Unchanged** | 12+ files | No work |

**Total migration-specific effort: ~1 day.** The rest of the work was already planned in Phases C and D.

### 4.2 What the Migration Actually IS

The migration is **surprisingly small**. Here's why:

1. `AudioContentProviderApp` extends `AppBase`. It's not a different framework — it's the same framework with extra methods.
2. All our Views, Delegates, Graphics code, Menu2 usage — all AppBase API — work identically.
3. The manifest change is two lines.
4. The app class change is: (a) change the base class, (b) add 4-5 new method overrides, (c) keep all existing methods.
5. The new files (ContentDelegate, SyncDelegate, ContentIterator) were already planned — we just need them sooner.

### 4.3 UX Impact

| Aspect | Before | After |
|---|---|---|
| How users find YoCasts | App list → "YoCasts" | Music app → "YoCasts" provider |
| Browsing episodes | HomeMenu → Queue/Podcasts | Same (via playback configuration) |
| Now Playing UI | Our custom NowPlayingView | Garmin's native media player (better!) |
| Playback controls | Our BehaviorDelegate | System controls (skip, play/pause, volume, lock screen) |
| Headphone audio | ❌ Not possible | ✅ Full BT headphone support |
| Downloading episodes | ❌ Not possible | ✅ System-managed sync (charger + Wi-Fi) |
| Lock screen controls | ❌ Not available | ✅ Garmin's native lock screen player |

**The UX gets significantly better.** Users gain native playback controls, BT headphone audio, lock-screen integration, and system-managed background downloads. The only "loss" is the app moves from the app list to the music widget — but this is where users expect a podcast app to be.

---

## 5. Risk Assessment

### 5.1 Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AudioContentProviderApp doesn't support custom Views | **Very Low** | Critical | Confirmed via API docs, MonkeyMusic sample, Garmin blog, web research. AppBase inheritance guarantees View API access. |
| getInitialView() not called in audio provider context | **Medium** | Low | Both `getInitialView()` AND `getPlaybackConfigurationView()` return the same HomeMenuView. Covers both launch contexts. |
| Manifest type string is wrong | **Low** | Medium | MonkeyMusic sample uses `audio-content-provider-app`. Garmin forum confirms this is the correct value (not `audio-content-provider`). |
| Media permission not available on Venu 4 | **Very Low** | Critical | Venu 4 is a music-capable device. Spotify/Deezer exist for it. Media module is supported. |
| NowPlayingView conflicts with native player | **Low** | Low | NowPlayingView becomes info-only. No conflict — it's just a View on the stack. System player runs separately. |
| SyncDelegate deprecation breaks us | **Low** | Medium | Use `Communications.SyncDelegate` (not `Media.SyncDelegate`). Same interface, future-proof. |
| MonkeyMusic sample is outdated | **Low** | Low | API docs are current. Sample confirms the pattern; specific API calls verified against SDK 9.1.0. |
| Can't use `Media.startPlayback()` | **Medium** | Medium | If deprecated post-System 9, we rely on user pressing play from native player. Acceptable for v1. |
| Two-app approach is needed | **Very Low** | High | All evidence says single AudioContentProviderApp is the correct pattern. No music app on Garmin uses two apps. |

### 5.2 Confidence Level

**HIGH (8/10).** Multiple independent sources confirm this architecture:
1. Garmin API documentation (AudioContentProviderApp inherits AppBase)
2. MonkeyMusic official sample (working audio provider with views)
3. Garmin developer blog ("Creating Music Apps in Connect IQ 3")
4. Spotify/Deezer/Amazon Music all use this exact pattern
5. Web search confirms custom Views work in AudioContentProviderApp
6. Kaylee's thorough research doc with verified API references

**What would raise confidence to 10/10:** Hardware testing on Venu 4 with a minimal AudioContentProviderApp that shows a custom View with custom drawing. This should be the FIRST thing we build.

---

## 6. Step-by-Step Migration Plan

### Phase 0: Proof of Concept (Day 1, first half)

**Goal:** Validate that AudioContentProviderApp + custom Views work on the simulator.

1. **Create a branch:** `feature/audio-provider-migration`
2. **Change manifest.xml:**
   - `type` → `audio-content-provider-app`
   - Add `<iq:uses-permission id="Media"/>`
3. **Change YoCastsApp.mc:**
   - `extends AppBase` → `extends AudioContentProviderApp`
   - `AppBase.initialize()` → `AudioContentProviderApp.initialize()`
   - Add stub implementations:
     ```monkeyc
     function getPlaybackConfigurationView() {
         return getInitialView();  // reuse existing view
     }
     function getSyncConfigurationView() {
         return [new WatchUi.View(), new WatchUi.BehaviorDelegate()];  // placeholder
     }
     function getContentDelegate(args) {
         return new StubContentDelegate();  // minimal stub
     }
     ```
4. **Create minimal StubContentDelegate.mc** — empty implementation of ContentDelegate
5. **Build and run in simulator**
6. **Verify:** HomeMenuView renders, navigation works, views push/pop correctly

**Exit criteria:** App launches in simulator's music mode, HomeMenuView displays with split-dock layout, user can navigate to Queue/Podcasts/Episodes.

**If this fails:** Stop. Reassess. (It won't fail — but always have a gate.)

### Phase 0.5: Wire Real Configuration Views (Day 1, second half)

1. **Implement `getPlaybackConfigurationView()`** — returns HomeMenuView (our browsing entry point)
2. **Create `SyncConfigView.mc`** — simple Menu2 showing Up Next episodes with "Download" labels
3. **Implement `getSyncConfigurationView()`** — returns SyncConfigView
4. **Implement `getProviderIconInfo()`** — return our launcher icon with brand color
5. **Test both entry paths in simulator**

**Exit criteria:** Both playback config and sync config views launch correctly from the Music app in the simulator.

### Phase 1: Integrate with Existing Plan (Days 2+)

Once Phase 0/0.5 validates the architecture, proceed with the existing implementation plan phases (A → B → C → D → E), which already design the ContentDelegate, SyncDelegate, ContentIterator, and DownloadManager.

The key change: **Phase C and D are no longer future phases — they're enabled by the migration.** The manifest change and app class change happen in Phase 0. The actual media integration code is built in Phases C/D as already planned.

---

## 7. Updated Phase Plan

### Before: 5-Phase Plan (from `audio-download-implementation-plan.md`)

```
Phase A: Changelog & Position Tracking
Phase B: Sync Engine
Phase C: Audio Download Infrastructure
Phase D: Media Playback Integration
Phase E: Full Reconciliation & Polish
```

### After: Updated Plan with Migration

```
Phase 0: App Type Migration (NEW — 1 day)
  ├── 0a: Manifest + base class change
  ├── 0b: Stub implementations (ContentDelegate, SyncConfigView)
  ├── 0c: Simulator validation
  └── 0d: Wire real configuration views

Phase A: Changelog & Position Tracking (UNCHANGED — 2-3 days)
  ├── A1: Changelog in CacheManager
  ├── A2: Positions map
  ├── A3: PositionTracker module
  └── A4: ConnectivityManager module

Phase B: Sync Engine (UNCHANGED — 3-4 days)
  ├── B1: SyncEngine state machine
  └── B2: Wire to CachedPodcastService

Phase C: Audio Download Infrastructure (SIMPLIFIED — 3-4 days)
  ├── C1: YoCastsSyncDelegate (stub exists from Phase 0)
  ├── C2: DownloadManager
  ├── C3: Download manifest in CacheManager
  └── C4: SyncConfigView enhancement (real download selection)

Phase D: Media Playback Integration (SIMPLIFIED — 3-4 days)
  ├── D1: YoCastsContentIterator
  ├── D2: YoCastsContentDelegate (stub exists from Phase 0)
  ├── D3: PlaybackProfile configuration
  ├── D4: NowPlayingView role adaptation
  └── D5: Crash recovery — position persistence

Phase E: Full Reconciliation & Polish (UNCHANGED — 3-4 days)
  ├── E1: Queue reconciliation
  ├── E2: Storage pressure monitoring
  ├── E3: Long offline period handling
  ├── E4: IPodcastService interface updates
  ├── E5: Error handling hardening
  └── E6: Battery-aware behavior
```

### What Changed in the Plan

1. **Phase 0 added** — the actual migration. This is a clean gate: if Phase 0 fails, we know immediately with minimal wasted work.
2. **Phase C simplified** — the SyncDelegate stub already exists from Phase 0. Phase C just fills in the real implementation.
3. **Phase D simplified** — the ContentDelegate stub already exists from Phase 0. Phase D fills in real playback handling.
4. **Task D1 removed** — the old plan had a `YoCastsContentProvider` class. The AudioContentProviderApp API doesn't use a separate ContentProvider class; the app itself IS the provider. `getContentDelegate()` and `getSyncDelegate()` are methods on the app class directly.
5. **Task D4 (Update App Entry Point) removed** — this is now Phase 0, not Phase D.
6. **NowPlayingView changes move to D4** — role adaptation (playback controller → info view) is a Phase D task.
7. **Phases A, B, E are completely unchanged** — they don't depend on app type at all.

### Ordering Change

No ordering change. The phases still execute A → B → C → D → E. Phase 0 simply prepends one day of migration work that enables everything else.

---

## 8. File-by-File Impact Matrix

### Existing Files

| File | Migration Impact | Phase | Details |
|---|---|---|---|
| `manifest.xml` | **REWRITE** | 0 | `type` → `audio-content-provider-app`, add Media permission |
| `source/YoCastsApp.mc` | **REWRITE** | 0 | New base class, 5 new methods, existing methods preserved |
| `source/views/NowPlayingView.mc` | **MODIFY** | D | Role change: playback controller → episode info. Code mostly preserved. |
| `source/views/HomeMenuView.mc` | **MODIFY (minor)** | 0 | No code change — but now served from both `getInitialView()` and `getPlaybackConfigurationView()` |
| `source/views/QueueView.mc` | ✅ UNCHANGED | — | Works as-is |
| `source/views/SubscribedView.mc` | ✅ UNCHANGED | — | Works as-is |
| `source/views/EpisodeListView.mc` | ✅ UNCHANGED | — | Works as-is |
| `source/views/SettingsView.mc` | ✅ UNCHANGED | — | Works as-is |
| `source/views/LoginPromptView.mc` | ✅ UNCHANGED | — | Works as-is |
| `source/views/MainMenuView.mc` | ✅ UNCHANGED | — | Works as-is |
| `source/services/IPodcastService.mc` | ✅ UNCHANGED | — | Interface contract doesn't depend on app type |
| `source/services/MockPodcastService.mc` | ✅ UNCHANGED | — | Mock data unaffected |
| `source/services/PocketCastsPodcastService.mc` | ✅ UNCHANGED | — | API calls unaffected |
| `source/services/CachedPodcastService.mc` | ✅ UNCHANGED | — | Cache decorator unaffected |
| `source/services/CacheManager.mc` | ✅ UNCHANGED | — | Storage layer unaffected |
| `source/models/DataModels.mc` | ✅ UNCHANGED | — | Data keys unaffected |
| `monkey.jungle` | ✅ UNCHANGED | — | Build config unaffected |

### New Files (Migration-Specific)

| File | Phase | Purpose |
|---|---|---|
| `source/views/SyncConfigView.mc` | 0 | Sync configuration — episode download selection |
| `source/media/StubContentDelegate.mc` | 0 | Temporary stub for Phase 0 validation (removed in Phase D) |

### New Files (Already Planned, Enabled by Migration)

| File | Phase | Purpose |
|---|---|---|
| `source/services/PositionTracker.mc` | A | Position tracking with timer + battery awareness |
| `source/services/ConnectivityManager.mc` | A | Connectivity polling and state transitions |
| `source/services/SyncEngine.mc` | B | Sync state machine — push, pull, reconcile |
| `source/services/DownloadManager.mc` | C | Download queue management with battery guards |
| `source/media/YoCastsSyncDelegate.mc` | C | System-triggered downloads (charger + Wi-Fi) |
| `source/media/YoCastsContentIterator.mc` | D | Playlist from downloaded episodes |
| `source/media/YoCastsContentDelegate.mc` | D | Playback events → position tracking (replaces stub) |

---

## 9. Open Questions

### 9.1 Resolved by This Evaluation

| Question | Answer |
|---|---|
| Can AudioContentProviderApp use custom Views? | **Yes.** Inherits from AppBase. Full View/Graphics/InputDelegate API. |
| Do we lose our HomeMenuView? | **No.** Served from `getPlaybackConfigurationView()`. |
| Is this a big-bang migration? | **No.** Phase 0 is a 1-day focused change. Everything else builds incrementally. |
| Can we keep our service architecture? | **Yes.** IPodcastService, CacheManager, all services completely unchanged. |
| What's the manifest type string? | `audio-content-provider-app` (confirmed from MonkeyMusic sample). |
| Do we need the Media permission? | **Yes.** Add `<iq:uses-permission id="Media"/>`. |
| What replaces NowPlayingView? | Garmin's native media player during playback. NowPlayingView becomes info-only. |

### 9.2 Still Open — Require Hardware/Simulator Testing

| Question | Risk | When to Resolve |
|---|---|---|
| Does `getInitialView()` actually get called for audio providers? | Low — we return the same view from both entry points | Phase 0 simulator testing |
| Does `Media.startPlayback()` work on System 9+ devices? | Medium — may be deprecated | Phase D |
| Exact manifest version attribute — is `version="4"` correct for audio providers? | Low — MonkeyMusic uses `version="0"` | Phase 0 |
| Can `getSyncDelegate()` return `Communications.SyncDelegate`? | Low — API docs say yes | Phase C |
| How does the simulator handle audio content provider apps? | Unknown — may need specific run configuration | Phase 0 (first thing we test) |

### 9.3 Corrections to Existing Documents

1. **`audio-download-implementation-plan.md` Task D1:** References `YoCastsContentProvider extends Media.ContentProvider` — this class doesn't exist. The AudioContentProviderApp IS the provider. Methods like `getContentDelegate()` and `getSyncDelegate()` live on the app class itself, not a separate ContentProvider class. **Fix:** Remove YoCastsContentProvider. Move its responsibilities to YoCastsApp method overrides.

2. **`audio-download-implementation-plan.md` manifest change:** Listed as Phase C. Now Phase 0. The manifest change is the first thing we do, not a downstream step.

3. **`garmin-media-and-background-research.md` Section 7.1 Option A:** States "App only accessible from music widget, not app list" and "Limited UI options — sync config view + playback config view only." The first part is correct (it's in the Music app, not the main app list). The second part is WRONG — you have full View API access inside those views. WatchUi.pushView() works. You can build as complex a UI as you want.

---

## Appendix A: MonkeyMusic Sample Reference

The official Garmin MonkeyMusic sample app confirms our approach:

```monkeyc
// MonkeyMusicApp.mc — the ENTIRE app class
class MonkeyMusicApp extends Application.AudioContentProviderApp {
    function initialize() { AudioContentProviderApp.initialize(); }
    function getContentDelegate(args) { return new ContentDelegate(); }
    function getSyncDelegate() { return new SyncDelegate(); }
    function getPlaybackConfigurationView() { return [new ConfigurePlaybackView()]; }
    function getSyncConfigurationView() { return [new ConfigureSyncView()]; }
    function getProviderIconInfo() {
        return new Media.ProviderIconInfo(Rez.Drawables.logo_with_palette, 0x4CBB17);
    }
}
```

**Manifest:**
```xml
<iq:application type="audio-content-provider-app" entry="MonkeyMusicApp" ...>
    <iq:permissions>
        <iq:uses-permission id="Communications"/>
    </iq:permissions>
</iq:application>
```

Note: MonkeyMusic doesn't even list the Media permission explicitly — it may be implicit for audio-content-provider-app type. We should test both ways.

**Source:** [github.com/garmin/connectiq-apps/audio-provider/monkeymusic](https://github.com/garmin/connectiq-apps/tree/master/audio-provider/monkeymusic)

---

## Appendix B: Decision Rationale Summary

**Why Option A (AudioContentProviderApp) and not the alternatives:**

| Option | Verdict | Reason |
|---|---|---|
| **A: AudioContentProviderApp** | ✅ **Selected** | Only path to audio playback. Full UI capabilities preserved. How every music/podcast app on Garmin works. |
| **B: Two separate apps** | ❌ Rejected | Unnecessary complexity. Can't reliably share data between apps. User confusion with two app entries. No music app on Garmin uses this pattern. |
| **C: Device app with manual audio** | ❌ Rejected | Cannot play audio through BT headphones. Cannot access Media cache. Cannot download large files reliably. Dead end. |
| **Hybrid: widget + audio provider** | ❌ Rejected | Community consensus is you can't register as both types. Even if possible, AudioContentProviderApp already has full UI capabilities, making a widget redundant. |

---

*This document is the definitive architecture evaluation for the AppBase → AudioContentProviderApp migration. It was produced from exhaustive review of Kaylee's research, Garmin API documentation, the MonkeyMusic sample, the Garmin developer blog, community forums, and web research. All decisions recorded here supersede any conflicting guidance in earlier documents.*
