# Hardware Testing Plan — Venu 4 41mm

> **Author:** Mal (Lead)  
> **Date:** 2026-04-16  
> **Status:** Ready for execution when hardware available  
> **Target Device:** Garmin Venu 4 41mm (390×390, 768 KB app RAM, 8 GB storage, CIQ API 5.0+)  
> **Prerequisite:** Phase B complete, Phase C implementation ready to deploy

---

## 1. What MUST Be Tested on Hardware vs Simulator

### Simulator-Safe (No Hardware Needed)

| Feature | Why Simulator Works |
|---|---|
| UI rendering (all views) | Simulator renders 390×390 AMOLED faithfully |
| Menu2 navigation | Full input simulation available |
| Application.Storage read/write | Storage API works identically |
| ChangeLog coalescing/eviction | Pure logic + storage, no hardware deps |
| CacheManager round-trips | Same storage API |
| ConnectivityManager state detection | Simulator exposes device settings |
| SyncEngine state machine (logic only) | HTTP mocking via simulator network |
| JSON parsing from makeWebRequest | Network simulation works |
| Auth flow (login, token refresh) | HTTP to real API works in simulator |
| DownloadQueue state management | Pure storage operations |
| View transitions and input handling | Full UI simulation |

### Hardware-Required (Cannot Verify in Simulator)

| Feature | Why Hardware Required |
|---|---|
| **SyncDelegate background lifecycle** | Simulator doesn't trigger system-initiated sync |
| **`HTTP_RESPONSE_CONTENT_TYPE_AUDIO` download** | Returns ContentRef only on real hardware |
| **Media module storage** | Encrypted media cache doesn't exist in simulator |
| **ContentIterator with real ContentRef** | No cached content objects in simulator |
| **Native media player integration** | Simulator has no BT audio path |
| **Wi-Fi direct connectivity** | Simulator network is always through host |
| **Battery-aware behavior** | Simulator battery is always 100% |
| **Background service memory limits** | Simulator doesn't enforce 64 KB cap |
| **BT headphone audio routing** | No real BT stack in simulator |
| **Charger detection** | Simulator doesn't simulate charging states |
| **System sync trigger** | System `isSyncNeeded()` polling doesn't occur |

---

## 2. Hardware Test Scenarios

### 2.1 SyncDelegate Background Download Lifecycle

**Purpose:** Verify the system correctly discovers and triggers our SyncDelegate for audio downloads.

**Setup:**
1. Deploy device build to Venu 4: `monkeyc -d venu441mm -f monkey.jungle -o bin/YoCasts.prg -l 3`
2. Install via `monkeydo bin/YoCasts.prg venu441mm` or USB sideload
3. Connect watch to known Wi-Fi network
4. Place watch on charger
5. Ensure one episode is added to DownloadQueue with `STATUS_PENDING`

**Test Cases:**

| ID | Test | Steps | Expected Result | Pass Criteria |
|---|---|---|---|---|
| SD-1 | System discovers sync need | Add episode to queue, place on charger + Wi-Fi | System calls `isSyncNeeded()` → returns true | Log: "isSyncNeeded: true" |
| SD-2 | System triggers sync | After SD-1, wait for system to trigger | System calls `onStartSync()` | Log: "onStartSync called" |
| SD-3 | Audio download completes | In onStartSync, makeWebRequest with AUDIO type | Callback receives `ContentRef` (not null) | `responseCode == 200`, `data` is `ContentRef` |
| SD-4 | ContentRef is valid | After SD-3, check `data.getId()` | Returns a non-null ID | Can construct `Media.Content(ref, metadata)` |
| SD-5 | Sync progress reported | Call `Media.notifySyncProgress()` after each download | Garmin UI shows download progress | Progress bar visible on music sync screen |
| SD-6 | Sync completion | Call `Media.notifySyncComplete(null)` | System acknowledges sync done | No error, sync status shows complete |
| SD-7 | User-cancelled sync | Start download, remove from charger | `onStopSync()` called | Download cancelled, state reset to PENDING |
| SD-8 | Wi-Fi loss during sync | Start download, disable Wi-Fi mid-download | Download fails gracefully | Error logged, download retried on next sync |
| SD-9 | Multiple sequential downloads | Queue 3 episodes, trigger sync | All 3 download in sequence | All 3 have valid ContentRef after completion |
| SD-10 | Empty queue sync | No pending downloads, charger + Wi-Fi | `isSyncNeeded()` returns false | System does not trigger onStartSync |

