# Venu 4 Hardware Test Plan

**Target:** Garmin Venu 4 41mm (`venu441mm`, 390x390, CIQ 6.0)
**App type:** `audio-content-provider-app`
**Provider memory budget:** 512 KB

The simulator covers API, cache, and visual behavior, but it cannot reproduce
Garmin's encrypted media cache, managed media sync, native player, Bluetooth
audio path, or native song callbacks. Download and native playback have already
worked on the target watch; this plan focuses on the rebuilt synchronization
and cross-lifecycle behavior.

## Prepare the sideload

1. Build both variants from `YoCastsGarmin`:

   ```powershell
   .\build.ps1
   ```

2. Generate a credential-bearing SET through Garmin's VS Code debug adapter:
   - Open the `YoCastsGarmin` folder in VS Code.
   - Press **F5** with **Run YoCasts Simulator**.
   - In the simulator, open **File -> Edit Persistent Storage -> Edit
     Application.Properties Data**.
   - Set `PocketCastsEmail`, `PocketCastsPassword`, `useMockData=false`, and
     `AutoDownloadCount` to `0`, `1`, `3`, or `5`.
   - Save and close the app.

3. Connect the watch over USB and copy:

   ```text
   YoCastsGarmin\build\YoCastsDevice.prg
       -> <WATCH>\GARMIN\APPS\YOCASTS.PRG

   newest simulator-generated YOCASTSGARMIN.SET
       -> <WATCH>\GARMIN\APPS\SETTINGS\YOCASTS.SET
   ```

   The PRG and SET base names must match. The generated
   `YoCastsDevice-settings.json` is only a schema and is not a device SET.

4. Safely eject the watch. Open YoCasts through **Music Controls -> Music
   Providers**.

## Acceptance matrix

### 1. Account and metadata

| ID | Test | Expected |
|----|------|----------|
| META-1 | Open YoCasts with phone connected | Subscriptions and Up Next load without a response-size error |
| META-2 | Open a podcast | Title, author, description, and Browse Episodes render inside the round safe area |
| META-3 | Browse episodes | Up to 15 recent episodes have real titles, dates/durations, and progress |
| META-4 | Open an episode | Show notes load, wrap, and scroll with touch and physical buttons |
| META-5 | Disconnect and reopen viewed pages | Cached subscriptions, queue, episode list, and recent details remain readable |

### 2. Managed download and storage

| ID | Test | Expected |
|----|------|----------|
| DL-1 | Queue one short MP3 episode | Garmin enters managed media sync and Downloads changes Pending -> Downloading -> Ready |
| DL-2 | Queue M4A/AAC content | Supported encoding is selected and a valid encrypted-cache `ContentRef` is stored |
| DL-3 | Cancel a sync | The active request stops and the item returns to a retryable state without starting another request |
| DL-4 | Interrupt Wi-Fi or reboot during download | Next sync repairs Downloading to Pending unless the media item was already committed |
| DL-5 | Fill media storage | Capacity failure is surfaced and the item becomes retryable; the app does not crash |
| DL-6 | Remove a ready download | Garmin's cached media and YoCasts metadata are both removed |

Record `Media.getCacheStatistics()` before and after DL-1, DL-2, and DL-6 to
confirm cache growth and reclamation.

### 3. Native player integration

| ID | Test | Expected |
|----|------|----------|
| PLAY-1 | Tap Play on a Ready episode | Garmin's first-party player opens and routes audio to Bluetooth |
| PLAY-2 | Pause and reopen YoCasts | The playback dock and Now Playing page show the native title, paused state, and position |
| PLAY-3 | Resume and wait between callbacks | Displayed position advances while playing and is corrected by the next native event |
| PLAY-4 | Use native skip forward/back | The next callback persists the adjusted absolute position |
| PLAY-5 | Use native next/previous track | YoCasts follows the new episode and keeps the iterator order |
| PLAY-6 | Restart the app/watch mid-episode | Playback resumes from the cached Pocket Casts/Garmin position |
| PLAY-7 | Let an episode complete | Local status remains Completed even if Garmin sends a later Stop event |

### 4. Offline progress reconciliation

| ID | Test | Expected |
|----|------|----------|
| SYNC-1 | Play and pause with phone/Wi-Fi unavailable | Position is retained in the local mutation journal |
| SYNC-2 | Restore the phone connection and leave Home open | Foreground reconnect polling pushes pending changes |
| SYNC-3 | Run Settings -> Sync Now on Wi-Fi | Managed sync pushes pending changes before downloading media |
| SYNC-4 | Complete an episode offline, then reconnect | Pocket Casts reports Completed at the episode duration |
| SYNC-5 | Advance farther on another Pocket Casts device | Reconciliation keeps the furthest position and strongest status |
| SYNC-6 | Let the access token expire before reconnecting | YoCasts refreshes or logs in again and then drains pending changes |

Intentional limitation: reconciliation is monotonic. A deliberate rewind made
on another device does not move the watch backward.

### 5. Automatic Up Next

| ID | Test | Expected |
|----|------|----------|
| AUTO-1 | Set Keep 1, 3, then 5 | Leading Up Next episodes are queued in Pocket Casts order |
| AUTO-2 | Reorder Up Next and sync | Pending automatic order follows the server order |
| AUTO-3 | Remove an undownloaded item from the configured window | Stale pending automatic work is removed before new items are added |
| AUTO-4 | Fill the 20-item queue, then change Up Next | Stale automatic entries free slots before desired items are queued |
| AUTO-5 | Complete an automatic episode and move it outside the window | A later media sync deletes its cached media unless it is currently playing |
| AUTO-6 | Set Off in the app | Pending/failed automatic work is cancelled; manual and already-downloaded items remain |
| AUTO-7 | Set Off while YoCasts is not running | App/sync startup applies Off before any stale automatic download begins |
| AUTO-8 | Leave the watch idle | Garmin, not a custom daemon, decides when the next managed sync runs |

### 6. Round-screen UX and input

Test touch and physical-button navigation for Home, Queue, Podcasts, Podcast
Detail, Episode List, Episode Detail, Downloads, Settings, and Now Playing.

Verify:

- Long titles are truncated or wrapped without drawing beyond the round safe
  area.
- Podcast descriptions and show notes scroll and show direction indicators.
- The fourth Home item is reachable by swipe/button navigation.
- Download, empty, loading, failure, offline, and retry states are legible.
- The playback dock never claims audio is playing before a native event.
- Settings clearly shows account, auto-download count, last sync, Up Next
  refresh age, and last native playback event.

## Logs and evidence

For each failed case, record:

- Exact action and connectivity state.
- Screenshot or video of the Garmin UI.
- CIQ log lines around `YoCasts Sync`, `ChangeSync`, `onSong`, or the relevant
  HTTP status.
- Download UUID and content type, but not credentials, bearer tokens, signed
  URLs, or the SET file.
- Whether the failure survives an app restart or watch reboot.

The most important remaining evidence is the native callback sequence for
Start, Playback Notify, Pause, Skip, Next/Previous, Complete, and Stop, plus the
resulting Pocket Casts state after connectivity returns.
