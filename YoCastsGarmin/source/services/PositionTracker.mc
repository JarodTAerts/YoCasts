import Toybox.Lang;
import Toybox.Timer;
import Toybox.System;

//! Tracks playback position at regular intervals and logs changes to
//! ChangeLog for offline sync. Battery-adaptive: halves frequency when
//! battery drops below 20%.
//!
//! Lifecycle: NowPlayingView creates an instance on init, calls
//! startTracking() when playback begins, stopTracking() on pause/exit.
//! Each tick samples the view's current position and writes to both
//! ChangeLog (for sync) and CacheManager (for instant offline resume).
class PositionTracker {

    private var _timer as Timer.Timer? = null;
    private var _episodeUuid as String;
    private var _podcastUuid as String;
    private var _duration as Number;
    private var _lastLoggedPosition as Number = -1;
    private var _positionProvider as NowPlayingView? = null;

    // 15-second interval per offline-sync-design.md §4.2
    const NORMAL_INTERVAL_MS = 15000;
    // 30 seconds when battery < 20% to reduce wake-ups
    const LOW_BATTERY_INTERVAL_MS = 30000;
    const LOW_BATTERY_THRESHOLD = 20.0;

    function initialize(episodeUuid as String, podcastUuid as String,
                        duration as Number) {
        _episodeUuid = episodeUuid;
        _podcastUuid = podcastUuid;
        _duration = duration;
    }

    //! Begin position tracking with a repeating timer.
    function startTracking(view as NowPlayingView) as Void {
        stopTracking();
        _positionProvider = view;
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onPositionTick),
                                       _getInterval(), true);
    }

    //! Stop tracking. Safe to call even if not currently tracking.
    function stopTracking() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
        _positionProvider = null;
    }

    //! Returns true if actively tracking.
    function isTracking() as Boolean {
        return _timer != null;
    }

    //! Force-log the current position immediately (e.g., on pause or skip).
    function logNow() as Void {
        if (_positionProvider != null) {
            var position = (_positionProvider as NowPlayingView).getCurrentPosition();
            _logPosition(position);
        }
    }

    //! Timer callback — samples position and logs if changed.
    function onPositionTick() as Void {
        if (_positionProvider == null) {
            return;
        }
        var position = (_positionProvider as NowPlayingView).getCurrentPosition();
        _logPosition(position);
    }

    //! Internal: write position to ChangeLog + CacheManager, skip if unchanged.
    private function _logPosition(position as Number) as Void {
        if (position == _lastLoggedPosition) {
            return;
        }
        _lastLoggedPosition = position;
        ChangeLog.logPositionUpdate(_episodeUuid, _podcastUuid,
                                     position, _duration);
        CacheManager.savePlaybackPosition(_episodeUuid, position, _duration);
    }

    //! Adaptive interval: 30 s when battery < 20%, otherwise 15 s.
    private function _getInterval() as Number {
        try {
            var stats = System.getSystemStats();
            if (stats.battery < LOW_BATTERY_THRESHOLD) {
                return LOW_BATTERY_INTERVAL_MS;
            }
        } catch (e) {
            // SystemStats may behave differently in simulator
        }
        return NORMAL_INTERVAL_MS;
    }
}
