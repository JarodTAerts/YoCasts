# Decision: PocketCasts Auth Strategy — Use Two-Token OAuth Flow

**Author:** Wash (API Dev)  
**Date:** 2026-04-12  
**Status:** Proposed  
**Affects:** Mal (Lead), Kaylee (Garmin Dev)

## Context

Our live API testing on 2026-04-11 showed `POST /user/token` returning 400 Bad Request. We assumed token refresh was broken or deprecated. Deep research into 6 community PocketCasts API clients revealed the real issue: **we were using the wrong request format and the wrong login endpoint.**

## Root Cause of the 400 Error

1. We logged in via `/user/login`, which returns `{ "token": "..." }` — a simple access token with **no refresh token**.
2. We sent `POST /user/token` with body `{}` and a `Bearer` auth header.
3. The endpoint actually requires: `{ "grantType": "refresh_token", "refreshToken": "<token>" }` in the JSON body, with NO Authorization header.
4. The refresh token is only available from `/user/login_pocket_casts`, which returns a full OAuth2-style response.

## Key Discovery: Two Login Endpoints, Two Token Systems

| Endpoint | Response Fields | Refresh Capable |
|----------|----------------|-----------------|
| `/user/login` | `token`, `uuid`, `email` | ❌ No refresh token |
| `/user/login_pocket_casts` | `accessToken`, `refreshToken`, `expiresIn`, `tokenType`, `uuid`, `email` | ✅ Full OAuth2 |

## Recommended Auth Strategy for YoCasts

### Primary: Proactive Token Refresh

1. **Login** via `POST /user/login_pocket_casts` with `{ email, password }`.
2. **Store** `accessToken`, `refreshToken`, and `expiresIn` (on Garmin: `Application.Properties` or `Application.Storage`).
3. **Track expiry** — before each API call, check if `accessToken` is near expiry.
4. **Refresh proactively** via `POST /user/token` with `{ "grantType": "refresh_token", "refreshToken": "<saved>" }`.
5. **Save the new tokens** — the refresh response returns NEW `accessToken` AND NEW `refreshToken` (token rotation).
6. **Fallback** — if refresh fails with `invalid_grant`, re-login with stored credentials.

### Why Not "Always Re-login"?

- Re-login requires sending the password each time — worse for security.
- Token refresh is lighter (no password needed).
- The refresh endpoint exists and works — we just weren't using it correctly.
- On Garmin, credentials come from phone settings — they're available, but refresh is cleaner.

### Why Not "Just Use /user/login"?

- `/user/login` returns no refresh token and no expiry info — you're flying blind on token lifetime.
- `/user/login_pocket_casts` gives you everything needed for proper token lifecycle management.

### Garmin-Specific Considerations

- Credentials stored in `Application.Properties` (set via Garmin Connect Mobile).
- Tokens stored in `Application.Storage` with expiry timestamp.
- On app start: check stored tokens → refresh if near expiry → re-login if refresh fails.
- On 401 response: attempt refresh → re-login → show error if both fail.

## Evidence

| Source | Auth Approach | Token Refresh |
|--------|--------------|---------------|
| [yfhyou/api_pocketcasts](https://github.com/yfhyou/api_pocketcasts) (Python, Dec 2025) | `/user/login_pocket_casts` → `accessToken` + `refreshToken` | ✅ `/user/token` with `grantType`/`refreshToken` |
| [rudiedirkx/pocketcasts-api-client](https://github.com/rudiedirkx/pocketcasts-api-client) (PHP, 2024) | `/user/login_pocket_casts` for refresh token | ✅ `/user/token` with `grantType`/`refreshToken` |
| [coughlanio/pocketcasts](https://github.com/coughlanio/pocketcasts) (Node.js) | `/user/login` only | ❌ No refresh |
| [podwriter/pocketcasts](https://github.com/podwriter/pocketcasts) (Rust) | `/user/login` only | ❌ No refresh |
| [furgoose/Pocket-Casts](https://github.com/furgoose/Pocket-Casts) (Python, legacy) | Old web player cookie auth | ❌ Completely different system |
| [juekr/pocketcasts-api-client](https://github.com/juekr/pocketcasts-api-client) (Python) | `/user/login` only | ❌ No refresh |

## Action Items

- [ ] **Wash:** Update C# test tool to use `/user/login_pocket_casts` and test `/user/token` with correct format
- [ ] **Mal:** Update `PocketCastsService.mc` architecture to store both tokens + expiry
- [ ] **Kaylee:** Plan `Application.Storage` keys for token persistence (`pc_access_token`, `pc_refresh_token`, `pc_token_expiry`)
