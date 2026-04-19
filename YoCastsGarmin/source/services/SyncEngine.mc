import Toybox.Lang;
import Toybox.Communications;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.System;

//! 7-step push-then-pull sync engine for reconciling local offline
//! changes with the PocketCasts server.
//!
//! Steps:
//!   1. Auth check — verify token, refresh/re-login if needed
//!   2. Read changelog — snapshot pending local changes
//!   3. Fetch server state — /user/in_progress bulk + individual gaps
//!   4. Reconcile — "furthest wins" for position, hierarchy for status
//!   5. Push changes — sequential POST /sync/update_episode per episode
//!   6. Refresh caches — trigger service.fetchAll()
//!   7. Cleanup — selectively clear confirmed changelog entries
//!
//! Snapshots the changelog at step 2 so PositionTracker writes during
//! sync are preserved and pushed on the next cycle.
class SyncEngine {

    // ---- State machine steps ----
    const STEP_IDLE = 0;
    const STEP_AUTH = 1;
    const STEP_READ_CHANGELOG = 2;
    const STEP_FETCH_SERVER = 3;
    const STEP_RECONCILE = 4;
    const STEP_PUSH = 5;
    const STEP_REFRESH = 6;
    const STEP_CLEANUP = 7;

    // ---- Runtime state ----
    private var _syncing as Boolean = false;
    private var _currentStep as Number = 0;

    // ---- Auth ----
    private var _accessToken as String = "";
    private var _tokenExpiresAt as Number = 0;

    // ---- Step 2: changelog snapshot & entry IDs ----
    private var _changelogSnapshot as Array<Dictionary> = [] as Array<Dictionary>;
    private var _snapshotIds as Dictionary = {} as Dictionary;

    // ---- Step 3: server episode state ----
    private var _serverEpisodes as Dictionary = {} as Dictionary;
    private var _affectedUuids as Array<String> = [] as Array<String>;
    private var _fetchIndex as Number = 0;

    // ---- Step 5: push queue ----
    private var _pushQueue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _pushIndex as Number = 0;
    private var _pushFailedUuids as Dictionary = {} as Dictionary;

    // ---- Service reference for cache refresh ----
    private var _service as IPodcastService?;

    // ---- API endpoints (same as PocketCastsPodcastService) ----
    private const API_BASE = "https://api.pocketcasts.com";
    private const PROXY_BASE = "https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts";
    private const TOKEN_REFRESH_BUFFER = 300;

    function initialize(service as IPodcastService?) {
        _service = service;
    }

    //! Start a sync cycle. No-op if already syncing, offline, or no changes.
    function startSync() as Void {
        if (_syncing) {
            System.println("YoCasts Sync: already syncing, skipping");
            return;
        }
        if (!ConnectivityManager.isConnected()) {
            System.println("YoCasts Sync: offline, skipping");
            return;
        }
        if (ChangeLog.getEntryCount() == 0) {
            System.println("YoCasts Sync: no changelog entries, skipping");
            return;
        }

        System.println("YoCasts Sync: starting sync cycle");
        _syncing = true;
        _currentStep = STEP_AUTH;
        _stepAuth();
    }

    //! Returns true if a sync is in progress.
    function isSyncing() as Boolean {
        return _syncing;
    }

    //! Returns the current step for debug/UI display.
    function getCurrentStep() as Number {
        return _currentStep;
    }

    // ================================================================
    // Step 1: Auth — verify token, refresh or re-login if needed
    // ================================================================

