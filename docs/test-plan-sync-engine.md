# YoCasts — Sync Engine Test Plan

> **Author:** Zoe (Tester)  
> **Date:** 2026-04-14  
> **Status:** Draft — written from spec; may need adjustment when implementation is final  
> **Spec:** `docs/offline-sync-design.md` v1.2  
> **Code Baseline:** `ChangeLog.mc`, `CacheManager.mc`, `ConnectivityManager.mc`, `StorageManager.mc`

---

## Overview

This test plan covers **Phase A** (Changelog Module + Position Tracker) and **Phase B** (Sync Engine) of the YoCasts offline sync architecture. Tests are written against the design spec while Kaylee builds Phase A — they may need adjustment once implementation is final.

### Priority Key

| Priority | Meaning | Gate |
|----------|---------|------|
| **P0** | Must-have. Blocks release. | Cannot ship without passing. |
| **P1** | Important. Covers significant edge cases. | Should pass; failures investigated before release. |
| **P2** | Nice-to-have. Robustness and stress testing. | Failures documented, may ship with known limitations. |

### Environment Key

| Tag | Meaning |
|-----|---------|
| **SIM** | Can run in Connect IQ Simulator (simulator build via `monkey.simulator.jungle`) |
| **HW** | Requires Venu 4 hardware (or another physical device) |
| **SIM+HW** | Run in simulator first, verify on hardware |

### Important Implementation Notes

- **ChangeLog.mc uses `MAX_ENTRIES = 100`** (not 50 as initially scoped). Tests use 100 as the boundary.
- **Storage key prefix is `"yc_"`** — changelog at `"yc_changelog"`, sequence at `"yc_cl_seq"`.
- **Coalescing applies only to `POSITION_UPDATE`**, not to `EPISODE_COMPLETED` or `QUEUE_REMOVE`.
- **Eviction prioritizes non-completion entries first.** Only evicts completions when all entries are completions.
- **Status values:** 0 = NOT_PLAYED, 2 = IN_PROGRESS, 3 = COMPLETED (no status 1).
- **Position tracking interval:** Design spec says 15s (§4.2), with possible battery scaling.

---

## Phase A — Changelog Module

### CL-01: Log a single position update

| Field | Value |
|-------|-------|
| **ID** | CL-01 |
| **Category** | Changelog |
| **Scenario** | Log a position update, verify it's stored in changelog |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty (`ChangeLog.getEntries()` returns empty array) |
| **Steps** | 1. Call `ChangeLog.addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 120, "status" => 2, "duration" => 781})` <br> 2. Call `ChangeLog.getEntries()` |
| **Expected Result** | Returns array with exactly 1 entry. Entry has: `type == "POSITION_UPDATE"`, `episodeUuid == "ep-001"`, `podcastUuid == "pod-001"`, `data.position == 120`, `data.status == 2`, `data.duration == 781`, `id == 1`, `timestamp` is a valid Unix epoch within last 5 seconds. |

---

### CL-02: Coalescing — multiple position updates for same episode

| Field | Value |
|-------|-------|
| **ID** | CL-02 |
| **Category** | Changelog |
| **Scenario** | Log multiple position updates for same episode, verify only latest survives |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 60, "status" => 2, "duration" => 781})` <br> 2. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 120, "status" => 2, "duration" => 781})` <br> 3. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 180, "status" => 2, "duration" => 781})` <br> 4. Call `getEntries()` |
| **Expected Result** | Returns array with exactly 1 entry. Position is 180 (latest). Earlier entries (60, 120) are gone. Entry ID reflects the latest insert. |

---

### CL-03: Coalescing — different episodes are NOT coalesced

| Field | Value |
|-------|-------|
| **ID** | CL-03 |
| **Category** | Changelog |
| **Scenario** | Log position updates for different episodes, verify all are preserved |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 60, ...})` <br> 2. `addEntry(TYPE_POSITION_UPDATE, "ep-002", "pod-001", {"position" => 120, ...})` <br> 3. `addEntry(TYPE_POSITION_UPDATE, "ep-003", "pod-002", {"position" => 90, ...})` <br> 4. Call `getEntries()` |
| **Expected Result** | Returns 3 entries, one per episode UUID. Positions: ep-001=60, ep-002=120, ep-003=90. |

---

### CL-04: Coalescing does NOT apply to EPISODE_COMPLETED

| Field | Value |
|-------|-------|
| **ID** | CL-04 |
| **Category** | Changelog |
| **Scenario** | Log a position update then an episode completion for same episode — both persist |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 700, "status" => 2, "duration" => 781})` <br> 2. `addEntry(TYPE_EPISODE_COMPLETED, "ep-001", "pod-001", {"position" => 781, "status" => 3, "duration" => 781})` <br> 3. Call `getEntries()` |
| **Expected Result** | Returns 2 entries: the POSITION_UPDATE (position=700) and the EPISODE_COMPLETED (position=781). Completion does not evict the position update — only POSITION_UPDATE entries coalesce with each other. |

---

### CL-05: Status transitions — NOT_PLAYED → IN_PROGRESS → COMPLETED

| Field | Value |
|-------|-------|
| **ID** | CL-05 |
| **Category** | Changelog |
| **Scenario** | Log status transitions via different entry types |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 0, "status" => 0, "duration" => 781})` — NOT_PLAYED <br> 2. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 120, "status" => 2, "duration" => 781})` — IN_PROGRESS <br> 3. `addEntry(TYPE_EPISODE_COMPLETED, "ep-001", "pod-001", {"position" => 781, "status" => 3, "duration" => 781})` — COMPLETED <br> 4. Call `getEntries()` |
| **Expected Result** | Returns 2 entries (position updates coalesced into 1 with latest=status 2, plus 1 completion with status 3). Transition sequence is captured. |

---

### CL-06: Queue actions — log QUEUE_REMOVE

| Field | Value |
|-------|-------|
| **ID** | CL-06 |
| **Category** | Changelog |
| **Scenario** | Log a queue removal, verify recorded |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_QUEUE_REMOVE, "ep-001", "pod-001", {})` <br> 2. Call `getEntries()` |
| **Expected Result** | Returns 1 entry with `type == "QUEUE_REMOVE"`, `episodeUuid == "ep-001"`, `data` is empty dictionary. |

---

### CL-07: Bounded growth — fill to MAX_ENTRIES (100), verify eviction on 101st

| Field | Value |
|-------|-------|
| **ID** | CL-07 |
| **Category** | Changelog |
| **Scenario** | Fill changelog to 100 entries, add 101st, verify oldest non-completion evicted |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. Add 100 POSITION_UPDATE entries for episodes "ep-001" through "ep-100" (different episodes to avoid coalescing) <br> 2. Verify `getEntryCount() == 100` <br> 3. Add 1 more: `addEntry(TYPE_POSITION_UPDATE, "ep-101", "pod-001", {...})` <br> 4. Call `getEntries()` |
| **Expected Result** | Entry count is 100 (not 101). The oldest entry (ep-001, lowest timestamp) was evicted. ep-101 is present. All other 99 entries (ep-002 through ep-100) remain. |

---

### CL-08: Eviction priority — completion entries protected over position updates

