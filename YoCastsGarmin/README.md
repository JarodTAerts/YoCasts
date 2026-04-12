# YoCasts — Garmin Connect IQ App

YoCasts is a Garmin watch client for [Pocket Casts](https://pocketcasts.com/). It lets you browse your subscribed podcasts, manage your Up Next queue, and view episode progress — all from your wrist.

**Primary target device:** Garmin Venu 4 41mm
**Supported devices:** Venu 2/2S/2 Plus, Venu 3/3S, Forerunner 245/245M/265/265S/965, Fenix 7/7S/7X, Epix 2, vívoactive 4/4S
**Min SDK:** Connect IQ 3.2.0

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) | Compiler, simulator, and device APIs |
| [VS Code](https://code.visualstudio.com/) + [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c) | Recommended IDE (alternative: Eclipse with the Connect IQ plugin) |
| [Java JDK 11+](https://adoptium.net/) | Required by the Connect IQ SDK tools |
| Developer key | Required to sign apps for sideloading and simulator use |

### Generating a developer key

If you don't already have one:

```bash
# Using the SDK manager CLI (connectiq SDK bin/ directory):
openssl genrsa -out developer_key.pem 4096
openssl req -new -x509 -key developer_key.pem -out developer_key.der -days 3650
```

Or generate one through the Connect IQ SDK Manager GUI → **Generate Developer Key**.

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
# Simulator build (for UI development & testing)
monkeyc -d venu441mm -f monkey.simulator.jungle -o bin/YoCasts.prg -y /path/to/developer_key.der -l 3

# Device build (for real hardware with audio support)
monkeyc -d venu441mm -f monkey.jungle -o bin/YoCasts.prg -y /path/to/developer_key.der -l 3
```

> **Tip:** Use the simulator build for day-to-day UI work. Switch to the device build only when deploying to hardware or testing audio/media features.

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

```bash
# Option 1: Use the deploy helper script (recommended)
deploy-sim.bat                                    # defaults: venu441mm, developer_key
deploy-sim.bat venu441mm /path/to/developer_key

# Option 2: Manual build and deploy with settings
monkeyc -d venu441mm -f monkey.simulator.jungle -o bin/YoCasts.prg -y /path/to/developer_key -l 3
monkeydo bin/YoCasts.prg venu441mm /a bin/YoCasts-settings.json 0:/GARMIN/APPS/YoCasts-settings.json
```

> **Settings in the simulator:** The `monkeydo` tool does **not** automatically deploy the `-settings.json` file that the compiler generates alongside the `.prg`. You must explicitly push it using the `/a` (additional files) flag as shown above. Without this, the simulator will show *"No settings file found for this app"* when you try to edit Application.Properties data via **File → Edit Persistent Storage → Edit Application.Properties Data**.

Or in VS Code: press **F5** to build, launch the simulator, and load the app automatically (the Monkey C extension handles settings deployment for you).

---

## Deploying to Device

### Sideloading via USB

1. Connect your Garmin watch to your computer via USB.
2. The watch mounts as a removable drive.
3. Copy the built `.prg` file to:
   ```
   <GARMIN_DRIVE>/GARMIN/APPS/YoCasts.prg
   ```
4. Safely eject the drive and disconnect. The app will appear in your watch's app list.

### Via Garmin Connect Mobile

If the app is published to the Connect IQ Store, you can install it directly from the **Connect IQ** section of the Garmin Connect mobile app. *(Not yet published.)*

---

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
    │   ├── YoCastsContentDelegate.mc   # Media playback delegate (device only)
    │   ├── YoCastsContentIterator.mc   # Content iterator (device only)
    │   └── YoCastsSyncDelegate.mc      # Sync delegate (device only)
    ├── models/
    │   └── DataModels.mc         # Data key constants & formatting helpers
    ├── services/
    │   ├── IPodcastService.mc    # Service interface (abstract base class)
    │   └── MockPodcastService.mc # Mock data implementation for development
    └── views/
        ├── MainMenuView.mc       # Home menu delegate — routes to Queue/Podcasts/Now Playing
        ├── LoginPromptView.mc    # Shown when no credentials are configured
        ├── QueueView.mc          # Up Next queue list (Menu2)
        ├── SubscribedView.mc     # Subscribed podcasts list (Menu2)
        ├── EpisodeListView.mc    # Episodes for a specific podcast (Menu2)
        └── NowPlayingView.mc     # Custom-drawn Now Playing screen with progress arc
```

### Key architectural decisions

- **Dictionary-based data models** — Episode and podcast data uses `Dictionary` objects with constant keys (defined in `DataModels.mc`) rather than classes. This matches the shape of `makeWebRequest` JSON responses and minimizes memory on constrained devices.
- **Service abstraction** — `IPodcastService` defines the data contract. `MockPodcastService` provides hardcoded data for UI development. A real `PocketCastsService` implementation will replace it.
- **Credentials via Garmin Connect Mobile** — Users enter PocketCasts email/password through the Garmin Connect app settings, which syncs to the watch via `App.Properties`.

---

## Current Status

🟡 **In Development — Mock Data Only**

The app UI is fully functional with mock data. You can navigate subscriptions, browse episodes, view the queue, and see the Now Playing screen.

**What works:**
- Home menu with Queue, Podcasts, and Now Playing
- Subscribed podcast browsing with episode lists
- Up Next queue display
- Now Playing screen with progress arc and play/pause
- Login prompt when credentials are missing
- Settings UI for PocketCasts credentials in Garmin Connect Mobile

**Coming soon:**
- Real Pocket Casts API integration (authentication, fetching subscriptions, queue, playback state)
- Audio playback control
- Background sync
