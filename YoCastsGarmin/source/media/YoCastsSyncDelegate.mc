import Toybox.Media;
import Toybox.Communications;
import Toybox.Application;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.PersistedContent;

//! System-triggered sync delegate for downloading podcast episodes.
//! Runs in background service context (64 KB memory limit).
//! Downloads episodes sequentially from DownloadQueue.
//!
//! Flow per sync cycle:
//!   1. Auth — login to PocketCasts (or use cached token)
//!   2. For each pending episode:
//!      a. GET AudioInfo from proxy (gets CDN URL + file size)
//!      b. Download audio via makeWebRequest(HTTP_RESPONSE_CONTENT_TYPE_AUDIO)
//!      c. Store ContentRef in StorageManager, mark DOWNLOADED in queue
//!   3. notifySyncComplete when all done or on error
//!
//! The system calls this when the watch is on the charger + connected to Wi-Fi.
class YoCastsSyncDelegate extends Communications.SyncDelegate {

    private var _isSyncing as Boolean = false;
    private var _currentItem as Dictionary? = null;
    private var _downloadedCount as Number = 0;
    private var _totalCount as Number = 0;
    private var _accessToken as String = "";

    // Persistent token storage keys (shared with foreground for efficiency)
    private const KEY_TOKEN = "yc_bg_token";
    private const KEY_TOKEN_EXPIRES = "yc_bg_token_exp";

    // API endpoints
    private const PROXY_BASE = "https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts";
    private const LOGIN_URL = "https://api.pocketcasts.com/user/login_pocket_casts";

    function initialize() {
        SyncDelegate.initialize();
    }

    //! System asks: do we need to sync?
    function isSyncNeeded() as Boolean {
        var needed = (DownloadQueue.getNextPending() != null);
        System.println("YoCasts Sync: isSyncNeeded=" + needed);
        return needed;
    }

    //! System triggers sync — authenticate then begin sequential downloads.
    function onStartSync() as Void {
        System.println("YoCasts Sync: onStartSync — freeMemory=" +
            System.getSystemStats().freeMemory);

        _isSyncing = true;
        _downloadedCount = 0;
        _totalCount = _countPending();

        if (_totalCount == 0) {
            System.println("YoCasts Sync: nothing to download");
            _isSyncing = false;
            Media.notifySyncComplete(null);
            return;
        }

        // Try cached token first
        var cachedToken = Application.Storage.getValue(KEY_TOKEN);
        var cachedExpiry = Application.Storage.getValue(KEY_TOKEN_EXPIRES);
        if (cachedToken != null && cachedExpiry != null &&
            cachedExpiry instanceof Number &&
            Time.now().value() < (cachedExpiry as Number) - 300) {
            _accessToken = cachedToken as String;
            System.println("YoCasts Sync: using cached token");
            _downloadNext();
        } else {
            _doLogin();
        }
    }

    //! User cancels sync — clean abort, preserve partial state.
    //! In-progress downloads reset to PENDING so they retry next cycle.
    function onStopSync() as Void {
        System.println("YoCasts Sync: onStopSync");
        Communications.cancelAllRequests();

        if (_currentItem != null) {
            var uuid = (_currentItem as Dictionary).get(DownloadQueue.DL_UUID);
            if (uuid != null) {
                DownloadQueue.updateStatus(uuid as String, DownloadQueue.STATUS_PENDING);
            }
        }

        _currentItem = null;
        _isSyncing = false;
        Media.notifySyncComplete(null);
    }

    //! Return whether sync is in progress.
    function isSyncing() as Boolean {
        return _isSyncing;
    }

    // ================================================================
    // Auth — Login to PocketCasts
    // ================================================================

