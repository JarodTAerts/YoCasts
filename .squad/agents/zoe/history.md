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
