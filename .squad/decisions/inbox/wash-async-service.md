# Decision: Async Service Interface with Cache + Sync Getters

**By:** Wash (API Dev)  
**Date:** 2026-04-12  
**Status:** Proposed  
**Affects:** Kaylee (Garmin Dev), Mal (Lead)

## Summary

Changed `IPodcastService` from a purely synchronous interface to a hybrid **cache-first + async fetch** pattern to support `Communications.makeWebRequest()` (which is inherently async on Garmin).

## What Changed

### IPodcastService gains 5 new methods:
1. `isAuthenticated()` — whether login has succeeded
2. `isDataReady()` — whether initial podcasts + queue data is cached
3. `hasEpisodesForPodcast(uuid)` — whether episode data for a specific podcast is cached
4. `fetchAll()` — triggers the async data pipeline (login → podcasts → queue → enrich)
5. `requestEpisodesForPodcast(uuid)` — triggers async fetch of episodes for one podcast

### Original 4 sync getters are UNCHANGED:
- `getSubscribedPodcasts()` — returns cached data (empty array if not yet loaded)
- `getEpisodesForPodcast(uuid)` — returns cached data
- `getQueue()` — returns cached data
- `getNowPlaying()` — returns cached data

### All view type annotations changed:
- Every `MockPodcastService` type annotation → `IPodcastService`
- Views are now service-implementation-agnostic

## Why This Design

`makeWebRequest()` is async — data arrives via callback. But Garmin's `Menu2` UI builds items in the constructor and can't be updated after. A fully async callback-per-method interface would require rewriting all views.

The cache-first hybrid lets:
- **MockPodcastService** work exactly as before (data pre-loaded, `isDataReady()` always true)
- **PocketCastsPodcastService** fetch data in background, cache it, and call `WatchUi.requestUpdate()` when done
- **Views** call sync getters as usual — they get cached data or empty arrays

## Impact on Views

Minimal. Views now show "Loading..." instead of "empty" when data isn't ready yet. The `HomeMenuView` (custom View) naturally redraws when `requestUpdate()` fires. `Menu2` views are constructed at navigation time — by then, core data should be cached.

## Impact on MockPodcastService

Added 4 no-op method stubs. All pre-existing behavior unchanged.

## Open Questions

- Episode list views show "Loading..." on first visit with real API since episode data is fetched on-demand. User must back out and re-enter to see populated list after fetch completes. A proper loading→populated transition needs a view swap mechanism (Phase 2 polish).
- Token refresh is proactive (checks before each request) but doesn't queue the original request during refresh. If refresh is in-flight when a data request fires, the data request uses the old token. Acceptable for v1 since tokens typically have 1hr lifetime.
