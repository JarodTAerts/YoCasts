# Decision: Phase A Changelog + Position Tracking Implementation

**By:** Kaylee (Garmin Dev)  
**Date:** 2026-07-16  
**Affects:** Wash (API Dev — sync engine), Mal (Lead)

## What Changed

Enhanced `ChangeLog.mc` and created `PositionTracker.mc` as the foundation for Phase B sync engine.

### Key Design Decisions

1. **Enhanced existing ChangeLog module** instead of creating a separate ChangelogManager — avoids duplicate storage and keeps a single source of truth for offline mutations. Added convenience methods (`logPositionUpdate`, `logStatusChange`, `logQueueAction`, `getChangelog`, `clearChangelog`) on top of the existing `addEntry` API.

2. **PositionTracker is a class, not a module** — Timer callbacks require `method(:symbol)` which needs class instance context (`self`). Module-level functions can't provide this. The class is created per-NowPlayingView and tracks one episode at a time.

3. **Dual-write pattern** — PositionTracker writes to both ChangeLog (for eventual sync push) and CacheManager (for instant offline resume). This means position data survives both network outages and app restarts through separate storage paths.

4. **Reduced MAX_ENTRIES from 100 to 50** — Design doc's 8 KB budget for changelog storage. With coalescing (only latest position per episode retained), 50 entries is more than sufficient for a typical run session.

5. **Battery-adaptive intervals** — 15s normal, 30s when battery < 20%. Checked via `System.getSystemStats().battery`.

### Files Changed
- `YoCastsGarmin/source/services/ChangeLog.mc` — Enhanced with convenience API + new types
- `YoCastsGarmin/source/services/PositionTracker.mc` — **NEW** — Timer-based position logger
- `YoCastsGarmin/source/views/NowPlayingView.mc` — Integrated PositionTracker lifecycle

### For Wash (Phase B)
The sync engine should:
- Call `ChangeLog.getChangelog()` to read pending mutations
- Call `ChangeLog.clearChangelog()` only after confirmed server push
- Handle all 5 entry types: `POSITION_UPDATE`, `EPISODE_COMPLETED`, `STATUS_CHANGE`, `QUEUE_ADD`, `QUEUE_REMOVE`
