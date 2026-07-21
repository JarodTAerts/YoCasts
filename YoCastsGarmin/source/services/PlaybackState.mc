import Toybox.Lang;
import Toybox.Application;
import Toybox.Time;

//! Shared playback state module — single source of truth for what's playing.
//! Written by: ContentDelegate (device, real native playback events) or
//!             NowPlayingView (sim, mock local playback).
//! Read by:    HomeMenuView (dock display), NowPlayingView (initial state).
module PlaybackState {

    const KEY_PLAYBACK_SESSION = "yc_playback_session";

    var isPlaying as Boolean = false;
    var currentUuid as String = "";
    var currentPodcastUuid as String = "";
    var currentTitle as String = "";
    var currentPodcastTitle as String = "";
    var currentPosition as Number = 0;
    var currentDuration as Number = 0;
    var lastEventTime as Number = 0;
    var lastNativeEvent as Number = -1;
    var nativeEventCount as Number = 0;

    //! Full state update (track change or initial load).
    function update(uuid as String, podcastUuid as String,
                    title as String, podcastTitle as String,
                    position as Number, duration as Number,
                    playing as Boolean) as Void {
        currentUuid = uuid;
        currentPodcastUuid = podcastUuid;
        currentTitle = title;
        currentPodcastTitle = podcastTitle;
        currentPosition = position;
        currentDuration = duration;
        isPlaying = playing;
        lastEventTime = Time.now().value();
        _persist();
    }

    //! Update position only (from timer tick or onSong event).
    function updatePosition(position as Number) as Void {
        currentPosition = position;
        lastEventTime = Time.now().value();
        _persist();
    }

    //! Toggle or set playing state.
    function setPlaying(playing as Boolean) as Void {
        if (isPlaying && !playing) {
            currentPosition = getEstimatedPosition();
        }
        isPlaying = playing;
        lastEventTime = Time.now().value();
        _persist();
    }

    //! Record a callback from Garmin's native player for diagnostics.
    function recordNativeEvent(event as Number) as Void {
        lastNativeEvent = event;
        nativeEventCount++;
        _persist();
    }

