# Project Context

- **Owner:** Jarod Aerts
- **Project:** YoCasts — a Garmin watch client for the PocketCasts podcast app
- **Stack:** Garmin Connect IQ (Monkey C), with existing C#/.NET API reverse-engineering code as reference
- **Created:** 2026-04-11

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- The repo contains an older Tizen watch app (C#/Xamarin) in `PodcastApp/` — the new app will be built for Garmin Connect IQ using Monkey C.
- Garmin watches have significant constraints: limited memory (64KB-256KB app memory depending on device), small screens (240x240 typical), no direct internet access (must proxy through phone via Communications API).
- The existing Tizen app has pages for: Login, Main/Home, Queue, Subscribed Podcasts — these represent the core user flows to replicate.
- Created full Garmin UX spec at `docs/garmin-ux-spec.md` — covers 7 screens, navigation flow, data caching strategy, memory budgets, and companion app requirements.
- Auth on Garmin uses settings-based flow (credentials entered in Garmin Connect Mobile, stored in Application.Properties) since watches have no keyboard.
- Minimum target device: 240×240 round, 128 KB app memory, CIQ 3.2+. Primary targets are Venu 2/3 and Forerunner 265/965.
- v1 uses `Communications.makeWebRequest()` with a lightweight proxy — no custom companion app needed.
- Memory budget: ~95 KB peak for minimum-spec devices. Queue capped at 20 episodes, podcasts at 30, episodes per podcast at 15.
- No podcast artwork in v1 — text-only lists to stay within memory budget.
- Now Playing is a custom View with progress arc, not a Menu2 — it's the only non-menu screen.
- Proposed file structure uses View+Delegate pairs per screen (e.g., `QueueView.mc` + `QueueDelegate.mc`).
- Key open question: Garmin audio playback (Media module) — need to determine stream vs download strategy. Impacts companion architecture.
- **Cross-team update (2026-04-11):** Wash discovered real queue is `/up_next/list` and playback sync is `/sync/update_episode` — these are the exact endpoints the UX targets. Mal's architecture patterns (Menu2, Dictionary models, LRU cache) are compatible with these API endpoints. All three teams aligned on API surface now.
