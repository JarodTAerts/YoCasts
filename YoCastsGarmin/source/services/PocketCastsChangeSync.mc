import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

//! Sequentially reconciles cached local mutations with Pocket Casts.
//! This class is transport-agnostic: foreground launches can use the phone
//! bridge or Wi-Fi, while SyncDelegate uses Garmin's managed Wi-Fi session.
class PocketCastsChangeSync {

    private const PROXY_BASE =
        "https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts";

    private var _accessToken as String;
    private var _onComplete as Method(failures as Number) as Void;
    private var _entries as Array<Dictionary> = [] as Array<Dictionary>;
    private var _index as Number = 0;
    private var _currentId as Number? = null;
    private var _pendingBody as Dictionary<Object, Object>? = null;
    private var _failures as Number = 0;
    private var _authenticationFailed as Boolean = false;
    private var _active as Boolean = false;

    function initialize(
        accessToken as String,
        onComplete as Method(failures as Number) as Void
    ) {
        _accessToken = accessToken;
        _onComplete = onComplete;
    }

    function start() as Void {
        if (_active) { return; }
        _entries = ChangeLog.getEntries();
        _index = 0;
        _failures = 0;
        _authenticationFailed = false;
        _active = true;

        if (_entries.size() == 0) {
            _finish();
            return;
        }

        SyncStatus.markStarted();
        System.println(
            "YoCasts ChangeSync: pushing " + _entries.size() + " changes"
        );
        _pushNext();
    }

    function isActive() as Boolean {
        return _active;
    }

    function stop() as Void {
        _active = false;
        _currentId = null;
        _pendingBody = null;
    }

    function hadAuthenticationFailure() as Boolean {
        return _authenticationFailed;
    }

    private function _pushNext() as Void {
        if (!_active) { return; }
        if (_index >= _entries.size()) {
            _finish();
            return;
        }

        var entry = _entries[_index] as Dictionary;
        var id = entry.get("id");
        _currentId = (id != null && id instanceof Number)
            ? id as Number : null;

        var type = _stringValue(entry.get("type"));
        var uuid = _stringValue(entry.get("episodeUuid"));
        var podcastUuid = _stringValue(entry.get("podcastUuid"));

        if (uuid.length() == 0) {
            _advance(true);
            return;
        }

        if (type.equals(ChangeLog.TYPE_QUEUE_ADD)) {
            _makeAuthPost(
                "/up_next/play_last",
                {
                    "uuid" => uuid,
                    "podcast" => podcastUuid
                } as Dictionary<Object, Object>,
                method(:onMutationResponse)
            );
        } else if (type.equals(ChangeLog.TYPE_QUEUE_REMOVE)) {
            _makeAuthPost(
                "/up_next/remove",
                { "uuid" => uuid } as Dictionary<Object, Object>,
                method(:onMutationResponse)
            );
        } else if (type.equals(ChangeLog.TYPE_POSITION_UPDATE) ||
                   type.equals(ChangeLog.TYPE_STATUS_CHANGE) ||
                   type.equals(ChangeLog.TYPE_EPISODE_COMPLETED)) {
            _pendingBody =
                _buildPlaybackBody(entry, uuid, podcastUuid);
            _makeAuthPost(
                "/user/episode",
                { "uuid" => uuid } as Dictionary<Object, Object>,
                method(:onServerEpisodeResponse)
            );
        } else {
            _advance(true);
        }
    }

    function onServerEpisodeResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        if (!_active) { return; }
        if (responseCode != 200 || data == null ||
            !(data instanceof Dictionary) || _pendingBody == null) {
            if (responseCode == 401) {
                _authenticationFailed = true;
            }
            _advance(false);
            return;
        }

        var server = data as Dictionary;
        var body = _pendingBody as Dictionary<Object, Object>;
        var localPosition = _numberValue(body.get("position"), 0);
        var localStatus = _numberValue(
            body.get("status"),
            DataKeys.STATUS_NOT_PLAYED
        );
        var localDuration = _numberValue(body.get("duration"), 0);
        var serverPosition = _numberValue(server.get("playedUpTo"), 0);
        var serverStatus = _numberValue(
            server.get("playingStatus"),
            DataKeys.STATUS_NOT_PLAYED
        );
        var serverDuration = _numberValue(server.get("duration"), 0);

