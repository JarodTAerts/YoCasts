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
- **Cross-team update (2026-04-12):** Wash completed live API validation (25 endpoints, 20 working). **Critical impacts to UI/UX:**
  1. **Up Next queue is a dictionary, not a list** — `/up_next/list` returns `{ order: [...], episodes: {uuid: {...}} }`. Queue screen must loop over `order` array and lookup titles/metadata from `episodes` dictionary. Update QueueDelegate to bind this structure correctly.
  2. **Episode titles missing from podcast list** — `/user/podcast/episodes` returns ONLY status (playingStatus, playedUpTo, starred, duration). NO titles. If Episodes screen needs titles (it does for UX), must fetch them separately via `POST /user/episode` per episode or bulk `podcast-api.pocketcasts.com`. This breaks the current assumption that `/user/podcast/episodes` is the source of truth for episode metadata. Episode list UX will need a loading state or multi-call strategy.
  3. **Token refresh broken** — `POST /user/token` returns 400. Credentials must be stored on companion and re-login used if session expires. Update auth flow assumptions.
  4. **Search requires Bearer token** — `POST /discover/search` returns 401 without token. If discover feature uses search, ensure token is passed.
  5. **Stats values are strings** — `/user/stats/summary` returns string time values, not numbers. Any stats display must parse these.
- **Build milestone (2026-04-12):** Created the full YoCastsGarmin/ Connect IQ project with mock data service. 17 files, ~900 lines of Monkey C. Five screens implemented (Home Menu2, Queue, Podcasts, Episode List, Now Playing). IPodcastService base class provides the interface — MockPodcastService implements it with 5 realistic podcasts, 18 episodes, and a 5-item queue. Data structures use Dictionary keys matching PocketCasts API fields so the real service can be a drop-in replacement. Now Playing has a progress arc, play/pause, skip ±30s controls. Settings-based auth flow ready (credentials via Garmin Connect Mobile). Need to verify compilation with actual Connect IQ SDK toolchain next.
- **Learned:** Monkey C `getInitialView()` must NOT have explicit return type annotation — SDK will reject override if typed. Menu2 can be returned directly from getInitialView, no wrapper View needed.
- **Note for future:** Up Next queue API returns dict structure (order + episodes map), not simple array. MockPodcastService currently uses simple array — will need to adjust when wiring real API, or normalize in the service layer.
- **Token auth breakthrough (2026-04-12):** Wash investigated `/user/token` 400 error root cause and discovered the two-endpoint token system. `/user/login` returns only access token (no refresh). `/user/login_pocket_casts` returns accessToken + refreshToken + expiresIn. Token refresh via `/user/token` requires `{ "grantType": "refresh_token", "refreshToken": "..." }` body — not Bearer header. This is critical for Garmin auth: login via `/user/login_pocket_casts`, store both tokens + expiry in `Application.Storage`, refresh proactively before expiry, fallback to re-login on 401. Decision proposed in decisions.md.
- **First successful build & simulator run (2026-04-12):** Built YoCastsGarmin with Connect IQ SDK 9.1.0 and deployed to Venu 4 41mm simulator. Required three fixes: (1) Removed invalid `base.device` line from monkey.jungle — device is set via `-d` flag, not jungle config. (2) Changed manifest app ID to 32-char hex UUID — CIQ requires minimum 32-char IDs. (3) Replaced `using Toybox.Lang;` with `import Toybox.Lang;` in all source files — `using` creates an alias but doesn't import types into scope, so `String`, `Number`, `Boolean`, `Array`, `Dictionary` were unresolved. `import` makes them directly available. Keep `using` for aliased imports like `using Toybox.Application as App;`. Also regenerated launcher_icon.png (was a 69-byte placeholder, not a valid PNG). Added try-catch around `App.Properties.getValue()` in `hasCredentials()` to prevent runtime crash when properties aren't populated.
- **Learned:** In Monkey C SDK 9.1.0: `import Toybox.Lang;` imports types directly (String, Number, etc.); `using` only creates aliases and doesn't import type names. Use `import` for Toybox.Lang, `using X as Y` for aliased modules. `import` does NOT support `as` aliasing.
- **Learned:** Connect IQ manifest requires app IDs of at least 32 characters. Use a hex UUID like `a3421feed75247efa2a683e6e5152865`.
- **Learned:** The `base.device` property is NOT valid in monkey.jungle files — specify target device via `-d` flag on monkeyc command line only.
- **Build environment:** SDK bin at `C:\Users\jaert\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b\bin`. Must set JAVA_HOME and add both SDK bin and Java bin to PATH. Use `.bat` extensions on Windows (monkeyc.bat, monkeydo.bat, simulator.exe). Developer key at `YoCastsGarmin/developer_key`.
- **Device deployment success (2026-04-12T01:22):** App built and deployed to Venu 4 41mm physical device. Simulator test passed. All 5 compilation issues from previous session resolved: (1) Invalid `base.device` removed from monkey.jungle. (2) UUID format fixed in manifest.xml. (3) Converted remaining `using` directives to `import` for Toybox.Lang. (4) Regenerated launcher_icon.png (was corrupted/placeholder). (5) Added try-catch guards around `Application.Properties` reads. App now runs cleanly on physical device. Ready for API integration phase. Orchestration log written to `.squad/orchestration-log/2026-04-12T01-22-kaylee-build.md`.
