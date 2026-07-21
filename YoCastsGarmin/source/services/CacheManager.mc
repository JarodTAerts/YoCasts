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
    const KEY_DETAIL_PREFIX = "yc_detail_";
    const KEY_EPISODE_CACHE_INDEX = "yc_episode_cache_index";
    const KEY_DETAIL_CACHE_INDEX = "yc_detail_cache_index";
    const KEY_POSITION_CACHE_INDEX = "yc_position_cache_index";
    const MAX_EPISODE_CACHES = 10;
    const MAX_DETAIL_CACHES = 5;
    const MAX_POSITION_CACHES = 30;

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
        _touchEpisodeCache(podcastUuid);
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
    // Extended episode details (per episode)
    // ================================================================

    function saveEpisodeDetails(episodeUuid as String,
                                details as Dictionary) as Void {
        var entry = {
            "data" => details as Application.Storage.ValueType,
            "cachedAt" => Time.now().value() as Application.Storage.ValueType
        } as Dictionary;
        Application.Storage.setValue(
            KEY_DETAIL_PREFIX + episodeUuid,
            entry as Application.Storage.ValueType
        );
        _touchDetailCache(episodeUuid);
    }

    function loadEpisodeDetails(episodeUuid as String) as Dictionary? {
        var entry = Application.Storage.getValue(
            KEY_DETAIL_PREFIX + episodeUuid
        );
        if (entry != null && entry instanceof Dictionary) {
            var data = (entry as Dictionary).get("data");
            if (data != null && data instanceof Dictionary) {
                return data as Dictionary;
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
        _touchPositionCache(episodeUuid);
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

    function removePlaybackPosition(episodeUuid as String) as Void {
        Application.Storage.deleteValue(KEY_POSITION_PREFIX + episodeUuid);
        var existing = _loadStringIndex(KEY_POSITION_CACHE_INDEX);
        var updated = [] as Array<String>;
        for (var i = 0; i < existing.size(); i++) {
            if (!existing[i].equals(episodeUuid)) {
                updated.add(existing[i]);
            }
        }
        if (updated.size() == 0) {
            Application.Storage.deleteValue(KEY_POSITION_CACHE_INDEX);
        } else {
            Application.Storage.setValue(
                KEY_POSITION_CACHE_INDEX,
                updated as Application.Storage.ValueType
            );
        }
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

    //! Wipe cached podcast data but preserve changelog, auth, and sync state.
    //! Selectively deletes known cache keys instead of clearValues() to
    //! protect ChangeLog entries and future auth token storage.
    function clearCache() as Void {
        Application.Storage.deleteValue(KEY_PODCASTS);
        Application.Storage.deleteValue(KEY_QUEUE);
        var index = _loadEpisodeCacheIndex();
        for (var i = 0; i < index.size(); i++) {
            Application.Storage.deleteValue(
                KEY_EPISODES_PREFIX + index[i]
            );
        }
        Application.Storage.deleteValue(KEY_EPISODE_CACHE_INDEX);
        var detailIndex = _loadStringIndex(KEY_DETAIL_CACHE_INDEX);
        for (var i = 0; i < detailIndex.size(); i++) {
            Application.Storage.deleteValue(
                KEY_DETAIL_PREFIX + detailIndex[i]
            );
        }
        Application.Storage.deleteValue(KEY_DETAIL_CACHE_INDEX);
        // Per-episode position caches are left intact for sync.
    }

    function _touchEpisodeCache(podcastUuid as String) as Void {
        var existing = _loadEpisodeCacheIndex();
        var updated = [] as Array<String>;
        for (var i = 0; i < existing.size(); i++) {
            if (!existing[i].equals(podcastUuid)) {
                updated.add(existing[i]);
            }
        }
        updated.add(podcastUuid);

        while (updated.size() > MAX_EPISODE_CACHES) {
            var oldest = updated[0];
            Application.Storage.deleteValue(KEY_EPISODES_PREFIX + oldest);
            updated = updated.slice(1, null) as Array<String>;
        }

        Application.Storage.setValue(
            KEY_EPISODE_CACHE_INDEX,
            updated as Application.Storage.ValueType
        );
    }

    function _loadEpisodeCacheIndex() as Array<String> {
        var value = Application.Storage.getValue(KEY_EPISODE_CACHE_INDEX);
        if (value != null && value instanceof Array) {
            return value as Array<String>;
        }
        return [] as Array<String>;
    }

    function _touchDetailCache(episodeUuid as String) as Void {
        var existing = _loadStringIndex(KEY_DETAIL_CACHE_INDEX);
        var updated = [] as Array<String>;
        for (var i = 0; i < existing.size(); i++) {
            if (!existing[i].equals(episodeUuid)) {
                updated.add(existing[i]);
            }
        }
        updated.add(episodeUuid);
        while (updated.size() > MAX_DETAIL_CACHES) {
            Application.Storage.deleteValue(
                KEY_DETAIL_PREFIX + updated[0]
            );
            updated = updated.slice(1, null) as Array<String>;
        }
        Application.Storage.setValue(
            KEY_DETAIL_CACHE_INDEX,
            updated as Application.Storage.ValueType
        );
    }

    function _touchPositionCache(episodeUuid as String) as Void {
        var existing = _loadStringIndex(KEY_POSITION_CACHE_INDEX);
        var updated = [] as Array<String>;
        for (var i = 0; i < existing.size(); i++) {
            if (!existing[i].equals(episodeUuid)) {
                updated.add(existing[i]);
            }
        }
        updated.add(episodeUuid);
        while (updated.size() > MAX_POSITION_CACHES) {
            Application.Storage.deleteValue(
                KEY_POSITION_PREFIX + updated[0]
            );
            updated = updated.slice(1, null) as Array<String>;
        }
        Application.Storage.setValue(
            KEY_POSITION_CACHE_INDEX,
            updated as Application.Storage.ValueType
        );
    }

    function _loadStringIndex(key as String) as Array<String> {
        var value = Application.Storage.getValue(key);
        return (value != null && value instanceof Array)
            ? value as Array<String>
            : [] as Array<String>;
    }
}
