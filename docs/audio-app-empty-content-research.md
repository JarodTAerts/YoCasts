# AudioContentProviderApp Empty Content Research

**Date:** 2026-04-14  
**Author:** Mal (Lead)  
**Status:** Complete  
**Question:** Can an AudioContentProviderApp launch, show a custom UI for login/browsing, let the user select episodes to download, and THEN provide content to the native player?

## Answer: YES

AudioContentProviderApp **absolutely supports** launching with zero downloaded content. The crash we experienced was NOT caused by ContentIterator.get() returning null — that's valid, expected API behavior. The crash was almost certainly the **API 6.0 Symbol Not Found bug** (documented in Garmin bug tracker) or an implementation issue in our stub code. The framework is designed for exactly the workflow Jarod described.

---

## 1. How AudioContentProviderApp Entry Points Work

### App Does NOT Appear in Normal App List

When manifest type is `audio-content-provider-app`, the app is **invisible** in the watch's app list. It only appears in:
- **Music Controls → Music Providers** (hold DOWN on watch → select provider)
- **Settings → Music → Music Providers**

This means `getInitialView()` is **never called by the system**. The MonkeyMusic sample does not override it at all.

### Entry Points (System-Triggered)

| Method | When Called | Purpose |
|--------|-----------|---------|
| `getPlaybackConfigurationView()` | User selects app from music provider list | Show UI for browsing/configuring what to play |
| `getSyncConfigurationView()` | User enters sync mode (device-dependent) | Show UI for selecting content to download |
| `getContentDelegate()` | **Immediately at launch** (before views) | System probes available content |
| `getSyncDelegate()` | System initiates sync (charger + Wi-Fi) | Handle actual downloads |
| `getProviderIconInfo()` | Provider list rendering | Icon + accent color |

### Critical Finding: getContentDelegate() Called At Launch

From the Garmin bug report (forum post "Audio apps on API 6.0 devices crash simulator on start"), the system call sequence on launch is:

```
getContentDelegate()         ← Called FIRST
ContentIterator.initialize()
ContentIterator.getPlaybackProfile()
ContentIterator.peekPrevious()  ← Returns null (no content) — OK
ContentIterator.get()           ← Returns null (no content) — OK
ContentIterator.canSkip()
ContentIterator.peekNext()      ← Returns null (no content) — OK
ContentIterator.shuffling()
```

On a working device (Fenix 7), this entire sequence completes successfully even when content methods return null. The native player simply shows "No Media" to the user.

**Source:** https://forums.garmin.com/developer/connect-iq/i/bug-reports/audio-apps-on-api-6-0-devices-crash-simulator-on-start

---

## 2. What Caused Our Crash

### Most Likely: API 6.0 Symbol Not Found Bug

The Garmin bug report documents that on API 6.0 devices (Fenix E, Forerunner 970), even the **stock template audio app** crashes with:
```
Error: Symbol Not Found Error
Details: Error starting music app
Stack: (empty)
```

This crash happens after `getPlaybackProfile()` returns but before `peekPrevious()` is called. It's an **SDK/simulator bug**, not an app code bug.

**Workaround:** Target API levels below 6.0, or wait for SDK fix. Our Venu 4 target (API 4.2.0+) may or may not be affected depending on the SDK version used.

### Also Possible: getInitialView() Override Conflict

Our `YoCastsApp.mc` currently overrides `getInitialView()`. If the app type was changed to `AudioContentProviderApp` while keeping `getInitialView()`, the system may have attempted to call it in some contexts (e.g., background service launch), causing undefined behavior. MonkeyMusic does **NOT** override `getInitialView()`.

### NOT the Cause: ContentIterator.get() Returning Null

The API explicitly defines `get()` as returning `Media.Content or Null`. Returning null means "no current track" and the native player handles this by showing "No Media" — no crash.

---

## 3. MonkeyMusic Sample: How Garmin Handles Empty Content

### MonkeyMusicApp.mc — The App Class

```monkeyc
class MonkeyMusicApp extends Application.AudioContentProviderApp {
    // NO getInitialView() override!
    
    function getContentDelegate(args) {
        return new ContentDelegate();  // Always returns a delegate
    }
    
    function getPlaybackConfigurationView() {
        return [new ConfigurePlaybackView()];  // Browse/configure UI
    }
    
    function getSyncConfigurationView() {
        return [new ConfigureSyncView()];  // Download selection UI
    }
    
    function getSyncDelegate() {
        return new SyncDelegate();  // Handles actual downloads
    }
}
```

### ConfigurePlaybackView.mc — Graceful Empty State Handling

