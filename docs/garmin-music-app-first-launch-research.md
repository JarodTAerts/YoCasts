# Garmin Music App First-Launch Experience Research

> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-04-14  
> **Status:** Research Complete  
> **Purpose:** Understand how existing Garmin CIQ audio apps handle first-launch when no content is downloaded, to fix our AudioContentProviderApp crash

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The AudioContentProviderApp Lifecycle](#2-the-audiocontentproviderapp-lifecycle)
3. [Spotify on Garmin — First Launch Flow](#3-spotify-on-garmin--first-launch-flow)
4. [Deezer on Garmin — First Launch Flow](#4-deezer-on-garmin--first-launch-flow)
5. [Amazon Music on Garmin — First Launch Flow](#5-amazon-music-on-garmin--first-launch-flow)
6. [Podcast Apps on Garmin](#6-podcast-apps-on-garmin)
7. [Garmin's Official MonkeyMusic Sample App](#7-garmins-official-monkeymusic-sample-app)
8. [Does the System Handle "No Content"?](#8-does-the-system-handle-no-content)
9. [The Universal Music Provider UX Pattern](#9-the-universal-music-provider-ux-pattern)
10. [Recommendations for YoCasts](#10-recommendations-for-yocasts)

---

## 1. Executive Summary

**The crash is our fault, and the fix is straightforward.**

Every Garmin music provider app — Spotify, Deezer, Amazon Music, and indie podcast apps — must handle the "no content downloaded" state itself. The Garmin system UI does **NOT** provide any fallback. If `getPlaybackConfigurationView()` or `getContentDelegate()` returns something invalid or crashes, the app dies.

The standard pattern across all apps:

1. **`getPlaybackConfigurationView()` always returns a valid View** — even when no content exists
2. That View checks for downloaded content on `onShow()`
3. If content exists → push a playback configuration menu
4. If no content → display a friendly message ("No songs on the system", "No episodes downloaded", etc.)
5. User presses back → returns to system music controls

This is exactly what Garmin's official `MonkeyMusic` sample demonstrates, and what the open-source `Garmin Podcasts` app does in production.

---

## 2. The AudioContentProviderApp Lifecycle

### Entry Points — When Does the System Call Our App?

An `AudioContentProviderApp` has **two user-facing entry points** and **one system entry point**:

| Entry Point | Method Called | When Triggered |
|---|---|---|
| **Play/Configure** | `getPlaybackConfigurationView()` | User taps the play button or selects the provider to configure playback |
| **Sync/Download** | `getSyncConfigurationView()` | User goes to Music > Manage > Music Providers > [App] to sync content |
| **System Playback** | `getContentDelegate(args)` | System needs to iterate available content for the native media player |

### Critical API Contract

From the [Garmin API docs](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html):

> **`getPlaybackConfigurationView()`** — "This method must be overridden in derived classes. **If called, this function will cause the application to crash.**"

> **`getSyncConfigurationView()`** — Same warning. Must override or crash.

> **`getContentDelegate(args)`** — Must return a valid `Media.ContentDelegate`. No override = crash.

**The base class intentionally crashes if you don't override these methods.** There is no default behavior, no system fallback, no "empty state" screen provided by Garmin. The app is 100% responsible.

### Order of Calls

1. `getContentDelegate()` is called first — system needs to know what content is available
2. `getPlaybackConfigurationView()` is called when user wants to configure/start playback
3. The View returned must handle ALL states: authenticated/not, content/no content

---

## 3. Spotify on Garmin — First Launch Flow

### Step-by-Step User Experience

1. **Navigate to Music**: On watch, go to Music widget or hold DOWN key → Music
2. **Select Music Providers**: Tap "Music Providers"
3. **Choose Spotify**: Select Spotify from list of installed providers
4. **Auth Prompt on Watch**: Watch displays "Set up on your phone" or a unique auth code + URL
5. **Auth on Phone**: Garmin Connect app on phone opens Spotify login. User enters Spotify Premium credentials and authorizes
6. **Confirmation**: Both watch and phone show "Connected" confirmation
7. **Browse Library**: Watch shows Spotify's `getSyncConfigurationView()` — user's playlists, albums, podcasts appear
8. **Select Content to Download**: User picks playlists to sync
9. **Download Over WiFi**: Watch downloads selected content (shows progress bar)
10. **Ready to Play**: Content now available in `getPlaybackConfigurationView()`

### Empty State Handling

- **Before auth**: Spotify shows the auth/setup screen (not a crash)
- **After auth, no downloads**: Spotify shows the sync configuration view with available playlists to download. If user tries to *play* instead, the playback config view shows the playlist browser or a message indicating no downloaded content
- **Key pattern**: Auth flow is embedded in the View returned by `getPlaybackConfigurationView()` and `getSyncConfigurationView()` — check auth first, then check content

**Sources:**
- [Garmin Support: Syncing Spotify](https://support.garmin.com/en-US/?faq=NP5CwjAhVN36MoazFOSrxA)
- [Pocket-lint: How to add Spotify](https://www.pocket-lint.com/how-to-add-spotify-to-garmin-watch/)

---

## 4. Deezer on Garmin — First Launch Flow

### Step-by-Step User Experience

1. **Select Deezer** from Music Providers
2. **Auth Prompt**: Watch shows "Log in via Garmin Connect"
3. **Auth on Phone**: Link Deezer account through Garmin Connect app
4. **Empty Library**: First launch shows NO music — this is normal and expected
5. **Browse & Select**: Navigate to "My Playlists" → select playlists to download
6. **Sync Over WiFi**: Download content (Garmin recommends being on charger during sync)
7. **Play**: Content available for offline playback

### Empty State Handling

- Deezer explicitly states that **no music is preloaded** on first launch
- The empty state is the normal first-launch state — user must actively select and sync content
- If no playlists exist in the Deezer account, the app shows "no playlists available"
- Large playlists (>150 songs) can cause sync issues — app handles this gracefully

**Sources:**
- [Deezer Support: Deezer on Garmin](https://support.deezer.com/hc/en-gb/articles/360001242309-Deezer-On-Garmin)
- [Garmin Support: Deezer FAQ](https://support.garmin.com/en-GB/?faq=Qcf8AHEg1d2p0YElgNB0k6)

---

## 5. Amazon Music on Garmin — First Launch Flow

### Step-by-Step User Experience

1. **Install**: Amazon Music app installed from Connect IQ store
2. **Select Provider**: Settings > Music > Music Providers > Amazon Music
3. **Device Code Auth**: Watch displays a unique code + URL (amazon.com/us/code)
4. **Auth on Computer/Phone**: User visits URL, enters code, signs in with Amazon credentials
5. **Confirmation**: Watch confirms registration
6. **Browse**: Open Amazon Music on watch → "Browse" → select playlists/albums
7. **Download Over WiFi**: Sync selected content
8. **Play**: Offline playback available

### Empty State Handling

- Amazon Music uses a **device code flow** (similar to TV auth) rather than phone-proxied OAuth
- Before content is downloaded, the app shows browse options but no playable content
- No crash on empty state — shows the library/browse view with instructions to add content

**Sources:**
- [Garmin Support: Amazon Music Setup](https://support.garmin.com/en-US/?faq=d0N2XUc9wi89EPgZ9tbmqA)
- [Wareable: Amazon Music on Garmin](https://www.wareable.com/garmin/how-to-sync-amazon-music-garmin-watch)

---

## 6. Podcast Apps on Garmin

### 6.1 Garmin Podcasts (by Lucas Asselli) — Open Source

The most relevant reference for YoCasts. This is a **free, open-source AudioContentProviderApp** that handles podcasts on Garmin.

**Source:** [github.com/lucasasselli/garmin-podcasts](https://github.com/lucasasselli/garmin-podcasts)

#### First Launch Flow

1. **Set as Music Provider**: Music widget → Menu → Manage → Music Providers → Podcasts
2. **Main Menu appears**: Queue, Podcasts, Episodes, Settings (same view for both playback and sync config)
3. **No Auth Required**: Uses Podcast Index (open service) — no account needed
4. **Optional**: Link gpodder.net account for subscription sync
5. **Subscribe**: Manage Subscriptions → Subscribe → search by title/feed
6. **Download**: Manage Episodes → Download → pick episodes → confirm
7. **Play**: Queue → select episodes → start playback

#### Empty State Handling (CRITICAL — from actual source code)

```monkeyc
// PodcastsApp.mc — Both entry points return the same MainMenu
function getPlaybackConfigurationView() {
    initData();
    return new MainMenu().get();  // Always returns a valid view!
}

function getSyncConfigurationView() {
    initData();
    return new MainMenu().get();  // Same menu for both
}
```

```monkeyc
// MainMenu.mc — Queue callback handles empty state
function callbackQueue(){
    var downloadedCount = getDownloadedSize();
    if (downloadedCount > 0) {
        // Episodes downloaded → proceed to playback
        Media.startPlayback(null);
    } else {
        // No episodes → show alert, don't crash
        var alert = new Ui.CompactAlert(Rez.Strings.errorNoQueueEpisodes);
        alert.show();
    }
}
```

**Key Design Decisions:**
- `getPlaybackConfigurationView()` and `getSyncConfigurationView()` return the **same** main menu
- No separate "playback mode" vs "sync mode" — one unified menu handles both
- Empty state = show alert when user tries to play, not on app launch
- App is always navigable, even with zero content
- `initData()` called in both entry points to ensure storage is initialized

### 6.2 Playrun

- Web-based podcast selection (playrun.app) → sync to device
- First launch prompts to visit website and configure podcasts
- Empty state = "set up at playrun.app"

### 6.3 RUNCASTS

- Similar model to Playrun — web-based selection, device sync
- Some premium features are paid
- First launch shows setup instructions

### 6.4 Podcast Addict

- **Does NOT have a Garmin CIQ app** — Android-only
- No native Garmin integration
- Workaround: manually download episodes and transfer audio files to watch

---

## 7. Garmin's Official MonkeyMusic Sample App

This is the **canonical reference implementation** from Garmin themselves.

**Source:** [github.com/garmin/connectiq-apps/audio-provider/monkeymusic](https://github.com/garmin/connectiq-apps/tree/master/audio-provider/monkeymusic)

### App Structure

```monkeyc
// MonkeyMusicApp.mc
class MonkeyMusicApp extends Application.AudioContentProviderApp {
    
    function getContentDelegate(args) {
        return new ContentDelegate();       // Always valid
    }
    
    function getPlaybackConfigurationView() {
        return [new ConfigurePlaybackView()];  // Always valid View
    }
    
    function getSyncConfigurationView() {
        return [new ConfigureSyncView()];      // Always valid View
    }
    
    function getProviderIconInfo() {
        return new Media.ProviderIconInfo(Rez.Drawables.logo_with_palette, 0x4CBB17);
    }
}
```

### The Empty State Pattern — ConfigurePlaybackView.mc

**This is the golden reference for our fix:**

```monkeyc
class ConfigurePlaybackView extends WatchUi.View {
    private var mMenuShown = false;
    private var mMessage = "";

    function initialize() {
        View.initialize();
        // Check auth — push OAuth view if needed
        var token = Application.getApp().getProperty(Properties.AUTHENTICATION_TOKEN);
        if (token == null) {
            WatchUi.pushView(new OauthView(), null, WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onShow() {
        if (!mMenuShown) {
            var songs = Application.getApp().getProperty(Properties.SONGS);
            
            // THE KEY CHECK: Content exists?
            if ((songs != null) && (songs.size() != 0)) {
                // YES → push the playback config menu
                WatchUi.pushView(new ConfigurePlaybackMenu(), 
                    new ConfigurePlaybackMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
            } else {
                // NO → show friendly message, don't crash
                mMessage = "No songs on\nthe system";
            }
            mMenuShown = true;
        } else {
            // Returning from menu → pop back to system
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_MEDIUM,
            mMessage, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
```

### The Sync Configuration View — ConfigureSyncView.mc

```monkeyc
class ConfigureSyncView extends WatchUi.View {
    function onShow() {
        // Check auth first
        var token = Application.getApp().getProperty(Properties.AUTHENTICATION_TOKEN);
        if (token == null) {
            WatchUi.pushView(new OauthView(), null, WatchUi.SLIDE_IMMEDIATE);
        } else if (mMenuShown) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        } else {
            // Fetch available songs from server
            Communications.makeWebRequest(...);
        }
    }

    function onUpdate(dc) {
        // Show "Fetching Songs..." while loading
        dc.drawText(..., "Fetching Songs...", ...);
    }
}
```

### ContentIterator — Handles Empty Playlist Gracefully

```monkeyc
function get() {
    var obj = null;
    if ((mSongIndex >= 0) && (mSongIndex < mPlaylist.size())) {
        obj = Media.getCachedContentObj(
            new Media.ContentRef(mPlaylist[mSongIndex], Media.CONTENT_TYPE_AUDIO));
    }
    return obj;  // Returns null if no songs — doesn't crash
}
```

---

## 8. Does the System Handle "No Content"?

### Answer: NO. The app handles everything.

The Garmin system UI provides:
- The "Music Providers" list in Settings > Music
- The native media player (play/pause/skip controls)
- The sync progress indicator during downloads

The Garmin system UI does **NOT** provide:
- ❌ Any "no content" fallback screen
- ❌ Any "please sync first" prompt
- ❌ Any empty state handling
- ❌ Any login/auth screens

**Every music provider app must handle these states itself** through the Views returned by `getPlaybackConfigurationView()` and `getSyncConfigurationView()`.

If these methods crash (unimplemented, null reference, etc.), the app simply dies. The system shows a generic error or returns to the previous screen.

---

## 9. The Universal Music Provider UX Pattern

All Garmin music provider apps follow this universal flow:

```
┌─────────────────────────────────────────────┐
│           SYSTEM: Music Widget              │
│  User selects [YoCasts] from providers list │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│    APP: getPlaybackConfigurationView()      │
│    Always returns a valid View              │
└──────────────────┬──────────────────────────┘
                   │
          ┌────────┴────────┐
          ▼                 ▼
    ┌───────────┐    ┌──────────────┐
    │ Not Authed│    │ Authenticated│
    │           │    │              │
    │ Push auth │    │ Check content│
    │ view      │    │              │
    └───────────┘    └──────┬───────┘
                           │
                  ┌────────┴────────┐
                  ▼                 ▼
           ┌───────────┐    ┌──────────────┐
           │ No Content │    │ Has Content  │
           │            │    │              │
           │ Show msg:  │    │ Push config  │
           │ "No songs" │    │ menu / start │
           │ "Sync      │    │ playback     │
           │  first"    │    │              │
           └───────────┘    └──────────────┘
```

### The Three States Every View Must Handle

1. **Not Authenticated** → Push auth/login/OAuth view
2. **Authenticated, No Content** → Display friendly message with guidance
3. **Authenticated, Has Content** → Show playback configuration / start playing

### Design Variations

| App | "No Content" Message | Action Available |
|---|---|---|
| MonkeyMusic (Garmin) | "No songs on the system" | Back button only |
| Garmin Podcasts | Alert: "No episodes in queue" | Back to main menu |
| Spotify | Shows playlist browser | "Download playlists" |
| Deezer | Shows "My Playlists" (empty) | "Select playlists to sync" |
| Amazon Music | Shows "Browse" | "Select content to download" |

**The commercial apps (Spotify, Deezer, Amazon) handle empty state by showing the sync/download UI directly from the playback view** — blurring the line between playback config and sync config. This is the better UX.

---

## 10. Recommendations for YoCasts

### Immediate Fix: Prevent the Crash

Our `getPlaybackConfigurationView()` must **always return a valid View** that handles all three states (not authed, no content, has content).

### Recommended Pattern (following Garmin Podcasts model)

```monkeyc
// YoCastsApp.mc
function getPlaybackConfigurationView() {
    return [new YoCastsMainView(), new YoCastsMainDelegate()];
}

function getSyncConfigurationView() {
    return [new YoCastsMainView(), new YoCastsMainDelegate()];
    // Same view for both — like Garmin Podcasts does
}
```

```monkeyc
// YoCastsMainView.mc
class YoCastsMainView extends WatchUi.View {
    function onShow() {
        if (!isAuthenticated()) {
            // State 1: Not logged in
            // Show "Set up in Garmin Connect" message
            mState = STATE_NO_AUTH;
        } else if (!hasDownloadedEpisodes()) {
            // State 2: Logged in but no content
            // Show "No episodes downloaded\nSync from Music settings"
            mState = STATE_NO_CONTENT;
        } else {
            // State 3: Has content → show queue/episode picker
            WatchUi.pushView(new QueueMenu(), new QueueMenuDelegate(), 
                WatchUi.SLIDE_IMMEDIATE);
        }
    }
}
```

### UX Copy for Empty States

**Not Authenticated:**
```
YoCasts

Set up your account
in Garmin Connect
Mobile settings
```

**Authenticated, No Content:**
```
No Episodes

Sync podcasts from
Music > Manage >
Music Providers
```

### Why Same View for Both Entry Points?

The Garmin Podcasts app uses the same MainMenu for both `getPlaybackConfigurationView()` and `getSyncConfigurationView()`. This makes sense for podcasts because:

1. Users don't distinguish between "configure playback" and "configure sync" — they just want to manage their podcasts
2. A unified menu simplifies the mental model
3. The podcast management workflow (subscribe → download → queue → play) is linear, not modal

YoCasts should follow this pattern. The PocketCasts integration means our workflow is: **login → sync queue from PocketCasts → download episodes → play**. One menu serves all of these.

### ContentDelegate Safety

Our `ContentDelegate` and `ContentIterator` must also handle empty state:

```monkeyc
// ContentIterator.mc
function get() {
    if (mPlaylist == null || mPlaylist.size() == 0) {
        return null;  // No content — don't crash
    }
    // ... normal content lookup
}
```

---

## Sources

### Official Garmin Documentation
- [AudioContentProviderApp API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html)
- [Toybox.Media API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Media.html)
- [Connect IQ FAQ: Audio Content Provider](https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-an-audio-content-provider/)
- [Creating Music Apps in Connect IQ 3 (Garmin Blog)](https://www.garmin.com/en-US/blog/developer/creating-music-apps-3x/)

### Reference Implementations
- [MonkeyMusic Sample App (Garmin Official)](https://github.com/garmin/connectiq-apps/tree/master/audio-provider/monkeymusic)
- [Garmin Podcasts (Lucas Asselli)](https://github.com/lucasasselli/garmin-podcasts)

### User Guides & Support
- [Garmin: Syncing Spotify](https://support.garmin.com/en-US/?faq=NP5CwjAhVN36MoazFOSrxA)
- [Garmin: Deezer FAQ](https://support.garmin.com/en-GB/?faq=Qcf8AHEg1d2p0YElgNB0k6)
- [Garmin: Amazon Music Setup](https://support.garmin.com/en-US/?faq=d0N2XUc9wi89EPgZ9tbmqA)
- [Deezer Support: Deezer on Garmin](https://support.deezer.com/hc/en-gb/articles/360001242309-Deezer-On-Garmin)

### Garmin Developer Forums
- [How do you get started making an Audio Content Provider?](https://forums.garmin.com/developer/connect-iq/f/discussion/347595/how-do-you-even-get-started-making-an-audio-content-provider)
