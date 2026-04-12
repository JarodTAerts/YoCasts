# PocketCasts API Reference

> **Status:** Unofficial / Reverse-Engineered — **Live-tested 2026-04-11** ✅  
> **Last Updated:** 2026-04-14  
> **Maintained by:** YoCasts project (Wash, API Dev)  
> **Sources:** Existing C# code in this repo, [furgoose/Pocket-Casts](https://github.com/furgoose/Pocket-Casts), [yfhyou/api_pocketcasts](https://github.com/yfhyou/api_pocketcasts), [api-pocketcasts on PyPI](https://pypi.org/project/api-pocketcasts/), [rudiedirkx/pocketcasts-api-client](https://github.com/rudiedirkx/pocketcasts-api-client), [coughlanio/pocketcasts](https://github.com/coughlanio/pocketcasts), [podwriter/pocketcasts](https://github.com/podwriter/pocketcasts), community research

⚠️ **This API is not officially documented by PocketCasts.** All endpoints were discovered through reverse engineering the web player, mobile apps, and community efforts. Endpoints may change without notice.

### Live Test Summary (2026-04-11)

| Endpoint | Status |
|----------|--------|
| `POST /user/login` | ✅ Confirmed |
| `POST /user/login_pocket_casts` | ✅ Confirmed |
| `POST /user/token` | ✅ Working (was 400 — wrong request format, now resolved) |
| `GET /subscription/status` | ✅ Confirmed |
| `POST /user/podcast/list` | ✅ Confirmed |
| `POST /user/podcast/episodes` | ✅ Confirmed |
| `POST /user/episode` | ✅ Confirmed |
| `POST /user/new_releases` | ✅ Confirmed |
| `POST /user/in_progress` | ✅ Confirmed |
| `POST /user/starred` | ✅ Confirmed |
| `POST /user/history` | ✅ Confirmed |
| `POST /up_next/list` | ✅ Confirmed |
| `POST /user/bookmark/list` | ✅ Confirmed |
| `POST /user/stats/summary` | ✅ Confirmed |
| `POST /discover/search` | ✅ Confirmed (requires auth) |
| `POST /discover/recommend_episodes` | ✅ Confirmed |
| `GET /recommendations/podcast/{uuid}` | ✅ Confirmed |
| `GET /recommendations/social` | ✅ Confirmed |
| `GET /recommendations/user_podcast` | ❌ Failed (404) |
| `POST /user/named_settings/fetch` | ❌ Failed (404) |
| `GET podcast-api.pocketcasts.com/podcast/full/{uuid}` | ✅ Confirmed |
| `GET lists.pocketcasts.com/featured.json` | ✅ Confirmed |
| `GET lists.pocketcasts.com/trending.json` | ✅ Confirmed |
| `GET static.pocketcasts.com/discover/json/categories_v2.json` | ✅ Confirmed |
| `GET static.pocketcasts.com/discover/web/content_v3.json` | ✅ Confirmed |

---

## Table of Contents

