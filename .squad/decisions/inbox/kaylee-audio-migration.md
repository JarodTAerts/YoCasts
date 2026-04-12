# AudioContentProviderApp Migration — Decisions & Findings

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Status:** COMPLETED — Phase 0 migration done, build passes `-l 3`

## Decisions Made

### 1. No `Media` Permission in Manifest
The SDK rejects `<iq:uses-permission id="Media"/>` as invalid. The Media module is implicitly available for `audio-content-provider-app` types. Only `Communications` permission is needed. Confirmed by Garmin's MonkeyMusic sample which also only declares `Communications`.

### 2. `Communications.SyncDelegate` Over `Media.SyncDelegate`
SDK 9.1.0 enforces `Null or Communications.SyncDelegate` as the return type for `getSyncDelegate()`. `Media.SyncDelegate` is fully deprecated — not just at API level but at the type system level. All future sync code must extend `Communications.SyncDelegate`.

### 3. Inlined View Construction (No Helper Method)
The strict type checker requires AudioContentProviderApp view methods to return specific tuple types (`[Views] or [Views, InputDelegates]`). A shared helper method returning untyped `Array` causes type errors. Each method (`getInitialView`, `getPlaybackConfigurationView`, `getSyncConfigurationView`) constructs views inline.

### 4. SyncConfigView Deferred to Phase C
For Phase 0, `getSyncConfigurationView()` returns the same HomeMenuView. A dedicated SyncConfigView with episode download selection UI will be built in Phase C alongside the real SyncDelegate implementation.

### 5. Settings Unchanged
PocketCastsPassword uses `alphaNumeric` type (no `password` type exists in CIQ). Settings XML works identically in audio-content-provider-app. No changes needed.

## Files Changed
- `manifest.xml` — `type` changed to `audio-content-provider-app`
- `YoCastsApp.mc` — base class changed, 5 new methods added
- `source/media/YoCastsContentDelegate.mc` — NEW stub
- `source/media/YoCastsContentIterator.mc` — NEW stub (includes PlaybackProfile)
- `source/media/YoCastsSyncDelegate.mc` — NEW stub
- `monkey.jungle` — added `source/media` to sourcePath

## What's Next
Phase 0 exit criteria met: app type migrated, builds clean, stubs in place. Ready for:
- **Phase A:** Changelog & position tracking
- **Phase C:** Real SyncDelegate + DownloadManager + SyncConfigView
- **Phase D:** Real ContentDelegate + ContentIterator with downloaded content
