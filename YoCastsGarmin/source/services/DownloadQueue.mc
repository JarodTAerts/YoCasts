import Toybox.Lang;
import Toybox.Application;
import Toybox.System;
import Toybox.Time;

//! Manages a persistent queue of episodes pending download.
//! Queue state is stored in Application.Storage so it survives app restarts.
//! Items are ordered by user-added time (FIFO) with priority ordering.
//! Status per item: PENDING → DOWNLOADING → DOWNLOADED or FAILED.
//!
//! This module is Media-agnostic — works in both simulator and device builds.
module DownloadQueue {

    // Download status constants
    const STATUS_PENDING = 0;
    const STATUS_DOWNLOADING = 1;
    const STATUS_DOWNLOADED = 2;
    const STATUS_FAILED = 3;

    // Download item dictionary keys
    const DL_UUID = "uuid";
    const DL_TITLE = "title";
    const DL_PODCAST_TITLE = "podcastTitle";
    const DL_STATUS = "dlStatus";
    const DL_PROGRESS = "dlProgress";       // 0–100 percentage
    const DL_DURATION = "duration";
    const DL_PLAYED_UP_TO = "playedUpTo";
    const DL_PODCAST_UUID = "podcastUuid";
    const DL_PLAYING_STATUS = "playingStatus";

    // Storage key
    const KEY_DL_QUEUE = "yc_dl_queue";

    // Configuration
    const MAX_QUEUE_SIZE = 20;

    //! Get all download items in queue order (user-added FIFO).
    function getDownloads() as Array<Dictionary> {
        return _loadQueue();
    }

    //! Get count of all items in the queue (any status).
    function getDownloadCount() as Number {
        return _loadQueue().size();
    }

    //! Get count of fully downloaded (ready to play) episodes.
    function getCompletedCount() as Number {
        var queue = _loadQueue();
        var count = 0;
        for (var i = 0; i < queue.size(); i++) {
            var dl = queue[i] as Dictionary;
            var status = dl.get(DL_STATUS);
            if (status != null && (status as Number) == STATUS_DOWNLOADED) {
                count = count + 1;
            }
        }
        return count;
    }

    //! Get download status for a specific episode UUID.
    //! Returns: status constant, or -1 if not in queue.
    function getStatus(uuid as String) as Number {
        var queue = _loadQueue();
        for (var i = 0; i < queue.size(); i++) {
            var dl = queue[i] as Dictionary;
            var dlUuid = dl.get(DL_UUID);
            if (dlUuid != null && (dlUuid as String).equals(uuid)) {
                var status = dl.get(DL_STATUS);
                return (status != null) ? status as Number : -1;
            }
        }
        return -1;
    }

    //! Get download progress (0–100) for a specific episode UUID.
    function getProgress(uuid as String) as Number {
        var queue = _loadQueue();
        for (var i = 0; i < queue.size(); i++) {
            var dl = queue[i] as Dictionary;
            var dlUuid = dl.get(DL_UUID);
            if (dlUuid != null && (dlUuid as String).equals(uuid)) {
                var progress = dl.get(DL_PROGRESS);
                return (progress != null) ? progress as Number : 0;
            }
        }
        return 0;
    }

    //! Check if an episode is in the queue (any status).
    function isInQueue(uuid as String) as Boolean {
        return getStatus(uuid) >= 0;
    }

    //! Get the queue size (alias for getDownloadCount).
    function getQueueSize() as Number {
        return getDownloadCount();
    }

    //! Get the next pending/retryable item from the queue.
    //! Returns null if no eligible items remain.
    function getNextPending() as Dictionary? {
        var queue = _loadQueue();
        for (var i = 0; i < queue.size(); i++) {
            var item = queue[i] as Dictionary;
            var status = item.get(DL_STATUS);
            if (status != null && (status as Number) == STATUS_PENDING) {
                return item;
            }
            if (status != null && (status as Number) == STATUS_FAILED) {
                var errCount = item.get("errorCount");
                var ec = (errCount != null && errCount instanceof Number)
                         ? errCount as Number : 0;
                if (ec < 3) {
                    return item;
                }
            }
        }
        return null;
    }

