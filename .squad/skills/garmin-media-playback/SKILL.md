# Skill: Garmin CIQ Media Playback Integration

## Pattern: AudioContentProviderApp Playback Lifecycle

### Problem
Wiring downloaded audio content to Garmin's native media player in a Connect IQ AudioContentProviderApp.

### Solution Architecture

```
YoCastsApp (AudioContentProviderApp)
  ├── getContentDelegate() → cached YoCastsContentDelegate singleton
  │     ├── getContentIterator() → YoCastsContentIterator (playlist)
  │     └── onSong(refId, event, position) → state machine
  ├── getPlaybackConfigurationView() → HomeMenuView
  └── getSyncDelegate() → YoCastsSyncDelegate (downloads)
```

### Key Patterns

1. **ContentDelegate as singleton** — cache in the app class. System calls `getContentDelegate()` multiple times; recreating loses timer/state.

2. **onSong() event state machine** — numeric event types:
   - 0 = start → begin position timer, set playing
   - 1 = pause → stop timer, log position
   - 2 = resume → restart timer, set playing
   - 3 = complete → stop timer, log completion to ChangeLog
   - 4 = stop → stop timer, log final position

3. **Position logging** — Timer at 15s intervals uses `PlaybackState.getEstimatedPosition()` (lastPosition + elapsed seconds). Ground-truth positions come from `onSong()` events.

4. **PlaybackState module** — shared mutable state (module-level vars). Written by ContentDelegate (device) or NowPlayingView (sim). Read by HomeMenuView dock. Media-agnostic (no Toybox.Media imports).

5. **ContentIterator UUID tracking** — parallel `_uuids` array alongside `_refIds`. Enables `setCurrentByUuid()` for episode selection and `getUuidForRefId()` reverse lookup.

6. **Dual-build safety** — Device build: `source/app/` (AudioContentProviderApp + Media). Simulator build: `source/sim/` (AppBase, no Media). Shared code in `source/views/` and `source/services/` must NOT import Toybox.Media.

### Applicable When
- Building a Connect IQ audio content provider app
- Need to track playback position for sync
- Supporting both device and simulator builds
