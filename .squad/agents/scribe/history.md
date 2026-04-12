# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

## Core Context

Agent Scribe initialized. Team cast from Firefly universe: Mal (Lead), Kaylee (Garmin Dev), Wash (API Dev), Zoe (Tester).

## Recent Updates

📌 Team cast and hired on 2026-04-11  
📌 Three agents completed background work on 2026-04-12T21:49:00Z — API service hardening, Phase A modules, UI polish

## Learnings

Initial setup complete. Team uses Firefly universe casting. Append-only files use union merge driver in .gitattributes.
- **Cross-team update (2026-04-12):** Kaylee replaced Menu2 home with custom `HomeMenuView` — centered pills, rich subtitles, 124px Now Playing pill, Graphics-drawn icons, button + touch nav. Home screen is now fully custom View, not Menu2.
- **Cross-team update (2026-04-12):** Mal designed offline sync architecture (`docs/offline-sync-design.md`) — furthest-position-wins conflict resolution, 7-step sync protocol, audio download promoted to Phase 3.
- **Cross-team update (2026-04-14):** Three background agents completed deliverables:
  1. **wash-api-login:** Fixed 6 critical issues in PocketCastsPodcastService (null-safety, Wi-Fi detection, graceful fallback, 401 handling, logging). Ready for Phase A integration.
  2. **kaylee-phase-a:** Built ConnectivityManager (3-state model), ChangeLog module (per-episode coalescing), hardened CachedPodcastService. Phase A modules ready.
  3. **kaylee-polish-screens:** Polished Queue/Episodes with status indicators, redesigned Now Playing with progress arc + 3-button controls, added InputDelegate for centralized button handling. All builds pass `-l 3` strict.
  - **All decisions merged:** Three inbox decisions (AudioContentProviderApp revert/re-migrate, dual-build config) merged to decisions.md and inbox cleared.
  - **Team history updated:** All agents' history files appended with cross-team updates from background work.