| Field | Value |
|-------|-------|
| **ID** | CL-08 |
| **Category** | Changelog |
| **Scenario** | Mix of completions and position updates at capacity — verify non-completions evict first |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. Add 50 EPISODE_COMPLETED entries (ep-001 to ep-050) <br> 2. Add 50 POSITION_UPDATE entries (ep-051 to ep-100) <br> 3. Verify `getEntryCount() == 100` <br> 4. Add 1 more POSITION_UPDATE for ep-101 <br> 5. Call `getEntries()` |
| **Expected Result** | Entry count is 100. The oldest POSITION_UPDATE (ep-051) was evicted, NOT the oldest EPISODE_COMPLETED (ep-001). All 50 completions are intact. |

---

### CL-09: Eviction fallback — all completions, oldest completion evicted

| Field | Value |
|-------|-------|
| **ID** | CL-09 |
| **Category** | Changelog |
| **Scenario** | All 100 entries are completions — eviction falls back to oldest completion |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. Add 100 EPISODE_COMPLETED entries (ep-001 to ep-100) <br> 2. Add 1 more EPISODE_COMPLETED for ep-101 <br> 3. Call `getEntries()` |
| **Expected Result** | Entry count is 100. ep-001 (oldest completion) was evicted. ep-101 and ep-002–ep-100 are all present. |

---

### CL-10: Persistence — entries survive app restart (Storage persistence)

| Field | Value |
|-------|-------|
| **ID** | CL-10 |
| **Category** | Changelog |
| **Scenario** | Log entries, simulate app restart, verify changelog survives from Storage |
| **Priority** | P0 |
| **Environment** | SIM+HW |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. Add 5 entries of mixed types (2 position updates, 1 completion, 2 queue removes) <br> 2. Verify `getEntryCount() == 5` <br> 3. **Simulator:** Exit app, relaunch. **Hardware:** Kill app via back button, relaunch from music providers <br> 4. Call `getEntries()` |
| **Expected Result** | Returns the same 5 entries with identical data. Sequence numbers, timestamps, UUIDs, and data payloads all match pre-restart values. `Application.Storage` persisted the `"yc_changelog"` key across app lifecycle. |

---

### CL-11: Clear — clearEntries() empties changelog

| Field | Value |
|-------|-------|
| **ID** | CL-11 |
| **Category** | Changelog |
| **Scenario** | Call clearEntries(), verify empty |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog has 5+ entries |
| **Steps** | 1. Add 5 entries <br> 2. Call `ChangeLog.clearEntries()` <br> 3. Call `getEntries()` <br> 4. Call `getEntryCount()` |
| **Expected Result** | `getEntries()` returns empty array. `getEntryCount()` returns 0. Storage key `"yc_changelog"` is deleted. |

---

### CL-12: Clear preserves sequence counter

| Field | Value |
|-------|-------|
| **ID** | CL-12 |
| **Category** | Changelog |
| **Scenario** | After clearEntries(), new entries continue sequence from where it left off |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. Add 5 entries (IDs 1–5) <br> 2. Call `clearEntries()` <br> 3. Add 1 more entry <br> 4. Read the entry |
| **Expected Result** | The new entry has `id == 6` (sequence counter `"yc_cl_seq"` persists across clear because `clearEntries()` only deletes `"yc_changelog"`, not `"yc_cl_seq"`). IDs never reuse. |

---

### CL-13: Mixed operations — interleave position updates, completions, queue actions

| Field | Value |
|-------|-------|
| **ID** | CL-13 |
| **Category** | Changelog |
| **Scenario** | Interleave different change types, verify all are present and correctly stored |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 120, "status" => 2, "duration" => 781})` <br> 2. `addEntry(TYPE_QUEUE_REMOVE, "ep-002", "pod-001", {})` <br> 3. `addEntry(TYPE_EPISODE_COMPLETED, "ep-003", "pod-002", {"position" => 600, "status" => 3, "duration" => 600})` <br> 4. `addEntry(TYPE_POSITION_UPDATE, "ep-004", "pod-002", {"position" => 30, "status" => 2, "duration" => 900})` <br> 5. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 240, "status" => 2, "duration" => 781})` — coalesces with step 1 <br> 6. Call `getEntries()` |
| **Expected Result** | Returns 4 entries total (not 5 — ep-001's position update was coalesced): <br> - ep-001: POSITION_UPDATE, position=240 (latest) <br> - ep-002: QUEUE_REMOVE <br> - ep-003: EPISODE_COMPLETED, position=600 <br> - ep-004: POSITION_UPDATE, position=30 <br> All IDs are unique and monotonically increasing (though some IDs may be "missing" due to coalesced replacements). |

---

### CL-14: Edge case — empty episode UUID

| Field | Value |
|-------|-------|
| **ID** | CL-14 |
| **Category** | Changelog |
| **Scenario** | Pass empty string as episodeUuid |
| **Priority** | P2 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "", "pod-001", {"position" => 60, "status" => 2, "duration" => 300})` <br> 2. Call `getEntries()` |
| **Expected Result** | Entry is stored (no crash). `episodeUuid == ""`. Sync engine should handle gracefully at push time by skipping empty UUIDs. *(Ideally, `addEntry` should validate and reject empty UUIDs — flag for implementation review.)* |

---

### CL-15: Edge case — null/zero/negative position values

| Field | Value |
|-------|-------|
| **ID** | CL-15 |
| **Category** | Changelog |
| **Scenario** | Pass boundary position values: 0, negative, and very large |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_POSITION_UPDATE, "ep-001", "pod-001", {"position" => 0, "status" => 0, "duration" => 781})` <br> 2. `addEntry(TYPE_POSITION_UPDATE, "ep-002", "pod-001", {"position" => -5, "status" => 2, "duration" => 781})` <br> 3. `addEntry(TYPE_POSITION_UPDATE, "ep-003", "pod-001", {"position" => 99999, "status" => 2, "duration" => 781})` — position > duration <br> 4. Call `getEntries()` |
| **Expected Result** | All 3 entries are stored (no crash). Values are stored as-is. Validation (rejecting negative, clamping to duration) should occur at the sync reconciliation layer, not at changelog storage. *(Document: should `addEntry` clamp `position` to `[0, duration]`? Flag for implementation review.)* |

---

### CL-16: Edge case — duplicate QUEUE_REMOVE for same episode

| Field | Value |
|-------|-------|
| **ID** | CL-16 |
| **Category** | Changelog |
| **Scenario** | Log QUEUE_REMOVE twice for the same episode |
| **Priority** | P2 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. `addEntry(TYPE_QUEUE_REMOVE, "ep-001", "pod-001", {})` <br> 2. `addEntry(TYPE_QUEUE_REMOVE, "ep-001", "pod-001", {})` <br> 3. Call `getEntries()` |
| **Expected Result** | Returns 2 entries — QUEUE_REMOVE is not coalesced (only POSITION_UPDATE coalesces). Both entries present. Sync engine must handle duplicate removes gracefully (idempotent). |

---

### CL-17: Entry count helper

| Field | Value |
|-------|-------|
| **ID** | CL-17 |
| **Category** | Changelog |
| **Scenario** | Verify getEntryCount() matches getEntries().size() at various counts |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty |
| **Steps** | 1. Verify `getEntryCount() == 0` <br> 2. Add 1 entry → verify `getEntryCount() == 1` <br> 3. Add 9 more → verify `getEntryCount() == 10` <br> 4. Clear → verify `getEntryCount() == 0` |
| **Expected Result** | `getEntryCount()` always equals `getEntries().size()`. |

