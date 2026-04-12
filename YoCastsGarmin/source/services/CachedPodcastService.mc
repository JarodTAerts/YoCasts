import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Decorator that adds persistent caching to any IPodcastService.
//!
//! On construction: loads cached data from Application.Storage so the UI
//! has data to show immediately (even before network fetch completes).
//!
//! When connected: delegates fetches to the wrapped service. On the next
//! view update cycle, reads fresh data from the wrapped service's getters
//! and writes it to the cache.
//!
//! When offline (no connection available): serves cached data only,
//! never attempts network calls via the wrapped service.
//!
//! Cache TTLs control when to *revalidate*, not when to *expire*.
//! Stale data is always served — it's better than an empty screen.
class CachedPodcastService extends IPodcastService {

    private var _wrapped as IPodcastService;

    // In-memory data (populated from Storage on init, updated from wrapped service)
    private var _podcasts as Array<Dictionary> = [] as Array<Dictionary>;
    private var _queue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _episodes as Dictionary = {} as Dictionary;
    private var _nowPlaying as Dictionary? = null;
    private var _hasCachedData as Boolean = false;

    // Refresh tracking — prevents redundant Storage writes
    private var _podcastsRefreshPending as Boolean = false;
    private var _queueRefreshPending as Boolean = false;
    private var _episodeRefreshPending as Dictionary = {} as Dictionary;

    // Cache TTLs in seconds (controls revalidation, not expiry)
    private const TTL_QUEUE = 300;       // 5 minutes
    private const TTL_PODCASTS = 1800;   // 30 minutes
    private const TTL_EPISODES = 3600;   // 1 hour

    function initialize(wrapped as IPodcastService) {
        IPodcastService.initialize();
        _wrapped = wrapped;
        _loadFromCache();
    }

    //! Hydrate in-memory fields from Application.Storage.
    private function _loadFromCache() as Void {
        var podcasts = CacheManager.loadPodcasts();
        if (podcasts != null) {
            _podcasts = podcasts;
            _hasCachedData = true;
        }

        var queue = CacheManager.loadQueue();
        if (queue != null) {
            _queue = queue;
            if (_queue.size() > 0) {
                _nowPlaying = _queue[0];
            }
            _hasCachedData = true;
        }
    }

    // ================================================================
    // IPodcastService — status
    // ================================================================

    function isAuthenticated() as Boolean {
        return _hasCachedData || _wrapped.isAuthenticated();
    }

    function isDataReady() as Boolean {
        return _hasCachedData || _wrapped.isDataReady();
    }

    // ================================================================
    // IPodcastService — async triggers
    // ================================================================

    //! Start full data fetch. Connectivity-aware:
    //!   STATE_WIFI:    full refresh (all data + future downloads)
    //!   STATE_PHONE:   metadata refresh (small payloads only)
    //!   STATE_OFFLINE: serve cache only, no-op
    function fetchAll() as Void {
        var state = ConnectivityManager.getState();
        if (state == ConnectivityManager.STATE_OFFLINE) {
            System.println("YoCasts: CachedService — offline, serving cached data only");
            return;
        }

        System.println("YoCasts: CachedService — connected (state=" + state + "), delegating fetchAll");
        _podcastsRefreshPending = true;
        _queueRefreshPending = true;
        _wrapped.fetchAll();
        // Future phases: STATE_WIFI triggers episode auto-downloads
    }

    //! Fetch episodes for a podcast. Loads from cache first; if connected
    //! and cache is stale (or missing), delegates to the wrapped service.
    function requestEpisodesForPodcast(podcastUuid as String) as Void {
        // Lazy-load from Storage if not yet in memory
        if (!_episodes.hasKey(podcastUuid)) {
            var cached = CacheManager.loadEpisodes(podcastUuid);
            if (cached != null) {
                _episodes.put(podcastUuid, cached);
            }
        }

        if (_isConnected()) {
            var cacheAge = CacheManager.getCacheAge(
                CacheManager.KEY_EPISODES_PREFIX + podcastUuid
            );
            if (cacheAge < 0 || cacheAge > TTL_EPISODES) {
                _episodeRefreshPending.put(podcastUuid, true);
                _wrapped.requestEpisodesForPodcast(podcastUuid);
            }
        }
    }

    // ================================================================
    // IPodcastService — synchronous getters (read-through cache)
    //
    // These are called by views on every update cycle. When a refresh
    // is pending, we check the wrapped service for fresh data. Once
    // we see it, we cache it and clear the pending flag so we don't
    // redundantly write to Storage on subsequent update cycles.
    // ================================================================

    function getSubscribedPodcasts() as Array<Dictionary> {
        if (_podcastsRefreshPending) {
            var fresh = _wrapped.getSubscribedPodcasts();
            if (fresh.size() > 0) {
                _podcasts = fresh;
                CacheManager.savePodcasts(_podcasts);
                _podcastsRefreshPending = false;
                _hasCachedData = true;
            }
        }
        return _podcasts;
    }

    function getEpisodesForPodcast(podcastUuid as String) as Array<Dictionary> {
        // Check for pending refresh from wrapped service
        if (_episodeRefreshPending.hasKey(podcastUuid)) {
            var fresh = _wrapped.getEpisodesForPodcast(podcastUuid);
            if (fresh.size() > 0) {
                _episodes.put(podcastUuid, fresh);
                CacheManager.saveEpisodes(podcastUuid, fresh);
                _episodeRefreshPending.remove(podcastUuid);
            }
        }

        // Return from in-memory cache
        var eps = _episodes.get(podcastUuid);
        if (eps != null) {
            return eps as Array<Dictionary>;
        }

        // Final fallback: try Storage directly (lazy load)
        var cached = CacheManager.loadEpisodes(podcastUuid);
        if (cached != null) {
            _episodes.put(podcastUuid, cached);
            return cached;
        }

        return [] as Array<Dictionary>;
    }

    function getQueue() as Array<Dictionary> {
        if (_queueRefreshPending) {
            var fresh = _wrapped.getQueue();
            if (fresh.size() > 0) {
                _queue = fresh;
                CacheManager.saveQueue(_queue);
                _queueRefreshPending = false;
                _hasCachedData = true;
                if (_queue.size() > 0) {
                    _nowPlaying = _queue[0];
                }
            }
        }
        return _queue;
    }

    function getNowPlaying() as Dictionary? {
        var wrappedNow = _wrapped.getNowPlaying();
        if (wrappedNow != null) {
            _nowPlaying = wrappedNow;
        }
        return _nowPlaying;
    }

    // ================================================================
    // Helpers
    // ================================================================

    //! Check if any connectivity is available (Wi-Fi direct or phone BLE).
    //! Delegates to ConnectivityManager for unified three-state detection.
    private function _isConnected() as Boolean {
        return ConnectivityManager.isConnected();
    }
}
