# Squad Decisions

## Active Decisions

### PocketCasts API Surface Documented

**By:** Wash (API Dev)  
**Date:** 2026-04-11  
**Affects:** All agents

Completed full investigation of the PocketCasts API. Discovered 30+ endpoints beyond the 4 in the old code. Rebuilt the C# test tool (`PocketcastsApiTesting/`) and created `docs/pocketcasts-api-reference.md`.

**Key Findings:**
1. **The real queue is `/up_next/*`**, not `/user/new_releases`. The old code's "queue" was just new episodes.
2. **Playback sync is via `/sync/update_episode`** — critical for reporting position back to PocketCasts.
3. **Origin header changed** from `playbeta.pocketcasts.com` to `play.pocketcasts.com`.
4. **No official API docs exist.** Everything is reverse-engineered. Reference doc should be treated as living documentation.
5. **Credentials no longer hardcoded.** Test tool uses env vars (`POCKETCASTS_EMAIL`, `POCKETCASTS_PASSWORD`) or CLI args.

---

### Garmin App Architecture & Implementation Plan

**Author:** Mal (Lead)  
**Date:** 2026-04-11  
**Status:** Active

Clear blueprint for the Garmin Connect IQ watch app with decision rationale.

**Decisions:**
1. **Menu2 for all list UIs** — Queue, Subscribed Podcasts, Episode List use `WatchUi.Menu2`. Handles round/rectangular screens natively.
2. **No text input on watch** — Credentials entered via Garmin Connect Mobile settings (`Application.Properties`).
3. **Dictionaries, not classes** — Data models are `Dictionary` instances. Matches `makeWebRequest` output, saves memory.
4. **Single PocketCastsService module** — Merged accessor/service pattern. No indirection needed on constrained device.
5. **Cache with LRU eviction** — `Application.Storage` for offline support (~61 KB budget). Episode caches per podcast with `ep_<uuid>` keys.
6. **Five-phase build plan** — Phase 1: skeleton + auth. Phase 2: queue + subscribed. Phase 3: episode browsing. Phase 4: polish + hardware. Phase 5: stretch goals.
7. **Audio download is Phase 5** — Too complex and memory-heavy for MVP.

---

### Garmin UX Spec Established

**Author:** Kaylee (Garmin Dev)  
**Date:** 2026-04-11  
**Affects:** All team members

Complete Garmin Connect IQ UX design with 7 screens and memory budgets.

**Key Architectural Choices:**
1. **Settings-based auth** — no on-watch login form.
2. **Menu2 for all list screens** — Home, Queue, Podcasts, Episodes.
3. **Now Playing as custom View** — only fully custom screen (progress arc, controls).
4. **makeWebRequest + proxy for v1** — watch calls proxy via phone, no custom companion app.
5. **Memory-first design** — 100 KB peak budget, hard caps on list sizes.
6. **No artwork in v1** — text-only lists.

**Open Questions:**
- Audio playback: stream vs download? (Biggest unresolved architecture question)
- Proxy hosting location and auth token management

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
