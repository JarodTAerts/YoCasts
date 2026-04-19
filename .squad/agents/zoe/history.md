# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- The existing Tizen app covers: login, subscribed podcasts list, episode list per podcast, queue (unplayed episodes). These are the core flows to test.
- Garmin watches have unique test challenges: limited memory, no direct network access (phone proxy), variable screen sizes, interrupted Bluetooth connections.
- The PocketCasts API uses token auth — test scenarios should cover token expiry, invalid tokens, and re-authentication flows.
- **Cross-team update (2026-04-12):** Kaylee replaced Menu2 home screen with custom `HomeMenuView` — centered rounded pills, rich subtitles, 124px Now Playing with embedded play/pause + progress bar, Graphics-drawn icons, physical button nav. Touch hit-test and button navigation both need testing on physical device.
- **Cross-team update (2026-04-12):** Mal designed offline sync architecture (`docs/offline-sync-design.md`). New test surface: offline scenarios, sync reconciliation edge cases, changelog coalescing, conflict resolution (furthest-position-wins), and interrupted sync recovery.
- **Test plan written (2026-04-14):** Created `docs/test-plan-sync-engine.md` — 48 test scenarios covering Phase A (Changelog + Position Tracker) and Phase B (Sync Engine). Key testability findings:
  - `ChangeLog.mc` uses MAX_ENTRIES=100 (spec says 100, task brief said 50) — tests aligned to actual code.
  - Coalescing only applies to `POSITION_UPDATE`, not to `EPISODE_COMPLETED` or `QUEUE_REMOVE`. This is correct but means duplicate QUEUE_REMOVE entries can accumulate — sync engine must handle idempotently.
  - Eviction has a two-pass algorithm: non-completions first, then completions. This is good for data safety but means the changelog can fill with 100 completions and start evicting them.
  - `clearEntries()` deletes `yc_changelog` but not `yc_cl_seq` — sequence IDs never reuse. This is an important invariant to verify.
  - Concurrent modification risk: position tracker timer callbacks and sync engine callbacks can interleave writes to `Application.Storage`. Storage writes are synchronous in Monkey C, but the logical read-modify-write in `addEntry()` is not atomic. This is a potential race condition to watch for.
  - Most Phase A tests (18 of 18) run fully in the simulator. Phase B tests need mocked API responses. Cross-cutting tests (BT disconnect, Wi-Fi fallback, memory pressure, app kill) require hardware.
  - ConnectivityManager is well-abstracted — it's the right seam for test doubles. The rest of the modules use Application.Storage directly, which is testable in the simulator.

**[2026-04-19 Cross-Agent Sync]**
- **Phase A + B Implementation Complete:** Kaylee shipped all 48 test plan requirements. ChangeLog works with coalescing (position only, not status/queue actions). PositionTracker class with 15s/30s battery-adaptive intervals. SyncEngine 7-step state machine with changelog snapshot race condition fix. Concurrent modification risk flagged in test CC-20 — Kaylee mitigated via snapshot pattern. MAX_ENTRIES=100 confirmed (not 50 from task brief). All modules compile at `-l 3` strict and are hardware-ready.
- **Race Condition Resolved:** Sync cleanup now preserves entries added by PositionTracker during sync by using snapshot IDs. Test CC-20 concept validated in implementation. Safe to proceed with Phase C hardware testing.
- **Hardware Testing Ready:** Mal created 40+ test cases across 6 categories (SyncDelegate, storage, Wi-Fi, BT, memory, battery). 5-day execution plan. Phase C MVP = download + playback one episode.