```monkeyc
class ConfigurePlaybackView extends WatchUi.View {
    function initialize() {
        View.initialize();
        // Push auth view if not authenticated
        var token = app.getProperty(Properties.AUTHENTICATION_TOKEN);
        if (token == null) {
            WatchUi.pushView(new OauthView(), null, SLIDE_IMMEDIATE);
        }
    }
    
    function onShow() {
        if (!mMenuShown) {
            var songs = app.getProperty(Properties.SONGS);
            if ((songs != null) && (songs.size() != 0)) {
                // Content exists → show playback configuration menu
                WatchUi.pushView(new ConfigurePlaybackMenu(), ...);
            } else {
                // NO content → show message (NOT a crash!)
                mMessage = "No songs on\nthe system";
            }
            mMenuShown = true;
        } else {
            WatchUi.popView(SLIDE_IMMEDIATE);
        }
    }
}
```

**Key pattern:** ConfigurePlaybackView acts as a **gate**. It checks auth first, then checks content. If no content exists, it shows a helpful message. No crash.

### ContentIterator.mc — Empty Playlist Is Safe

```monkeyc
function get() {
    var obj = null;
    if ((mSongIndex >= 0) && (mSongIndex < mPlaylist.size())) {
        obj = Media.getCachedContentObj(new ContentRef(mPlaylist[mSongIndex], CONTENT_TYPE_AUDIO));
    }
    return obj;  // Returns null if playlist is empty — by design
}

function initializePlaylist() {
    var tempPlaylist = app.getProperty(Properties.PLAYLIST);
    if (tempPlaylist == null) {
        // No playlist configured → try all cached audio
        var availableSongs = Media.getContentRefIter({:contentType => CONTENT_TYPE_AUDIO});
        mPlaylist = [];
        if (availableSongs != null) {
            var song = availableSongs.next();
            while (song != null) {
                mPlaylist.add(song.getId());
                song = availableSongs.next();
            }
        }
        // mPlaylist may be empty [] — that's fine
    }
}
```

**Source:** https://github.com/garmin/connectiq-apps/blob/master/audio-provider/monkeymusic/source/

---

## 4. The User Flow That Works for YoCasts

### First Launch (No Content)

```
User holds DOWN → Music Controls → Music Providers → YoCasts
                                          │
                     System calls getContentDelegate()
                     ContentIterator returns null from get()
                     Native player notes: "no content available"
                                          │
                     System calls getPlaybackConfigurationView()
                                          │
                              ┌───────────▼───────────┐
                              │  OUR UI STARTS HERE   │
                              │                       │
                              │  1. Check credentials  │
                              │     → Login prompt     │
                              │                       │
                              │  2. Check content      │
                              │     → "No episodes"    │
                              │     → Browse podcasts  │
                              │     → Select episodes  │
                              │                       │
                              │  3. Trigger sync       │
                              │     → Download starts  │
                              └───────────────────────┘
```

### After Content Is Downloaded

```
User opens Music Controls → YoCasts already selected
                                          │
                     System calls getContentDelegate()
                     ContentIterator returns episode from get()
                     Native player shows: episode title, controls
                                          │
                     User presses PLAY → audio streams via BT headphones
```

### Full Lifecycle

1. **Install** → App appears in Music Providers list
2. **First select** → `getPlaybackConfigurationView()` → Our login/browse UI
3. **Browse** → User sees subscribed podcasts, episodes (via our PocketCastsService)
4. **Select for download** → User picks episodes → stored in sync queue
5. **Sync** → `getSyncDelegate()` → Downloads episodes to device storage
6. **Play** → `getContentDelegate()` → ContentIterator provides downloaded episodes → Native player plays via BT

---

## 5. What We Need to Change for Migration

### Must Remove: getInitialView() Override

AudioContentProviderApp should NOT override `getInitialView()`. All UI entry goes through `getPlaybackConfigurationView()`.

### getPlaybackConfigurationView() → Our Main UI

This is where HomeMenuView lives. Pattern from MonkeyMusic:

```monkeyc
function getPlaybackConfigurationView() {
    // Wrap in a gate view that checks auth + content
    return [new PlaybackGateView(getService())];
}
```

Where `PlaybackGateView`:
1. Checks credentials → pushes login prompt if missing
2. Checks downloaded content → shows browse UI regardless
3. If content exists, also offers "Play now" option
4. If no content, shows "No episodes downloaded — browse to add some"

### getSyncConfigurationView() → Episode Selection UI

This is where users pick which episodes to download:

```monkeyc
function getSyncConfigurationView() {
    return [new SyncConfigView(getService())];
}
```

### ContentDelegate Must Handle Empty State

Our `YoCastsContentDelegate` and `YoCastsContentIterator` stubs are **already correct** — they return null from all content methods. This is the right behavior when no content is downloaded.

### ContentIterator.get() Returning Null Is Fine

