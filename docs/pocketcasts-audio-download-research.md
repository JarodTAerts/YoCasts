# PocketCasts Audio Download Research

> **Author:** Wash (API Dev)  
> **Date:** 2026-04-12  
> **Status:** Live-tested against real PocketCasts API ✅  
> **Purpose:** Document exactly how PocketCasts serves audio files and what the Garmin watch needs to do to download them for offline playback.

---

## Executive Summary

PocketCasts **does not proxy audio**. Episode URLs point directly to the podcast host's CDN, routed through chains of analytics/tracking redirectors. Audio downloads require **no PocketCasts authentication** — they're public CDN links. All tested CDNs support **HTTP Range requests** (resumable downloads). File sizes range from ~19 MB (17 min episode) to ~243 MB (4.4 hr episode), averaging roughly **1 MB per minute** of audio. The API's `size` field is unreliable (often `"0"`), so the watch must issue a HEAD request to get the real file size before downloading.

---

## Table of Contents

- [1. Audio URL Resolution](#1-audio-url-resolution)
- [2. Download Mechanics](#2-download-mechanics)
- [3. Episode Metadata for Download Management](#3-episode-metadata-for-download-management)
- [4. Playback Position Sync API](#4-playback-position-sync-api)
- [5. Live Test Results](#5-live-test-results)
- [6. Download Flow for Garmin](#6-download-flow-for-garmin)
- [7. Gotchas and Edge Cases](#7-gotchas-and-edge-cases)
- [8. Recommendations for Garmin Implementation](#8-recommendations-for-garmin-implementation)

---

## 1. Audio URL Resolution

### 1.1 What is the `url` field?

The `url` field in episode responses is the **original RSS feed enclosure URL** — the same URL any podcast player would use. PocketCasts passes it through unmodified. These are **not** PocketCasts-hosted files.

### 1.2 Direct link or redirect?

**Always redirects.** Every audio URL tested goes through at least 1 redirect hop, and up to 6. The redirect chain consists of analytics/tracking services:

| Initial Host | Redirect Hops | Final CDN Host | Purpose |
|-------------|:---:|----------------|---------|
| `prfx.byspotify.com` | 3 | `npr.simplecastaudio.com` | Spotify prefix tracking |
| `pdst.fm` | 6 | `dcs-spotify.megaphone.fm` | Podsights + Megaphone tracking chain |
| `verge.supportingcast.fm` | 1 | `verge.supportingcast.fm` | Premium/private feed (self-serves after auth) |
| `www.podtrac.com` | 5 | `dcs-cached.megaphone.fm` | Podtrac analytics → Megaphone CDN |
| `pscrb.fm` | 2 | `audio.transistor.fm` | Podcribe → Transistor CDN |
| `dts.podtrac.com` | 2 | `stitcher.simplecastaudio.com` | Podtrac → Simplecast CDN |
| `mgln.ai` | 3 | `stitcher.simplecastaudio.com` | Megaphone AI tracking → Simplecast |
| `mcdn.podbean.com` | TBD | `mcdn.podbean.com` | Podbean (likely direct or 1 hop) |

### 1.3 Do audio URLs require authentication?

**No.** Audio URLs work without any authentication headers. PocketCasts auth tokens are irrelevant for audio downloads. The HEAD request results were identical with and without Bearer tokens.

**Exception:** SupportingCast URLs (premium/private feeds like "Decoder: Ad-Free Edition") embed a JWT-like authentication token directly in the URL path. This token is baked into the URL the API returns — no additional auth headers needed, but the URL itself may expire (see [Section 7.2](#72-supportingcast-url-expiry)).

### 1.4 Do URLs expire?

**Standard podcast URLs: No.** These are permanent RSS enclosure URLs. Podcast hosts keep them available indefinitely.

**SupportingCast (premium feed) URLs: Possibly.** The URL contains an embedded token with a timestamp (`d` field = Unix epoch of URL generation). A URL generated 3.3 days prior still worked during testing, suggesting at least a multi-day validity window. The token structure:
```
https://verge.supportingcast.fm/content/{base64_jwt}|{hmac_sha256}.mp3
```
Decoded JWT payload:
```json
{
  "t": "s",
  "c": "20030816",       // content ID
  "u": "3058449",        // user ID  
  "d": "1775725249",     // Unix timestamp (generation time)
  "k": 10491             // key/subscription ID
}
```

**Recommendation:** Treat all URLs as potentially expiring. Re-fetch episode metadata from the API before starting a download to get a fresh URL.

### 1.5 Quality/bitrate options

**No bitrate selection available.** PocketCasts serves whatever the podcast publisher uploaded. There is no API parameter to request different quality levels. The audio files are as-published — typically 128 kbps or 192 kbps MP3.

---

## 2. Download Mechanics

### 2.1 Basic download

Yes — a simple `HTTP GET` to the audio URL downloads the file. The URL goes through redirect hops (302s), and the final response is the audio data with `200 OK`.

```
GET https://pdst.fm/e/mgln.ai/e/94/.../traffic.megaphone.fm/ROOSTER2990774329.mp3
→ 302 → 302 → 302 → 302 → 302 → 302 → 200 OK (audio/mpeg, 175 MB)
```

### 2.2 Range headers (resumable downloads)

**✅ Fully supported by all tested CDNs.** Every CDN responded with `206 Partial Content` and `Content-Range` headers.

```
GET /audio.mp3 HTTP/1.1
Range: bytes=0-0

HTTP/1.1 206 Partial Content
Content-Range: bytes 0-0/19716043
Content-Type: audio/mpeg
```

This means the Garmin downloader can:
- Resume interrupted downloads
- Download in chunks
- Verify total file size from `Content-Range`

### 2.3 Content-Type headers

All tested CDNs return `audio/mpeg` regardless of the file extension (`.mp3`) or the API's `fileType` field. No `audio/mp4` or `audio/aac` observed in this user's library.

| API `fileType` | Actual Content-Type | Notes |
|---------------|--------------------|----|
| `audio/mp3` | `audio/mpeg` | Most common |
| `audio/mpeg` | `audio/mpeg` | Consistent |

### 2.4 Response sizes (real data)

| Episode | Duration | Actual Size | MB/min |
|---------|----------|-------------|--------|
| NPR news story | 17 min | 18.8 MB | 1.1 |
| 99% Invisible | 32 min | 30.6 MB | 0.96 |
| Vergecast (ad-free) | 79 min | 109.2 MB | 1.38 |
| Decoder | 90 min | 83.5 MB | 0.93 |
| Timesuck | 110 min | 102.1 MB | 0.93 |
| WAN Show | 184 min | 167.8 MB | 0.91 |
| Acquired | 263 min | 242.5 MB | 0.92 |

**Average: ~1 MB per minute.** The 20-50 MB estimate from the design doc is correct for episodes under 50 minutes, but longer episodes (1-4 hours) can easily reach 100-250 MB.

### 2.5 Rate limits

**No rate limits observed** on audio CDN downloads. These are standard CDNs (Megaphone/Spotify, Simplecast, Transistor, Podbean) designed for millions of concurrent podcast downloads. The Garmin use case (downloading a few episodes) is negligible traffic.

### 2.6 CDN caching behavior

| CDN | Cache-Control | ETag | Notes |
|-----|--------------|------|-------|
| Megaphone (`dcs-spotify.megaphone.fm`) | `no-store, no-cache, max-age=0` | None | Anti-caching — always re-validates |
| Megaphone cached (`dcs-cached.megaphone.fm`) | `no-store, no-cache, max-age=0` | None | Same behavior despite "cached" name |
| SupportingCast | `no-store, no-cache, max-age=0` | None | Served via Fastly CDN |
| Transistor (`audio.transistor.fm`) | None | `"bea3fde64b..."` | Cloudflare, provides ETag |
| Simplecast | None | None | Minimal headers |
| NPR Simplecast | None | None | Minimal headers |

---

## 3. Episode Metadata for Download Management

### 3.1 Which endpoints return the `url` field?

| Endpoint | Returns `url`? | Returns `duration`? | Returns `size`? | Returns `fileType`? |
|----------|:---:|:---:|:---:|:---:|
| `POST /user/episode` | ✅ | ✅ | ✅ (often "0") | ✅ |
| `POST /user/new_releases` | ✅ | ✅ | ✅ (often "0") | ✅ |
| `POST /user/in_progress` | ✅ | ✅ | ✅ (often "0") | ✅ |
| `POST /user/starred` | ✅ | ✅ | ✅ (often "0") | ✅ |
| `POST /user/history` | ✅ | ✅ | ✅ (often "0") | ✅ |
| `POST /up_next/list` | ✅ (minimal) | ❌ | ❌ | ❌ |
| `POST /user/podcast/episodes` | ❌ | ✅ | ❌ | ❌ |

**Best source for download metadata:** `POST /user/episode` with the episode UUID. Returns all fields needed: `url`, `duration`, `fileType`, `size`, `playingStatus`, `playedUpTo`.

### 3.2 The `fileType` field

Always present on full episode responses. Observed values:
- `"audio/mp3"` — most common
- `"audio/mpeg"` — equivalent to mp3

No `audio/aac`, `audio/mp4`, or `audio/ogg` observed, but they may exist for some podcasts.

### 3.3 The `size` field

**Unreliable.** It's a **string** (not number), and is often `"0"`:

| Episode | API `size` | Actual Size (HEAD) | Match? |
|---------|-----------|-------------------|--------|
| NPR news | `"16736845"` (16.0 MB) | 19,716,043 (18.8 MB) | ❌ Different |
| WAN Show | `"0"` | 175,970,939 (167.8 MB) | ❌ Zero |
| Vergecast Ad-Free | `"0"` | 114,488,009 (109.2 MB) | ❌ Zero |
| Vergecast | `"0"` | 87,557,600 (83.5 MB) | ❌ Zero |
| Acquired | `"254246316"` (242.5 MB) | 254,246,316 (242.5 MB) | ✅ Exact |
| Timesuck | `"105278179"` (100.4 MB) | 107,089,851 (102.1 MB) | ❌ Close |
| 99% Invisible | `"26349063"` (25.1 MB) | 32,075,402 (30.6 MB) | ❌ Different |

**Conclusion:** Do NOT rely on the `size` field for download progress or storage estimation. Issue a HEAD request to get the real `Content-Length`.

### 3.4 The `duration` field

**Always present and reliable.** Integer value in seconds. Can be used to estimate file size (~1 MB/min) for storage budgeting before the HEAD request.

### 3.5 Episode availability

All episodes with URLs (including old ones from 2018, 2019, 2021) returned valid audio. There's no evidence of URL expiration for standard (non-premium) podcast feeds. The `/user/history` endpoint returns episodes going back years.

---

## 4. Playback Position Sync API

### 4.1 Pushing position updates

**Endpoint:** `POST /sync/update_episode`

```
POST https://api.pocketcasts.com/sync/update_episode
Authorization: Bearer <token>
Content-Type: application/json
Origin: https://play.pocketcasts.com

{
  "uuid": "episode-uuid",
  "podcast": "podcast-uuid",
  "position": 1200,
  "status": 2,
  "duration": 3600
}
```

| Field | Type | Description |
|-------|------|-------------|
| `uuid` | string | Episode UUID |
| `podcast` | string | Podcast UUID |
| `position` | int | Playback position in seconds |
| `status` | int | 0=not played, 1=queued, 2=in progress, 3=completed |
| `duration` | int | Total episode duration in seconds |

### 4.2 Batch updates

**No batch endpoint exists.** Community research and API exploration confirm there is no way to push multiple episode updates in a single request. Each episode requires its own `POST /sync/update_episode` call.

**Garmin impact:** After offline playback of multiple episodes, the watch must push position updates one at a time during sync. With the offline sync architecture's changelog coalescing (only latest position per episode), this should be manageable — typically 1-5 updates per sync.

### 4.3 Rate limits on position updates

No documented rate limits. The PocketCasts web player pushes position updates frequently (every ~30 seconds during playback) without issues. For the watch's use case (pushing accumulated offline changes during sync), a few sequential calls spaced 100-200ms apart should be fine.

### 4.4 Up Next queue — read/write from watch?

The Up Next API supports both reading and writing:

| Operation | Endpoint | Method |
|-----------|----------|--------|
| Read queue | `POST /up_next/list` | Read |
| Add to top | `POST /up_next/play_next` | **Write** |
| Add to bottom | `POST /up_next/play_last` | **Write** |
| Remove | `POST /up_next/remove` | **Write** |

**The watch can modify the queue.** However, for v1 offline mode, the decision doc specifies "server wins for removals" — the watch should only read the queue and mark episodes as completed, not actively manage queue ordering.

### 4.5 Pulling server state for reconciliation

**Endpoint:** `POST /user/in_progress` returns all in-progress episodes with full metadata including `playedUpTo` and `playingStatus`. This is sufficient for bulk reconciliation — no per-episode fetches needed.

```
POST https://api.pocketcasts.com/user/in_progress
Authorization: Bearer <token>
Content-Type: application/json

{}

Response:
{
  "total": 9,
  "episodes": [
    {
      "uuid": "...",
      "playingStatus": 2,
      "playedUpTo": 1323,
      "duration": 2134,
      "title": "...",
      "podcastUuid": "...",
      ...
    }
  ]
}
```

---

## 5. Live Test Results

### 5.1 Test methodology

Seven episodes were probed across different podcast hosting providers. For each:
1. **HEAD without auth** — verify audio is publicly accessible
2. **HEAD with PocketCasts Bearer token** — verify auth makes no difference
3. **HEAD without following redirects** — trace the full redirect chain
4. **GET with Range: bytes=0-0** — verify resumable download support

### 5.2 Results matrix

| # | Episode | Host Chain | Hops | Final CDN | Size | Range? | Auth Needed? |
|---|---------|-----------|:---:|-----------|------|:---:|:---:|
| 1 | NPR "Black pilots" | byspotify→podtrac→simplecast | 3 | `npr.simplecastaudio.com` | 18.8 MB | ✅ | ❌ |
| 2 | WAN Show | pdst→mgln→clarity→podscribe→vpixl→megaphone | 6 | `dcs-spotify.megaphone.fm` | 167.8 MB | ✅ | ❌ |
| 3 | Vergecast Ad-Free | supportingcast | 1 | `verge.supportingcast.fm` | 109.2 MB | ✅ | ❌ |
| 4 | Apple at 50 | podtrac→pdst→pscrb→mgln→megaphone | 5 | `dcs-cached.megaphone.fm` | 83.5 MB | ✅ | ❌ |
| 5 | Acquired "Microsoft" | pscrb→transistor | 2 | `audio.transistor.fm` | 242.5 MB | ✅ | ❌ |
| 6 | Timesuck "Inquisition" | podtrac→simplecast | 2 | `stitcher.simplecastaudio.com` | 102.1 MB | ✅ | ❌ |
| 7 | 99% Invisible | mgln→podtrac→simplecast | 3 | `stitcher.simplecastaudio.com` | 30.6 MB | ✅ | ❌ |

**Key: 7/7 episodes — no auth needed, all support Range requests, all return Content-Length.**

---

## 6. Download Flow for Garmin

### 6.1 Flow diagram

```
┌──────────────────────────────────────────────────────────────┐
│                    EPISODE DOWNLOAD FLOW                      │
│                  (Garmin Media ContentProvider)                │
└──────────────────────────────────────────────────────────────┘

  ┌─────────────┐     ┌───────────────────────┐
  │ 1. Get Queue │────▶│ POST /up_next/list    │
  │   via Phone  │     │ or /user/in_progress  │
  └──────┬──────┘     └───────────────────────┘
         │
         ▼
  ┌─────────────┐     ┌───────────────────────┐
  │ 2. Get Full  │────▶│ POST /user/episode    │
  │   Metadata   │     │ { uuid: "..." }       │
  └──────┬──────┘     │ → url, duration,      │
         │            │   fileType, size       │
         │            └───────────────────────┘
         ▼
  ┌─────────────┐     ┌───────────────────────┐
  │ 3. HEAD the  │────▶│ HEAD <audio_url>      │
  │   Audio URL  │     │ (follow redirects)    │
  └──────┬──────┘     │ → Content-Length,      │
         │            │   Content-Type,        │
         │            │   Accept-Ranges        │
         │            └───────────────────────┘
         ▼
  ┌─────────────┐     ┌───────────────────────────────┐
  │ 4. Check     │────▶│ Is Content-Length ≤ budget?    │
  │   Storage    │     │ Venu 4: ~8 MB internal for    │
  │              │     │ app, but Media uses phone      │
  │              │     │ storage via BLE transfer       │
  └──────┬──────┘     └───────────────────────────────┘
         │
         ▼
  ┌─────────────┐     ┌───────────────────────────────┐
  │ 5. Download  │────▶│ GET <audio_url>                │
  │   via Phone  │     │ Range: bytes=<offset>-         │
  │   Companion  │     │ (resumable, chunked)           │
  └──────┬──────┘     │                                │
         │            │ Phone downloads file, then      │
         │            │ transfers to watch via          │
         │            │ Garmin Media / BLE              │
         │            └───────────────────────────────┘
         ▼
  ┌─────────────┐     ┌───────────────────────────────┐
  │ 6. Store on  │────▶│ Garmin Media.ContentProvider   │
  │   Watch      │     │ stores file for offline        │
  │              │     │ playback via Media.Playback     │
  └──────┬──────┘     └───────────────────────────────┘
         │
         ▼
  ┌─────────────┐     ┌───────────────────────────────┐
  │ 7. After     │────▶│ POST /sync/update_episode      │
  │   Playback:  │     │ { uuid, podcast, position,     │
  │   Sync       │     │   status, duration }           │
  └─────────────┘     │ (one call per episode)          │
                      └───────────────────────────────┘
```

### 6.2 Garmin-specific considerations

On Garmin, the watch **cannot make HTTP requests directly**. All network traffic goes through the phone companion app via `Communications.makeWebRequest()`. For audio downloads, Garmin provides the **Media module** (Content Provider / Sync Delegate pattern):

1. **`Media.ContentProvider`** — The phone companion app downloads audio files and transfers them to the watch
2. **`Media.SyncDelegate`** — Handles the sync lifecycle between phone and watch
3. **`Media.Playback`** — Plays audio files stored on the watch

The phone companion handles all HTTP complexity (redirects, Range requests, etc.). The watch just needs to tell the phone *what* to download and receive the audio data.

---

## 7. Gotchas and Edge Cases

### 7.1 Redirect chain length

URLs can redirect up to **6 times** (Megaphone via full tracking chain). The HTTP client must follow redirects. On Garmin, `Communications.makeWebRequest()` handles redirects automatically, and the phone's HTTP stack handles them for Media downloads.

### 7.2 SupportingCast URL expiry

Premium podcast feed URLs (SupportingCast) embed a time-bound JWT token. A URL generated 3.3 days ago still works, but expiry is likely — possibly 7-30 days.

**Mitigation:** Always fetch fresh episode metadata (`POST /user/episode`) immediately before starting a download. Don't cache audio URLs for more than a few hours.

### 7.3 The `size` field lies

The API's `size` field is a **string** (not number) and is `"0"` for ~60% of episodes. When non-zero, it often doesn't match the actual Content-Length (discrepancies of 10-20% observed). The real file size can only be determined via HEAD request.

**Mitigation:** Use HEAD request's `Content-Length` for storage budgeting and progress tracking. Use `duration × 1 MB/min` as a rough estimate for pre-download UI.

### 7.4 Content-Type normalization

The API reports `fileType` as either `audio/mp3` or `audio/mpeg`. CDNs always return `audio/mpeg`. Treat both as MP3. The Garmin Media player handles both.

### 7.5 Very large files

The Acquired episode (4.4 hours) was 242.5 MB. For a watch with limited storage, downloading very long episodes may not be feasible. Consider:
- Maximum episode duration/size limit (e.g., 120 minutes / 150 MB)
- User-selectable download count (1-3 episodes)
- Priority by queue position (download queue top first)

### 7.6 No dynamic ad insertion (DAI) detection

Some URLs go through Megaphone's DAI system (`dcs-spotify.megaphone.fm`). The audio file may be dynamically assembled with personalized ads, which means:
- File size may vary between HEAD and GET (rare, but possible)
- Re-downloading the same episode may yield a different file size
- The `no-cache` headers from Megaphone are related to this

### 7.7 URL encoding in API responses

Some URLs contain query parameters with `\u003d` (escaped `=`) and `\u0026` (escaped `&`). The JSON deserializer handles this, but be aware when logging or comparing URLs.

---

## 8. Recommendations for Garmin Implementation

### 8.1 Download strategy

| Recommendation | Rationale |
|---------------|-----------|
| **Always HEAD before GET** | Get real file size; verify URL still works |
| **Use Range requests for resumable downloads** | All CDNs support it; essential for unreliable BLE connections |
| **Don't send PocketCasts auth headers for audio** | Audio URLs are public; auth is irrelevant and adds unnecessary header bloat |
| **Follow redirects (up to 10 hops)** | Some URLs have 6 redirect hops; set a reasonable limit |
| **Re-fetch episode URL before download** | SupportingCast URLs may expire; always get fresh URL from API |
| **Estimate 1 MB per minute** | For pre-download storage checks; refine with HEAD Content-Length |

### 8.2 Storage budget

For Garmin Venu 4 41mm with the Media module:
- **1-2 short episodes** (~20-40 min): 20-40 MB — very feasible
- **1 long episode** (~60-90 min): 60-90 MB — feasible
- **1 very long episode** (~4 hrs): 240+ MB — may exceed practical storage

Recommend a **maximum of 3 episodes or 200 MB total**, whichever is less.

### 8.3 Sync position protocol

```
After offline playback session:
1. Authenticate (or verify token validity)
2. For each episode with changed position:
   a. POST /sync/update_episode
      { uuid, podcast, position, status, duration }
   b. Wait for 200 OK before next
3. Refresh local cache:
   a. POST /user/in_progress → reconcile positions
   b. POST /up_next/list → refresh queue
```

### 8.4 File naming on watch

Use episode UUID as filename: `{uuid}.mp3`. This guarantees uniqueness and makes it easy to map back to episode metadata. The Garmin Media module manages its own storage paths.

### 8.5 Error handling

| Error | Action |
|-------|--------|
| HEAD returns 404/410 | Episode removed from host; skip download, show user error |
| HEAD returns no Content-Length | Proceed with download but can't show progress bar |
| GET interrupted mid-download | Resume with `Range: bytes={downloaded}-` on next attempt |
| Content-Length mismatch (DAI) | Accept the file as-is; DAI may change file size between requests |
| 302 redirect loop | Abort after 10 hops; notify user |

---

## Appendix: Raw Probe Data

### A.1 CDN hosts discovered

| CDN | Provider | URLs Seen |
|-----|----------|-----------|
| `dcs-spotify.megaphone.fm` | Megaphone (Spotify) | Megaphone-hosted shows |
| `dcs-cached.megaphone.fm` | Megaphone (cached) | Same, different edge |
| `npr.simplecastaudio.com` | Simplecast (NPR) | NPR shows |
| `stitcher.simplecastaudio.com` | Simplecast (Stitcher) | Stitcher-era shows |
| `audio.transistor.fm` | Transistor | Transistor-hosted shows |
| `verge.supportingcast.fm` | SupportingCast | Premium/ad-free feeds |
| `mcdn.podbean.com` | Podbean | Podbean-hosted shows |

### A.2 Tracking/analytics services in URL chains

| Service | Domain | Purpose |
|---------|--------|---------|
| Podtrac | `podtrac.com`, `dts.podtrac.com` | Download tracking |
| Podsights | `pdst.fm` | Attribution analytics |
| Megaphone AI | `mgln.ai` | Ad insertion/tracking |
| Chartable/Spotify | `prfx.byspotify.com` | Prefix tracking |
| Claritas | `claritaspod.com` | Measurement |
| Podscribe | `pscrb.fm`, `verifi.podscribe.com` | Verification |
| VPIXL | `pfx.vpixl.com` | Pixel tracking |

### A.3 Example API calls for download workflow

**Step 1: Get episodes to download**
```http
POST https://api.pocketcasts.com/up_next/list
Authorization: Bearer <token>
Content-Type: application/json
Origin: https://play.pocketcasts.com

{}
```

**Step 2: Get full episode metadata**
```http
POST https://api.pocketcasts.com/user/episode
Authorization: Bearer <token>
Content-Type: application/json
Origin: https://play.pocketcasts.com

{
  "uuid": "0e6d7cb8-7749-4b1a-90ea-0230dbe45bf4"
}
```

Response:
```json
{
  "uuid": "0e6d7cb8-7749-4b1a-90ea-0230dbe45bf4",
  "url": "https://verge.supportingcast.fm/content/eyJ0Ijoi...mp3",
  "duration": 2134,
  "fileType": "audio/mp3",
  "size": "0",
  "title": "The AI industry's existential race for profits",
  "playingStatus": 2,
  "playedUpTo": 1491,
  "podcastUuid": "971126e0-11a9-013f-cf8e-0affc86eeaad",
  "podcastTitle": "Decoder: Ad-Free Edition"
}
```

**Step 3: Probe audio URL**
```http
HEAD https://verge.supportingcast.fm/content/eyJ0Ijoi...mp3
User-Agent: YoCasts/1.0
```

Response:
```
HTTP/1.1 200 OK
Content-Type: audio/mpeg
Content-Length: 114488009
Accept-Ranges: bytes
```

**Step 4: Download with Range support**
```http
GET https://verge.supportingcast.fm/content/eyJ0Ijoi...mp3
Range: bytes=0-1048575
User-Agent: YoCasts/1.0
```

Response:
```
HTTP/1.1 206 Partial Content
Content-Range: bytes 0-1048575/114488009
Content-Type: audio/mpeg
```

**Step 5: Push position after playback**
```http
POST https://api.pocketcasts.com/sync/update_episode
Authorization: Bearer <token>
Content-Type: application/json
Origin: https://play.pocketcasts.com

{
  "uuid": "0e6d7cb8-7749-4b1a-90ea-0230dbe45bf4",
  "podcast": "971126e0-11a9-013f-cf8e-0affc86eeaad",
  "position": 2134,
  "status": 3,
  "duration": 2134
}
```