---

### CL-18: Monotonic sequence IDs across multiple addEntry calls

| Field | Value |
|-------|-------|
| **ID** | CL-18 |
| **Category** | Changelog |
| **Scenario** | Verify IDs are monotonically increasing and never reuse |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Fresh app install (no prior sequence counter) |
| **Steps** | 1. Add 5 entries <br> 2. Read all entries <br> 3. Clear changelog <br> 4. Add 3 more entries <br> 5. Read all entries |
| **Expected Result** | First batch: IDs 1, 2, 3, 4, 5. Second batch: IDs 6, 7, 8. No ID is ever reused. Sequence counter persists independently of changelog data. |

---

## Phase A — Position Tracker

> **Note:** Position tracker is not yet implemented. These tests are written against the design spec (§4.2, §6.5). Method names are provisional — adjust to match Kaylee's implementation.

### PT-01: Start tracker, verify ticks at ~15s intervals

| Field | Value |
|-------|-------|
| **ID** | PT-01 |
| **Category** | PositionTracker |
| **Scenario** | Start position tracker during playback, verify periodic ticks |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Episode "ep-001" (duration 781s) is playing at position 0. Position tracker is not started. |
| **Steps** | 1. Start the position tracker for ep-001 <br> 2. Wait ~45 seconds (3 tick intervals) <br> 3. Read `ChangeLog.getEntries()` |
| **Expected Result** | Due to coalescing, there is 1 POSITION_UPDATE entry for ep-001 (each tick replaces the previous). The position value is approximately 45 ± 5 seconds (accounting for timer imprecision). The `status` is 2 (IN_PROGRESS). |

---

### PT-02: Stop tracker, verify no more ticks

| Field | Value |
|-------|-------|
| **ID** | PT-02 |
| **Category** | PositionTracker |
| **Scenario** | Start then stop the tracker, verify ticks stop |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Episode is playing. Position tracker is active. |
| **Steps** | 1. Start tracker <br> 2. Wait 20 seconds (1+ tick) <br> 3. Stop tracker <br> 4. Note the current changelog entry count and last position <br> 5. Wait 30 more seconds <br> 6. Read changelog |
| **Expected Result** | Changelog entry count and position have not changed since step 4. No new ticks after stop. |

---

### PT-03: Battery scaling — low battery increases interval

| Field | Value |
|-------|-------|
| **ID** | PT-03 |
| **Category** | PositionTracker |
| **Scenario** | Simulate battery < 20%, verify tracker interval increases |
| **Priority** | P1 |
| **Environment** | SIM (if battery simulation is available) or HW |
| **Preconditions** | Episode is playing. Battery > 50% initially. |
| **Steps** | 1. Start tracker at normal battery — verify ~15s tick interval <br> 2. Simulate battery dropping to 15% (or set battery level in simulator) <br> 3. Observe next tick interval |
| **Expected Result** | Tick interval increases to 30s or 60s when battery is low. Exact threshold and interval TBD by implementation — verify against Kaylee's constants. Position is still logged correctly, just less frequently. |

---

### PT-04: Integration — each tick calls ChangeLog.addEntry()

| Field | Value |
|-------|-------|
| **ID** | PT-04 |
| **Category** | PositionTracker |
| **Scenario** | Verify the tracker writes to changelog on each tick |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty. Episode is playing at position 0. |
| **Steps** | 1. Start position tracker <br> 2. Wait for 1 tick (~15s) <br> 3. Read changelog |
| **Expected Result** | Exactly 1 POSITION_UPDATE entry exists with the correct episode UUID, podcast UUID, current position (≈15s), status=2, and episode duration. |

---

### PT-05: Integration — tick also updates CacheManager position

| Field | Value |
|-------|-------|
| **ID** | PT-05 |
| **Category** | PositionTracker |
| **Scenario** | Verify the tracker updates both changelog AND CacheManager position cache |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Episode "ep-001" is playing. No cached position exists for ep-001. |
| **Steps** | 1. Start position tracker <br> 2. Wait for 1 tick <br> 3. Call `CacheManager.loadPlaybackPosition("ep-001")` |
| **Expected Result** | Returns a dictionary with `position ≈ 15`, `duration == 781`, and a recent `cachedAt` timestamp. Both changelog and position cache are updated in sync. |

---

### PT-06: Playback pause — tracker stops ticking

| Field | Value |
|-------|-------|
| **ID** | PT-06 |
| **Category** | PositionTracker |
| **Scenario** | Pause playback, verify tracker stops. Resume, verify tracker restarts. |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Episode is playing. Tracker is active. |
| **Steps** | 1. Wait for at least 1 tick — note position in changelog <br> 2. Pause playback <br> 3. Wait 30 seconds <br> 4. Verify no new changelog entries (position unchanged) <br> 5. Resume playback <br> 6. Wait for at least 1 tick (~15s) <br> 7. Read changelog |
| **Expected Result** | Position in changelog advances after resume but not during pause. Tracker is effectively idled during pause and automatically restarts on resume. |

---

### PT-07: Edge case — start tracker twice (idempotent)

| Field | Value |
|-------|-------|
| **ID** | PT-07 |
| **Category** | PositionTracker |
| **Scenario** | Call start tracker twice — should not create duplicate timers |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Episode is playing. Tracker is not started. |
| **Steps** | 1. Start tracker <br> 2. Start tracker again (duplicate call) <br> 3. Wait 20 seconds <br> 4. Read changelog |
| **Expected Result** | Only 1 POSITION_UPDATE entry exists (coalesced). There is no evidence of double-ticking (e.g., two entries logged within the same second). The second start call is a no-op. |

---

### PT-08: Edge case — stop tracker when not started

| Field | Value |
|-------|-------|
| **ID** | PT-08 |
| **Category** | PositionTracker |
| **Scenario** | Stop tracker before it's started — no crash |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Tracker has never been started |
| **Steps** | 1. Call stop tracker |
| **Expected Result** | No exception, no crash, no side effects. Stop on an inactive tracker is a safe no-op. |

---

### PT-09: Edge case — very short episode (duration < 15s)

| Field | Value |
|-------|-------|
| **ID** | PT-09 |
| **Category** | PositionTracker |
| **Scenario** | Play a 10-second episode — does tracker fire at all? |
| **Priority** | P2 |
| **Environment** | SIM |
| **Preconditions** | Episode "ep-short" has duration 10s. Changelog is empty. |
| **Steps** | 1. Start playing ep-short at position 0 <br> 2. Start tracker <br> 3. Episode ends after 10 seconds (completes before first tick) <br> 4. Read changelog |
| **Expected Result** | At minimum, an EPISODE_COMPLETED entry should be logged when the episode finishes, even if no POSITION_UPDATE tick fired. The completion handler should not depend on the tracker having ticked first. |

---

### PT-10: Episode completion — logs EPISODE_COMPLETED and QUEUE_REMOVE