The API explicitly supports this:
- `get() as Media.Content or Null` — null means "no current track"
- `getContentIterator() as Media.ContentIterator or Null` — null means "no iterator available"
- The native player displays "No Media" and doesn't crash

---

## 6. getSyncConfigurationView() Behavior

### When Is It Called?

Forum post from a developer with a working podcast audio provider app on Fenix 7 Pro:
> "I have found no scenario on my device where getSyncConfigurationView() is called. I'll probably just return my main menu from that call."

**Source:** https://forums.garmin.com/developer/connect-iq/f/discussion/380397/when-is-sync-configuration-view-shown-in-audio-provider

This suggests `getSyncConfigurationView()` may rarely or never be triggered on some devices. The primary entry point is always `getPlaybackConfigurationView()`.

### Our Strategy

Implement `getSyncConfigurationView()` to return the same HomeMenuView (or a focused episode-selection view). This way it works regardless of which entry point the system uses.

---

## 7. Known SDK Bugs to Watch For

### API 6.0 Symbol Not Found (Active Bug)

- **Affects:** API 6.0 devices (Fenix E, Forerunner 970)
- **Symptom:** Crash with "Symbol Not Found Error" on start, empty stack trace
- **Cause:** SDK simulator bug — `peekPrevious()` not properly defined for API 6.0
- **Impact on YoCasts:** Venu 4 is NOT API 6.0 — likely unaffected
- **Source:** https://forums.garmin.com/developer/connect-iq/i/bug-reports/audio-apps-on-api-6-0-devices-crash-simulator-on-start

### Manifest Type Must Be Exact

The correct manifest type is `audio-content-provider-app` (NOT `audio-content-provider`). The docs are inconsistent about this.

**Source:** https://forums.garmin.com/developer/connect-iq/i/bug-reports/docs-issue-application-type-audio-content-provider-does-not-exist

---

## 8. Recommendations

### Immediate Action: Re-attempt Migration

The AudioContentProviderApp migration should work. The crash was not caused by empty content. Steps:

1. **Change manifest type** to `audio-content-provider-app`
2. **Remove `getInitialView()` override** — not called for audio providers
3. **Wire `getPlaybackConfigurationView()`** to return our HomeMenuView (with auth gate)
4. **Keep existing ContentIterator stubs** — returning null is correct
5. **Test on Venu 4 simulator** specifically (avoid API 6.0 targets)

### Implementation Checklist

- [ ] `YoCastsApp extends AudioContentProviderApp` (not AppBase)
- [ ] Remove `getInitialView()` — dead code for this app type
- [ ] `getPlaybackConfigurationView()` → auth-gated HomeMenuView
- [ ] `getSyncConfigurationView()` → same UI or episode picker
- [ ] `getContentDelegate()` → existing YoCastsContentDelegate (already correct)
- [ ] `getSyncDelegate()` → existing YoCastsSyncDelegate (already correct)
- [ ] `getProviderIconInfo()` → icon + accent color
- [ ] Manifest: `type="audio-content-provider-app"`
- [ ] Manifest: add `<iq:uses-permission id="Media"/>` (test if needed)
- [ ] Remove `getInitialView` / `onStart` service init → move to `initialize()` or lazy init

---

## Sources

1. **Garmin API Docs — AudioContentProviderApp:** https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AudioContentProviderApp.html
2. **Garmin API Docs — ContentIterator:** https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentIterator.html
3. **Garmin API Docs — ContentDelegate:** https://developer.garmin.com/connect-iq/api-docs/Toybox/Media/ContentDelegate.html
4. **MonkeyMusic Sample App:** https://github.com/garmin/connectiq-apps/tree/master/audio-provider/monkeymusic/source
5. **Garmin Blog — Creating Music Apps in CIQ 3:** https://www.garmin.com/en-US/blog/developer/creating-music-apps-3x/
6. **C2DJOY — Creating Music Apps Guide:** https://c2djoy.com/blogs/garmin-blog/creating-music-apps-in-connect-iq-3
7. **Forum — Sync Config View Trigger:** https://forums.garmin.com/developer/connect-iq/f/discussion/380397/when-is-sync-configuration-view-shown-in-audio-provider
8. **Forum — Getting Started with ACP:** https://forums.garmin.com/developer/connect-iq/f/discussion/347595/how-do-you-even-get-started-making-an-audio-content-provider
9. **Bug Report — API 6.0 Crash:** https://forums.garmin.com/developer/connect-iq/i/bug-reports/audio-apps-on-api-6-0-devices-crash-simulator-on-start
10. **Bug Report — Manifest Type:** https://forums.garmin.com/developer/connect-iq/i/bug-reports/docs-issue-application-type-audio-content-provider-does-not-exist
11. **Garmin FAQ — Audio Content Provider:** https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-an-audio-content-provider/
