# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

## Core Context

Agent Scribe initialized. Team cast from Firefly universe: Mal (Lead), Kaylee (Garmin Dev), Wash (API Dev), Zoe (Tester).

## Recent Updates

📌 Team cast and hired on 2026-04-11

## Learnings

Initial setup complete. Team uses Firefly universe casting. Append-only files use union merge driver in .gitattributes.
- **Cross-team update (2026-04-12):** Kaylee replaced Menu2 home with custom `HomeMenuView` — centered pills, rich subtitles, 124px Now Playing pill, Graphics-drawn icons, button + touch nav. Home screen is now fully custom View, not Menu2.
- **Cross-team update (2026-04-12):** Mal designed offline sync architecture (`docs/offline-sync-design.md`) — furthest-position-wins conflict resolution, 7-step sync protocol, audio download promoted to Phase 3.