    //! Add an episode to the download queue. Takes a full episode Dictionary
    //! (with DataKeys.E_* fields). No-op if already present or queue is full.
    function addToQueue(episode as Dictionary) as Void {
        var uuid = episode.get(DataKeys.E_UUID);
        if (uuid == null) { return; }
        var uuidStr = uuid as String;

        if (isInQueue(uuidStr)) {
            return;
        }

        var queue = _loadQueue();
        if (queue.size() >= MAX_QUEUE_SIZE) {
            System.println("YoCasts DLQueue: queue full (" + MAX_QUEUE_SIZE + "), rejecting " + uuidStr);
            return;
        }

        var title = episode.get(DataKeys.E_TITLE);
        var podTitle = episode.get(DataKeys.E_PODCAST_TITLE);
        var podUuid = episode.get(DataKeys.E_PODCAST_UUID);
        var duration = episode.get(DataKeys.E_DURATION);
        var playedUpTo = episode.get(DataKeys.E_PLAYED_UP_TO);
        var playingStatus = episode.get(DataKeys.E_PLAYING_STATUS);

        var item = {
            DL_UUID => uuidStr as Application.Storage.ValueType,
            DL_TITLE => (title != null ? title as String : "Unknown") as Application.Storage.ValueType,
            DL_PODCAST_TITLE => (podTitle != null ? podTitle as String : "") as Application.Storage.ValueType,
            DL_PODCAST_UUID => (podUuid != null ? podUuid as String : "") as Application.Storage.ValueType,
            DL_STATUS => STATUS_PENDING as Application.Storage.ValueType,
            DL_PROGRESS => 0 as Application.Storage.ValueType,
            DL_DURATION => (duration != null ? duration as Number : 0) as Application.Storage.ValueType,
            DL_PLAYED_UP_TO => (playedUpTo != null ? playedUpTo as Number : 0) as Application.Storage.ValueType,
            DL_PLAYING_STATUS => (playingStatus != null ? playingStatus as Number : DataKeys.STATUS_NOT_PLAYED) as Application.Storage.ValueType,
            "addedAt" => Time.now().value() as Application.Storage.ValueType,
            "errorCount" => 0 as Application.Storage.ValueType
        } as Dictionary;

        queue.add(item);
        _saveQueue(queue);
        System.println("YoCasts DLQueue: added " + uuidStr + " (size=" + queue.size() + ")");
    }

    //! Remove a download by UUID. Persists the change.
    function removeFromQueue(uuid as String) as Void {
        var queue = _loadQueue();
        var updated = [] as Array<Dictionary>;
        for (var i = 0; i < queue.size(); i++) {
            var dl = queue[i] as Dictionary;
            var dlUuid = dl.get(DL_UUID);
            if (dlUuid == null || !(dlUuid as String).equals(uuid)) {
                updated.add(dl);
            }
        }
        _saveQueue(updated);
        System.println("YoCasts DLQueue: removed " + uuid);
    }

    //! Update the status of a queue item by episode UUID.
    function updateStatus(uuid as String, newStatus as Number) as Void {
        var queue = _loadQueue();
        for (var i = 0; i < queue.size(); i++) {
            var item = queue[i] as Dictionary;
            var dlUuid = item.get(DL_UUID);
            if (dlUuid != null && (dlUuid as String).equals(uuid)) {
                item.put(DL_STATUS, newStatus as Application.Storage.ValueType);
                if (newStatus == STATUS_FAILED) {
                    var errCount = item.get("errorCount");
                    var ec = (errCount != null && errCount instanceof Number)
                             ? (errCount as Number) + 1 : 1;
                    item.put("errorCount", ec as Application.Storage.ValueType);
                }
                if (newStatus == STATUS_DOWNLOADED) {
                    item.put("completedAt", Time.now().value() as Application.Storage.ValueType);
                    item.put(DL_PROGRESS, 100 as Application.Storage.ValueType);
                }
                _saveQueue(queue);
                return;
            }
        }
    }