    private function _stepAuth() as Void {
        _currentStep = STEP_AUTH;
        System.println("YoCasts Sync: step 1 — auth check");

        // Skip login if we already have a valid token
        if (_accessToken.length() > 0 && !_isTokenExpiringSoon()) {
            System.println("YoCasts Sync: token valid");
            _stepReadChangelog();
            return;
        }

        try {
            var email = Application.Properties.getValue("PocketCastsEmail");
            var password = Application.Properties.getValue("PocketCastsPassword");
            if (email == null || password == null ||
                (email as String).length() == 0 ||
                (password as String).length() == 0) {
                System.println("YoCasts Sync: no credentials, aborting");
                _abortSync();
                return;
            }

            Communications.makeWebRequest(
                API_BASE + "/user/login_pocket_casts",
                {
                    "email" => email as String,
                    "password" => password as String,
                    "scope" => "webplayer"
                },
                {
                    :method => Communications.HTTP_REQUEST_METHOD_POST,
                    :headers => {
                        "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                    },
                    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                },
                method(:onAuthResponse)
            );
        } catch (e) {
            System.println("YoCasts Sync: auth exception, aborting");
            _abortSync();
        }
    }

    //! @hide (public for makeWebRequest callback)
    function onAuthResponse(responseCode as Number,
                            data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var at = dict.get("accessToken");
            var ei = dict.get("expiresIn");
            if (at != null && at instanceof String && ei != null) {
                _accessToken = at as String;
                _tokenExpiresAt = Time.now().value() + (ei as Number);
                System.println("YoCasts Sync: auth OK");
                _stepReadChangelog();
                return;
            }
        }
        System.println("YoCasts Sync: auth FAILED — HTTP " + responseCode);
        _abortSync();
    }

    // ================================================================
    // Step 2: Snapshot changelog (isolates from PositionTracker writes)
    // ================================================================

    private function _stepReadChangelog() as Void {
        _currentStep = STEP_READ_CHANGELOG;
        System.println("YoCasts Sync: step 2 — snapshot changelog");

        var entries = ChangeLog.getEntries();
        _changelogSnapshot = [] as Array<Dictionary>;
        _snapshotIds = {} as Dictionary;

        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            _changelogSnapshot.add(entry);
            var id = entry.get("id");
            if (id != null) {
                _snapshotIds.put(id, true);
            }
        }

        if (_changelogSnapshot.size() == 0) {
            System.println("YoCasts Sync: changelog empty after snapshot, done");
            _stepRefresh();
            return;
        }

        System.println("YoCasts Sync: " + _changelogSnapshot.size() + " entries to process");

        // Build unique affected episode UUIDs
        _affectedUuids = [] as Array<String>;
        for (var i = 0; i < _changelogSnapshot.size(); i++) {
            var entry = _changelogSnapshot[i] as Dictionary;
            var uuid = entry.get("episodeUuid");
            if (uuid != null && uuid instanceof String) {
                if (!_arrayContains(_affectedUuids, uuid as String)) {
                    _affectedUuids.add(uuid as String);
                }
            }
        }

