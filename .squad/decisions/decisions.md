# Decision Log

## PocketCasts Auth Strategy — Use Two-Token OAuth Flow (2026-04-12)

**Author:** Wash (API Dev)  
**Status:** Proposed  
**Affects:** Mal (Lead), Kaylee (Garmin Dev)

### Context

Live API testing showed `POST /user/token` returning 400 Bad Request. Investigation of 6 community PocketCasts API clients revealed the root issue: **wrong request format and wrong login endpoint**.

### Root Cause

1. We logged in via `/user/login`, which returns `{ "token": "..." }` — a simple access token with **no refresh token**
2. We sent `POST /user/token` with empty body `{}` and a `Bearer` auth header
3. The endpoint actually requires: `{ "grantType": "refresh_token", "refreshToken": "<token>" }` in JSON body, with NO Authorization header
4. The refresh token is only available from `/user/login_pocket_casts`, which returns full OAuth2-style response

### Key Discovery: Two Login Endpoints, Two Token Systems

| Endpoint | Response Fields | Refresh Capable |
|----------|----------------|-----------------|
| `/user/login` | `token`, `uuid`, `email` | ❌ No refresh token |
| `/user/login_pocket_casts` | `accessToken`, `refreshToken`, `expiresIn`, `tokenType`, `uuid`, `email` | ✅ Full OAuth2 |

### Recommended Auth Strategy

**Primary: Proactive Token Refresh**

1. Login via `POST /user/login_pocket_casts` with `{ email, password }`
2. Store `accessToken`, `refreshToken`, and `expiresIn`
3. Track expiry — before each API call, check if token is near expiry
4. Refresh proactively via `POST /user/token` with `{ "grantType": "refresh_token", "refreshToken": "<saved>" }`
5. Save new tokens — refresh response returns NEW `accessToken` AND NEW `refreshToken` (token rotation)
6. Fallback — if refresh fails with `invalid_grant`, re-login with stored credentials

### Evidence Base

All 6 community clients that implement token refresh use `/user/login_pocket_casts` + `/user/token` with `grantType`/`refreshToken` format:
- `yfhyou/api_pocketcasts` (Python, Dec 2025)
- `rudiedirkx/pocketcasts-api-client` (PHP, 2024)

Others use `/user/login` only (no refresh capability).

### Garmin-Specific Implementation

- Credentials stored in `Application.Properties` (set via Garmin Connect Mobile)
- Tokens stored in `Application.Storage` with expiry timestamp
- On app start: check stored tokens → refresh if near expiry → re-login if refresh fails
- On 401 response: attempt refresh → re-login → show error if both fail

### Action Items

- [ ] **Wash:** Update C# test tool to validate `/user/login_pocket_casts` and correct `/user/token` format
- [ ] **Mal:** Update `PocketCastsService.mc` to store both tokens + expiry
- [ ] **Kaylee:** Plan `Application.Storage` keys for token persistence

### Documentation

- Updated `docs/pocketcasts-api-reference.md` with corrected auth documentation and examples

---

## Target Venu 4 41mm Only (2026-04-12)

**Author:** Kaylee (Garmin Dev)  
**Status:** Implemented  
**Scope:** Device targeting, UX specification, build configuration

### Context

YoCasts is Jarod's personal project. Previous manifest targeted 16 devices across Venu, Forerunner, Fenix, Vivoactive, and epix lines. For a single user with one watch, this multi-device support is unnecessary overhead.

### Decision

Target exclusively the **Garmin Venu 4 41mm** (`venu441mm`).

### Device Specifications

- 390×390 AMOLED round display (capacitive touch + 2 buttons)
- 768 KB watch app memory
- 54×54 px launcher icon
- Connect IQ SDK 4.2+

### Changes Made

| File | Change |
|---|---|
| `YoCastsGarmin/manifest.xml` | Single `<iq:product>` entry: `venu441mm`. Bumped `minSdkVersion` to 4.2.0. |
| `YoCastsGarmin/monkey.jungle` | Added `base.device = venu441mm` build target. |
| `docs/garmin-ux-spec.md` | Rewrote §1 (Target Device) for single device. Updated input model to touch + 2-button. Updated Now Playing from 240×240 to 390×390. Updated memory budget from 128 KB to 768 KB. |

### Design Implications

- **Touch-first design** — touchscreen is primary input; buttons secondary
- **Memory-generous** — 768 KB available enables richer caching, larger lists, future artwork support
- **Modern SDK** — no backward-compatibility constraint, can use SDK 4.2+ APIs freely
- **Simplified testing** — one simulator device, one physical device to deploy to

### Impact

- **Mal (Architecture):** Can assume 768 KB memory budget for caching and feature design
- **Wash (API):** Device constraints confirmed; API surface targets align with Venu 4 specs
- **Team:** Single-device focus allows optimized UX instead of lowest-common-denominator design

### Verification

All files updated and internally consistent. Ready for development phase.

---

## User Directive: Venu 4 41mm Personal Watch (2026-04-12)

**Requestor:** Jarod Aerts  
**Timestamp:** 2026-04-12T00:56Z

The Garmin app should be built specifically for the Venu 4 41mm. This app is mainly just for Jarod, so it will pretty much only run on that watch. No need to support a wide range of devices.

---

## Garmin App MVP Scaffolding (2026-04-12)

**Author:** Kaylee (Garmin Dev)  
**Status:** Approved (implementation complete)

Created the full `YoCastsGarmin/` Connect IQ project with mock data service. The app has 5 screens, Menu2 navigation, and an `IPodcastService` interface that `MockPodcastService` implements. The mock data uses Dictionary keys matching PocketCasts API field names for easy swap to real service.

### Key Implementation Decisions

1. **Menu2 returned directly from `getInitialView()`** — no wrapper View for the home screen. Cleaner and avoids view stack issues.
2. **NowPlayingView uses delegate-holds-view-reference pattern** — delegate calls `setView()` to get a reference for controlling playback. This is the standard CIQ pattern since delegates can't access the view stack.
3. **Mock data normalizes the Up Next structure** — real API returns `{order: [...], episodes: {...}}` but mock uses a simple array. The real PocketCastsService should normalize this in its `getQueue()` method.
4. **No `static` functions used** — Monkey C supports them but they cause issues in some SDK versions. Instance methods throughout.
5. **`getInitialView()` has no explicit return type annotation** — SDK will reject override if typed.

### Impact

- **Mal (Architecture):** IPodcastService interface ready for service implementation. Dictionary models align with API response structure.
- **Zoe (Testing):** Fixtures available for UI logic testing without live API.
- **Team:** Scaffolding complete and ready for real API integration.
