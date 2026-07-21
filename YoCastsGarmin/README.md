# YoCasts - Garmin Connect IQ App

YoCasts is a Pocket Casts client and native audio provider for the Garmin Venu
4. It browses subscriptions and Up Next, downloads episodes into Garmin's
managed media cache, hands playback to Garmin's first-party player, and caches
progress changes until they can be synchronized.

**Primary target device:** Garmin Venu 4 41mm
**Supported device:** Garmin Venu 4 41mm (`venu441mm`)
**Min SDK:** Connect IQ 4.2.0

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) | Compiler, simulator, and device APIs |
| [VS Code](https://code.visualstudio.com/) + [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c) | Recommended IDE (alternative: Eclipse with the Connect IQ plugin) |
| [Java JDK 11+](https://adoptium.net/) | Required by the Connect IQ SDK tools |
| Developer key | Required to sign apps for sideloading and simulator use |

### Generating a developer key

Generate a key through Connect IQ SDK Manager or Garmin's Monkey C VS Code
extension. The build script defaults to:

```text
%APPDATA%\Garmin\ConnectIQ\developer_key.der
```

> **Keep your key safe.** You'll need the same key to update apps you've already published or sideloaded.

---

## Setup Instructions

### 1. Clone the repo

```bash
git clone https://github.com/JarodTAerts/YoCasts.git
cd YoCasts/YoCastsGarmin
```

### 2. Install the Connect IQ SDK

Download and install the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/). Use it to download the latest SDK and device files for your target (e.g. Venu 4 41mm, or any of the supported devices listed above).

### 3. Configure the SDK path

- **VS Code:** The Monkey C extension will prompt for the SDK path on first use. You can also set it in VS Code settings → `monkeyc.connectiq.sdk`.
- **Environment variable:** Add the SDK `bin/` directory to your `PATH` so `monkeyc` and `connectiq` are available from the terminal.

### 4. Generate a developer key (if needed)

See [Generating a developer key](#generating-a-developer-key) above. The Monkey C VS Code extension will prompt you for the key location on first build.

---

## Building

YoCasts uses a **dual-build configuration** because the CIQ simulator cannot run `audio-content-provider-app` types (Garmin platform limitation). Two jungle files select the right app entry point and manifest:

| Build | Jungle file | Manifest | App type | Entry point |
|-------|------------|----------|----------|-------------|
| **Simulator** | `monkey.simulator.jungle` | `manifest.simulator.xml` | `watch-app` (AppBase) | `getInitialView()` |
| **Device** | `monkey.jungle` | `manifest.xml` | `audio-content-provider-app` | `getPlaybackConfigurationView()` |

All UI code (views, services, models) is shared. Only the app entry point and media stubs differ.

### Command line

From the `YoCastsGarmin/` directory:

```bash
# Strict-build both variants
.\build.ps1

# Build only one variant
.\build.ps1 -Target Simulator
.\build.ps1 -Target Device

# Override the default key when needed
.\build.ps1 -DeveloperKey C:\path\to\developer_key.der
```

Outputs are `build\YoCastsSimulator.prg` and
`build\YoCastsDevice.prg`.

### VS Code

1. Open the `YoCastsGarmin/` folder in VS Code.
2. Make sure the Monkey C extension is installed and the SDK path is configured.
3. Press **Ctrl+Shift+B** (or **Cmd+Shift+B** on macOS) to run the default build task.
4. Select your target device when prompted.

> **Note:** VS Code uses `monkey.jungle` by default. To build the simulator variant, either configure a custom build task or use the command line.

---

## Running in the Simulator

> **Important:** Use the **simulator build** (`monkey.simulator.jungle`) for the CIQ simulator. The device build (`audio-content-provider-app`) cannot run in the simulator.

### Starting the simulator

```bash
# Start the Connect IQ simulator (from SDK bin/)
connectiq
```

Or use the VS Code command palette: **Monkey C: Start Simulator**.

### Loading the app

For normal UI/API testing:

```powershell
.\deploy-sim.ps1
```

`monkeydo` can launch the app but cannot supply the descriptor used by App
Settings Editor. To edit `Application.Properties`, open the `YoCastsGarmin`
folder itself in VS Code and press **F5** with the included **Run YoCasts
Simulator** configuration. Then use **File -> Edit Persistent Storage -> Edit
Application.Properties Data** in the simulator.

---

## Deploying to Device

### Sideloading via USB

Sideloaded apps cannot edit their settings through Garmin Connect Mobile or
Garmin Express. For a physical-device test, copy both the app and a matching
simulator-generated `.SET` file.

1. Open the `YoCastsGarmin` folder itself in VS Code with Garmin's **Monkey C**
   extension installed.
2. Press **F5** and use the included **Run YoCasts Simulator** launch
   configuration. Do not use `deploy-sim.ps1` for this step: Garmin's
   `monkeydo` CLI cannot provide the schema consumed by App Settings Editor.
3. In the simulator, open **File → Edit Persistent Storage → Edit
   Application.Properties Data** and set:
   - `PocketCastsEmail`
   - `PocketCastsPassword`
   - `useMockData` = `false`
   - `AutoDownloadCount` = `0`, `1`, `3`, or `5`
4. Click **Save**, then close the simulator app so settings are flushed. The
   generated file is normally:
   ```
   %TEMP%\com.garmin.connectiq\GARMIN\APPS\SETTINGS\YOCASTSGARMIN.SET
   ```
   If the filename differs, use the newest `.SET` file in that directory.
5. Connect the watch by USB and wait for it to mount.
6. Copy `build\YoCastsDevice.prg` to:
   ```
   <GARMIN_DRIVE>\GARMIN\APPS\YOCASTS.PRG
   ```
7. Copy the simulator settings file to the matching settings name:
   ```
   <GARMIN_DRIVE>\GARMIN\APPS\SETTINGS\YOCASTS.SET
   ```
   The `.PRG` and `.SET` base names must match exactly.
8. Safely eject and disconnect. Open YoCasts from **Music Controls → Music
   Providers**, not from the normal app list.

The `.SET` file contains account credentials. Keep it out of source control.
Do not copy `build\YoCastsDevice-settings.json`; that is SDK schema metadata,
not the device settings file.

### Via Garmin Connect Mobile

If the app is published to the Connect IQ Store, you can install it directly from the **Connect IQ** section of the Garmin Connect mobile app. *(Not yet published.)*

---

## Runtime behavior

### Native playback

Episodes are not streamed by the Connect IQ app. Garmin downloads each file
during a system media sync and returns an opaque `Media.ContentRef`. YoCasts
stores that reference and supplies `Media.ActiveContent` to Garmin's player.
Bluetooth routing, volume, pause, skip, and lock-screen controls therefore stay
inside Garmin's native media UI.

YoCasts receives discrete native song events rather than a per-second callback.
The in-app progress display estimates time between events, then persists the
next real callback. Position, completion, and queue mutations are retained in
`Application.Storage` until Pocket Casts can be reached.

### Automatic Up Next

`AutoDownloadCount` can be Off, 1, 3, or 5. YoCasts keeps that many leading Up
Next episodes queued, preserves Pocket Casts ordering, and removes completed
automatic downloads after they leave the configured window. Turning the setting
off cancels automatic work that has not reached Garmin's media cache.

Connect IQ audio providers cannot run an unrestricted periodic daemon.
Automatic refresh therefore occurs when Garmin invokes the media
`SyncDelegate`, when the app is opened and refreshes Up Next, or when the user
selects **Settings -> Sync Now**. Garmin decides when managed Wi-Fi sync can run.
Foreground reconnect checks also push cached progress when phone or Wi-Fi
connectivity returns.

### Details and offline data

Subscription and queue data are cached. Podcast pages include descriptions;
episode pages include metadata, playback/download state, and scrollable show
notes. Large Pocket Casts responses are compacted by `YoCastsProxy` before they
reach the watch.

## Project Structure

```
YoCastsGarmin/
├── manifest.xml                  # Device manifest (audio-content-provider-app)
├── manifest.simulator.xml        # Simulator manifest (watch-app)
├── monkey.jungle                 # Device build config (includes media stubs)
├── monkey.simulator.jungle       # Simulator build config (no media)
├── resources/
│   ├── drawables/
│   │   ├── drawables.xml         # Drawable resource definitions
│   │   └── launcher_icon.png     # App launcher icon
│   ├── settings/
│   │   ├── properties.xml        # App properties (PocketCasts email/password)
│   │   └── settings.xml          # Settings UI shown in Garmin Connect Mobile
│   └── strings/
│       └── strings.xml           # Localized string resources
└── source/
    ├── app/
    │   └── YoCastsApp.mc         # Device entry — AudioContentProviderApp
    ├── sim/
    │   └── YoCastsApp.mc         # Simulator entry — AppBase (watch-app)
    ├── media/
    │   ├── YoCastsContentDelegate.mc   # Native playback callbacks
    │   ├── YoCastsContentIterator.mc   # ActiveContent and playback ordering
    │   └── YoCastsSyncDelegate.mc      # Managed Wi-Fi/media synchronization
    ├── models/
    │   └── DataModels.mc         # Data key constants & formatting helpers
    ├── services/
    │   ├── AutoSyncManager.mc          # Up Next replenishment policy
    │   ├── CacheManager.mc             # Bounded persistent metadata caches
    │   ├── ChangeLog.mc                # Offline mutation journal
    │   ├── DownloadQueue.mc            # Persistent media work and metadata
    │   ├── PlaybackState.mc            # Cross-lifecycle native state
    │   ├── PocketCastsChangeSync.mc    # Two-way progress reconciliation
    │   └── PocketCastsPodcastService.mc
    └── views/
        ├── HomeMenuView.mc          # Home list and persistent playback dock
        ├── QueueView.mc             # Up Next
        ├── SubscribedView.mc        # Subscriptions
        ├── PodcastDetailView.mc     # Podcast description and episode action
        ├── EpisodeListView.mc       # Compact episode browser
        ├── EpisodeDetailView.mc     # Playback status and episode actions
        ├── EpisodeShowNotesView.mc  # Dedicated long-form notes reader
        ├── DownloadsView.mc         # Download state and deletion
        ├── NowPlayingView.mc        # Native-player status and handoff
        └── SyncConfigurationView.mc # Native account/auto-download/sync list
```

### Key architectural decisions

- **Dictionary-based data models** — Episode and podcast data uses `Dictionary` objects with constant keys (defined in `DataModels.mc`) rather than classes. This matches the shape of `makeWebRequest` JSON responses and minimizes memory on constrained devices.
- **Service abstraction** - `IPodcastService` defines the data contract.
  `PocketCastsPodcastService` provides the live API implementation,
  `CachedPodcastService` adds offline reads, and `MockPodcastService` remains
  available for simulator UI work.
- **Credentials via app properties** — Store installs use Garmin Connect
  Mobile settings. USB-sideload tests use a matching `.SET` file copied to
  `GARMIN\APPS\SETTINGS`.

---

## Hardware test matrix

Strict simulator and device builds pass. Download and native playback have
already been confirmed on a physical Venu 4. Before treating a build as a
release candidate, test:

1. **Native lifecycle:** Download an episode, start it, pause, skip, change
   tracks, reopen YoCasts, and confirm title and position follow Garmin's player.
2. **Resume/completion:** Resume after an app/watch restart, finish an episode,
   reconnect, and verify Pocket Casts reports it completed.
3. **Offline reconciliation:** Play while disconnected, reconnect through the
   phone and through Wi-Fi media sync, and confirm cached progress is pushed.
4. **Automatic Up Next:** Set the count to 1, 3, and 5; reorder Up Next; run
   sync; and confirm download order and replenishment. Set it Off and confirm
   pending automatic items are cancelled.
5. **Cleanup:** Complete an automatically downloaded episode, remove it from
   the configured Up Next window, sync, and confirm its cached media is removed.
6. **UX:** Scroll long podcast descriptions and show notes, inspect long titles,
   test touch and physical buttons, and verify empty/error/download states.