    private function _doLogin() as Void {
        var email = "";
        var password = "";
        try {
            var e = Application.Properties.getValue("PocketCastsEmail");
            if (e != null) { email = e as String; }
            var p = Application.Properties.getValue("PocketCastsPassword");
            if (p != null) { password = p as String; }
        } catch (ex) {
            System.println("YoCasts Sync: cannot read credentials");
        }

        if (email.equals("") || password.equals("")) {
            System.println("YoCasts Sync: no credentials configured, aborting");
            _isSyncing = false;
            Media.notifySyncComplete("No credentials");
            return;
        }

        System.println("YoCasts Sync: logging in...");
        Communications.makeWebRequest(
            LOGIN_URL,
            { "email" => email, "password" => password, "scope" => "webplayer" },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => { "Content-Type" => "application/json" },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onLoginResponse)
        );
    }

    //! @hide
    function onLoginResponse(responseCode as Number,
                              data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var at = dict.get("accessToken");
            var ei = dict.get("expiresIn");
            if (at != null && ei != null) {
                _accessToken = at as String;
                var expiresAt = Time.now().value() + (ei as Number);
                // Cache token for future sync cycles
                Application.Storage.setValue(KEY_TOKEN,
                    _accessToken as Application.Storage.ValueType);
                Application.Storage.setValue(KEY_TOKEN_EXPIRES,
                    expiresAt as Application.Storage.ValueType);
                System.println("YoCasts Sync: login success");
                _downloadNext();
                return;
            }
        }

        System.println("YoCasts Sync: login failed (code=" + responseCode + ")");
        _isSyncing = false;
        Media.notifySyncComplete("Login failed");
    }

    // ================================================================
    // Download Pipeline — sequential, one episode at a time
    // ================================================================

    //! Pick the next pending episode and start the AudioInfo → Download chain.
    private function _downloadNext() as Void {
        if (!_isSyncing) { return; }

        var nextItem = DownloadQueue.getNextPending();
        if (nextItem == null) {
            System.println("YoCasts Sync: all done (" +
                _downloadedCount + " downloaded)");
            _isSyncing = false;
            Media.notifySyncComplete(null);
            return;
        }

        _currentItem = nextItem;
        var uuid = nextItem.get(DownloadQueue.DL_UUID) as String;

        // Report progress to system sync UI
        if (_totalCount > 0) {
            Media.notifySyncProgress(_downloadedCount * 100 / _totalCount);
        }

        DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_DOWNLOADING);

        // Step 1: Fetch audio URL + metadata from proxy
        System.println("YoCasts Sync: audioinfo for " + uuid);
        var url = PROXY_BASE + "/episode/" + uuid + "/audio-info";
        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "Authorization" => "Bearer " + _accessToken },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onAudioInfoResponse)
        );
    }

    //! @hide — AudioInfo proxy response callback.
    //! Expected: { audioUrl, fileSize, contentType, requiresAuth, ... }
    function onAudioInfoResponse(responseCode as Number,
                                  data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        if (_currentItem == null) { return; }
        var uuid = (_currentItem as Dictionary).get(DownloadQueue.DL_UUID) as String;

        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            System.println("YoCasts Sync: audioinfo FAIL uuid=" + uuid +
                " code=" + responseCode);
            DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_FAILED);
            _currentItem = null;
            _downloadNext();
            return;
        }

        var info = data as Dictionary;
        var audioUrl = info.get("audioUrl");

        if (audioUrl == null) {
            System.println("YoCasts Sync: no audioUrl for " + uuid);
            DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_FAILED);
            _currentItem = null;
            _downloadNext();
            return;
        }

        // Cache file metadata on the current item for the download callback
        var fileSize = info.get("fileSize");
        var contentType = info.get("contentType");
        if (fileSize != null) {
            (_currentItem as Dictionary).put("_fileSize", fileSize);
        }
        if (contentType != null) {
            (_currentItem as Dictionary).put("_contentType", contentType);
        }

        // Step 2: Download audio from CDN — no auth needed
        System.println("YoCasts Sync: downloading " + uuid);
        Communications.makeWebRequest(
            audioUrl as String,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO
            },
            method(:onAudioDownloadResponse)
        );
    }

    //! @hide — Audio download callback.
    //! On success, data is a PersistedContent.Iterator with the cached audio.
    function onAudioDownloadResponse(responseCode as Number,
                                      data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        if (_currentItem == null) { return; }
        var item = _currentItem as Dictionary;
        var uuid = item.get(DownloadQueue.DL_UUID) as String;
        var podUuid = item.get(DownloadQueue.DL_PODCAST_UUID);

        if (responseCode == 200 && data != null &&
            data instanceof PersistedContent.Iterator) {
            var iter = data as PersistedContent.Iterator;
            var contentRef = iter.next();

            if (contentRef != null) {
                var refId = contentRef.getId().toString();

                // Get file metadata cached from AudioInfo response
                var fSize = item.get("_fileSize");
                var fs = (fSize != null && fSize instanceof Number) ?
                         fSize as Number : 0;
                var ct = item.get("_contentType");
                var contentType = (ct != null) ? ct as String : "audio/mpeg";

                StorageManager.markDownloaded(
                    uuid,
                    (podUuid != null ? podUuid as String : ""),
                    refId,
                    fs,
                    contentType
                );

                DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_DOWNLOADED);
                _downloadedCount = _downloadedCount + 1;
                System.println("YoCasts Sync: OK uuid=" + uuid +
                    " refId=" + refId);
            } else {
                System.println("YoCasts Sync: FAIL uuid=" + uuid +
                    " — no content ref in iterator");
                DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_FAILED);
            }
        } else {
            System.println("YoCasts Sync: FAIL uuid=" + uuid +
                " code=" + responseCode);
            DownloadQueue.updateStatus(uuid, DownloadQueue.STATUS_FAILED);
        }

        _currentItem = null;
        _downloadNext();
    }

    // ================================================================
    // Helpers
    // ================================================================

    //! Count pending + retryable downloads for progress tracking.
    private function _countPending() as Number {
        var downloads = DownloadQueue.getDownloads();
        var count = 0;
        for (var i = 0; i < downloads.size(); i++) {
            var dl = downloads[i] as Dictionary;
            var status = dl.get(DownloadQueue.DL_STATUS);
            if (status != null) {
                var s = status as Number;
                if (s == DownloadQueue.STATUS_PENDING) {
                    count = count + 1;
                } else if (s == DownloadQueue.STATUS_FAILED) {
                    var ec = dl.get("errorCount");
                    if (ec == null || !(ec instanceof Number) ||
                        (ec as Number) < 3) {
                        count = count + 1;
                    }
                }
            }
        }
        return count;
    }
}
