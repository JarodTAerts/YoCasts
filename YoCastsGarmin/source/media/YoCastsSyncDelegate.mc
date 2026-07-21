import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Media;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;

//! Garmin-managed media sync pipeline.
//! Pushes pending Pocket Casts playback changes first, then downloads queued
//! audio sequentially into Garmin's encrypted media cache.
class YoCastsSyncDelegate extends Communications.SyncDelegate {

    private const API_BASE = "https://api.pocketcasts.com";
    private const PROXY_BASE =
        "https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts";

    private var _accessToken as String = "";
    private var _changeSync as PocketCastsChangeSync?;

    private var _currentItem as Dictionary? = null;
    private var _currentFileSize as Number = 0;
    private var _currentContentType as String = "audio/mpeg";
    private var _completedWork as Number = 0;
    private var _totalWork as Number = 0;
    private var _failureCount as Number = 0;
    private var _cancelled as Boolean = false;

    function initialize() {
        SyncDelegate.initialize();
    }

    function isSyncNeeded() as Boolean {
        return ChangeLog.getEntryCount() > 0 ||
               DownloadQueue.getNextPending() != null ||
               AutoSyncManager.isRefreshDue() ||
               AutoSyncManager.hasMediaSyncRequest();
    }

    function onStartSync() as Void {
        AutoSyncManager.applyDisabledSetting();
        DownloadQueue.recoverInterruptedDownloads();
        if (AutoSyncManager.hasMediaSyncRequest()) {
            AutoSyncManager.clearMediaSyncRequest();
            AutoSyncManager.forceRefresh();
        }

        _changeSync = null;
        _currentItem = null;
        _completedWork = 0;
        _failureCount = 0;
        _cancelled = false;
        _totalWork = _countPendingDownloads();

        if (_totalWork == 0 && ChangeLog.getEntryCount() == 0 &&
            !AutoSyncManager.isRefreshDue()) {
            Communications.notifySyncComplete(null);
            return;
        }

        System.println("YoCasts Sync: starting " + _totalWork + " work items");
        _login();
    }

    function onStopSync() as Void {
        _cancelled = true;
        if (_changeSync != null) {
            (_changeSync as PocketCastsChangeSync).stop();
            _changeSync = null;
        }
        Communications.cancelAllRequests();

        if (_currentItem != null) {
            var uuid = (_currentItem as Dictionary).get(DownloadQueue.DL_UUID);
            if (uuid != null) {
                DownloadQueue.updateStatus(
                    uuid as String,
                    DownloadQueue.STATUS_PENDING
                );
            }
        }

        _currentItem = null;
        Communications.notifySyncComplete("Sync cancelled");
    }

    private function _login() as Void {
        var email = Application.Properties.getValue("PocketCastsEmail");
        var password = Application.Properties.getValue("PocketCastsPassword");

        if (email == null || password == null ||
            !(email instanceof String) || !(password instanceof String) ||
            (email as String).length() == 0 ||
            (password as String).length() == 0) {
            Communications.notifySyncComplete("Pocket Casts account not configured");
            return;
        }

        Communications.makeWebRequest(
            API_BASE + "/user/login_pocket_casts",
            {
                "email" => email as String,
                "password" => password as String,
                "scope" => "mobile"
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onLoginResponse)
        );
    }

    function onLoginResponse(responseCode as Number,
                             data as Dictionary or String or Null) as Void {
        if (_cancelled) { return; }

        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var token = (data as Dictionary).get("accessToken");
            if (token != null && token instanceof String) {
                _accessToken = token as String;
                _changeSync = new PocketCastsChangeSync(
                    _accessToken,
                    method(:onPendingChangesSynced)
                );
                (_changeSync as PocketCastsChangeSync).start();
                return;
            }
        }