| Field | Value |
|-------|-------|
| **ID** | PT-10 |
| **Category** | PositionTracker |
| **Scenario** | Episode plays to the end — verify completion and queue removal logged |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Episode "ep-001" (duration 781s) is nearly complete (position 775). Changelog is empty. Episode is in the local queue. |
| **Steps** | 1. Play to completion (position reaches 781) <br> 2. Read changelog |
| **Expected Result** | Changelog contains: <br> - 1 EPISODE_COMPLETED entry: `status == 3`, `position == 781 (== duration)` <br> - 1 QUEUE_REMOVE entry for ep-001 <br> Local queue cache is also updated (ep-001 removed from order). |

---

## Phase B — Sync Engine (7-Step State Machine)

> **Note:** Sync engine is not yet implemented. Tests describe the expected behavior from the design spec (§6.1, §6.2). Method signatures and state names are provisional.

### SE-01: Happy path — full sync cycle with no conflicts

| Field | Value |
|-------|-------|
| **ID** | SE-01 |
| **Category** | SyncEngine |
| **Scenario** | Complete sync cycle: auth → read changelog → fetch server → reconcile → push → refresh → cleanup |
| **Priority** | P0 |
| **Environment** | SIM (with mocked API responses) |
| **Preconditions** | - Auth token is valid <br> - Changelog has 3 entries: position updates for ep-001 (pos=120), ep-002 (pos=300), and ep-003 completed <br> - Server state: ep-001 at pos=60 (behind local), ep-002 at pos=300 (equal), ep-003 IN_PROGRESS at pos=500 <br> - Connection is available |
| **Steps** | 1. Trigger sync <br> 2. Wait for sync to complete <br> 3. Verify API calls made <br> 4. Check changelog <br> 5. Check local caches |
| **Expected Result** | - **Step 2 (Auth):** Token validated, no re-login needed <br> - **Step 3 (Read changelog):** 3 entries read <br> - **Step 4 (Fetch server):** `/user/episode` called for ep-001, ep-002, ep-003; `/up_next/list` called <br> - **Step 5 (Reconcile & push):** <br> &nbsp;&nbsp;• ep-001: `max(120, 60) = 120` → push position 120, status 2 <br> &nbsp;&nbsp;• ep-002: `max(300, 300) = 300` → no push needed (equal) <br> &nbsp;&nbsp;• ep-003: COMPLETED wins → push position max(781, 500) = 781, status 3 <br> - **Step 6 (Refresh):** Caches refreshed from server <br> - **Step 7 (Cleanup):** Changelog cleared. Sync state = COMPLETE. |

---

### SE-02: Position conflict — server ahead (server wins)

| Field | Value |
|-------|-------|
| **ID** | SE-02 |
| **Category** | SyncEngine |
| **Scenario** | Local position 120s, server position 180s → server wins via max() |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog: ep-001 POSITION_UPDATE, position=120, status=2. Server: ep-001 playedUpTo=180, playingStatus=2. |
| **Steps** | 1. Trigger sync <br> 2. Read reconciled state |
| **Expected Result** | Resolved position = `max(120, 180) = 180`. Local cache updated to 180. No push needed to server (server already has the winning value). Changelog entry cleared. |

---

### SE-03: Position conflict — local ahead (local wins)

| Field | Value |
|-------|-------|
| **ID** | SE-03 |
| **Category** | SyncEngine |
| **Scenario** | Local position 180s, server position 120s → local wins via max() |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog: ep-001 POSITION_UPDATE, position=180, status=2. Server: ep-001 playedUpTo=120, playingStatus=2. |
| **Steps** | 1. Trigger sync <br> 2. Inspect push request to `/sync/update_episode` |
| **Expected Result** | Resolved position = `max(180, 120) = 180`. Push to server: `{uuid: "ep-001", position: 180, status: 2}`. Local cache updated to 180. |

---

### SE-04: Status conflict — local IN_PROGRESS, server COMPLETED → COMPLETED wins

| Field | Value |
|-------|-------|
| **ID** | SE-04 |
| **Category** | SyncEngine |
| **Scenario** | Local says IN_PROGRESS, server says COMPLETED — COMPLETED wins per hierarchy |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog: ep-001, position=300, status=2 (IN_PROGRESS). Server: ep-001, playedUpTo=781, playingStatus=3 (COMPLETED). |
| **Steps** | 1. Trigger sync <br> 2. Inspect resolved state |
| **Expected Result** | Resolved status = COMPLETED (3). Resolved position = `max(300, 781) = 781`. Local cache updated to COMPLETED. No push needed (server already has COMPLETED). |

---

### SE-05: Status conflict — local COMPLETED, server IN_PROGRESS → COMPLETED wins

| Field | Value |
|-------|-------|
| **ID** | SE-05 |
| **Category** | SyncEngine |
| **Scenario** | Local says COMPLETED, server says IN_PROGRESS — COMPLETED still wins |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog: ep-001, EPISODE_COMPLETED, position=781, status=3. Server: ep-001, playedUpTo=120, playingStatus=2. |
| **Steps** | 1. Trigger sync <br> 2. Inspect push request |
| **Expected Result** | Resolved status = COMPLETED (3). Resolved position = `max(781, 120, duration=781) = 781`. Push to server: `{uuid: "ep-001", position: 781, status: 3, duration: 781}`. |

---

### SE-06: Status conflict — both NOT_PLAYED

| Field | Value |
|-------|-------|
| **ID** | SE-06 |
| **Category** | SyncEngine |
| **Scenario** | Both local and server say NOT_PLAYED — no conflict, stays NOT_PLAYED |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog: ep-001, position=0, status=0. Server: ep-001, playedUpTo=0, playingStatus=0. |
| **Steps** | 1. Trigger sync |
| **Expected Result** | Resolved status = NOT_PLAYED (0), position = 0. No push needed. No local update needed. |

---

### SE-07: Queue reconciliation — local completed episode → removed from queue

| Field | Value |
|-------|-------|
| **ID** | SE-07 |
| **Category** | SyncEngine |
| **Scenario** | Watch completed an episode that's still in the server queue |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | - Local changelog: EPISODE_COMPLETED for ep-A <br> - Server queue order: [ep-A, ep-B, ep-C] <br> - Local queue: [ep-B, ep-C] (ep-A already auto-removed locally) |
| **Steps** | 1. Trigger sync <br> 2. Inspect resolved queue |
| **Expected Result** | Resolved queue: [ep-B, ep-C]. ep-A is removed because it was completed locally. ep-A's completion is pushed to server via `/sync/update_episode`. |

---

### SE-08: Queue reconciliation — server added new episode → merged

| Field | Value |
|-------|-------|
| **ID** | SE-08 |
| **Category** | SyncEngine |
| **Scenario** | Server added episodes while watch was offline |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | - Local queue: [ep-A, ep-B] (no changes) <br> - Server queue: [ep-A, ep-B, ep-C, ep-D] (ep-C, ep-D added on phone) <br> - Changelog: empty (no local modifications) |
| **Steps** | 1. Trigger sync <br> 2. Inspect resolved queue |
| **Expected Result** | Resolved queue: [ep-A, ep-B, ep-C, ep-D]. Server order is base. New episodes merged. Local queue cache updated. |

---

### SE-09: Queue reconciliation — server removed episode → respected