    //! Update download progress (0–100) for an episode.
    function updateProgress(uuid as String, progress as Number) as Void {
        var queue = _loadQueue();
        for (var i = 0; i < queue.size(); i++) {
            var item = queue[i] as Dictionary;
            var dlUuid = item.get(DL_UUID);
            if (dlUuid != null && (dlUuid as String).equals(uuid)) {
                item.put(DL_PROGRESS, progress as Application.Storage.ValueType);
                _saveQueue(queue);
                return;
            }
        }
    }

    //! Remove all completed items from the queue (cleanup after sync).
    function purgeCompleted() as Void {
        var queue = _loadQueue();
        var remaining = [] as Array<Dictionary>;
        for (var i = 0; i < queue.size(); i++) {
            var item = queue[i] as Dictionary;
            var status = item.get(DL_STATUS);
            if (status == null || (status as Number) != STATUS_DOWNLOADED) {
                remaining.add(item);
            }
        }
        _saveQueue(remaining);
    }

    //! Remove failed items that exceeded retry limit (3 attempts).
    function purgeFailed() as Void {
        var queue = _loadQueue();
        var remaining = [] as Array<Dictionary>;
        for (var i = 0; i < queue.size(); i++) {
            var item = queue[i] as Dictionary;
            var status = item.get(DL_STATUS);
            if (status != null && (status as Number) == STATUS_FAILED) {
                var errCount = item.get("errorCount");
                var ec = (errCount != null && errCount instanceof Number)
                         ? errCount as Number : 0;
                if (ec >= 3) {
                    continue;
                }
            }
            remaining.add(item);
        }
        _saveQueue(remaining);
    }

    //! Clear the entire download queue.
    function clearQueue() as Void {
        Application.Storage.deleteValue(KEY_DL_QUEUE);
    }

    //! Build an episode-compatible Dictionary from a download item
    //! (for passing to NowPlayingView).
    function toEpisodeDict(dl as Dictionary) as Dictionary {
        return {
            DataKeys.E_UUID => dl.get(DL_UUID),
            DataKeys.E_TITLE => dl.get(DL_TITLE),
            DataKeys.E_PODCAST_TITLE => dl.get(DL_PODCAST_TITLE),
            DataKeys.E_PODCAST_UUID => dl.get(DL_PODCAST_UUID),
            DataKeys.E_DURATION => dl.get(DL_DURATION),
            DataKeys.E_PLAYED_UP_TO => dl.get(DL_PLAYED_UP_TO),
            DataKeys.E_PLAYING_STATUS => dl.get(DL_PLAYING_STATUS),
            DataKeys.E_STARRED => false,
            DataKeys.E_IS_DELETED => false
        } as Dictionary;
    }

    //! Get status display string for an episode.
    function getStatusText(uuid as String) as String {
        var status = getStatus(uuid);
        if (status == STATUS_DOWNLOADED) {
            return "Downloaded";
        } else if (status == STATUS_DOWNLOADING) {
            return "Downloading " + getProgress(uuid).toString() + "%";
        } else if (status == STATUS_PENDING) {
            return "In queue";
        } else if (status == STATUS_FAILED) {
            return "Failed";
        }
        return "";
    }

    // ================================================================
    // Internal persistence
    // ================================================================

    function _loadQueue() as Array<Dictionary> {
        var val = Application.Storage.getValue(KEY_DL_QUEUE);
        if (val != null && val instanceof Array) {
            return val as Array<Dictionary>;
        }
        return [] as Array<Dictionary>;
    }

    function _saveQueue(queue as Array<Dictionary>) as Void {
        Application.Storage.setValue(KEY_DL_QUEUE,
                                     queue as Application.Storage.ValueType);
    }
}
