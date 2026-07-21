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

2. **Use Garmin's `Media.SONG_EVENT_*` constants** — never redefine them:
   - 0 = start
   - 1 = skip next
   - 2 = skip previous
   - 3 = playback notification
   - 4 = complete
   - 5 = stop
   - 6 = pause
   - 7 = resume
   - 8/9 = skip forward/backward

3. **Position logging** — use `onSong()` playback-notify, pause, stop,
   skip, and complete events. Do not use `Timer.Timer` in playback context.

4. **PlaybackState module** — a display cache written from real native
   ContentDelegate events. UI must never toggle it as a substitute for audio.

5. **Resume with `Media.ActiveContent`** — return the encrypted media
   `ContentRef`, patched metadata, and saved playback position.

6. **Dual-build safety** — Device build: `source/app/` (AudioContentProviderApp + Media). Simulator build: `source/sim/` (AppBase, no Media). Shared code in `source/views/` and `source/services/` must NOT import Toybox.Media.

7. **Manifest safety** — audio providers require `Communications`; do not add
   `Background`. A SyncDelegate is not a Background ServiceDelegate.

### Applicable When
- Building a Connect IQ audio content provider app
- Need to track playback position for sync
- Supporting both device and simulator builds