| Field | Value |
|-------|-------|
| **ID** | SE-09 |
| **Category** | SyncEngine |
| **Scenario** | Server removed an episode the watch didn't play |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | - Local queue: [ep-A, ep-B, ep-C, ep-D] <br> - Server queue: [ep-A, ep-C] (ep-B and ep-D removed on phone) <br> - Changelog: no entries for ep-B or ep-D |
| **Steps** | 1. Trigger sync <br> 2. Inspect resolved queue |
| **Expected Result** | Resolved queue: [ep-A, ep-C]. Server removals respected because watch never touched ep-B or ep-D. |

---

### SE-10: Queue reconciliation — complex merge scenario

| Field | Value |
|-------|-------|
| **ID** | SE-10 |
| **Category** | SyncEngine |
| **Scenario** | Combination: local completed ep-A, server removed ep-D, server added ep-E and ep-F |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | - Local queue: [ep-B, ep-C, ep-D] (ep-A auto-removed after completion) <br> - Server queue: [ep-A, ep-B, ep-C, ep-E, ep-F] (ep-D removed, ep-E/F added) <br> - Changelog: EPISODE_COMPLETED for ep-A |
| **Steps** | 1. Trigger sync |
| **Expected Result** | Resolved queue: [ep-B, ep-C, ep-E, ep-F]. <br> - ep-A removed (completed locally) <br> - ep-D removed (server removed, watch didn't play) <br> - ep-E, ep-F added (from server) <br> - ep-A's completion pushed to server |

---

### SE-11: Empty changelog — sync with no local changes

| Field | Value |
|-------|-------|
| **ID** | SE-11 |
| **Category** | SyncEngine |
| **Scenario** | Changelog is empty — sync should skip to cache refresh |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog is empty. Connection available. Auth valid. |
| **Steps** | 1. Trigger sync <br> 2. Monitor API calls <br> 3. Check local caches |
| **Expected Result** | - Steps 1–2 (Auth): Validated <br> - Step 3 (Read changelog): Empty → **skip to Step 6** <br> - Steps 4–5 (Fetch/Reconcile/Push): Skipped entirely <br> - Step 6 (Refresh): Caches refreshed from server (podcasts, queue, in_progress) <br> - Step 7 (Cleanup): Sync state = COMPLETE. No changelog to clear. |

---

### SE-12: Auth failure during sync — token expired → refresh → retry

| Field | Value |
|-------|-------|
| **ID** | SE-12 |
| **Category** | SyncEngine |
| **Scenario** | Token is expired at sync start, engine refreshes and continues |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | - Auth token is expired (or mock 401 response) <br> - Refresh token is valid <br> - Changelog has entries |
| **Steps** | 1. Trigger sync <br> 2. Step 2 detects expired token <br> 3. Observe retry with `/user/token` <br> 4. Sync continues |
| **Expected Result** | - First attempt: 401 detected <br> - Token refreshed via `/user/token` <br> - Sync resumes from Step 2 with new token <br> - Full sync completes successfully <br> - New token persisted for future use |

---

### SE-13: Auth failure — refresh fails, re-login succeeds

| Field | Value |
|-------|-------|
| **ID** | SE-13 |
| **Category** | SyncEngine |
| **Scenario** | Token refresh fails, falls back to full re-login |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Token expired. Refresh returns error. Stored credentials valid. |
| **Steps** | 1. Trigger sync <br> 2. Token refresh via `/user/token` returns 400 <br> 3. Engine falls back to `/user/login_pocket_casts` |
| **Expected Result** | Re-login succeeds. New token and refresh token stored. Sync continues from Step 3. |

---

### SE-14: Auth failure — both refresh and re-login fail

| Field | Value |
|-------|-------|
| **ID** | SE-14 |
| **Category** | SyncEngine |
| **Scenario** | All auth methods fail — sync aborts gracefully |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Token expired. Refresh fails. Re-login fails (bad credentials or server error). |
| **Steps** | 1. Trigger sync <br> 2. All auth attempts fail |
| **Expected Result** | - Sync aborts at Step 2 <br> - Sync state = IDLE (with auth error indicator) <br> - **Changelog is preserved** (not cleared) <br> - UI shows auth error <br> - Next sync attempt will try auth again |

---

### SE-15: Network loss during sync — at Step 4 (fetch server state)

| Field | Value |
|-------|-------|
| **ID** | SE-15 |
| **Category** | SyncEngine |
| **Scenario** | Connectivity drops while fetching server episode state |
| **Priority** | P0 |
| **Environment** | SIM+HW |
| **Preconditions** | Sync is in progress. Auth succeeded. Changelog read. HTTP request to `/user/episode` fails (network error). |
| **Steps** | 1. Trigger sync <br> 2. Simulate network drop after auth succeeds <br> 3. `makeWebRequest` callback returns error code |
| **Expected Result** | - Sync aborts gracefully <br> - State machine returns to IDLE <br> - **Changelog is preserved** — no entries cleared <br> - No partial pushes occurred (we haven't reached push phase yet) <br> - Storage is consistent — all cached data remains valid |

---

### SE-16: Network loss during sync — at Step 5 (push, mid-batch)

| Field | Value |
|-------|-------|
| **ID** | SE-16 |
| **Category** | SyncEngine |
| **Scenario** | Network drops after pushing 2 of 5 episodes |
| **Priority** | P0 |
| **Environment** | SIM+HW |
| **Preconditions** | Changelog has 5 position updates. Sync has pushed ep-001 and ep-002 successfully. Push of ep-003 fails (network error). |
| **Steps** | 1. Trigger sync <br> 2. ep-001 push: 200 OK → entry cleared <br> 3. ep-002 push: 200 OK → entry cleared <br> 4. ep-003 push: network error |
| **Expected Result** | - Sync stops pushing <br> - ep-001 and ep-002 changelog entries are cleared (successfully pushed) <br> - ep-003, ep-004, ep-005 entries **remain in changelog** <br> - Next sync will pick up where this one left off (ep-003, ep-004, ep-005) <br> - No data loss, no duplicate pushes (idempotent) |

---

### SE-17: Network loss during sync — at Step 6 (cache refresh)

| Field | Value |
|-------|-------|
| **ID** | SE-17 |
| **Category** | SyncEngine |
| **Scenario** | Network drops during cache refresh after successful push |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | All pushes completed. Cache refresh requests fail. |
| **Steps** | 1. Trigger sync <br> 2. All pushes succeed <br> 3. Cache refresh requests fail |
| **Expected Result** | - Pushes were successful — changelog entries are cleared <br> - Stale caches remain (from before sync) <br> - Sync state reflects partial success <br> - Next sync (or next app launch with connectivity) will refresh caches |

---

### SE-18: Idempotency — run sync twice with same changelog

| Field | Value |
|-------|-------|
| **ID** | SE-18 |
| **Category** | SyncEngine |
| **Scenario** | Sync completes, then runs again immediately — no duplicate pushes |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog has 3 entries. Connection available. |
| **Steps** | 1. Trigger sync → completes successfully <br> 2. Verify changelog is cleared <br> 3. Trigger sync again immediately |
| **Expected Result** | - First sync: 3 push requests made <br> - Second sync: 0 push requests made (changelog is empty → skips to cache refresh) <br> - No duplicate `/sync/update_episode` calls |

---

### SE-19: Idempotency — sync interrupted, then resumed

| Field | Value |
|-------|-------|
| **ID** | SE-19 |
| **Category** | SyncEngine |
| **Scenario** | First sync pushes 2 of 3, interrupted. Second sync pushes remaining 1 plus re-pushes nothing. |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog has 3 entries (ep-001, ep-002, ep-003). |
| **Steps** | 1. Start sync → pushes ep-001 and ep-002 (200 OK) → ep-003 fails → sync aborts <br> 2. Re-trigger sync |
| **Expected Result** | - Second sync reads changelog: only ep-003 remains <br> - Only 1 push request made (ep-003) <br> - Even if ep-001 and ep-002 are pushed again (from idempotent re-read), server accepts them harmlessly <br> - Final state: all episodes synced, changelog empty |

---

### SE-20: Concurrent modification — app writes changelog while sync reads it

| Field | Value |
|-------|-------|
| **ID** | SE-20 |
| **Category** | SyncEngine |
| **Scenario** | User plays episode during active sync, adding new changelog entries |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog has 2 entries. Sync starts. User continues playing, generating position updates. |
| **Steps** | 1. Start sync <br> 2. During sync processing (between push callbacks), position tracker adds new entries to changelog <br> 3. Sync completes and clears changelog |
| **Expected Result** | - Sync processes the 2 original entries <br> - New entries added during sync are **not cleared** — they were added after the sync read the changelog <br> - After sync cleanup, new entries remain in changelog for next sync <br> - **No entries lost.** The critical safety property: clearing only successfully-pushed entries, not the entire log indiscriminately. |

---

### SE-21: Large changelog — 100 entries (maximum capacity)

| Field | Value |
|-------|-------|
| **ID** | SE-21 |
| **Category** | SyncEngine |
| **Scenario** | Sync with changelog at max capacity (100 entries) |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog has exactly 100 entries (mix of types: 70 position updates for different episodes, 20 completions, 10 queue removes). Server state available for all affected episodes. |
| **Steps** | 1. Trigger sync <br> 2. Monitor push sequence <br> 3. Verify all entries processed |
| **Expected Result** | - Sync reads all 100 entries <br> - Reconciliation processes each position/completion against server state <br> - Only entries that differ from server are pushed (subset of 100) <br> - Sequential push: one `/sync/update_episode` at a time via callback chain <br> - All successfully pushed entries cleared <br> - Sync completes without timeout or memory error |

---

### SE-22: Push rate throttling — 1 request per second

| Field | Value |
|-------|-------|
| **ID** | SE-22 |
| **Category** | SyncEngine |
| **Scenario** | Verify push requests are throttled to prevent rate limiting |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | 10 entries need pushing. |
| **Steps** | 1. Trigger sync <br> 2. Measure time between consecutive push callbacks initiating next request |
| **Expected Result** | Minimum ~1 second gap between push requests (per §7.4). No 429 responses from server. Total push phase takes ≥ 10 seconds for 10 entries. |

---

### SE-23: Retry with exponential backoff on 429 response

| Field | Value |
|-------|-------|
| **ID** | SE-23 |
| **Category** | SyncEngine |
| **Scenario** | Server returns 429 (rate limited) — engine backs off |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Push in progress. Server returns 429. |
| **Steps** | 1. Push ep-001 → 200 OK <br> 2. Push ep-002 → 429 Too Many Requests <br> 3. Observe backoff behavior |
| **Expected Result** | - Retry after 5s, then 10s, then 20s, then 40s (exponential backoff per §7.4) <br> - Max 4 retries per entry <br> - After 4 failures, stop pushing, preserve remaining entries <br> - ep-001 is cleared (succeeded), ep-002 and beyond remain |

---

### SE-24: 401 during push — token refresh mid-sync

| Field | Value |
|-------|-------|
| **ID** | SE-24 |
| **Category** | SyncEngine |
| **Scenario** | Push returns 401 — token expired during active sync |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Auth succeeded initially. Token expires during push phase. |
| **Steps** | 1. Push ep-001 → 200 OK <br> 2. Push ep-002 → 401 Unauthorized <br> 3. Observe token refresh |
| **Expected Result** | - Engine refreshes token via `/user/token` <br> - Retries ep-002 push with new token <br> - If refresh succeeds, sync continues <br> - If refresh fails, sync aborts. ep-001 cleared, ep-002+ preserved. |

---

### SE-25: Sync trigger — connectivity transition offline → online

| Field | Value |
|-------|-------|
| **ID** | SE-25 |
| **Category** | SyncEngine |
| **Scenario** | Watch reconnects — sync triggers automatically |
| **Priority** | P0 |
| **Environment** | HW |
| **Preconditions** | Watch was offline (tracked via `_wasOffline` flag). Changelog has entries. |
| **Steps** | 1. Ensure watch is offline (airplane mode or out of BT range) <br> 2. Add changelog entries while offline <br> 3. Restore connectivity (come in BT range or connect Wi-Fi) <br> 4. Wait for connectivity polling (30s interval per §6.5) |
| **Expected Result** | Sync triggers automatically within 30 seconds of reconnection. All changelog entries are processed and pushed. |

---

### SE-26: Sync trigger — app launch with connectivity

| Field | Value |
|-------|-------|
| **ID** | SE-26 |
| **Category** | SyncEngine |
| **Scenario** | App launches with connectivity and unsynced changes — sync triggers |
| **Priority** | P0 |
| **Environment** | SIM+HW |
| **Preconditions** | Changelog has entries from previous offline session. Watch has connectivity. |
| **Steps** | 1. Launch app <br> 2. Observe sync behavior |
| **Expected Result** | Sync begins on or shortly after launch. Changelog entries pushed. Caches refreshed. |

---

### SE-27: Conflict resolution truth table — full matrix

| Field | Value |
|-------|-------|
| **ID** | SE-27 |
| **Category** | SyncEngine |
| **Scenario** | Verify all 9 rows of the conflict resolution truth table (§5.4) |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | For each row below, set up changelog entry and mock server response. |
| **Steps & Expected Results** | |

| # | Local Status | Server Status | Local Pos | Server Pos | → Status | → Pos | Push? |
|---|---|---|---|---|---|---|---|
| 1 | NOT_PLAYED (0) | NOT_PLAYED (0) | 0 | 0 | NOT_PLAYED | 0 | No |
| 2 | IN_PROGRESS (2) | NOT_PLAYED (0) | 500 | 0 | IN_PROGRESS | 500 | Yes |
| 3 | NOT_PLAYED (0) | IN_PROGRESS (2) | 0 | 300 | IN_PROGRESS | 300 | No |
| 4 | IN_PROGRESS (2) | IN_PROGRESS (2) | 500 | 300 | IN_PROGRESS | 500 | Yes |
| 5 | IN_PROGRESS (2) | IN_PROGRESS (2) | 300 | 500 | IN_PROGRESS | 500 | No |
| 6 | COMPLETED (3) | NOT_PLAYED (0) | 781 | 0 | COMPLETED | 781 | Yes |
| 7 | COMPLETED (3) | IN_PROGRESS (2) | 781 | 300 | COMPLETED | 781 | Yes |
| 8 | IN_PROGRESS (2) | COMPLETED (3) | 300 | 781 | COMPLETED | 781 | No |
| 9 | COMPLETED (3) | COMPLETED (3) | 781 | 781 | COMPLETED | 781 | No |

Each row should be tested as a separate sync with one changelog entry and corresponding server state. "Push?" indicates whether a `/sync/update_episode` call should be made (resolved differs from server).

---

### SE-28: Reconciliation — episode deleted on server

| Field | Value |
|-------|-------|
| **ID** | SE-28 |
| **Category** | SyncEngine |
| **Scenario** | Server returns null/404 for an episode in the changelog |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog: POSITION_UPDATE for ep-deleted. Server: `/user/episode` returns 404 or null for ep-deleted. |
| **Steps** | 1. Trigger sync <br> 2. Observe handling of deleted episode |
| **Expected Result** | - Skip reconciliation for ep-deleted (per §5.5) <br> - Remove ep-deleted from local cache <br> - Clear the changelog entry (nothing to sync) <br> - Other entries processed normally <br> - No crash, no error state |

---

### SE-29: Hybrid pull strategy — bulk fetch then individual fallback

| Field | Value |
|-------|-------|
| **ID** | SE-29 |
| **Category** | SyncEngine |
| **Scenario** | Verify the engine uses /user/in_progress + /user/history first, then individual fallback |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog has 5 entries: 3 in-progress episodes (covered by bulk fetch), 2 episodes not in any bulk response (need individual fetch). |
| **Steps** | 1. Trigger sync <br> 2. Count API requests |
| **Expected Result** | - 1 request to `/user/in_progress` <br> - 1 request to `/user/history` (optional) <br> - 2 requests to `/user/episode` (only for episodes not found in bulk responses) <br> - Total: 3–4 requests instead of 5 individual requests |

---

### SE-30: Sync state machine states — UI indicator

| Field | Value |
|-------|-------|
| **ID** | SE-30 |
| **Category** | SyncEngine |
| **Scenario** | Verify sync state transitions reflected in UI |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | Changelog has entries. Connection available. |
| **Steps** | 1. Observe UI state before sync → no indicator (IDLE) <br> 2. Trigger sync → "Syncing..." indicator shown <br> 3. Sync completes → indicator removed or shows "Sync complete" <br> 4. On sync failure → error indicator |
| **Expected Result** | State transitions visible: IDLE → AUTH → PUSH_LOCAL → PULL_SERVER → CLEANUP → IDLE. UI updates at each transition. |

---

## Cross-Cutting Tests

### CC-01: Memory pressure — sync engine with low free memory

| Field | Value |
|-------|-------|
| **ID** | CC-01 |
| **Category** | CrossCutting |
| **Scenario** | Run sync with constrained memory (near device limits) |
| **Priority** | P2 |
| **Environment** | HW |
| **Preconditions** | Device memory is under pressure (large caches loaded, episode lists populated). Changelog has 50+ entries. |
| **Steps** | 1. Load maximum cache data (30 podcasts, 15 episodes each, full queue) <br> 2. Trigger sync with 50-entry changelog <br> 3. Monitor for memory errors |
| **Expected Result** | - Sync completes without `OutOfMemoryError` <br> - If memory allocation fails, sync aborts gracefully — no crash, no data loss <br> - Changelog preserved on failure <br> - Worst case: sync defers to next opportunity with smaller batch |

---

### CC-02: Bluetooth disconnect during sync

| Field | Value |
|-------|-------|
| **ID** | CC-02 |
| **Category** | CrossCutting |
| **Scenario** | Phone goes out of BT range mid-sync (BT-only connectivity) |
| **Priority** | P1 |
| **Environment** | HW |
| **Preconditions** | Watch is syncing over BT proxy (no Wi-Fi). Phone is paired and in range. Sync is at push phase. |
| **Steps** | 1. Start sync over BT <br> 2. Move phone out of BT range during push phase <br> 3. `makeWebRequest` returns connectivity error <br> 4. Watch detects offline state on next connectivity poll |
| **Expected Result** | - Active push request fails with network error <br> - Sync aborts gracefully → state returns to IDLE <br> - Successfully-pushed entries are cleared; remaining entries preserved <br> - App continues to function in offline mode <br> - Sync re-triggers when phone comes back in range |

---

### CC-03: Wi-Fi → BT fallback scenario

| Field | Value |
|-------|-------|
| **ID** | CC-03 |
| **Category** | CrossCutting |
| **Scenario** | Wi-Fi drops during sync, BT proxy still available |
| **Priority** | P2 |
| **Environment** | HW |
| **Preconditions** | Watch connected via Wi-Fi. Phone also in BT range. Sync in progress. |
| **Steps** | 1. Start sync over Wi-Fi <br> 2. Wi-Fi network goes down <br> 3. Observe behavior |
| **Expected Result** | - `connectionAvailable` remains true (BT proxy takes over) <br> - `makeWebRequest` may see transient errors during transition <br> - Sync engine either continues (if transparent) or retries current step <br> - No data loss — changelog preserved regardless of outcome <br> - **Note:** Garmin's `makeWebRequest` abstracts the transport; the transition may be transparent to the app |

---

### CC-04: App kill during sync — Storage consistency on next launch

| Field | Value |
|-------|-------|
| **ID** | CC-04 |
| **Category** | CrossCutting |
| **Scenario** | User exits app mid-sync — verify data integrity on next launch |
| **Priority** | P0 |
| **Environment** | HW |
| **Preconditions** | Sync in progress (push phase). Some entries already cleared, some pending. |
| **Steps** | 1. Start sync <br> 2. Force-kill app during push phase (back button or system) <br> 3. Relaunch app <br> 4. Check Storage state |
| **Expected Result** | - `"yc_changelog"` contains remaining (un-pushed) entries <br> - Already-pushed entries may or may not be cleared (depends on when kill happened relative to Storage write) <br> - **Key invariant:** No entry is cleared without being pushed first <br> - On relaunch, sync triggers again and processes remaining entries <br> - All cached data (podcasts, queue, positions) is intact <br> - No corrupted Storage keys |

---

### CC-05: ConnectivityManager state detection accuracy

| Field | Value |
|-------|-------|
| **ID** | CC-05 |
| **Category** | CrossCutting |
| **Scenario** | Verify ConnectivityManager returns correct states for all 4 setting combinations |
| **Priority** | P0 |
| **Environment** | HW |
| **Preconditions** | Venu 4 with Wi-Fi configured and phone paired. |
| **Steps & Expected Results** | |

| connectionAvailable | phoneConnected | Expected State | Test Method |
|---|---|---|---|
| true | false | STATE_WIFI (0) | Connect to Wi-Fi, turn off phone BT |
| true | true | STATE_PHONE (1) | Connect Wi-Fi + phone BT |
| false | false | STATE_OFFLINE (2) | Airplane mode |
| false | true | STATE_OFFLINE (2) | Very rare — verify `isConnected()` returns false |

Verify `isConnected()`, `isWifiDirect()`, and `canMakeRequests()` return correct values for each state.

---

### CC-06: Changelog + CacheManager isolation

| Field | Value |
|-------|-------|
| **ID** | CC-06 |
| **Category** | CrossCutting |
| **Scenario** | Verify CacheManager.clearCache() does NOT clear changelog |
| **Priority** | P0 |
| **Environment** | SIM |
| **Preconditions** | Changelog has 5 entries. Caches populated. |
| **Steps** | 1. Add 5 changelog entries <br> 2. Call `CacheManager.clearCache()` <br> 3. Call `ChangeLog.getEntries()` |
| **Expected Result** | Changelog still has 5 entries. `clearCache()` only deletes podcast/queue/episode cache keys (`yc_podcasts`, `yc_queue`), not `yc_changelog`. Position caches (`yc_pos_*`) are also preserved. |

---

### CC-07: Storage key namespace isolation

| Field | Value |
|-------|-------|
| **ID** | CC-07 |
| **Category** | CrossCutting |
| **Scenario** | Verify all modules use distinct Storage key prefixes — no key collisions |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | All modules initialized. |
| **Steps** | 1. Populate all storage: <br> - CacheManager: save podcasts, queue, episodes, positions <br> - ChangeLog: add entries <br> - StorageManager: mark a download <br> 2. Read each module's data independently |
| **Expected Result** | No key collisions. All keys use `"yc_"` prefix: <br> - `yc_podcasts`, `yc_queue`, `yc_episodes_*`, `yc_pos_*` (CacheManager) <br> - `yc_changelog`, `yc_cl_seq` (ChangeLog) <br> - `yc_downloads` (StorageManager) <br> Each module reads only its own data. |

---

### CC-08: Connectivity polling timer — 30s interval

| Field | Value |
|-------|-------|
| **ID** | CC-08 |
| **Category** | CrossCutting |
| **Scenario** | Verify connectivity check runs every ~30 seconds |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | App is running. Connectivity polling started. |
| **Steps** | 1. Enable logging on connectivity check callback <br> 2. Wait 2 minutes <br> 3. Count poll invocations |
| **Expected Result** | Approximately 4 polls in 2 minutes (every 30s ± timer jitter). Each poll reads `System.getDeviceSettings()` and evaluates sync trigger conditions. |

---

### CC-09: Sync does not block UI

| Field | Value |
|-------|-------|
| **ID** | CC-09 |
| **Category** | CrossCutting |
| **Scenario** | User can navigate while sync is in progress |
| **Priority** | P1 |
| **Environment** | SIM+HW |
| **Preconditions** | Sync in progress (push phase, multiple entries). |
| **Steps** | 1. Trigger sync with 10 entries <br> 2. While sync is running, navigate: Home → Queue → Episode list → back <br> 3. Verify UI responsiveness |
| **Expected Result** | - UI is responsive during sync — no freezing or lag <br> - `makeWebRequest` is async (non-blocking by design) <br> - Navigation works normally <br> - Sync indicator visible throughout <br> - Sync completes in background |

---

### CC-10: Storage 32KB per-value limit — large changelog

| Field | Value |
|-------|-------|
| **ID** | CC-10 |
| **Category** | CrossCutting |
| **Scenario** | Verify 100-entry changelog fits within Application.Storage 32KB per-value limit |
| **Priority** | P1 |
| **Environment** | SIM |
| **Preconditions** | None |
| **Steps** | 1. Build a worst-case changelog: 100 entries with maximum-length UUIDs (36 chars), full data payloads <br> 2. Call `Application.Storage.setValue("yc_changelog", ...)` <br> 3. Call `Application.Storage.getValue("yc_changelog")` |
| **Expected Result** | Storage write succeeds. Read returns identical data. Estimated size: ~100 entries × ~100 bytes ≈ 10 KB — well within 32 KB limit. If this fails on a real device, `MAX_ENTRIES` needs to be reduced. |

---

## Test Execution Notes

### Simulator vs Hardware Matrix

| Test IDs | Simulator | Hardware | Notes |
|----------|:---------:|:--------:|-------|
| CL-01 through CL-18 | ✅ | — | Pure logic, no device features needed |
| PT-01, PT-02, PT-04 through PT-10 | ✅ | Verify | Timer behavior; sim is sufficient for logic |
| PT-03 | ⚠️ | ✅ | Battery simulation may not be available in sim |
| SE-01 through SE-24, SE-26, SE-27 through SE-30 | ✅ | — | Mocked API responses in sim |
| SE-25 | — | ✅ | Real connectivity transitions |
| CC-01 | — | ✅ | Real memory constraints |
| CC-02, CC-03 | — | ✅ | Real BT/Wi-Fi behavior |
| CC-04 | — | ✅ | Real app kill behavior |
| CC-05 | — | ✅ | Real device settings |
| CC-06, CC-07, CC-08, CC-09, CC-10 | ✅ | Verify | Logic tests; hardware verify for confidence |

### Test Doubles Needed

| Component | Mock Strategy |
|-----------|---------------|
| **PocketCasts API** | Mock `makeWebRequest` responses with pre-built dictionaries matching documented response shapes |
| **Application.Storage** | Use real Storage in simulator (it persists). For unit tests, consider an in-memory dictionary wrapper. |
| **Timer.Timer** | Sim supports timers. For deterministic tests, inject a mock timer that can be manually advanced. |
| **System.getDeviceSettings()** | Cannot mock in CIQ simulator. Use ConnectivityManager as the abstraction layer and test via its module. |
| **Battery level** | Simulator may expose battery settings. Otherwise, inject battery level as a parameter to the tracker. |

### Priority Summary

| Priority | Count | Categories |
|----------|-------|------------|
| **P0** | 24 | CL-01, CL-02, CL-03, CL-04, CL-05, CL-06, CL-07, CL-10, CL-11, CL-13, PT-01, PT-02, PT-04, PT-06, PT-10, SE-01, SE-02, SE-03, SE-04, SE-05, SE-07, SE-08, SE-09, SE-11, SE-14, SE-15, SE-16, SE-18, SE-25, SE-26, SE-27, CC-04, CC-05, CC-06 |
| **P1** | 20 | CL-08, CL-09, CL-12, CL-17, CL-18, PT-03, PT-05, PT-07, PT-08, SE-06, SE-10, SE-13, SE-17, SE-19, SE-20, SE-21, SE-22, SE-28, SE-29, SE-30, CC-02, CC-07, CC-08, CC-09, CC-10 |
| **P2** | 4 | CL-14, CL-15, CL-16, PT-09, CC-01, CC-03 |

---

## Open Questions for Implementation Review

1. **Changelog MAX_ENTRIES:** Spec says 100, task brief mentioned 50. Current code uses 100. Tests use 100. Confirm with Mal.
2. **Input validation in addEntry():** Should `addEntry` reject empty UUIDs, negative positions, positions > duration? Currently stores as-is. Recommend: validate at sync reconciliation time, not at logging time (simpler, keeps logging fast).
3. **Concurrent changelog modification safety:** `Application.Storage` writes are synchronous in Monkey C, but the position tracker timer and sync engine callbacks can interleave. Need to confirm that `addEntry` + `clearEntries` cannot corrupt the array.
4. **Position tracker implementation details:** Timer class, start/stop API, battery scaling thresholds — all TBD. Tests will need updating once Kaylee's implementation is in place.
5. **Sync engine error codes:** Which `makeWebRequest` response codes map to "network error" vs "server error" vs "auth error"? Need to define the mapping for tests.

---

*This test plan will be revised once Phase A implementation is complete. Zoe will update test IDs, method signatures, and expected values to match the actual code.*
