# Decision: Phase C Audio Download Implementation

**Date:** 2026-07-16
**Author:** Kaylee (Garmin Dev)
**Status:** Implemented

## Context

Phase C implements the core audio download pipeline — the SyncDelegate that runs in background
when the watch is on charger+WiFi, and the ContentIterator that feeds downloaded episodes to the
native Garmin media player.

## Decisions Made

### 1. PersistedContent.Iterator for Audio Downloads
`makeWebRequest` with `HTTP_RESPONSE_CONTENT_TYPE_AUDIO` returns `PersistedContent.Iterator`,
not `Media.ContentRef` directly. We call `iter.next()` to extract the ContentRef. This required
adding `PersistedContent` permission to manifest.xml.

### 2. Background Token Management
The SyncDelegate authenticates independently by reading PocketCasts email/password from
`Application.Properties` and caching the token in `Application.Storage` (keys: `yc_bg_token`,
`yc_bg_token_exp`). Token is reused across sync cycles with 5-minute expiry buffer.

### 3. Sequential Downloads Only
One episode at a time within the 64KB background memory limit. After each download completes
(or fails), we move to the next pending item. Failed downloads get up to 3 retry attempts
across sync cycles.

### 4. Cancel-Safe Design
`onStopSync()` resets in-progress downloads to PENDING status so they retry on the next sync
cycle. No partial state is left behind.

### 5. StorageManager Cleanup on UI Remove
Added `StorageManager.removeDownload(uuid)` call in DownloadsView when removing episodes,
ensuring both the queue entry AND the persisted content metadata are cleaned up.

## Files Changed

- `YoCastsGarmin/manifest.xml` — Added Background, PersistedContent permissions
- `YoCastsGarmin/source/media/YoCastsSyncDelegate.mc` — Full implementation (~300 lines)
- `YoCastsGarmin/source/media/YoCastsContentIterator.mc` — Full implementation (~125 lines)
- `YoCastsGarmin/source/views/DownloadsView.mc` — StorageManager cleanup on remove
- `YoCastsGarmin/source/sim/LocalCredentials.mc` — Created stub for simulator build

## Build Verification

- ✅ Device build passes (default type check level)
- ✅ Simulator build passes (media/ excluded from sim build)

## Open Items for Hardware Testing

- ContentRef ID type: stored as String via `.toString()`. May need exact type if constructor expects Number.
- 64KB memory limit: cannot validate in simulator, requires real Venu 4 hardware.
- `mediaEncoding` option: not set in makeWebRequest — system should auto-detect from HTTP Content-Type. May need explicit `Media.ENCODING_MP3` if hardware testing reveals issues.