### 2.2 Media Module Storage Limits

**Purpose:** Determine actual per-app storage quota and verify cache management.

| ID | Test | Steps | Expected Result | Pass Criteria |
|---|---|---|---|---|
| MS-1 | Query cache stats | Call `Media.getCacheStatistics()` | Returns `capacity` and `size` in bytes | Both values are non-zero Longs |
| MS-2 | Storage after 1 episode | Download 1 episode (~30 MB), check cache stats | `size` increases by ~episode size | Delta within 10% of file size |
| MS-3 | Storage after 5 episodes | Download 5 episodes, check cumulative | Total tracked accurately | Sum matches getCacheStatistics().size |
| MS-4 | Delete cached item | Call `Media.deleteCachedItem(contentRef)` | Cache size decreases | `size` drops by approximately episode size |
| MS-5 | Storage near capacity | Download until close to capacity | Graceful handling | App detects low space via getCacheStatistics |
| MS-6 | Cache reset | Call `Media.resetContentCache()` | All downloaded audio deleted | `size` returns to 0 |

### 2.3 Wi-Fi Direct Download Performance

**Purpose:** Measure download throughput and reliability over the watch's Wi-Fi radio.

**Setup:** Connect Venu 4 to home Wi-Fi (no phone nearby to ensure Wi-Fi direct path).

| ID | Test | Steps | Expected Result | Pass Criteria |
|---|---|---|---|---|
| WF-1 | Small episode download | Download ~20 MB episode (17 min) | Completes within 2 minutes | < 120 seconds |
| WF-2 | Medium episode download | Download ~60 MB episode (1 hour) | Completes within 5 minutes | < 300 seconds |
| WF-3 | Large episode download | Download ~150 MB episode (2.5 hours) | Completes within 15 minutes | < 900 seconds |
| WF-4 | Redirect chain handling | Download URL with 3+ redirect hops | Final audio data received | ContentRef returned, valid audio |
| WF-5 | CDN compatibility: Megaphone | Download from dcs-spotify.megaphone.fm | Successful download | 200 response, valid ContentRef |
| WF-6 | CDN compatibility: Simplecast | Download from simplecastaudio.com | Successful download | 200 response, valid ContentRef |
| WF-7 | CDN compatibility: Transistor | Download from audio.transistor.fm | Successful download | 200 response, valid ContentRef |
| WF-8 | Wi-Fi disconnect mid-download | Disable Wi-Fi during download | Clean failure, retryable | No crash, download marked PENDING |

### 2.4 BT Proxy Download Performance

**Purpose:** Measure download feasibility over Bluetooth proxy (phone-relayed).

**Setup:** Disconnect from Wi-Fi, ensure phone is paired and connected via BT.

| ID | Test | Steps | Expected Result | Pass Criteria |
|---|---|---|---|---|
| BT-1 | Small episode via BT | Download ~20 MB over BT proxy | Completes (slowly) | < 600 seconds (10 min) |
| BT-2 | Timeout behavior | Start ~60 MB download over BT | May timeout — document behavior | Understand timeout threshold |
| BT-3 | BT disconnect recovery | Remove phone from BT range during download | Graceful failure | Download paused/failed, no crash |

**Note:** BT proxy downloads are expected to be 5-10x slower than Wi-Fi. Audio downloads over BT should only be triggered manually by the user, never automatically.

### 2.5 Memory Usage Under Download + Playback

**Purpose:** Verify app stays within 768 KB foreground and 64 KB background limits.

| ID | Test | Steps | Expected Result | Pass Criteria |
|---|---|---|---|---|
| MEM-1 | Background memory at sync start | Log `System.getSystemStats().freeMemory` in `onStartSync()` | Available memory reported | > 15 KB free after SyncDelegate init |
| MEM-2 | Background memory during download | Log memory before/after makeWebRequest callback | No significant leak | Memory stable across 3 downloads |
| MEM-3 | Background memory at peak | Monitor during download + DownloadQueue read | Stays under 64 KB total | No `OutOfMemoryError` |
| MEM-4 | Foreground memory with 5 downloads | Navigate DownloadsView with 5 items | Renders smoothly | < 400 KB peak, no GC pressure |
| MEM-5 | Foreground + playback | Play downloaded episode while browsing | Both work | < 600 KB total |
| MEM-6 | Memory after 10 downloads | 10 episodes downloaded, navigate all views | No crashes | All views render, memory stable |