        var resolvedPosition = localPosition > serverPosition
            ? localPosition : serverPosition;
        var resolvedStatus = _strongestStatus(localStatus, serverStatus);
        var resolvedDuration = localDuration > serverDuration
            ? localDuration : serverDuration;

        if (resolvedStatus == DataKeys.STATUS_COMPLETED &&
            resolvedDuration > 0 && resolvedPosition < resolvedDuration) {
            resolvedPosition = resolvedDuration;
        }

        if (resolvedPosition == serverPosition &&
            resolvedStatus == serverStatus) {
            _advance(true);
            return;
        }

        body.put("position", resolvedPosition);
        body.put("status", resolvedStatus);
        body.put("duration", resolvedDuration);
        _makeAuthPost(
            "/sync/update_episode",
            body,
            method(:onMutationResponse)
        );
    }

    function onMutationResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        if (!_active) { return; }
        if (responseCode == 401) {
            _authenticationFailed = true;
        }
        _advance(responseCode >= 200 && responseCode < 300);
    }

    private function _advance(success as Boolean) as Void {
        if (success && _currentId != null) {
            ChangeLog.removeEntryById(_currentId as Number);
        } else if (!success) {
            _failures++;
        }

        _currentId = null;
        _pendingBody = null;
        _index++;
        _pushNext();
    }

    private function _finish() as Void {
        _active = false;
        if (_failures == 0) {
            if (_entries.size() > 0) {
                SyncStatus.markSuccess();
            }
        } else {
            SyncStatus.markFailure(
                _failures + (_failures == 1
                    ? " change failed" : " changes failed")
            );
        }
        _onComplete.invoke(_failures);
    }

    private function _buildPlaybackBody(
        entry as Dictionary,
        uuid as String,
        podcastUuid as String
    ) as Dictionary<Object, Object> {
        var position = 0;
        var duration = 0;
        var status = DataKeys.STATUS_IN_PROGRESS;
        var entryData = entry.get("data");

        if (entryData != null && entryData instanceof Dictionary) {
            var values = entryData as Dictionary;
            position = _numberValue(values.get("position"), position);
            duration = _numberValue(values.get("duration"), duration);
            status = _numberValue(values.get("status"), status);
        }

        var cached = CacheManager.loadPlaybackPosition(uuid);
        if (cached != null) {
            position = _numberValue(
                (cached as Dictionary).get("position"),
                position
            );
            duration = _numberValue(
                (cached as Dictionary).get("duration"),
                duration
            );
        }

        return {
            "uuid" => uuid,
            "podcast" => podcastUuid,
            "position" => position,
            "status" => status,
            "duration" => duration
        } as Dictionary<Object, Object>;
    }

    private function _makeAuthPost(
        path as String,
        body as Dictionary<Object, Object>,
        callback as Method(
            responseCode as Number,
            data as Dictionary or String or Null
        ) as Void
    ) as Void {
        Communications.makeWebRequest(
            PROXY_BASE + path,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" =>
                        Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType =>
                    Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            callback
        );
    }

    private function _stringValue(value as Object?) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return "";
    }

    private function _numberValue(value as Object?, fallback as Number)
                                  as Number {
        if (value != null && value instanceof Number) {
            return value as Number;
        }
        return fallback;
    }

    private function _strongestStatus(first as Number,
                                      second as Number) as Number {
        if (first == DataKeys.STATUS_COMPLETED ||
            second == DataKeys.STATUS_COMPLETED) {
            return DataKeys.STATUS_COMPLETED;
        }
        if (first == DataKeys.STATUS_IN_PROGRESS ||
            second == DataKeys.STATUS_IN_PROGRESS) {
            return DataKeys.STATUS_IN_PROGRESS;
        }
        return first > second ? first : second;
    }
}
