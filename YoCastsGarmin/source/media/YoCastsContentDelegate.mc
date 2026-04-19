import Toybox.Media;
import Toybox.System;
import Toybox.Lang;
import Toybox.Timer;

//! ContentDelegate for the native Garmin media player.
//! Receives playback events (start, pause, resume, complete, stop) and
//! logs position/status changes to ChangeLog for PocketCasts sync.
//!
//! Lifecycle: System calls getContentDelegate() on YoCastsApp → returns
//! this singleton. System calls onSong() on every playback state change.
//! Timer-based position logging supplements onSong for 15s intervals.
class YoCastsContentDelegate extends Media.ContentDelegate {

    private var _iterator as YoCastsContentIterator?;
    private var _currentRefId as String = "";
    private var _currentUuid as String = "";
    private var _isPlaying as Boolean = false;
    private var _positionTimer as Timer.Timer? = null;
    private var _lastPosition as Number = 0;

    // Song event constants (Garmin Media module values)
    private const EVENT_START = 0;
    private const EVENT_PAUSE = 1;
    private const EVENT_RESUME = 2;
    private const EVENT_COMPLETE = 3;
    private const EVENT_STOP = 4;

    // 15s position logging interval per offline-sync-design.md §4.2
    private const POSITION_LOG_INTERVAL_MS = 15000;

    function initialize() {
        ContentDelegate.initialize();
    }

    //! Returns the content iterator backed by downloaded episodes.
    function getContentIterator() {
        if (_iterator == null) {
            _iterator = new YoCastsContentIterator();
        }
        return _iterator;
    }

    //! Rebuild the iterator (e.g., after new downloads complete).
    function resetContentIterator() as YoCastsContentIterator {
        _iterator = new YoCastsContentIterator();
        return _iterator;
    }

    //! Set the iterator to start at a specific episode by UUID.
    //! Call before playback begins to control which track plays first.
    function setStartEpisode(uuid as String) as Void {
        var iter = getContentIterator() as YoCastsContentIterator;
        iter.setCurrentByUuid(uuid);
    }

    //! Main event handler — called by the system on every playback state change.
    //! contentRefId: ID of the ContentRef being played
    //! songEvent: numeric event type (start/pause/resume/complete/stop)
    //! playbackPosition: current position in seconds
    function onSong(contentRefId, songEvent, playbackPosition) {
        System.println("YoCasts: onSong refId=" + contentRefId +
            " event=" + songEvent + " pos=" + playbackPosition);

        var posNum = 0;
        if (playbackPosition != null && playbackPosition instanceof Number) {
            posNum = playbackPosition as Number;
        }
        _lastPosition = posNum;

        // Detect track change
        if (contentRefId != null) {
            var refStr = contentRefId.toString();
            if (!refStr.equals(_currentRefId)) {
                _onTrackChanged(refStr, posNum);
            }
        }

        // Log position on every event (ground truth from system)
        if (_currentUuid.length() > 0) {
            _logPosition(posNum);
        }

        // Handle state-specific logic
        _handleSongEvent(songEvent, posNum);
    }

    function onShuffle() {
        // Podcasts don't shuffle — ignore
    }

    function onRepeat() {
        // Podcasts don't repeat — ignore
    }

    function onThumbsUp(contentRefId) {
        // Could map to star/favorite in future
    }

    function onThumbsDown(contentRefId) {
        // Could map to archive in future
    }

    // ================================================================
    // Track change handling
    // ================================================================

    //! Called when the native player switches to a different track.
    private function _onTrackChanged(refId as String, position as Number) as Void {
        // Log final position for previous episode
        if (_currentUuid.length() > 0 && _isPlaying) {
            _logPosition(_lastPosition);
        }
        _stopPositionTimer();

        _currentRefId = refId;
        _currentUuid = _resolveUuid(refId);
        _lastPosition = position;

        // Update shared PlaybackState with new track info
        _updatePlaybackState(position, false);

        System.println("YoCasts: track changed to uuid=" + _currentUuid);
    }

    // ================================================================
    // Song event state machine
    // ================================================================

    private function _handleSongEvent(songEvent, position as Number) as Void {
        var evt = -1;
        if (songEvent != null && songEvent instanceof Number) {
            evt = songEvent as Number;
        }

        if (evt == EVENT_START || evt == EVENT_RESUME) {
            _isPlaying = true;
            _startPositionTimer();
            PlaybackState.setPlaying(true);
        } else if (evt == EVENT_PAUSE) {
            _isPlaying = false;
            _stopPositionTimer();
            _logPosition(position);
            PlaybackState.setPlaying(false);
        } else if (evt == EVENT_COMPLETE) {
            _isPlaying = false;
            _stopPositionTimer();
            _onEpisodeComplete();
            PlaybackState.setPlaying(false);
        } else if (evt == EVENT_STOP) {
            _isPlaying = false;
            _stopPositionTimer();
            _logPosition(position);
            PlaybackState.setPlaying(false);
        }
    }

