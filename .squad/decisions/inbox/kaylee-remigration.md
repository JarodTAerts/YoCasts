# Decision: Re-migrate to AudioContentProviderApp

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Affects:** Mal (Lead), Wash (API Dev), Jarod Aerts

## Decision

YoCasts is now an `audio-content-provider-app` again. The earlier revert to `watch-app` was based on a misdiagnosis — the crash was our fault, not a platform limitation.

## What Changed

1. **manifest.xml:** `type="audio-content-provider-app"` (was `watch-app`)
2. **YoCastsApp.mc:** extends `AudioContentProviderApp` (was `AppBase`)
3. **Removed `getInitialView()`** — audio providers use `getPlaybackConfigurationView()` as entry point
4. **Added provider methods:** `getPlaybackConfigurationView()`, `getSyncConfigurationView()`, `getContentDelegate()`, `getSyncDelegate()`, `getProviderIconInfo()`
5. **monkey.jungle:** `source/media` re-included in build path

## What We Got Wrong Last Time

- We assumed `ContentIterator.get()` returning null caused the crash — it doesn't. The native player shows "No Media" and that's fine.
- We may have kept `getInitialView()` overridden, which conflicts with audio provider launch flow.
- The API 6.0 simulator bug may have been a factor (our Venu 4 target shouldn't be affected).

## How to Launch/Test in Simulator

Audio content provider apps **do NOT appear in the app list**. To test:

1. Build: `monkeyc.bat -d venu441mm -f monkey.jungle -o bin\YoCasts.prg -y <key> -l 3`
2. Start simulator: `simulator.exe`
3. Load app: `monkeydo.bat bin\YoCasts.prg venu441mm`
4. In the simulator, the app appears as a **music provider** — NOT in the app list
5. Navigate to **Music Controls** (hold DOWN button on watch face, or swipe to music widget)
6. Select **Music Providers** → **YoCasts**
7. System calls `getPlaybackConfigurationView()` → shows HomeMenuView (or LoginPromptView if not authed)

## Current State

- Build passes clean at `-l 3` (strict)
- ContentIterator stubs return null safely (no crash)
- Three-state auth gate in `getPlaybackConfigurationView()`: unauthenticated → LoginPromptView, authenticated/mock → HomeMenuView
- All existing views, services, and models unchanged

## Next Steps

- Verify in simulator that the music provider flow works end-to-end
- Implement SyncDelegate download logic (Phase C) so ContentIterator can return real content
- Test on Venu 4 hardware
