### Download UI Architecture & DownloadQueue Interface Contract

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-04-14  
**Affects:** Wash (API Dev), Mal (Lead)

Implemented download management UI screens with a stub DownloadQueue module. The interface contract is defined and ready for Wash to implement the real download engine.

**Decisions Made:**

1. **DownloadQueue as a module (not class)** — Module-level singleton pattern with in-memory state. Real implementation will persist to `Application.Storage`. Module functions: `addToQueue()`, `removeFromQueue()`, `getStatus()`, `getProgress()`, `getDownloads()`, `getDownloadCount()`, `toEpisodeDict()`.

2. **Download status constants** — Four states: `STATUS_PENDING (0)`, `STATUS_DOWNLOADING (1)`, `STATUS_DOWNLOADED (2)`, `STATUS_FAILED (3)`. Stored as `dlStatus` key in download item dictionaries.

3. **Episode action menu pattern** — EpisodeListView now shows a Menu2 action popup on episode select (Play / Download) instead of navigating directly to NowPlayingView. This is extensible for future actions (Star, Mark Played, etc.).

4. **Downloads pill placement** — Added between Podcasts and Settings in HomeMenuView. Total pills: Queue → Podcasts → Downloads → Settings. TOTAL_MENU_HEIGHT increased from 382 to 478px.

5. **Download item dictionary keys** — Separate from DataKeys.E_* to avoid coupling. Uses `DL_UUID`, `DL_TITLE`, `DL_PODCAST_TITLE`, `DL_STATUS`, `DL_PROGRESS`, etc. `toEpisodeDict()` converts for NowPlayingView compatibility.

**For Wash (DownloadQueue real implementation):**
- Match the interface in `source/services/DownloadQueue.mc`
- Persist downloads to `Application.Storage` with key prefix `yc_dl_`
- Hook into `Communications.SyncDelegate.makeWebRequest()` for actual downloads
- Call `WatchUi.requestUpdate()` when download progress changes

**Open Questions:**
- Should failed downloads auto-retry on next sync, or require manual retry?
- Maximum number of downloaded episodes (storage budget)?
- Should DownloadQueue sort by status (downloading first) or by add order?