        Communications.notifySyncComplete(
            "Pocket Casts login failed (" + responseCode + ")"
        );
    }

    function onPendingChangesSynced(failures as Number) as Void {
        if (_cancelled) { return; }
        _changeSync = null;
        _failureCount += failures;
        _refreshAutoQueue();
    }

    private function _refreshAutoQueue() as Void {
        if (!AutoSyncManager.isRefreshDue()) {
            _prepareDownloads();
            return;
        }

        AutoSyncManager.markAttempt();
        _makeAuthPost(
            "/up_next/list",
            {} as Dictionary<Object, Object>,
            method(:onAutoQueueResponse)
        );
    }

    function onAutoQueueResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        if (_cancelled) { return; }
        if (responseCode == 200 && data != null &&
            data instanceof Dictionary) {
            var desired = AutoSyncManager.getDesiredUuids(
                data as Dictionary
            );
            _cleanupCompletedAutomatic(desired);
            var added = AutoSyncManager.reconcileApiResponse(
                data as Dictionary,
                false
            );
            System.println(
                "YoCasts Sync: auto-queued " + added + " Up Next episodes"
            );
        } else {
            _failureCount++;
            SyncStatus.markFailure("Up Next refresh failed");
        }
        _prepareDownloads();
    }

    private function _cleanupCompletedAutomatic(
        desired as Array<String>
    ) as Void {
        var keep = {} as Dictionary;
        for (var i = 0; i < desired.size(); i++) {
            keep.put(desired[i], true);
        }

        PlaybackState.restore();
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var item = downloads[i] as Dictionary;
            var uuid = item.get(DownloadQueue.DL_UUID);
            var status = item.get(DownloadQueue.DL_STATUS);
            var playingStatus = item.get(DownloadQueue.DL_PLAYING_STATUS);
            var automatic = item.get(DownloadQueue.DL_AUTO);
            if (uuid == null || status == null || playingStatus == null ||
                automatic == null || !(automatic instanceof Boolean) ||
                !(automatic as Boolean) || keep.hasKey(uuid as String) ||
                (status as Number) != DownloadQueue.STATUS_DOWNLOADED ||
                (playingStatus as Number) != DataKeys.STATUS_COMPLETED ||
                PlaybackState.currentUuid.equals(uuid as String)) {
                continue;
            }

            var refId = StorageManager.getEpisodeRefId(uuid as String);
            if (refId != null) {
                try {
                    Media.deleteCachedItem(new Media.ContentRef(
                        refId,
                        Media.CONTENT_TYPE_AUDIO
                    ));
                } catch (e) {
                    System.println(
                        "YoCasts Sync: stale media delete failed for " + uuid
                    );
                    continue;
                }
            }
            StorageManager.removeDownload(uuid as String);
            DownloadQueue.removeFromQueue(uuid as String);
            CacheManager.removePlaybackPosition(uuid as String);
        }
    }

    private function _prepareDownloads() as Void {
        _completedWork = 0;
        _totalWork = _countPendingDownloads();
        if (_totalWork == 0) {
            _finish();
            return;
        }
        _downloadNext();
    }

    // ------------------------------------------------------------------------
    // Audio download
    // ------------------------------------------------------------------------

    private function _downloadNext() as Void {
        if (_cancelled) { return; }

        var nextItem = DownloadQueue.getNextPending();
        if (nextItem == null) {
            _finish();
            return;
        }

        _currentItem = nextItem;
        _currentFileSize = 0;
        _currentContentType = "audio/mpeg";

        var uuid = nextItem.get(DownloadQueue.DL_UUID) as String;
        DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_DOWNLOADING);

        Communications.makeWebRequest(
            PROXY_BASE + "/episode/" + uuid + "/audio-info",
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onAudioInfoResponse)
        );
    }

    function onAudioInfoResponse(responseCode as Number,
                                 data as Dictionary or String or Null) as Void {
        if (_cancelled || _currentItem == null) { return; }

        if (responseCode != 200 || data == null ||
            !(data instanceof Dictionary)) {
            _failCurrent("Audio metadata failed (" + responseCode + ")");
            return;
        }

        var info = data as Dictionary;
        var audioUrl = info.get("audioUrl");
        if (audioUrl == null || !(audioUrl instanceof String)) {
            _failCurrent("Episode has no audio URL");
            return;
        }

        _currentFileSize = _numberValue(info.get("fileSize"), 0);
        _currentContentType =
            _stringOr(info.get("contentType"), "audio/mpeg");
        var currentUuid = (_currentItem as Dictionary).get(
            DownloadQueue.DL_UUID
        );
        if (currentUuid != null) {
            DownloadQueue.updateMetadata(
                currentUuid as String,
                _stringOr(info.get("title"), ""),
                _stringOr(info.get("podcastTitle"), ""),
                _stringOr(info.get("podcastUuid"), ""),
                _numberValue(info.get("duration"), 0),
                _stringOr(info.get("summary"), ""),
                _stringOr(info.get("published"), "")
            );
        }

        if (!_hasMediaCapacity(_currentFileSize)) {
            _failCurrent("Not enough media storage");
            return;
        }

        var encoding = _encodingFor(_currentContentType, audioUrl as String);
        if (encoding == Media.ENCODING_INVALID) {
            _failCurrent("Unsupported audio format");
            return;
        }

        Communications.makeWebRequest(
            audioUrl as String,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
                :mediaEncoding => encoding,
                :fileDownloadProgressCallback => method(:onDownloadProgress)
            },
            method(:onAudioDownloaded)
        );
    }

    function onDownloadProgress(totalBytesTransferred as Number,
                                fileSize as Number?) as Void {
        if (_cancelled || _currentItem == null) { return; }

        var percent = 0;
        if (fileSize != null && (fileSize as Number) > 0) {
            percent = totalBytesTransferred * 100 / (fileSize as Number);
            if (percent > 99) { percent = 99; }
        }

        var uuid = (_currentItem as Dictionary).get(DownloadQueue.DL_UUID);
        if (uuid != null) {
            DownloadQueue.updateProgress(uuid as String, percent);
        }
        _notifyProgress(percent);
    }

    //! Current Monkey C's generic callback type omits Media.ContentRef even
    //! though AUDIO responses return one. Disable type checking only for this
    //! SDK boundary and follow Garmin's official data.getId() pattern.
    (:typecheck(false))
    function onAudioDownloaded(
        responseCode as Number,
        data as Dictionary or String or PersistedContent.Iterator or Null
    ) as Void {
        if (_cancelled || _currentItem == null) { return; }

        if (responseCode != 200 || data == null) {
            _failCurrent("Audio download failed (" + responseCode + ")");
            return;
        }

        try {
            var refId = data.getId();
            if (refId == null) {
                _failCurrent("Media response had no content ID");
                return;
            }
            var item = _currentItem as Dictionary;
            var uuid = item.get(DownloadQueue.DL_UUID) as String;
            var podcastUuid =
                _stringValue(item.get(DownloadQueue.DL_PODCAST_UUID));

            StorageManager.markDownloaded(
                uuid,
                podcastUuid,
                refId as Application.Storage.ValueType,
                _currentFileSize,
                _currentContentType
            );
            DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_DOWNLOADED);

            _currentItem = null;
            _completedWork++;
            _notifyProgress(0);
            _downloadNext();
        } catch (e) {
            _failCurrent("Invalid media response");
        }
    }

    private function _failCurrent(message as String) as Void {
        if (_currentItem != null) {
            var uuid = (_currentItem as Dictionary).get(DownloadQueue.DL_UUID);
            if (uuid != null) {
                DownloadQueue.updateStatus(
                    uuid as String,
                    DownloadQueue.STATUS_FAILED
                );
            }
        }
        System.println("YoCasts Sync: " + message);
        _failureCount++;
        _completedWork++;
        _currentItem = null;
        _notifyProgress(0);
        _downloadNext();
    }

    private function _finish() as Void {
        Communications.notifySyncProgress(100);
        if (_failureCount > 0) {
            SyncStatus.markFailure(
                "Media sync completed with errors"
            );
            Communications.notifySyncComplete(
                "Sync completed with " + _failureCount + " error(s)"
            );
        } else {
            SyncStatus.markSuccess();
            Communications.notifySyncComplete(null);
        }
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    private function _makeAuthPost(
        path as String,
        body as Dictionary<Object, Object>,
        callback as Method(responseCode as Number,
                           data as Dictionary or String or Null) as Void
    ) as Void {
        Communications.makeWebRequest(
            PROXY_BASE + path,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            callback
        );
    }

    private function _hasMediaCapacity(fileSize as Number) as Boolean {
        if (fileSize <= 0) {
            return true;
        }
        try {
            var stats = Media.getCacheStatistics();
            var available = stats.capacity - stats.size;
            return fileSize.toLong() <= available;
        } catch (e) {
            System.println("YoCasts Sync: media capacity unavailable");
            return true;
        }
    }

    private function _encodingFor(contentType as String,
                                  url as String) as Media.Encoding {
        var type = contentType.toLower();
        var lowerUrl = url.toLower();

        if (type.equals("audio/mp4") || type.equals("audio/m4a") ||
            type.equals("audio/x-m4a") || lowerUrl.find(".m4a") != null ||
            lowerUrl.find(".m4b") != null) {
            return Media.ENCODING_M4A;
        }
        if (type.equals("audio/aac") || type.equals("audio/aacp") ||
            lowerUrl.find(".aac") != null ||
            lowerUrl.find(".adts") != null) {
            return Media.ENCODING_ADTS;
        }
        if (type.equals("audio/wav") || type.equals("audio/x-wav") ||
            lowerUrl.find(".wav") != null) {
            return Media.ENCODING_WAV;
        }
        if (type.equals("audio/mpeg") || type.equals("audio/mp3") ||
            lowerUrl.find(".mp3") != null) {
            return Media.ENCODING_MP3;
        }
        return Media.ENCODING_INVALID;
    }

    private function _countPendingDownloads() as Number {
        var downloads = DownloadQueue.getDownloads();
        var count = 0;
        for (var i = 0; i < downloads.size(); i++) {
            var status = (downloads[i] as Dictionary).get(
                DownloadQueue.DL_STATUS
            );
            if (status != null &&
                (status as Number) == DownloadQueue.STATUS_PENDING) {
                count++;
            }
        }
        return count;
    }

    private function _notifyProgress(filePercent as Number) as Void {
        if (_totalWork <= 0) { return; }
        var progress =
            (_completedWork * 100 + filePercent) / _totalWork;
        if (progress > 99 && _completedWork < _totalWork) {
            progress = 99;
        }
        Communications.notifySyncProgress(progress);
    }

    private function _stringValue(value as Object?) as String {
        return _stringOr(value, "");
    }

    private function _stringOr(value as Object?, fallback as String) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return fallback;
    }

    private function _numberValue(value as Object?, fallback as Number)
                                  as Number {
        if (value != null && value instanceof Number) {
            return value as Number;
        }
        return fallback;
    }

}
