import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

//! Configures and reconciles automatic downloads from Pocket Casts Up Next.
//! Garmin controls when media sync actually runs; this module only decides
//! which episodes should be present and when a refresh is due.
module AutoSyncManager {

    const PROPERTY_AUTO_DOWNLOAD_COUNT = "AutoDownloadCount";
    const KEY_LAST_REFRESH = "yc_auto_last_refresh";
    const KEY_LAST_ATTEMPT = "yc_auto_last_attempt";
    const KEY_MEDIA_SYNC_REQUEST = "yc_media_sync_request";
    const REFRESH_INTERVAL_SECONDS = 7200;
    const RETRY_INTERVAL_SECONDS = 1800;

    function getCount() as Number {
        try {
            var value = Application.Properties.getValue(
                PROPERTY_AUTO_DOWNLOAD_COUNT
            );
            if (value != null && value instanceof Number) {
                var count = value as Number;
                if (count == 0 || count == 1 || count == 3 || count == 5) {
                    return count;
                }
            }
        } catch (e) {
            // Use the behavior-safe default.
        }
        return 3;
    }

    function cycleCount() as Number {
        var count = getCount();
        var next = count == 0 ? 1 : (count == 1 ? 3 : (count == 3 ? 5 : 0));
        Application.Properties.setValue(
            PROPERTY_AUTO_DOWNLOAD_COUNT,
            next
        );
        onSettingsChanged();
        return next;
    }

    function onSettingsChanged() as Void {
        forceRefresh();
        applyDisabledSetting();
    }

    function applyDisabledSetting() as Void {
        if (getCount() == 0) {
            _removePendingAutomaticDownloads();
            clearMediaSyncRequest();
        }
    }

    function getLabel() as String {
        var count = getCount();
        return count == 0 ? "Off" : "Keep " + count + " from Up Next";
    }

    function isRefreshDue() as Boolean {
        if (getCount() == 0) {
            return false;
        }
        var now = Time.now().value();
        var lastRefresh = _numberStorage(KEY_LAST_REFRESH);
        if (lastRefresh > 0 &&
            now - lastRefresh < REFRESH_INTERVAL_SECONDS) {
            return false;
        }
        var lastAttempt = _numberStorage(KEY_LAST_ATTEMPT);
        return lastAttempt == 0 || now - lastAttempt >= RETRY_INTERVAL_SECONDS;
    }

    function markAttempt() as Void {
        Application.Storage.setValue(
            KEY_LAST_ATTEMPT,
            Time.now().value() as Application.Storage.ValueType
        );
    }

    function forceRefresh() as Void {
        Application.Storage.deleteValue(KEY_LAST_REFRESH);
        Application.Storage.deleteValue(KEY_LAST_ATTEMPT);
    }

    function markSuccess() as Void {
        Application.Storage.setValue(
            KEY_LAST_REFRESH,
            Time.now().value() as Application.Storage.ValueType
        );
        Application.Storage.deleteValue(KEY_LAST_ATTEMPT);
    }

    //! Reconcile a normalized DataKeys episode array.
    function reconcileQueue(episodes as Array<Dictionary>,
                            requestSync as Boolean) as Number {
        var count = getCount();
        if (count == 0) {
            return 0;
        }

        var desired = {} as Dictionary;
        var preferred = [] as Array<String>;
        var limit = episodes.size() < count ? episodes.size() : count;
        var added = 0;
        var needsMediaCleanup = false;
        for (var i = 0; i < limit; i++) {
            var episode = episodes[i] as Dictionary;
            var uuid = episode.get(DataKeys.E_UUID);
            if (uuid == null) { continue; }
            desired.put(uuid as String, true);
            preferred.add(uuid as String);
        }

        // Free stale automatic queue slots before adding the new desired set.
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var item = downloads[i] as Dictionary;
            var uuid = item.get(DownloadQueue.DL_UUID);
            var status = item.get(DownloadQueue.DL_STATUS);
            var automatic = item.get(DownloadQueue.DL_AUTO);
            if (uuid == null || status == null || automatic == null ||
                !(automatic instanceof Boolean) ||
                !(automatic as Boolean)) {
                continue;
            }
            if (!desired.hasKey(uuid as String) &&
                ((status as Number) == DownloadQueue.STATUS_PENDING ||
                 (status as Number) == DownloadQueue.STATUS_FAILED)) {
                DownloadQueue.removeFromQueue(uuid as String);
            } else if (!desired.hasKey(uuid as String) &&
                       (status as Number) ==
                           DownloadQueue.STATUS_DOWNLOADED) {
                var playingStatus = item.get(
                    DownloadQueue.DL_PLAYING_STATUS
                );
                if (playingStatus != null &&
                    (playingStatus as Number) ==
                        DataKeys.STATUS_COMPLETED) {
                    needsMediaCleanup = true;
                }
            }
        }