- [Authentication](#authentication)
- [Account & Subscription](#account--subscription)
- [Podcast Management](#podcast-management)
- [Episode Management](#episode-management)
- [Up Next (Queue)](#up-next-queue)
- [Sync & Playback](#sync--playback)
- [Bookmarks](#bookmarks)
- [Discovery & Search](#discovery--search)
- [Statistics](#statistics)
- [Secondary API Hosts](#secondary-api-hosts)
- [Changes from Old API](#changes-from-old-api)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)

---

## Authentication

PocketCasts uses a **two-token OAuth2-style** authentication system. There are two login endpoints with different capabilities, and a separate token refresh endpoint.

> ⚠️ **Critical Discovery (2026-04-12):** `/user/login` and `/user/login_pocket_casts` return **different response schemas**. Only `/user/login_pocket_casts` returns a `refreshToken` needed for token refresh. Our earlier 400 error on `/user/token` was caused by sending an empty body `{}` instead of the required `grantType`/`refreshToken` fields.

### POST `/user/login` — ✅ Confirmed (Legacy/Simple)

Simple login endpoint. Returns **only an access token** — no refresh token, no expiry info. Suitable for short-lived sessions where re-login is acceptable.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/login` |
| **Method** | POST |
| **Content-Type** | `application/json` |
| **Auth Required** | No |

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "yourpassword",
  "scope": "webplayer"
}
```

**Response (200 OK):** Returns token (JWT, ~528 chars), user UUID, and email. **No refresh token.**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs... (528 chars)",
  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "email": "user@example.com"
}
```

### POST `/user/login_pocket_casts` — ✅ Confirmed (Modern/Recommended) ⭐

**Preferred login endpoint.** Returns full OAuth2-style response including access token, refresh token, token type, and expiry. This is the endpoint used by the PocketCasts web player.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/login_pocket_casts` |
| **Method** | POST |
| **Content-Type** | `application/json` |
| **Auth Required** | No |

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "yourpassword"
}
```

> Note: `"scope": "webplayer"` is optional here — some clients include it, some don't.

**Response (200 OK):** Full authentication response with both tokens.
```json
{
  "email": "user@example.com",
  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "isNew": false,
  "accessToken": "eyJhbGciOi... (access token)",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "refreshToken": "eyJhbGciOi... (refresh token)"
}
```

| Response Field | Description |
|---------------|-------------|
| `accessToken` | Bearer token for API requests (short-lived) |
| `refreshToken` | Token for obtaining new access tokens via `/user/token` |
| `expiresIn` | Access token lifetime in seconds |
| `tokenType` | Always `"Bearer"` |
| `isNew` | Whether this is a new account |

> ⚠️ **Key difference:** `/user/login` returns `"token"` field. `/user/login_pocket_casts` returns `"accessToken"` + `"refreshToken"` fields. Different response schemas!

### POST `/user/token` — ✅ Working (Token Refresh)

Token refresh endpoint. Exchanges a refresh token for a new access token. **Does NOT use Bearer auth** — the refresh token is sent in the request body.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/token` |
| **Method** | POST |
| **Content-Type** | `application/json` |
| **Auth Required** | **No** (refresh token is in the body) |

**Request Body:**
```json
{
  "grantType": "refresh_token",
  "refreshToken": "eyJhbGciOi... (refresh token from login)"
}
```

**Response (200 OK):** Returns new tokens (same schema as `/user/login_pocket_casts`).
```json
{
  "email": "user@example.com",
  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "isNew": false,
  "accessToken": "eyJhbGciOi... (NEW access token)",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "refreshToken": "eyJhbGciOi... (NEW refresh token)"
}
```

> ⚠️ **Token rotation:** The response includes a NEW `refreshToken`. Always save the latest refresh token — the old one may be invalidated.

**Why our initial test returned 400:** We sent `{}` as the body with a Bearer auth header. The endpoint requires `grantType` and `refreshToken` fields in the JSON body, with no Authorization header.

**Required headers (from web player sniffing):**
```
Content-Type: application/json
Origin: https://play.pocketcasts.com
Referer: https://play.pocketcasts.com/
```

**Error responses:**
- `400 Bad Request` — Missing or invalid `grantType`/`refreshToken` fields
- `invalid_grant` error — Refresh token expired or revoked; must re-login

### Token Expiry & Lifecycle

| Property | Value |
|----------|-------|
| **Access token lifetime** | Reported via `expiresIn` field (typically seconds) |
| **Refresh token lifetime** | Unknown; likely long-lived but may expire on password change or revocation |
| **Token type** | JWT (JSON Web Token) |
| **Token rotation** | Yes — refresh returns new refresh token; save it |

### Auth Flow Summary

```
┌─────────────────────────────────────────────────────┐
│ 1. POST /user/login_pocket_casts                    │
│    Body: { email, password }                        │
│    → accessToken + refreshToken + expiresIn          │
├─────────────────────────────────────────────────────┤
│ 2. Use accessToken as Bearer token for all API calls │
│    Authorization: Bearer <accessToken>               │
├─────────────────────────────────────────────────────┤
│ 3. When accessToken expires (or 401 received):       │
│    POST /user/token                                  │
│    Body: { grantType: "refresh_token",               │
│            refreshToken: "<saved_refresh_token>" }   │
│    → NEW accessToken + NEW refreshToken              │
├─────────────────────────────────────────────────────┤
│ 4. If refresh fails (invalid_grant):                 │
│    → Re-login with credentials (step 1)             │
└─────────────────────────────────────────────────────┘
```

### Using the Token

All subsequent requests include the access token as a Bearer token:
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

Additional recommended headers:
```
Origin: https://play.pocketcasts.com
Content-Type: application/json
```

---

## Account & Subscription

### GET `/subscription/status` — ✅ Confirmed

Check the user's subscription tier (free vs Plus).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/subscription/status` |
| **Method** | GET |
| **Auth Required** | Yes |

**Response (real data):**
```json
{
  "paid": 1,
  "platform": 4,
  "expiryDate": "2118-08-26T04:23:33Z",
  "autoRenewing": false,
  "giftDays": 36135,
  "frequency": 0,
  "type": 1,
  "tier": "Plus",
  "web": {
    "monthly": 556536,
    "yearly": 830808,
    "trial": 30,
    "plus": { "monthly": 556536, "yearly": 830808, "trialDays": 30 },
    "patron": { "monthly": 829092, "yearly": 829091, "trialDays": 0 }
  },
  "subscriptions": [{
    "platform": 4,
    "type": 1,
    "frequency": 0,
    "autoRenewing": false,
    "expiryDate": "2118-08-26T04:23:33.009Z",
    "plan": "gift_plus",
    "paid": 1,
    "tier": ""
  }],
  "features": {
    "removeBannerAds": true,
    "removeDiscoverAds": true
  },
  "createdAt": "2019-09-09T23:54:30Z"
}
```

> **Note:** `paid: 1` = PocketCasts Plus subscriber. `type: 1` = Plus. The `tier` field may show "Plus" or "Patron". Prices appear to be in microcurrency units.

---

## Podcast Management

### POST `/user/podcast/list` — ✅ Confirmed

Get all podcasts the user is subscribed to.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/podcast/list` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response (real schema — 43 KB for test account):**
```json
{
  "podcasts": [{
    "uuid": "0d90e750-fab5-0134-ec6b-4114446340cb",
    "episodesSortOrder": 3,
    "autoStartFrom": 0,
    "title": "Up First from NPR",
    "author": "NPR",
    "description": "...",
    "url": "https://www.npr.org/podcasts/510318/up-first",
    "lastEpisodePublished": "2026-04-11T14:50:06Z",
    "unplayed": false,
    "lastEpisodeUuid": "71776e2e-8207-4e5d-b6ec-ab5fed38ebf8",
    "lastEpisodePlayingStatus": 3,
    "lastEpisodeArchived": true,
    "autoSkipLast": 0,
    "folderUuid": "973df93c-e4dc-41fb-879e-0c7b532ebb70",
    "sortPosition": 0,
    "dateAdded": "2020-07-13T18:57:57Z",
    "descriptionHtml": "...",
    "isPrivate": false,
    "slug": "up-first-from-npr",
    "settings": {
      "notification": { "value": false, "changed": false },
      "addToUpNext": { "value": false, "changed": false },
      "addToUpNextPosition": { "value": 0, "changed": false },
      "playbackSpeed": { "value": 1.0, "changed": false },
      "trimSilence": { "value": 0, "changed": false },
      "volumeBoost": { "value": false, "changed": false },
      "autoArchivePlayed": { "value": 1, "changed": false },
      "episodeGrouping": { "value": 0, "changed": false },
      "showArchived": { "value": false, "changed": false }
    }
  }]
}
```

> **New fields discovered:** `folderUuid`, `sortPosition`, `dateAdded`, `descriptionHtml`, `isPrivate`, `slug`, `settings` (per-podcast playback preferences), `unplayed`, `lastEpisodePlayingStatus`, `lastEpisodeArchived`.

### POST `/user/podcast/episodes` — ✅ Confirmed

Get episodes for a specific podcast. Returns a large payload (528 KB for a long-running podcast).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/podcast/episodes` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "podcast-uuid-here"
}
```

**Response (real schema — note: lightweight per-episode):**
```json
{
  "episodes": [{
    "uuid": "000f1cfd-daf0-4bf9-8457-5f07433837b4",
    "playingStatus": 3,
    "playedUpTo": 781,
    "isDeleted": true,
    "starred": false,
    "duration": 781,
    "bookmarks": [],
    "deselectedChapters": ""
  }]
}
```

> ⚠️ **Schema change:** This endpoint returns a **minimal** episode schema (no title, url, published date). To get full episode details, use `POST /user/episode` with the episode UUID, or use `podcast-api.pocketcasts.com/podcast/full/{uuid}` for the full metadata.

### POST `/user/episode` — ✅ Confirmed

Get detailed info for a single episode. Returns the full episode schema.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/episode` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid"
}
```

**Response (real schema):**
```json
{
  "uuid": "0e6d7cb8-7749-4b1a-90ea-0230dbe45bf4",
  "url": "https://example.com/episode.mp3",
  "published": "2026-04-09T09:00:00Z",
  "duration": 2134,
  "fileType": "audio/mp3",
  "title": "Episode Title",
  "size": "0",
  "playingStatus": 2,
  "playedUpTo": 1491,
  "starred": false,
  "podcastUuid": "971126e0-11a9-013f-cf8e-0affc86eeaad",
  "podcastTitle": "Podcast Title",
  "episodeType": "full",
  "episodeSeason": 0,
  "episodeNumber": 0,
  "isDeleted": false,
  "author": "Author Name",
  "bookmarks": [],
  "podcastSlug": "podcast-slug",
  "slug": "episode-slug"
}
```

> **New fields discovered:** `episodeType`, `episodeSeason`, `episodeNumber`, `author`, `podcastSlug`, `slug`, `bookmarks` (inline array).

### POST `/user/podcast/subscribe`

Subscribe to a podcast.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/podcast/subscribe` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "podcast-uuid"
}
```

### POST `/user/podcast/unsubscribe`

Unsubscribe from a podcast.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/podcast/unsubscribe` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "podcast-uuid"
}
```

---

## Episode Management

**Playing Status Values (confirmed):**
| Value | Meaning |
|-------|---------|
| 0 | Not played |
| 1 | Queued / not started |
| 2 | In progress |
| 3 | Completed |

### POST `/user/new_releases` — ✅ Confirmed

Get new (unplayed) episodes from subscribed podcasts. This is what the old code called "the queue."

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/new_releases` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response (real schema):**
```json
{
  "total": 5,
  "episodes": [{
    "uuid": "dd343d3e-f743-4ac2-aa62-a7b8999f6b66",
    "url": "https://example.com/episode.mp3",
    "published": "2026-04-11T04:30:00Z",
    "duration": 11011,
    "fileType": "audio/mp3",
    "title": "Episode Title",
    "size": "0",
    "playingStatus": 1,
    "playedUpTo": 0,
    "starred": false,
    "podcastUuid": "...",
    "podcastTitle": "...",
    "episodeType": "full",
    "episodeSeason": 0,
    "episodeNumber": 0,
    "isDeleted": false,
    "author": "...",
    "bookmarks": []
  }]
}
```

> **New field:** `total` — count of episodes. Episodes include full schema with `author`, `episodeType`, `episodeSeason`, `episodeNumber`, `bookmarks`.

### POST `/user/in_progress` — ✅ Confirmed

Get episodes currently being listened to (partially played).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/in_progress` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response:** Same schema as `/user/new_releases` with `total` and full episode objects. Episodes have `playingStatus: 2` and non-zero `playedUpTo`.

### POST `/user/starred` — ✅ Confirmed

Get all starred/favorited episodes.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/starred` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response:** Same schema with `total` and full episode objects.

### POST `/user/history` — ✅ Confirmed

Get the user's listening history. **Can be very large** (93 KB in testing).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/history` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

---

## Up Next (Queue)

The "Up Next" queue is the ordered list of episodes the user plans to listen to. This is distinct from "new releases" — Up Next is explicitly curated by the user.

### POST `/up_next/list` — ✅ Confirmed

Get the current Up Next queue.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/up_next/list` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response (real schema):**
```json
{
  "serverModified": "1775953728729",
  "order": ["0e6d7cb8-7749-4b1a-90ea-0230dbe45bf4"],
  "episodes": {
    "0e6d7cb8-7749-4b1a-90ea-0230dbe45bf4": {
      "title": "Episode Title",
      "url": "https://example.com/episode.mp3",
      "podcast": "971126e0-11a9-013f-cf8e-0affc86eeaad"
    }
  }
}
```

> ⚠️ **Schema change from previous docs:** `episodes` is a **map/dictionary keyed by episode UUID**, not an array. The `order` array defines queue ordering. Each episode object is minimal (title, url, podcast UUID). `serverModified` is a string timestamp (Unix millis).
```

### POST `/up_next/play_next`

Add an episode to play next (top of queue).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/up_next/play_next` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid"
}
```

### POST `/up_next/play_last`

Add an episode to the end of the queue.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/up_next/play_last` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid"
}
```

### POST `/up_next/remove`

Remove an episode from the Up Next queue.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/up_next/remove` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid"
}
```

---

## Sync & Playback

These endpoints update episode state on the server, enabling cross-device sync.

### POST `/sync/update_episode`

Update playback position and status for an episode.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/sync/update_episode` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid",
  "position": 1200,
  "status": 2,
  "duration": 3600
}
```

> **Critical for Garmin:** This is how we sync playback progress from the watch back to PocketCasts.

### POST `/sync/update_episode_star`

Star or unstar an episode.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/sync/update_episode_star` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid",
  "starred": true
}
```

### POST `/sync/update_episodes_archive`

Archive an episode.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/sync/update_episodes_archive` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:**
```json
{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid"
}
```

### POST `/history/do`

Record episode playback in listening history.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/history/do` |
| **Method** | POST |
| **Auth Required** | Yes |

---

## Bookmarks

> **Note:** Bookmarks may require a PocketCasts Plus subscription. ✅ Confirmed working with Plus account.

### POST `/user/bookmark/list` — ✅ Confirmed

Get all bookmarks.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/bookmark/list` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response (real — empty for test account):**
```json
{
  "bookmarks": []
}
```
```

### POST `/user/bookmark/add`

Add a bookmark.

**Request Body:**
```json
{
  "episodeUuid": "uuid",
  "podcastUuid": "uuid",
  "time": 300,
  "title": "My bookmark"
}
```

### POST `/user/bookmark/delete`

Delete a bookmark.

**Request Body:**
```json
{
  "bookmarkUuid": "uuid"
}
```

---

## Discovery & Search

### POST `/discover/search` — ✅ Confirmed (⚠️ Requires Auth)

Search for podcasts by term. **Now requires authentication** (returns 401 without Bearer token).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/discover/search` |
| **Method** | POST |
| **Auth Required** | **Yes** (changed from previous docs) |

**Request Body:**
```json
{
  "term": "technology"
}
```

**Response (real schema — ~11 KB):**
```json
{
  "podcasts": [{
    "uuid": "b7e73db0-aa2e-0138-e691-0acc26574db2",
    "title": "MIT Technology Review Narrated",
    "author": "MIT Technology Review",
    "description": "",
    "url": "",
    "slug": "mit-technology-review-narrated"
  }]
}
```

> **Note:** Search returns `slug` field. `description` and `url` are empty strings in search results — use `/podcast/full/{uuid}` for full metadata.

### POST `/discover/recommend_episodes` — ✅ Confirmed

Get recommended episodes based on listening history.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/discover/recommend_episodes` |
| **Method** | POST |
| **Auth Required** | Yes |

**Response:** Same schema as other episode list endpoints with `total` and full episode objects. Returns episodes from podcasts not in user's subscriptions.

### GET `/recommendations/podcast/{podcast_uuid}` — ✅ Confirmed

Get podcast recommendations based on a specific podcast.

**Response (real schema):**
```json
{
  "title": "Up First from NPR",
  "subtitle": "Similar Shows",
  "description": "recommendations_podcast",
  "datetime": "2026-04-01T07:40:10Z",
  "list_id": "recommendations_podcast",
  "type": "podcast_list",
  "feature_image": "0d90e750-fab5-0134-ec6b-4114446340cb",
  "podcasts": [{
    "uuid": "0e5c21f0-693c-0133-2cb8-6dc413d6d41d",
    "title": "The NPR Politics Podcast",
    "author": "NPR",
    "slug": "the-npr-politics-podcast"
  }],
  "podroll": []
}
```

> **New field:** `podroll` (empty array in testing, may be used for RSS podroll data).

### GET `/recommendations/social` — ✅ Confirmed

Get socially recommended podcasts. Same response format as `/recommendations/podcast/{uuid}` with `list_id: "recommendations_social"` and subtitle "Loved by listeners of".

### GET `/recommendations/user_podcast` — ❌ Failed (404)

This endpoint no longer exists or has moved.

---

## Statistics

### POST `/user/stats/summary` — ✅ Confirmed

Get the user's listening statistics.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/stats/summary` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response (real schema):**
```json
{
  "timeSilenceRemoval": "0",
  "timeSkipping": "356745",
  "timeIntroSkipping": "0",
  "timeVariableSpeed": "539523",
  "timeListened": "14716300",
  "timesStartedAt": "2019-09-09T23:43:53Z"
}
```

> **Note:** All time values are strings (not numbers) representing seconds. `timesStartedAt` is the account creation date. `timeListened` = ~170 days total listening time in this example.

---

## Secondary API Hosts

PocketCasts uses multiple subdomains for different types of data:

### podcast-api.pocketcasts.com — ✅ Confirmed

| Endpoint | Method | Status | Description |
|----------|--------|--------|-------------|
| `/podcast/full/{podcast_uuid}` | GET | ✅ Confirmed (361 KB) | Full podcast metadata with all episodes (no auth needed) |
| `/mobile/show_notes/full/{podcast_uuid}` | GET | ⚠️ Untested | Show notes for mobile clients |

### lists.pocketcasts.com — ✅ Confirmed

| Endpoint | Method | Status | Description |
|----------|--------|--------|-------------|
| `/featured.json` | GET | ✅ Confirmed (32 KB) | Featured podcast list |
| `/trending.json` | GET | ✅ Confirmed (91 KB) | Trending podcast list |
| `/{uuid}.json` | GET | ⚠️ Untested | Specific curated list |

### static.pocketcasts.com — ✅ Confirmed

| Endpoint | Method | Status | Description |
|----------|--------|--------|-------------|
| `/discover/json/categories_v2.json` | GET | ✅ Confirmed (5 KB) | Podcast category list |
| `/discover/web/content_v3.json` | GET | ✅ Confirmed (16 KB) | Web discover content |
| `/discover/images/metadata/{uuid}.json` | GET | ⚠️ Untested | Image metadata |

### shownotes.pocketcasts.com

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/show_notes/{podcast_uuid}/episodes_{timestamp}.json` | POST | Episode show notes |

### podcasts.pocketcasts.com

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/{podcast_uuid}/episodes_full_{timestamp}.json` | GET | Full episode data for a podcast |

---

## Changes from Old API

The old Tizen app code in this repo (`PodcastApp/`) used several patterns that have changed:

| What Changed | Old (Tizen App) | Current |
|-------------|----------------|---------|
| **Origin header** | `https://playbeta.pocketcasts.com` | `https://play.pocketcasts.com` |
| **Base URL path** | `https://api.pocketcasts.com/user/` (trailing slash) | `https://api.pocketcasts.com` (no trailing slash, paths start with `/user/` etc.) |
| **Login endpoint** | `/user/login` | `/user/login` still works; `/user/login_pocket_casts` is an alternative |
| **Episodes path** | `/user/podcast/episodes` | Same — still works |
| **Queue** | Old code used `/user/new_releases` as "the queue" | True queue is now `/up_next/list`; `/user/new_releases` is just new episodes |
| **Hardcoded creds** | Credentials were hardcoded in `PocketCastsApiAccessorcs.cs` | Now uses env vars or CLI args |
| **HTTP client** | Newtonsoft.Json, netcoreapp3.0 | System.Text.Json, .NET 8 |
| **Scope of endpoints** | Only 4 endpoints: login, podcast/list, podcast/episodes, new_releases | 30+ endpoints now documented |

### New Endpoints Not in Old Code

- `/up_next/*` — Queue management (play next, play last, remove)
- `/user/in_progress` — Partially played episodes
- `/user/starred` — Starred episodes
- `/user/history` — Listening history
- `/sync/update_episode` — Playback position sync (critical for watch app)
- `/sync/update_episode_star` — Star sync
- `/user/bookmark/*` — Bookmark management
- `/discover/search` — Podcast search
- `/discover/recommend_episodes` — Recommendations
- `/subscription/status` — Account tier check
- `/user/stats/summary` — Listening statistics
- All secondary host endpoints (podcast-api, lists, static, etc.)

---

## Error Handling

### Common HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad request (malformed JSON or missing fields) |
| 401 | Unauthorized (bad/expired token) |
| 403 | Forbidden (feature requires Plus subscription) |
| 404 | Not found (invalid endpoint or resource UUID) |
| 429 | Too many requests (rate limited) |
| 500 | Server error |

### Token Expiry

Tokens appear to expire after an extended period (days to weeks). When a 401 is received:
1. Try refreshing with `POST /user/token` (body: `{ "grantType": "refresh_token", "refreshToken": "..." }`, NO Bearer header)
2. If that fails (`invalid_grant`), re-authenticate with `POST /user/login_pocket_casts`

### Recommended Error Strategy for Garmin

Since the watch may lose connectivity frequently:
1. Store access and refresh tokens persistently in `Application.Storage`
2. On 401, attempt token refresh via `POST /user/token` with `{grantType, refreshToken}`
3. If refresh fails (`invalid_grant`), re-login via `POST /user/login_pocket_casts` with stored credentials
4. Queue failed sync updates in changelog and retry when connectivity returns
5. Keep payloads minimal — only send what changed

---

## Rate Limiting

No official rate limiting documentation exists. Community observations:

- The API appears to tolerate moderate request rates (several requests per second)
- Aggressive polling (e.g., checking queue every few seconds) may result in 429 responses
- Recommended: Poll no more than once per minute for user data
- For the Garmin watch use case, requests will be infrequent enough that rate limiting shouldn't be an issue
- If 429 is received, implement exponential backoff

---

## Failed / Removed Endpoints (2026-04-11)

These endpoints returned errors during live testing:

| Endpoint | Status | Notes |
|----------|--------|-------|
| `POST /user/named_settings/fetch` | 404 Not Found | Settings endpoint removed or moved |
| `GET /user/settings` | 404 Not Found | Does not exist |
| `GET /user/profile` | 404 Not Found | Does not exist |
| `POST /files/list` | 404 Not Found | User files — may be Plus-only or removed |
| `POST /user/filters` | 404 Not Found | Episode filters — may have moved |
| `GET /recommendations/user_podcast` | 404 Not Found | Personalized recs removed |

> **Note:** `POST /user/token` was previously listed here as "400 Bad Request" — this has been **resolved**. The 400 was caused by sending `{}` with a Bearer header. The correct request format is `{ "grantType": "refresh_token", "refreshToken": "..." }` with no Authorization header. See the [Authentication](#authentication) section for details.

---

## Testing

The comprehensive test tool is at `PocketcastsApiTesting/`:

### Setup

1. Copy the template settings file:
   ```bash
   cd PocketcastsApiTesting/PocketcastsApiTesting
   cp appsettings.local.example.json appsettings.local.json
   ```

2. Edit `appsettings.local.json` with your PocketCasts credentials:
   ```json
   {
     "PocketCasts": {
       "Email": "your@email.com",
       "Password": "your-password"
     }
   }
   ```
   This file is gitignored — your credentials stay local.

3. Run:
   ```bash
   dotnet run
   ```

### Alternative credential methods

```bash
# CLI arguments
dotnet run -- your@email.com yourpassword

# Environment variables
set POCKETCASTS_EMAIL=your@email.com
set POCKETCASTS_PASSWORD=yourpassword
dotnet run
```

### Interactive Menu

The tool presents an interactive menu for testing individual endpoints or running the full suite. All tests are **read-only** — no user data is modified.

### Output

- Console output shows request method, URL, headers (auth token redacted), and response body
- All API responses are saved to `test-results/` as timestamped JSON files with request metadata
- The `test-results/` directory is gitignored

The test tool exercises every documented endpoint and reports pass/fail with full request/response details.