        _stepFetchServer();
    }

    // ================================================================
    // Step 3: Fetch server state (hybrid: bulk in_progress + gaps)
    // ================================================================

    private function _stepFetchServer() as Void {
        _currentStep = STEP_FETCH_SERVER;
        _serverEpisodes = {} as Dictionary;
        System.println("YoCasts Sync: step 3 — fetch server state");

        _makeAuthPost(
            "/user/in_progress",
            {} as Dictionary<Object, Object>,
            method(:onInProgressResponse)
        );
    }

    //! @hide
    function onInProgressResponse(responseCode as Number,
                                  data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var episodes = dict.get("episodes");
            if (episodes != null && episodes instanceof Array) {
                var arr = episodes as Array;
                for (var i = 0; i < arr.size(); i++) {
                    if (arr[i] != null && arr[i] instanceof Dictionary) {
                        var ep = arr[i] as Dictionary;
                        var uuid = ep.get("uuid");
                        if (uuid != null && uuid instanceof String) {
                            _serverEpisodes.put(uuid as String, ep);
                        }
                    }
                }
            }
            System.println("YoCasts Sync: in_progress returned " +
                           _serverEpisodes.size() + " episodes");
        } else {
            System.println("YoCasts Sync: in_progress failed — HTTP " +
                           responseCode);
        }

        // Fetch individual episodes not covered by bulk response
        _fetchIndex = 0;
        _fetchNextGapEpisode();
    }

    //! Fetch server state for changelog episodes missing from in_progress.
    private function _fetchNextGapEpisode() as Void {
        while (_fetchIndex < _affectedUuids.size()) {
            var uuid = _affectedUuids[_fetchIndex];
            if (!_serverEpisodes.hasKey(uuid)) {
                System.println("YoCasts Sync: fetching gap episode " + uuid);
                _makeAuthPost(
                    "/user/episode",
                    { "uuid" => uuid } as Dictionary<Object, Object>,
                    method(:onGapEpisodeResponse)
                );
                return;
            }
            _fetchIndex++;
        }

        System.println("YoCasts Sync: server state complete");
        _stepReconcile();
    }

    //! @hide
    function onGapEpisodeResponse(responseCode as Number,
                                  data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var d = data as Dictionary;
            var uuid = d.get("uuid");
            if (uuid != null && uuid instanceof String) {
                _serverEpisodes.put(uuid as String, d);
            }
        } else {
            System.println("YoCasts Sync: gap fetch failed — HTTP " +
                           responseCode);
        }
        _fetchIndex++;
        _fetchNextGapEpisode();
    }

    // ================================================================
    // Step 4: Reconcile — aggregate local state, compare with server
    // ================================================================

    private function _stepReconcile() as Void {
        _currentStep = STEP_RECONCILE;
        System.println("YoCasts Sync: step 4 — reconcile");

        // Aggregate local state per episode from changelog entries
        var localStates = {} as Dictionary;

        for (var i = 0; i < _changelogSnapshot.size(); i++) {
            var entry = _changelogSnapshot[i] as Dictionary;
            var entryType = entry.get("type");
            if (entryType == null) { continue; }
            var typeStr = entryType as String;

            // Only process position/status/completion changes
            if (!typeStr.equals(ChangeLog.TYPE_POSITION_UPDATE) &&
                !typeStr.equals(ChangeLog.TYPE_EPISODE_COMPLETED) &&
                !typeStr.equals(ChangeLog.TYPE_STATUS_CHANGE)) {
                continue;
            }

            var uuid = entry.get("episodeUuid");
            if (uuid == null || !(uuid instanceof String)) { continue; }
            var uuidStr = uuid as String;

            var entryData = entry.get("data");
            if (entryData == null || !(entryData instanceof Dictionary)) { continue; }
            var eData = entryData as Dictionary;

            var pos = _numOr(eData.get("position"), 0);
            var status = _numOr(eData.get("status"), DataKeys.STATUS_NOT_PLAYED);
            var dur = _numOr(eData.get("duration"), 0);
            var podUuid = _strOr(entry.get("podcastUuid"), "");

            if (localStates.hasKey(uuidStr)) {
                // Merge: keep highest position, highest status, max duration
                var ex = localStates.get(uuidStr) as Dictionary;
                var exPos = ex.get("position") as Number;
                var exStatus = ex.get("status") as Number;
                var exDur = ex.get("duration") as Number;
                ex.put("position", pos > exPos ? pos : exPos);
                ex.put("status", reconcileStatus(status, exStatus));
                ex.put("duration", dur > exDur ? dur : exDur);
            } else {
                localStates.put(uuidStr, {
                    "position" => pos,
                    "status" => status,
                    "duration" => dur,
                    "podcastUuid" => podUuid
                } as Dictionary);
            }
        }

        // Reconcile each episode vs server state, build push queue
        _pushQueue = [] as Array<Dictionary>;
        var uuids = localStates.keys();

        for (var i = 0; i < uuids.size(); i++) {
            var uuidStr = uuids[i] as String;
            var local = localStates.get(uuidStr) as Dictionary;
            var lPos = local.get("position") as Number;
            var lStatus = local.get("status") as Number;
            var lDur = local.get("duration") as Number;
            var podUuid = _strOr(local.get("podcastUuid"), "");

            // Server state for this episode
            var sPos = 0;
            var sStatus = DataKeys.STATUS_NOT_PLAYED;
            var sDur = lDur;

            var serverEp = _serverEpisodes.get(uuidStr);
            if (serverEp != null && serverEp instanceof Dictionary) {
                var sep = serverEp as Dictionary;
                sPos = _numOr(sep.get("playedUpTo"), 0);
                sStatus = _numOr(sep.get("playingStatus"),
                                 DataKeys.STATUS_NOT_PLAYED);
                sDur = _numOr(sep.get("duration"), lDur);
            }

            var resolvedStatus = reconcileStatus(lStatus, sStatus);
            var resolvedPos = reconcilePosition(lPos, sPos);

            // Completed episodes: position should be >= duration
            if (resolvedStatus == DataKeys.STATUS_COMPLETED) {
                var maxDur = lDur > sDur ? lDur : sDur;
                if (resolvedPos < maxDur) {
                    resolvedPos = maxDur;
                }
            }

            // Only push if resolved differs from server
            if (resolvedPos != sPos || resolvedStatus != sStatus) {
                var durToSend = lDur > sDur ? lDur : sDur;
                _pushQueue.add({
                    "uuid" => uuidStr,
                    "podcast" => podUuid,
                    "position" => resolvedPos,
                    "status" => resolvedStatus,
                    "duration" => durToSend
                } as Dictionary);
            }

            // Update local position cache with resolved values
            var cacheDur = lDur > sDur ? lDur : sDur;
            CacheManager.savePlaybackPosition(uuidStr, resolvedPos, cacheDur);
        }

        // Free step 3 memory
        _serverEpisodes = {} as Dictionary;
        _affectedUuids = [] as Array<String>;

        System.println("YoCasts Sync: " + _pushQueue.size() + " updates to push");

        if (_pushQueue.size() == 0) {
            _stepRefresh();
        } else {
            _stepPush();
        }
    }

    // ================================================================
    // Step 5: Push — sequential /sync/update_episode per episode
    // ================================================================

    private function _stepPush() as Void {
        _currentStep = STEP_PUSH;
        _pushIndex = 0;
        _pushFailedUuids = {} as Dictionary;
        System.println("YoCasts Sync: step 5 — pushing " +
                       _pushQueue.size() + " updates");
        _pushNextChange();
    }

    private function _pushNextChange() as Void {
        if (_pushIndex >= _pushQueue.size()) {
            var failures = _pushFailedUuids.size();
            System.println("YoCasts Sync: push done — " +
                           (_pushQueue.size() - failures) + " OK, " +
                           failures + " failed");
            // Free snapshot memory (IDs are kept for cleanup)
            _changelogSnapshot = [] as Array<Dictionary>;
            _stepRefresh();
            return;
        }

        var change = _pushQueue[_pushIndex] as Dictionary;
        var u = change.get("uuid");
        var pos = change.get("position");
        var st = change.get("status");
        var dur = change.get("duration");

        if (u == null || pos == null || st == null) {
            _pushIndex++;
            _pushNextChange();
            return;
        }

        var p = change.get("podcast");
        System.println("YoCasts Sync: push " + (_pushIndex + 1) +
                       "/" + _pushQueue.size());

        _makeAuthPost("/sync/update_episode", {
            "uuid" => u as String,
            "podcast" => (p != null ? p as String : ""),
            "position" => pos as Number,
            "status" => st as Number,
            "duration" => (dur != null ? dur as Number : 0)
        } as Dictionary<Object, Object>, method(:onPushResponse));
    }

    //! @hide
    function onPushResponse(responseCode as Number,
                            data as Dictionary or String or Null) as Void {
        if (responseCode == 200) {
            System.println("YoCasts Sync: push OK");
        } else if (responseCode == 401) {
            System.println("YoCasts Sync: push 401 — aborting");
            _abortSync();
            return;
        } else {
            System.println("YoCasts Sync: push FAILED — HTTP " + responseCode);
            var change = _pushQueue[_pushIndex] as Dictionary;
            var uuid = change.get("uuid");
            if (uuid != null) {
                _pushFailedUuids.put(uuid as String, true);
            }
        }
        _pushIndex++;
        _pushNextChange();
    }

    // ================================================================
    // Step 6: Refresh caches — trigger full service re-fetch
    // ================================================================

    private function _stepRefresh() as Void {
        _currentStep = STEP_REFRESH;
        System.println("YoCasts Sync: step 6 — refresh caches");

        if (_service != null && ConnectivityManager.isConnected()) {
            (_service as IPodcastService).fetchAll();
        }

        _stepCleanup();
    }

    // ================================================================
    // Step 7: Cleanup — selectively clear synced entries, update UI
    // ================================================================

    private function _stepCleanup() as Void {
        _currentStep = STEP_CLEANUP;
        System.println("YoCasts Sync: step 7 — cleanup");

        _clearSyncedEntries();

        _syncing = false;
        _currentStep = STEP_IDLE;
        _pushQueue = [] as Array<Dictionary>;
        _pushFailedUuids = {} as Dictionary;
        _snapshotIds = {} as Dictionary;

        WatchUi.requestUpdate();
        System.println("YoCasts Sync: complete");
    }

    //! Selectively remove synced entries from changelog.
    //! Entries added during sync (by PositionTracker) are preserved.
    //! Entries for episodes whose push failed are preserved for retry.
    private function _clearSyncedEntries() as Void {
        var current = ChangeLog.getEntries();
        var remaining = [] as Array<Dictionary>;

        for (var i = 0; i < current.size(); i++) {
            var entry = current[i] as Dictionary;
            var id = entry.get("id");

            // Keep entries not in our snapshot (added during sync)
            if (id == null || !_snapshotIds.hasKey(id)) {
                remaining.add(entry);
                continue;
            }

            // Keep entries for episodes whose push failed
            var uuid = entry.get("episodeUuid");
            if (uuid != null && uuid instanceof String &&
                _pushFailedUuids.hasKey(uuid as String)) {
                remaining.add(entry);
                continue;
            }
        }

        if (remaining.size() == 0) {
            ChangeLog.clearChangelog();
        } else {
            Application.Storage.setValue(ChangeLog.KEY_CHANGELOG,
                remaining as Application.Storage.ValueType);
        }
        System.println("YoCasts Sync: " + remaining.size() + " entries remain");
    }

    // ================================================================
    // Pure reconciliation functions (no side effects, testable)
    // ================================================================

    //! Resolve position conflict: furthest position wins.
    function reconcilePosition(localPos as Number,
                               serverPos as Number) as Number {
        return localPos > serverPos ? localPos : serverPos;
    }

    //! Resolve status per hierarchy: COMPLETED > IN_PROGRESS > NOT_PLAYED.
    function reconcileStatus(localStatus as Number,
                             serverStatus as Number) as Number {
        if (localStatus == DataKeys.STATUS_COMPLETED ||
            serverStatus == DataKeys.STATUS_COMPLETED) {
            return DataKeys.STATUS_COMPLETED;
        }
        if (localStatus == DataKeys.STATUS_IN_PROGRESS ||
            serverStatus == DataKeys.STATUS_IN_PROGRESS) {
            return DataKeys.STATUS_IN_PROGRESS;
        }
        return DataKeys.STATUS_NOT_PLAYED;
    }

    //! Resolve queue: server order as base, remove locally-completed episodes.
    //! Returns array of episode UUID strings in resolved order.
    function reconcileQueue(serverOrder as Array,
                            changelog as Array<Dictionary>) as Array<String> {
        // Build set of locally completed episode UUIDs
        var completedSet = {} as Dictionary;
        for (var i = 0; i < changelog.size(); i++) {
            var entry = changelog[i] as Dictionary;
            var entryType = entry.get("type");
            if (entryType != null && entryType instanceof String &&
                (entryType as String).equals(ChangeLog.TYPE_EPISODE_COMPLETED)) {
                var uuid = entry.get("episodeUuid");
                if (uuid != null) {
                    completedSet.put(uuid as String, true);
                }
            }
        }

        var resolved = [] as Array<String>;
        for (var i = 0; i < serverOrder.size(); i++) {
            var uuid = serverOrder[i];
            if (uuid != null && uuid instanceof String) {
                if (!completedSet.hasKey(uuid as String)) {
                    resolved.add(uuid as String);
                }
            }
        }

        return resolved;
    }

    // ================================================================
    // Internal helpers
    // ================================================================

    //! Abort sync, preserving changelog for next attempt.
    private function _abortSync() as Void {
        System.println("YoCasts Sync: ABORTED at step " + _currentStep);
        _syncing = false;
        _currentStep = STEP_IDLE;
        _changelogSnapshot = [] as Array<Dictionary>;
        _serverEpisodes = {} as Dictionary;
        _affectedUuids = [] as Array<String>;
        _pushQueue = [] as Array<Dictionary>;
        _pushFailedUuids = {} as Dictionary;
        _snapshotIds = {} as Dictionary;
    }

    private function _isTokenExpiringSoon() as Boolean {
        return Time.now().value() > (_tokenExpiresAt - TOKEN_REFRESH_BUFFER);
    }

    //! Authenticated POST through the Azure proxy (mirrors PocketCastsPodcastService).
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

    private function _arrayContains(arr as Array<String>,
                                    val as String) as Boolean {
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i].equals(val)) {
                return true;
            }
        }
        return false;
    }

    private function _strOr(val as Object?, fallback as String) as String {
        if (val != null && val instanceof String) {
            return val as String;
        }
        return fallback;
    }

    private function _numOr(val as Object?, fallback as Number) as Number {
        if (val != null && val instanceof Number) {
            return val as Number;
        }
        return fallback;
    }
}
