# PocketCasts API Reference

> **Status:** Unofficial / Reverse-Engineered  
> **Last Updated:** 2025-04-11  
> **Maintained by:** YoCasts project (Wash, API Dev)  
> **Sources:** Existing C# code in this repo, [furgoose/Pocket-Casts](https://github.com/furgoose/Pocket-Casts), [yfhyou/api_pocketcasts](https://github.com/yfhyou/api_pocketcasts), [api-pocketcasts on PyPI](https://pypi.org/project/api-pocketcasts/), community research

⚠️ **This API is not officially documented by PocketCasts.** All endpoints were discovered through reverse engineering the web player, mobile apps, and community efforts. Endpoints may change without notice.

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

All authenticated endpoints require a Bearer token obtained from the login endpoint.

### POST `/user/login`

Primary login endpoint.

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

**Response (200 OK):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "email": "user@example.com"
}
```

**Error Response (401):**
```json
{
  "errorMessage": "Invalid email or password"
}
```

### POST `/user/login_pocket_casts`

Alternative login endpoint (used by some newer clients). Same request/response format as `/user/login`.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/login_pocket_casts` |
| **Method** | POST |
| **Content-Type** | `application/json` |

### POST `/user/token`

Refresh an existing authentication token.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/token` |
| **Method** | POST |
| **Auth Required** | Yes (Bearer) |

**Request Body:** `{}`

**Response:** New token in same format as login response.

### Using the Token

All subsequent requests include the token as a Bearer token:
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

### GET `/subscription/status`

Check the user's subscription tier (free vs Plus).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/subscription/status` |
| **Method** | GET |
| **Auth Required** | Yes |

**Response:**
```json
{
  "paid": 0,
  "platform": 2,
  "expiryDate": "",
  "autoRenewing": false,
  "type": 0,
  "frequency": 0
}
```

> **Note:** `paid: 1` = PocketCasts Plus subscriber. Some features (bookmarks, etc.) may require Plus.

---

## Podcast Management

### POST `/user/podcast/list`

Get all podcasts the user is subscribed to.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/podcast/list` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response:**
```json
{
  "podcasts": [
    {
      "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "title": "Podcast Title",
      "author": "Author Name",
      "description": "...",
      "url": "https://feed.url/rss",
      "lastEpisodePublished": "2025-04-10T12:00:00Z",
      "lastEpisodeUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
    }
  ]
}
```

### POST `/user/podcast/episodes`

Get episodes for a specific podcast.

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

**Response:**
```json
{
  "episodes": [
    {
      "uuid": "episode-uuid",
      "title": "Episode Title",
      "url": "https://cdn.example.com/episode.mp3",
      "published": "2025-04-10T12:00:00Z",
      "duration": 3600,
      "fileType": "audio/mpeg",
      "size": "45000000",
      "playedUpTo": 1200,
      "starred": false,
      "podcastUuid": "podcast-uuid",
      "podcastTitle": "Podcast Title",
      "playingStatus": 2,
      "isDeleted": false
    }
  ]
}
```

**Playing Status Values:**
| Value | Meaning |
|-------|---------|
| 0 | Not played |
| 2 | In progress |
| 3 | Completed |

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

### POST `/user/episode`

Get detailed info for a single episode.

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

### POST `/user/new_releases`

Get new (unplayed) episodes from subscribed podcasts. This is what the old code called "the queue."

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/new_releases` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response:** Same episode list format as `/user/podcast/episodes`.

### POST `/user/in_progress`

Get episodes currently being listened to (partially played).

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/in_progress` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

### POST `/user/starred`

Get all starred/favorited episodes.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/starred` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

### POST `/user/history`

Get the user's listening history.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/history` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

---

## Up Next (Queue)

The "Up Next" queue is the ordered list of episodes the user plans to listen to. This is distinct from "new releases" — Up Next is explicitly curated by the user.

### POST `/up_next/list`

Get the current Up Next queue.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/up_next/list` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response:**
```json
{
  "episodes": [...],
  "serverModified": 1712764800000
}
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

> **Note:** Bookmarks may require a PocketCasts Plus subscription.

### POST `/user/bookmark/list`

Get all bookmarks.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/bookmark/list` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

**Response:**
```json
{
  "bookmarks": [
    {
      "bookmarkUuid": "uuid",
      "podcastUuid": "uuid",
      "episodeUuid": "uuid",
      "time": 300,
      "title": "Interesting point",
      "createdAt": "2025-04-10T12:00:00Z"
    }
  ]
}
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

### POST `/discover/search`

Search for podcasts by term.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/discover/search` |
| **Method** | POST |
| **Auth Required** | No (but may return richer results when authenticated) |

**Request Body:**
```json
{
  "term": "technology"
}
```

### POST `/discover/recommend_episodes`

Get recommended episodes based on listening history.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/discover/recommend_episodes` |
| **Method** | POST |
| **Auth Required** | Yes |

### GET `/recommendations/podcast/{podcast_uuid}`

Get podcast recommendations based on a specific podcast.

### GET `/recommendations/social`

Get socially recommended podcasts.

### GET `/recommendations/user_podcast`

Get personalized podcast recommendations.

---

## Statistics

### POST `/user/stats/summary`

Get the user's listening statistics.

| Field | Value |
|-------|-------|
| **URL** | `https://api.pocketcasts.com/user/stats/summary` |
| **Method** | POST |
| **Auth Required** | Yes |

**Request Body:** `{}`

### POST `/user/stats/add`

Add stats data (usually called by the client to report listening time).

---

## Secondary API Hosts

PocketCasts uses multiple subdomains for different types of data:

### podcast-api.pocketcasts.com

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/podcast/full/{podcast_uuid}` | GET | Full podcast metadata (no auth needed) |
| `/mobile/show_notes/full/{podcast_uuid}` | GET | Show notes for mobile clients |

### lists.pocketcasts.com

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/featured.json` | GET | Featured podcast list |
| `/trending.json` | GET | Trending podcast list |
| `/{uuid}.json` | GET | Specific curated list |

### static.pocketcasts.com

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/discover/json/categories_v2.json` | GET | Podcast category list |
| `/discover/web/content_v3.json` | GET | Web discover content |
| `/discover/images/metadata/{uuid}.json` | GET | Image metadata |

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
1. Try refreshing with `POST /user/token`
2. If that fails, re-authenticate with `POST /user/login`

### Recommended Error Strategy for Garmin

Since the watch loses connectivity frequently:
1. Cache the auth token persistently on the phone companion
2. On 401, attempt one token refresh before re-login
3. Queue failed sync updates and retry when connectivity returns
4. Keep payloads minimal — only send what changed

---

## Rate Limiting

No official rate limiting documentation exists. Community observations:

- The API appears to tolerate moderate request rates (several requests per second)
- Aggressive polling (e.g., checking queue every few seconds) may result in 429 responses
- Recommended: Poll no more than once per minute for user data
- For the Garmin watch use case, requests will be infrequent enough that rate limiting shouldn't be an issue
- If 429 is received, implement exponential backoff

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
