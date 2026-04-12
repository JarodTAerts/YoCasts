# Audio Download API Findings

**Author:** Wash (API Dev)  
**Date:** 2026-04-12  
**Affects:** Mal (Lead), Kaylee (Garmin Dev)  
**Document:** `docs/pocketcasts-audio-download-research.md`

## Summary

Completed live-tested research on how PocketCasts serves audio and what the Garmin watch needs to do for offline downloads. Tested 7 episodes across 7 different CDN providers.

## Critical Findings

### 1. Audio is NOT proxied by PocketCasts
Episode URLs are original RSS feed URLs. PocketCasts just passes them through. The watch/phone downloads directly from podcast host CDNs (Megaphone, Simplecast, Transistor, SupportingCast, Podbean).

### 2. No authentication needed for audio
All 7 CDNs returned `200 OK` without any Bearer token. PocketCasts auth is only for the metadata API, not for audio file access. **The phone companion can download audio without API credentials.**

### 3. Range requests work everywhere
All 7 CDNs support `Range: bytes=X-Y` headers with `206 Partial Content` responses. Resumable downloads are fully supported — critical for unreliable BLE connections.

### 4. URLs redirect heavily (1-6 hops)
Every audio URL goes through analytics/tracking redirectors before reaching the CDN. HTTP client must follow redirects. The phone's HTTP stack handles this natively.

### 5. API `size` field is unreliable
Often `"0"` (string, not number). When non-zero, doesn't match actual Content-Length (10-20% discrepancy). **Must issue HEAD request for real file size.**

### 6. Premium feed URLs may expire
SupportingCast (Verge ad-free, etc.) URLs contain embedded JWT tokens with timestamps. A 3.3-day-old URL still worked, but expiry is likely. **Always re-fetch episode URL from API immediately before download.**

## Decisions Needed

1. **Maximum download size/count** — Episodes range from 19 MB to 243 MB. Recommend capping at 3 episodes or 200 MB total. Need Kaylee's input on Garmin Media storage limits.

2. **Download timing** — Should downloads happen during Garmin Media sync (the standard approach) or via a custom background transfer? The Media module's ContentProvider/SyncDelegate pattern is the intended mechanism.

3. **URL refresh strategy** — Given possible SupportingCast expiry, should we cache URLs for max 1 hour? Or always call `/user/episode` right before download?

## Impact on Architecture

- Mal's offline-sync-design.md Phase 3 (Audio Download) is now unblocked — all API mechanics documented
- The phone companion does all the heavy HTTP lifting (redirects, Range requests, downloads)
- Watch-side storage is through Garmin Media module, not `Application.Storage`
- Position sync after playback uses per-episode `POST /sync/update_episode` (no batch)
- `/user/in_progress` provides all data needed for bulk reconciliation