### 2.6 Battery Impact of Background Sync

**Purpose:** Measure battery drain from audio download operations.

| ID | Test | Steps | Expected Result | Pass Criteria |
|---|---|---|---|---|
| BAT-1 | Battery drain: 1 episode | Record battery %, download 1 episode (~30 MB), record again | Measurable drain | < 2% per episode |
| BAT-2 | Battery drain: 5 episodes | Record battery, download 5 episodes sequentially | Cumulative drain | < 8% for 5 episodes |
| BAT-3 | Battery guard at 30% | Set battery to ~30%, attempt auto-download | Downloads blocked | Log: "battery too low" |
| BAT-4 | Battery guard at 20% | Start download at 25%, monitor as it drops | Downloads pause at 20% | In-progress download pauses cleanly |
| BAT-5 | Charger bypass of battery guard | Place on charger at 15%, trigger sync | Downloads proceed | Charger overrides battery threshold |
| BAT-6 | Overnight sync impact | Leave on charger overnight, 10 episodes queued | All download, minimal battery net | Watch charges fully despite syncing |

---

## 3. Required Setup

### 3.1 Deployment to Venu 4

**Prerequisites:**
- Garmin Connect IQ SDK 9.1.0+ installed
- USB drivers for Venu 4 installed
- Device registered as developer device in Garmin Connect

**Build and Deploy (device build):**
```bash
# Build with strict type checking
cd YoCastsGarmin
monkeyc -d venu441mm -f monkey.jungle -o bin/YoCasts.prg -l 3

# Deploy via USB
# 1. Connect Venu 4 to PC via USB
# 2. Watch appears as USB mass storage
# 3. Copy bin/YoCasts.prg to GARMIN/APPS/ on the watch
# 4. Eject and wait for watch to install

# OR deploy via monkeydo (if simulator connected to device)
monkeydo bin/YoCasts.prg venu441mm
```

**Configure Settings:**
1. Open Garmin Connect Mobile app on phone
2. Navigate to: Devices → Venu 4 → Connect IQ Apps → YoCasts → Settings
3. Set `PocketCastsEmail` and `PocketCastsPassword`
4. Set `useMockData` to `false`

### 3.2 Monitoring Logs

**USB Debug Logging:**
```bash
# Connect watch via USB
# In Connect IQ SDK tools:
monkeydo bin/YoCasts.prg venu441mm --verbose

# Or use the Garmin Connect IQ app debug log viewer
# Watch: Settings → About → System → Developer Menu → Debug Logs
```

**Log Points to Add for Testing:**
- `onStartSync()`: "SYNC: starting, N pending downloads"
- `isSyncNeeded()`: "SYNC: needed = true/false (N pending)"
- Download callback: "SYNC: download complete, uuid=X, refId=Y, code=Z"
- Memory: "SYNC: free memory = X bytes"
- Error: "SYNC: download failed, uuid=X, code=Y, error=Z"

### 3.3 Inspecting Storage

```monkeyc
// Add to a debug menu or settings handler:
var stats = Media.getCacheStatistics();
System.println("Media cache: " + stats.size + " / " + stats.capacity + " bytes");
System.println("Downloads: " + StorageManager.getDownloadCount());
System.println("Total size: " + StorageManager.getTotalDownloadSize() + " bytes");
System.println("Queue pending: " + DownloadQueue.getNextPending());
```

**Application.Storage inspection:**
```monkeyc
// Log all storage keys for debugging:
var dlQueue = Application.Storage.getValue("yc_dl_queue");
System.println("DL Queue: " + (dlQueue != null ? "exists" : "null"));
var downloads = Application.Storage.getValue("yc_downloads");
System.println("Downloads: " + (downloads != null ? "exists" : "null"));
```

---

## 4. Acceptance Criteria by Phase Gate

### Phase B→C Gate

**Phase B is complete when ALL of these pass:**