        for (var i = 0; i < limit; i++) {
            if (DownloadQueue.addAutoToQueue(
                    episodes[i] as Dictionary)) {
                added++;
            }
        }

        DownloadQueue.reorderByPreference(preferred);
        markSuccess();
        if ((added > 0 || needsMediaCleanup) && requestSync) {
            Application.Storage.setValue(
                KEY_MEDIA_SYNC_REQUEST,
                true as Application.Storage.ValueType
            );
        }
        return added;
    }

    //! Normalize the compact /up_next/list API response and reconcile it.
    function reconcileApiResponse(data as Dictionary,
                                  requestSync as Boolean) as Number {
        var order = data.get("order");
        var episodesMap = data.get("episodes");
        if (order == null || !(order instanceof Array) ||
            episodesMap == null || !(episodesMap instanceof Dictionary)) {
            return 0;
        }

        var normalized = [] as Array<Dictionary>;
        var ids = order as Array;
        var episodeById = episodesMap as Dictionary;
        var count = getCount();
        var limit = ids.size() < count ? ids.size() : count;
        for (var i = 0; i < limit; i++) {
            var uuid = ids[i] as String;
            var raw = episodeById.get(uuid);
            if (raw == null || !(raw instanceof Dictionary)) {
                continue;
            }
            var episode = raw as Dictionary;
            normalized.add({
                DataKeys.E_UUID => uuid,
                DataKeys.E_TITLE =>
                    _stringValue(episode.get("title"), "Episode"),
                DataKeys.E_DURATION => 0,
                DataKeys.E_PLAYED_UP_TO => 0,
                DataKeys.E_PLAYING_STATUS => DataKeys.STATUS_NOT_PLAYED,
                DataKeys.E_PODCAST_UUID =>
                    _stringValue(episode.get("podcast"), ""),
                DataKeys.E_PODCAST_TITLE =>
                    _stringValue(episode.get("podcastTitle"), ""),
                DataKeys.E_STARRED => false,
                DataKeys.E_IS_DELETED => false,
                DataKeys.E_SUMMARY => "",
                DataKeys.E_PUBLISHED => ""
            } as Dictionary);
        }
        return reconcileQueue(normalized, requestSync);
    }

    function getDesiredUuids(data as Dictionary) as Array<String> {
        var result = [] as Array<String>;
        var order = data.get("order");
        if (order == null || !(order instanceof Array)) {
            return result;
        }
        var ids = order as Array;
        var count = getCount();
        var limit = ids.size() < count ? ids.size() : count;
        for (var i = 0; i < limit; i++) {
            if (ids[i] != null && ids[i] instanceof String) {
                result.add(ids[i] as String);
            }
        }
        return result;
    }

    function hasMediaSyncRequest() as Boolean {
        var value = Application.Storage.getValue(KEY_MEDIA_SYNC_REQUEST);
        return value != null && value instanceof Boolean &&
               value as Boolean;
    }

    function clearMediaSyncRequest() as Void {
        Application.Storage.deleteValue(KEY_MEDIA_SYNC_REQUEST);
    }

    function getRefreshSummary() as String {
        if (getCount() == 0) {
            return "Auto downloads off";
        }
        var last = _numberStorage(KEY_LAST_REFRESH);
        if (last == 0) {
            return "Waiting for Up Next";
        }
        var age = Time.now().value() - last;
        if (age < 60) { return "Up Next updated now"; }
        if (age < 3600) {
            return "Up Next " + (age / 60) + "m ago";
        }
        return "Up Next " + (age / 3600) + "h ago";
    }

    function _removePendingAutomaticDownloads() as Void {
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var item = downloads[i] as Dictionary;
            var uuid = item.get(DownloadQueue.DL_UUID);
            var status = item.get(DownloadQueue.DL_STATUS);
            var automatic = item.get(DownloadQueue.DL_AUTO);
            if (uuid != null && status != null &&
                automatic != null && automatic instanceof Boolean &&
                automatic as Boolean &&
                ((status as Number) == DownloadQueue.STATUS_PENDING ||
                 (status as Number) == DownloadQueue.STATUS_FAILED)) {
                DownloadQueue.removeFromQueue(uuid as String);
            }
        }
    }

    function _numberStorage(key as String) as Number {
        var value = Application.Storage.getValue(key);
        return (value != null && value instanceof Number)
            ? value as Number : 0;
    }

    function _stringValue(value as Object?, fallback as String) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return fallback;
    }
}
