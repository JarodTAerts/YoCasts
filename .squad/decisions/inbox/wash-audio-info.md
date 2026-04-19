# Decision: Audio URL Auth Confirmed + AudioInfo Proxy Enhanced

**By:** Wash (API Dev)  
**Date:** 2026-04-19  
**Affects:** Kaylee (Garmin Dev), Mal (Lead)

## Audio URL Auth Validation — DEFINITIVELY CONFIRMED

Ran structured live test against 5 episodes from 5 different podcasts across 4 CDNs:

| Podcast | CDN | Auth Required? | Range Support? | File Size |
|---------|-----|:-:|:-:|-----------|
| The Vergecast: Ad-Free Edition | supportingcast.fm | NO | YES (206) | 69.6 MB |
| The Vergecast | megaphone.fm | NO | YES (206) | 84.9 MB |
| Acquired | transistor.fm | NO | YES (206) | 242.5 MB |
| Timesuck | simplecastaudio.com | NO | YES (206) | 102.2 MB |
| 99% Invisible | simplecastaudio.com | NO | YES (206) | 30.4 MB |

**Conclusion:** Garmin SyncDelegate can download audio directly from CDN URLs. No PocketCasts auth headers needed. All CDNs support Range (resumable). SupportingCast JWT-embedded URLs are also publicly accessible — the token is baked into the URL itself.

## AudioInfo Proxy Endpoint — Enhanced & Deployed

**Endpoint:** `GET https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts/episode/{uuid}/audio-info`

**Response shape:**
```json
{
  "uuid": "episode-uuid",
  "audioUrl": "https://cdn.example.com/episode.mp3",
  "fileSize": 88844501,
  "duration": 5428,
  "contentType": "audio/mpeg",
  "requiresAuth": false,
  "title": "Episode Title",
  "podcastTitle": "Podcast Name",
  "podcastUuid": "podcast-uuid"
}
```

**Enhancements over previous version:**
1. `requiresAuth` field — flags SupportingCast premium URLs so Garmin client can re-fetch before download
2. `podcastTitle` field — from episode metadata
3. In-memory caching — 2hr TTL for standard, 30min for premium URLs
4. SupportingCast detection via `IsPremiumUrl()` pattern matching
5. Response ~515 bytes typical — well under 2 KB Garmin per-value limit

**For Kaylee:** SyncDelegate should call this endpoint before each download to get:
- `audioUrl` — the actual CDN URL to download (after redirects resolved by proxy)
- `fileSize` — for storage space check before downloading
- `requiresAuth` — if `true`, re-call this endpoint to get fresh URL (don't use cached)
- `contentType` — for Media.ContentObj metadata

## Test Artifacts

- Auth validation results: `PocketcastsApiTesting/.../test-results/audio-auth-validation-*.json`
- Test tool: Menu option 17 in API tester (`AudioAuthValidator.cs`)