| # | Criterion | Verification Method |
|---|---|---|
| 1 | SyncEngine pushes at least 1 position update to PocketCasts | API response 200 from `/sync/update_episode` |
| 2 | SyncEngine pulls in-progress episodes from server | `/user/in_progress` response parsed correctly |
| 3 | SyncEngine pulls and normalizes Up Next queue | `/up_next/list` response → cached queue updated |
| 4 | Position reconciliation works (furthest wins) | Local pos=120, server pos=200 → resolved to 200 |
| 5 | Status reconciliation works (highest wins) | Local=IN_PROGRESS, server=COMPLETED → resolved to COMPLETED |
| 6 | Connectivity transition triggers sync | Simulate offline→online → sync starts automatically |
| 7 | Auth token persists across app restart | Kill app, relaunch → no re-login required |
| 8 | Retry logic handles transient failures | Simulate 500 response → retries up to 3 times |

**Can be verified in simulator:** Yes — all Phase B criteria are simulator-testable.

### Phase C→D Gate

**Phase C is complete when ALL of these pass (hardware required):**

| # | Criterion | Verification Method |
|---|---|---|
| 1 | `isSyncNeeded()` returns true when downloads pending | Add episode to queue → system discovers sync need |
| 2 | `onStartSync()` initiates audio download | `makeWebRequest` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` succeeds |
| 3 | Download callback receives valid ContentRef | `data` is `ContentRef`, `data.getId()` non-null |
| 4 | ContentRef stored in StorageManager | `StorageManager.getEpisodeRefId(uuid)` returns valid ID |
| 5 | DownloadQueue status updated to DOWNLOADED | `DownloadQueue.getStatus(uuid) == STATUS_DOWNLOADED` |
| 6 | Sequential downloads work (3+ episodes) | Chain 3 downloads, all complete with valid ContentRef |
| 7 | `Media.notifySyncProgress()` shows UI feedback | Garmin sync screen shows progress bar |
| 8 | `Media.notifySyncComplete(null)` accepted by system | Sync marked complete, no errors |
| 9 | User cancel triggers `onStopSync()` cleanly | Remove from charger → download stops, no crash |
| 10 | `Media.getCacheStatistics()` reports accurate usage | Cache size increases after download |
| 11 | Audio file plays through native media player | ContentIterator returns Content, native player plays audio through BT headphones |
| 12 | Memory stays under 64 KB in background context | `freeMemory > 0` throughout sync lifecycle |

**Minimum viable Phase C:** Criteria 1-8, 12. Criteria 9-11 can be addressed in Phase D refinement if needed.

---

## 5. Test Execution Order

For the most efficient use of hardware testing time:

1. **Day 1: Smoke test**
   - Deploy device build
   - Verify app appears in Music Providers list
   - Verify getPlaybackConfigurationView() launches
   - Run SD-10 (empty queue, no sync triggered)
   - Run MS-1 (query cache stats — baseline)
   - Run MEM-1 (background memory baseline)

2. **Day 2: First download**
   - Add one episode to DownloadQueue manually
   - Run SD-1 through SD-6 (full sync lifecycle)
   - Run WF-4 (redirect chain test — critical risk)
   - Run MEM-2, MEM-3 (memory under download)
   - If SD-3 fails (no ContentRef): STOP. This is the highest-risk item. Debug before proceeding.

3. **Day 3: Multiple downloads + playback**
   - Run SD-9 (3 sequential downloads)
   - Run WF-1, WF-2 (download speed benchmarks)
   - Run MS-2, MS-3 (storage tracking)
   - Run the Phase C→D gate criteria 1-8

4. **Day 4: Edge cases + battery**
   - Run SD-7, SD-8 (cancellation, Wi-Fi loss)
   - Run WF-8 (Wi-Fi disconnect)
   - Run BAT-1, BAT-2 (battery impact)
   - Run MEM-4, MEM-5 (memory with playback)

5. **Day 5: CDN compatibility + stress**
   - Run WF-5, WF-6, WF-7 (different CDN providers)
   - Run BT-1, BT-2 (Bluetooth proxy)
   - Run MEM-6 (10 downloads stress test)
   - Run MS-4 (delete cached item)
   - Run BAT-6 (overnight sync)
