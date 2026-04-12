# Orchestration Log — Mal Offline Sync Design

**Date:** 2026-04-12T01:44Z  
**Agent:** Mal (Lead)  
**Mode:** Background  
**Task:** Design offline mode & sync reconciliation algorithm  
**Outcome:** ✅ SUCCESS

## Outcome

Created comprehensive offline mode and sync reconciliation architecture at `docs/offline-sync-design.md`. Covers caching strategy, audio downloads, and full sync reconciliation algorithm.

## Deliverables

- ✓ **Conflict resolution algorithm** — "Furthest position wins" (`max(localPos, serverPos)`), status hierarchy (COMPLETED > IN_PROGRESS > NOT_PLAYED).
- ✓ **Change log architecture** — Structured changelog in `Application.Storage`, per-episode coalescing, cleared only after confirmed server push.
- ✓ **Queue reconciliation** — Server order as base, local completions removed, phone-side additions merged. Server wins for removals.
- ✓ **Authority model** — Server authoritative for metadata/subscriptions; watch participates in playback state via max-based resolution.
- ✓ **7-step sync protocol** — Auth → read changelog → fetch server state → reconcile → push → refresh caches → cleanup. Fully idempotent.
- ✓ **4-phase implementation plan** — (1) Metadata caching, (2) Position tracking + sync, (3) Audio download via Media module, (4) Full reconciliation.

## Key Architecture Shift

Audio download elevated from Phase 5 stretch goal to Phase 3 in the offline architecture — now part of the core plan, not a nice-to-have.

## Impact

- **Kaylee (Garmin Dev):** All existing Views need offline-aware updates (connectivity check, offline indicator, gray-out logic). Must prototype `Media.ContentProvider`/`SyncDelegate` for audio downloads.
- **Wash (API Dev):** Need to verify if `/user/in_progress` returns enough data for bulk reconciliation or if per-episode fetches are required.
- **Zoe (Testing):** Offline scenarios and sync edge cases are new test surface areas.

## Open Questions

- Garmin Media module API specifics — Kaylee needs to prototype ContentProvider/SyncDelegate.
- Exact `Application.Storage` limit on Venu 4 41mm — needs hardware testing.
- Whether `/user/in_progress` supports bulk reconciliation.
