import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

//! Tracks downloaded episode metadata and available storage.
//! Uses Application.Storage for metadata persistence — no direct Media
//! module references so this works in both simulator and device builds.
//!
//! The actual audio files are managed by the Media module (device only).
//! StorageManager tracks the mapping: episodeUuid → refId (ContentRef id)
//! so other modules can look up downloaded content without importing Media.
module StorageManager {

    // ---- Storage keys ----
    const KEY_DOWNLOADS = "yc_downloads";
    const KEY_SELECTED_EPISODE = "yc_selected_episode";

    //! Media capacity is only available through Toybox.Media in the device
    //! build. Shared code must treat -1 as unknown rather than confusing RAM
    //! with disk capacity.
    function getAvailableSpace() as Number {
        return -1;
    }

    //! Get a list of all downloaded episodes with their metadata.
    //! Returns Array of Dictionaries with keys: episodeUuid, podcastUuid,
    //! refId, downloadedAt, fileSize, contentType.
    function getDownloadedEpisodes() as Array<Dictionary> {
        var downloads = _loadDownloads();
        var result = [] as Array<Dictionary>;
        var keys = downloads.keys();
        for (var i = 0; i < keys.size(); i++) {
            var uuid = keys[i] as String;
            var entry = downloads.get(uuid);
            if (entry != null && entry instanceof Dictionary) {
                var d = entry as Dictionary;
                d.put("episodeUuid", uuid as Application.Storage.ValueType);
                result.add(d);
            }
        }
        return result;
    }

    //! Check if a specific episode is downloaded.
    function isEpisodeDownloaded(uuid as String) as Boolean {
        var downloads = _loadDownloads();
        return downloads.hasKey(uuid);
    }

    //! Get the ContentRef ID for a downloaded episode (for Media module playback).
    //! Returns null if the episode is not downloaded.
    function getEpisodeRefId(
        uuid as String
    ) as Application.Storage.ValueType? {
        var downloads = _loadDownloads();
        var entry = downloads.get(uuid);
        if (entry != null && entry instanceof Dictionary) {
            var d = entry as Dictionary;
            var refId = d.get("refId");
            if (refId != null) {
                return refId as Application.Storage.ValueType;
            }
        }
        return null;
    }

    //! Get the podcast UUID for a downloaded episode.
    function getEpisodePodcastUuid(uuid as String) as String? {
        var downloads = _loadDownloads();
        var entry = downloads.get(uuid);
        if (entry != null && entry instanceof Dictionary) {
            var d = entry as Dictionary;
            var podUuid = d.get("podcastUuid");
            if (podUuid != null) {
                return podUuid as String;
            }
        }
        return null;
    }

    //! Return the complete metadata entry for one downloaded episode.
    function getDownload(uuid as String) as Dictionary? {
        var entry = _loadDownloads().get(uuid);
        if (entry != null && entry instanceof Dictionary) {
            return entry as Dictionary;
        }
        return null;
    }

    //! Record a completed download. Called after an audio file is
    //! successfully saved to the Media cache (device) or after a
    //! simulated download (simulator testing).
    //! @param uuid Episode UUID
    //! @param podcastUuid Parent podcast UUID
    //! @param refId ContentRef ID assigned by the Media module (or test ID)
    //! @param fileSize Size of the downloaded file in bytes (0 if unknown)
    //! @param contentType MIME type of the audio file (e.g., "audio/mpeg")
    function markDownloaded(uuid as String, podcastUuid as String,
                            refId as Application.Storage.ValueType,
                            fileSize as Number,
                            contentType as String) as Void {
        var downloads = _loadDownloads();
        downloads.put(uuid, {
            "podcastUuid" => podcastUuid as Application.Storage.ValueType,
            "refId" => refId,
            "downloadedAt" => Time.now().value() as Application.Storage.ValueType,
            "fileSize" => fileSize as Application.Storage.ValueType,
            "contentType" => contentType as Application.Storage.ValueType
        } as Dictionary);
        _saveDownloads(downloads);
        System.println("YoCasts Storage: marked downloaded " + uuid + " (refId=" + refId + ")");
    }

    //! Remove a download record. Call this when deleting the audio file
    //! from Media storage or when cleaning up stale entries.
    function removeDownload(uuid as String) as Void {
        var downloads = _loadDownloads();
        if (downloads.hasKey(uuid)) {
            downloads.remove(uuid);
            _saveDownloads(downloads);
            System.println("YoCasts Storage: removed download record " + uuid);
        }
        var selected = getSelectedEpisode();
        if (selected != null && (selected as String).equals(uuid)) {
            Application.Storage.deleteValue(KEY_SELECTED_EPISODE);
        }
        if (PlaybackState.currentUuid.equals(uuid)) {
            PlaybackState.clear();
        }
    }

    //! Persist the episode that playback configuration selected.
    function setSelectedEpisode(uuid as String) as Void {
        Application.Storage.setValue(
            KEY_SELECTED_EPISODE,
            uuid as Application.Storage.ValueType
        );
    }

    function getSelectedEpisode() as String? {
        var value = Application.Storage.getValue(KEY_SELECTED_EPISODE);
        if (value != null && value instanceof String) {
            return value as String;
        }
        return null;
    }

    //! Get the number of downloaded episodes.
    function getDownloadCount() as Number {
        return _loadDownloads().size();
    }

    //! Get total size of all downloaded episodes in bytes.
    function getTotalDownloadSize() as Number {
        var downloads = _loadDownloads();
        var total = 0;
        var keys = downloads.keys();
        for (var i = 0; i < keys.size(); i++) {
            var entry = downloads.get(keys[i]);
            if (entry != null && entry instanceof Dictionary) {
                var d = entry as Dictionary;
                var size = d.get("fileSize");
                if (size != null && size instanceof Number) {
                    total += size as Number;
                }
            }
        }
        return total;
    }

    //! Clear all download records. Use with caution — only for full reset.
    function clearDownloads() as Void {
        Application.Storage.deleteValue(KEY_DOWNLOADS);
        Application.Storage.deleteValue(KEY_SELECTED_EPISODE);
    }

    // ================================================================
    // Internal persistence
    // ================================================================

    function _loadDownloads() as Dictionary {
        var val = Application.Storage.getValue(KEY_DOWNLOADS);
        if (val != null && val instanceof Dictionary) {
            return val as Dictionary;
        }
        return {} as Dictionary;
    }

    function _saveDownloads(downloads as Dictionary) as Void {
        Application.Storage.setValue(KEY_DOWNLOADS,
                                     downloads as Application.Storage.ValueType);
    }
}
