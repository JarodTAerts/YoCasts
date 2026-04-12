import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

//! Stores offline mutations for later sync to PocketCasts.
//! Each entry records a user action (position update, completion, queue remove)
//! that happened while offline or hasn't been pushed to the server yet.
//!
//! Entries persist in Application.Storage under "yc_changelog".
//! Coalescing: multiple POSITION_UPDATEs for the same episode keep only the latest.
//! Max 100 entries — oldest non-completion entries are evicted first.
module ChangeLog {

    // Change types
    const TYPE_POSITION_UPDATE = "POSITION_UPDATE";
    const TYPE_EPISODE_COMPLETED = "EPISODE_COMPLETED";
    const TYPE_QUEUE_REMOVE = "QUEUE_REMOVE";

    // Storage keys
    const KEY_CHANGELOG = "yc_changelog";
    const KEY_CHANGELOG_SEQ = "yc_cl_seq";

    const MAX_ENTRIES = 100;

    //! Add a changelog entry. Coalesces POSITION_UPDATEs for the same episode.
    //! @param type One of TYPE_POSITION_UPDATE, TYPE_EPISODE_COMPLETED, TYPE_QUEUE_REMOVE
    //! @param episodeUuid UUID of the episode
    //! @param podcastUuid UUID of the parent podcast
    //! @param data Additional data (e.g., position, status, duration)
    function addEntry(type as String, episodeUuid as String,
                      podcastUuid as String, data as Dictionary) as Void {
        var log = getEntries();

        // Coalesce: remove existing POSITION_UPDATE for same episode
        if (type.equals(TYPE_POSITION_UPDATE)) {
            var filtered = [] as Array<Dictionary>;
            for (var i = 0; i < log.size(); i++) {
                var entry = log[i] as Dictionary;
                var eType = entry.get("type");
                var eUuid = entry.get("episodeUuid");
                if (eType != null && eUuid != null &&
                    (eType as String).equals(TYPE_POSITION_UPDATE) &&
                    (eUuid as String).equals(episodeUuid)) {
                    // Skip — this old position update will be replaced
                } else {
                    filtered.add(entry);
                }
            }
            log = filtered;
        }

        // Monotonic sequence number for entry IDs
        var seqVal = Application.Storage.getValue(KEY_CHANGELOG_SEQ);
        var seq = (seqVal != null && seqVal instanceof Number)
                  ? (seqVal as Number) + 1 : 1;

        log.add({
            "id" => seq as Application.Storage.ValueType,
            "type" => type as Application.Storage.ValueType,
            "episodeUuid" => episodeUuid as Application.Storage.ValueType,
            "podcastUuid" => podcastUuid as Application.Storage.ValueType,
            "data" => data as Application.Storage.ValueType,
            "timestamp" => Time.now().value() as Application.Storage.ValueType
        } as Dictionary);

        // Evict if over cap
        if (log.size() > MAX_ENTRIES) {
            log = _evictOne(log);
        }

        Application.Storage.setValue(KEY_CHANGELOG_SEQ,
                                     seq as Application.Storage.ValueType);
        Application.Storage.setValue(KEY_CHANGELOG,
                                     log as Application.Storage.ValueType);
    }

    //! Get all pending changelog entries.
    function getEntries() as Array<Dictionary> {
        var val = Application.Storage.getValue(KEY_CHANGELOG);
        if (val != null && val instanceof Array) {
            return val as Array<Dictionary>;
        }
        return [] as Array<Dictionary>;
    }

    //! Clear all entries after successful sync push.
    function clearEntries() as Void {
        Application.Storage.deleteValue(KEY_CHANGELOG);
    }

    //! Number of pending entries (for UI display, e.g., "3 pending syncs").
    function getEntryCount() as Number {
        return getEntries().size();
    }

    //! Evict the oldest non-completion entry. If all entries are completions,
    //! evict the oldest completion. Returns the trimmed log.
    function _evictOne(log as Array<Dictionary>) as Array<Dictionary> {
        var evictIdx = -1;
        var oldestTime = 2147483647;

        // Pass 1: find oldest non-completion entry
        for (var i = 0; i < log.size(); i++) {
            var entry = log[i] as Dictionary;
            var eType = entry.get("type");
            if (eType == null || !(eType as String).equals(TYPE_EPISODE_COMPLETED)) {
                var ts = entry.get("timestamp");
                if (ts != null && ts instanceof Number && (ts as Number) < oldestTime) {
                    oldestTime = ts as Number;
                    evictIdx = i;
                }
            }
        }

        // Pass 2: fallback — evict oldest of any type
        if (evictIdx < 0) {
            oldestTime = 2147483647;
            for (var i = 0; i < log.size(); i++) {
                var entry = log[i] as Dictionary;
                var ts = entry.get("timestamp");
                if (ts != null && ts instanceof Number && (ts as Number) < oldestTime) {
                    oldestTime = ts as Number;
                    evictIdx = i;
                }
            }
        }

        if (evictIdx >= 0) {
            var trimmed = [] as Array<Dictionary>;
            for (var j = 0; j < log.size(); j++) {
                if (j != evictIdx) {
                    trimmed.add(log[j] as Dictionary);
                }
            }
            return trimmed;
        }

        return log;
    }
}