    // ================================================================
    // Episode completion
    // ================================================================

    //! Called when the native player reaches the end of a track.
    private function _onEpisodeComplete() as Void {
        if (_currentUuid.length() == 0) { return; }

        System.println("YoCasts: episode completed " + _currentUuid);

        var podUuid = StorageManager.getEpisodePodcastUuid(_currentUuid);
        var podUuidStr = (podUuid != null) ? podUuid as String : "";

        // Log completion to ChangeLog for PocketCasts sync
        ChangeLog.logStatusChange(_currentUuid, podUuidStr,
                                   DataKeys.STATUS_COMPLETED);

        // Update cached position to full duration
        var duration = _getDuration();
        if (duration > 0) {
            CacheManager.savePlaybackPosition(_currentUuid, duration, duration);
        }

        PlaybackState.clear();
    }

    // ================================================================
    // Position logging
    // ================================================================

    //! Write position to ChangeLog + CacheManager.
    private function _logPosition(position as Number) as Void {
        if (_currentUuid.length() == 0) { return; }

        var podUuid = StorageManager.getEpisodePodcastUuid(_currentUuid);
        var podUuidStr = (podUuid != null) ? podUuid as String : "";
        var duration = _getDuration();

        ChangeLog.logPositionUpdate(_currentUuid, podUuidStr,
                                     position, duration);
        CacheManager.savePlaybackPosition(_currentUuid, position, duration);

        // Keep PlaybackState in sync
        PlaybackState.updatePosition(position);
    }

    //! Start 15-second position logging timer.
    private function _startPositionTimer() as Void {
        _stopPositionTimer();
        _positionTimer = new Timer.Timer();
        (_positionTimer as Timer.Timer).start(
            method(:onPositionLogTick), POSITION_LOG_INTERVAL_MS, true);
    }

    private function _stopPositionTimer() as Void {
        if (_positionTimer != null) {
            (_positionTimer as Timer.Timer).stop();
            _positionTimer = null;
        }
    }

    //! Timer callback — estimates position and logs it.
    //! Between onSong events, we estimate position = last known + elapsed.
    function onPositionLogTick() as Void {
        if (!_isPlaying || _currentUuid.length() == 0) { return; }

        // Use PlaybackState's estimated position (accounts for elapsed time)
        var estimated = PlaybackState.getEstimatedPosition();
        _logPosition(estimated);
    }

    // ================================================================
    // Helpers
    // ================================================================

    //! Look up episode UUID from a ContentRef ID via StorageManager.
    private function _resolveUuid(refId as String) as String {
        var downloads = StorageManager.getDownloadedEpisodes();
        for (var i = 0; i < downloads.size(); i++) {
            var d = downloads[i] as Dictionary;
            var r = d.get("refId");
            if (r != null && (r as String).equals(refId)) {
                var uuid = d.get("episodeUuid");
                return (uuid != null) ? uuid as String : "";
            }
        }
        return "";
    }

    //! Get episode duration from DownloadQueue metadata.
    private function _getDuration() as Number {
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var dl = downloads[i] as Dictionary;
            var uuid = dl.get(DownloadQueue.DL_UUID);
            if (uuid != null && (uuid as String).equals(_currentUuid)) {
                var dur = dl.get(DownloadQueue.DL_DURATION);
                return (dur != null && dur instanceof Number) ? dur as Number : 0;
            }
        }
        return 0;
    }

    //! Update the shared PlaybackState with current track metadata.
    private function _updatePlaybackState(position as Number,
                                           playing as Boolean) as Void {
        if (_currentUuid.length() == 0) { return; }

        var title = "";
        var podTitle = "";
        var podUuid = "";
        var duration = 0;

        // Pull metadata from DownloadQueue
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var dl = downloads[i] as Dictionary;
            var uuid = dl.get(DownloadQueue.DL_UUID);
            if (uuid != null && (uuid as String).equals(_currentUuid)) {
                var t = dl.get(DownloadQueue.DL_TITLE);
                if (t != null) { title = t as String; }
                var pt = dl.get(DownloadQueue.DL_PODCAST_TITLE);
                if (pt != null) { podTitle = pt as String; }
                var pu = dl.get(DownloadQueue.DL_PODCAST_UUID);
                if (pu != null) { podUuid = pu as String; }
                var d = dl.get(DownloadQueue.DL_DURATION);
                if (d != null && d instanceof Number) { duration = d as Number; }
                break;
            }
        }

        PlaybackState.update(_currentUuid, podUuid, title, podTitle,
                             position, duration, playing);
    }
}