    //! Restore state written by the native playback lifecycle. The media
    //! player and playback-configuration UI may run in separate app contexts,
    //! so Application.Storage is the communication boundary.
    function restore() as Void {
        var stored = Application.Storage.getValue(KEY_PLAYBACK_SESSION);
        if (stored != null && stored instanceof Dictionary) {
            var session = stored as Dictionary;
            var uuid = session.get("uuid");
            if (uuid != null && uuid instanceof String &&
                StorageManager.isEpisodeDownloaded(uuid as String)) {
                currentUuid = uuid as String;
                currentPodcastUuid =
                    _stringValue(session.get("podcastUuid"));
                currentTitle = _stringValue(session.get("title"));
                currentPodcastTitle =
                    _stringValue(session.get("podcastTitle"));
                currentPosition =
                    _numberValue(session.get("position"), 0);
                currentDuration =
                    _numberValue(session.get("duration"), 0);
                isPlaying =
                    _booleanValue(session.get("playing"), false);
                lastEventTime =
                    _numberValue(session.get("eventTime"), 0);
                lastNativeEvent =
                    _numberValue(session.get("nativeEvent"), -1);
                nativeEventCount =
                    _numberValue(session.get("eventCount"), 0);
                _expireImpossiblePlayback();
                return;
            }
        }

        // Before the first native callback, show the explicitly selected
        // downloaded episode at its last cached position.
        var selected = StorageManager.getSelectedEpisode();
        if (selected == null) {
            return;
        }

        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var item = downloads[i] as Dictionary;
            var uuid = item.get(DownloadQueue.DL_UUID);
            if (uuid == null || !(uuid as String).equals(selected as String)) {
                continue;
            }

            var position = 0;
            var duration = item.get(DownloadQueue.DL_DURATION);
            var cached = CacheManager.loadPlaybackPosition(selected as String);
            if (cached != null) {
                var saved = (cached as Dictionary).get("position");
                if (saved != null && saved instanceof Number) {
                    position = saved as Number;
                }
            }

            update(
                selected as String,
                _stringValue(item.get(DownloadQueue.DL_PODCAST_UUID)),
                _stringValue(item.get(DownloadQueue.DL_TITLE)),
                _stringValue(item.get(DownloadQueue.DL_PODCAST_TITLE)),
                position,
                (duration != null && duration instanceof Number)
                    ? duration as Number : 0,
                false
            );
            return;
        }
    }

    //! Estimate current position accounting for elapsed playback time.
    function getEstimatedPosition() as Number {
        if (!isPlaying || lastEventTime == 0) {
            return currentPosition;
        }
        var elapsed = Time.now().value() - lastEventTime;
        var estimated = currentPosition + elapsed;
        if (currentDuration > 0 && estimated > currentDuration) {
            return currentDuration;
        }
        return estimated;
    }

    //! True when there is an active episode loaded.
    function hasActivePlayback() as Boolean {
        return currentUuid.length() > 0;
    }

    //! Reset all state.
    function clear() as Void {
        isPlaying = false;
        currentUuid = "";
        currentPodcastUuid = "";
        currentTitle = "";
        currentPodcastTitle = "";
        currentPosition = 0;
        currentDuration = 0;
        lastEventTime = 0;
        lastNativeEvent = -1;
        nativeEventCount = 0;
        Application.Storage.deleteValue(KEY_PLAYBACK_SESSION);
    }

    function getNativeEventSummary() as String {
        if (nativeEventCount == 0) {
            return "No playback yet";
        }
        return "Events " + nativeEventCount + ": " +
               _eventName(lastNativeEvent);
    }

    function _stringValue(value as Object?) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return "";
    }

    function _numberValue(value as Object?, fallback as Number) as Number {
        if (value != null && value instanceof Number) {
            return value as Number;
        }
        return fallback;
    }

    function _booleanValue(value as Object?, fallback as Boolean) as Boolean {
        if (value != null && value instanceof Boolean) {
            return value as Boolean;
        }
        return fallback;
    }

    function _persist() as Void {
        if (currentUuid.length() == 0) {
            return;
        }
        var session = {
            "uuid" => currentUuid as Application.Storage.ValueType,
            "podcastUuid" =>
                currentPodcastUuid as Application.Storage.ValueType,
            "title" => currentTitle as Application.Storage.ValueType,
            "podcastTitle" =>
                currentPodcastTitle as Application.Storage.ValueType,
            "position" => currentPosition as Application.Storage.ValueType,
            "duration" => currentDuration as Application.Storage.ValueType,
            "playing" => isPlaying as Application.Storage.ValueType,
            "eventTime" => lastEventTime as Application.Storage.ValueType,
            "nativeEvent" => lastNativeEvent as Application.Storage.ValueType,
            "eventCount" => nativeEventCount as Application.Storage.ValueType
        } as Dictionary;
        Application.Storage.setValue(
            KEY_PLAYBACK_SESSION,
            session as Application.Storage.ValueType
        );
    }

    function _expireImpossiblePlayback() as Void {
        if (!isPlaying || lastEventTime <= 0) {
            return;
        }
        var elapsed = Time.now().value() - lastEventTime;
        var remaining = currentDuration - currentPosition;
        if ((currentDuration > 0 && elapsed > remaining + 60) ||
            elapsed > 43200) {
            if (currentDuration > 0 && currentPosition < currentDuration) {
                currentPosition = currentDuration;
            }
            isPlaying = false;
            _persist();
        }
    }

    function _eventName(event as Number) as String {
        if (event == 0) { return "Start"; }
        if (event == 1) { return "Next"; }
        if (event == 2) { return "Previous"; }
        if (event == 3) { return "Progress"; }
        if (event == 4) { return "Complete"; }
        if (event == 5) { return "Stop"; }
        if (event == 6) { return "Pause"; }
        if (event == 7) { return "Resume"; }
        if (event == 8) { return "Skip forward"; }
        if (event == 9) { return "Skip back"; }
        return "Event " + event;
    }
}
