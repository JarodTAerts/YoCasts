import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

//! Manages persistent caching of podcast data via Application.Storage.
//! Each cache entry wraps its payload in a Dictionary with "data" and
//! "cachedAt" keys so we can compute cache age for TTL decisions.
//!
//! Storage keys are prefixed with "yc_" to avoid collisions with
//! future keys (changelog, auth, etc.) added in later phases.
module CacheManager {

    // ---- Storage key constants ----
    const KEY_PODCASTS = "yc_podcasts";
    const KEY_QUEUE = "yc_queue";
    const KEY_EPISODES_PREFIX = "yc_episodes_";
    const KEY_POSITION_PREFIX = "yc_pos_";

    // ================================================================
    // Podcasts
    // ================================================================

    //! Cache the subscribed podcasts list.
    function savePodcasts(podcasts as Array<Dictionary>) as Void {
        var entry = {
            "data" => podcasts as Application.Storage.ValueType,
            "cachedAt" => Time.now().value() as Application.Storage.ValueType
        };
        Application.Storage.setValue(KEY_PODCASTS, entry as Application.Storage.ValueType);
    }

    //! Load cached podcasts. Returns null if nothing is cached.
    function loadPodcasts() as Array<Dictionary>? {
        var entry = Application.Storage.getValue(KEY_PODCASTS);
        if (entry != null && entry instanceof Dictionary) {
            var dict = entry as Dictionary;
            var data = dict.get("data");
            if (data != null && data instanceof Array) {
                return data as Array<Dictionary>;
            }
        }
        return null;
    }

    // ================================================================
    // Episodes (per podcast)
    // ================================================================

    //! Cache episodes for a specific podcast.
    function saveEpisodes(podcastUuid as String, episodes as Array<Dictionary>) as Void {
        var key = KEY_EPISODES_PREFIX + podcastUuid;
        var entry = {
            "data" => episodes as Application.Storage.ValueType,
            "cachedAt" => Time.now().value() as Application.Storage.ValueType
        };
        Application.Storage.setValue(key, entry as Application.Storage.ValueType);
    }

    //! Load cached episodes for a podcast. Returns null if no cache.
    function loadEpisodes(podcastUuid as String) as Array<Dictionary>? {
        var key = KEY_EPISODES_PREFIX + podcastUuid;
        var entry = Application.Storage.getValue(key);
        if (entry != null && entry instanceof Dictionary) {
            var dict = entry as Dictionary;
            var data = dict.get("data");
            if (data != null && data instanceof Array) {
                return data as Array<Dictionary>;
            }
        }
        return null;
    }

    // ================================================================
    // Queue (Up Next)
    // ================================================================

    //! Cache the Up Next queue.
    function saveQueue(queue as Array<Dictionary>) as Void {
        var entry = {
            "data" => queue as Application.Storage.ValueType,
            "cachedAt" => Time.now().value() as Application.Storage.ValueType
        };
        Application.Storage.setValue(KEY_QUEUE, entry as Application.Storage.ValueType);
    }

    //! Load cached queue. Returns null if nothing cached.
    function loadQueue() as Array<Dictionary>? {
        var entry = Application.Storage.getValue(KEY_QUEUE);
        if (entry != null && entry instanceof Dictionary) {
            var dict = entry as Dictionary;
            var data = dict.get("data");
            if (data != null && data instanceof Array) {
                return data as Array<Dictionary>;
            }
        }
        return null;
    }

    // ================================================================
    // Playback positions (per episode)
    // ================================================================

    //! Cache playback position for an episode.
    function savePlaybackPosition(episodeUuid as String, position as Number,
                                   duration as Number) as Void {
        var key = KEY_POSITION_PREFIX + episodeUuid;
        var entry = {
            "position" => position as Application.Storage.ValueType,
            "duration" => duration as Application.Storage.ValueType,
            "cachedAt" => Time.now().value() as Application.Storage.ValueType
        };
        Application.Storage.setValue(key, entry as Application.Storage.ValueType);
    }

    //! Load cached playback position. Returns Dictionary with "position",
    //! "duration", and "cachedAt" keys, or null if not cached.
    function loadPlaybackPosition(episodeUuid as String) as Dictionary? {
        var key = KEY_POSITION_PREFIX + episodeUuid;
        var entry = Application.Storage.getValue(key);
        if (entry != null && entry instanceof Dictionary) {
            return entry as Dictionary;
        }
        return null;
    }

    // ================================================================
    // Cache metadata
    // ================================================================

    //! Returns the age of a cache entry in seconds, or -1 if not cached.
    //! Accepts a full storage key (e.g., KEY_PODCASTS or KEY_EPISODES_PREFIX + uuid).
    function getCacheAge(key as String) as Number {
        var entry = Application.Storage.getValue(key);
        if (entry != null && entry instanceof Dictionary) {
            var dict = entry as Dictionary;
            var cachedAt = dict.get("cachedAt");
            if (cachedAt != null && cachedAt instanceof Number) {
                return Time.now().value() - (cachedAt as Number);
            }
        }
        return -1;
    }

    //! Wipe all cached data from Application.Storage.
    //! Safe in Phase 1 — auth lives in Application.Properties, not Storage.
    //! Will need revision when changelog/auth tokens move to Storage (Phase 2+).
    function clearCache() as Void {
        Application.Storage.clearValues();
    }
}
