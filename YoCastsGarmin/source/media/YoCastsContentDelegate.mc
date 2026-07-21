import Toybox.Media;
import Toybox.System;
import Toybox.Lang;

//! ContentDelegate for the native Garmin media player.
//! Receives playback events (start, pause, resume, complete, stop) and
//! logs position/status changes to ChangeLog for PocketCasts sync.
//!
//! Lifecycle: System calls getContentDelegate() on YoCastsApp → returns
//! this singleton. System calls onSong() on every playback state change.
//! Playback is owned by Garmin's native player. Position is persisted from
//! native song events; no foreground timer is required or available here.
class YoCastsContentDelegate extends Media.ContentDelegate {

    private var _iterator as YoCastsContentIterator?;
    private var _currentRefId as Object? = null;
    private var _currentUuid as String = "";
    private var _isPlaying as Boolean = false;
    private var _currentCompleted as Boolean = false;
    private var _lastPosition as Number = 0;
    private var _playbackStartOffset as Number = 0;

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
    function resetContentIterator() as Media.ContentIterator? {
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
    function onSong(contentRefId as Object, songEvent as Media.SongEvent,
                    playbackPosition) as Void {
        System.println("YoCasts: onSong refId=" + contentRefId +
            " event=" + songEvent + " pos=" + playbackPosition);

        var rawPosition = 0;
        if (playbackPosition != null && playbackPosition instanceof Number) {
            rawPosition = playbackPosition as Number;
        }

        // Detect track change
        var trackChanged = false;
        if (_currentRefId == null ||
            !(_currentRefId as Object).equals(contentRefId)) {
            _onTrackChanged(contentRefId, rawPosition);
            trackChanged = true;
        }
        var posNum = rawPosition + _playbackStartOffset;
        if (!trackChanged) {
            _lastPosition = posNum;
        }

        _handleSongEvent(songEvent, posNum);
        PlaybackState.recordNativeEvent(songEvent as Number);
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
    private function _onTrackChanged(refId as Object,
                                     position as Number) as Void {
        // Log final position for previous episode
        if (_currentUuid.length() > 0 && _isPlaying) {
            _logPosition(_lastPosition);
        }

        _currentRefId = refId;
        _currentUuid = _resolveUuid(refId);
        _currentCompleted = false;
        _playbackStartOffset = _getResumeOffset(refId);
        var absolutePosition = position + _playbackStartOffset;
        _lastPosition = absolutePosition;
        if (_currentUuid.length() > 0) {
            StorageManager.setSelectedEpisode(_currentUuid);
        }

        // Update shared PlaybackState with new track info
        _updatePlaybackState(absolutePosition, false);

        System.println("YoCasts: track changed to uuid=" + _currentUuid);
    }

    // ================================================================
    // Song event state machine
    // ================================================================

    private function _handleSongEvent(songEvent as Media.SongEvent,
                                      position as Number) as Void {
        if (songEvent == Media.SONG_EVENT_START ||
            songEvent == Media.SONG_EVENT_RESUME) {
            _currentCompleted = false;
            _isPlaying = true;
            _logPosition(position);
            PlaybackState.setPlaying(true);
        } else if (songEvent == Media.SONG_EVENT_PLAYBACK_NOTIFY) {
            _isPlaying = true;
            _logPosition(position);
            PlaybackState.setPlaying(true);
        } else if (songEvent == Media.SONG_EVENT_PAUSE) {
            _isPlaying = false;
            _logPosition(position);
            PlaybackState.setPlaying(false);
        } else if (songEvent == Media.SONG_EVENT_COMPLETE) {
            _isPlaying = false;
            _onEpisodeComplete(position);
        } else if (songEvent == Media.SONG_EVENT_STOP) {
            _isPlaying = false;
            if (!_currentCompleted) {
                _logPosition(position);
            }
            PlaybackState.setPlaying(false);
        } else if (songEvent == Media.SONG_EVENT_SKIP_NEXT ||
                   songEvent == Media.SONG_EVENT_SKIP_PREVIOUS ||
                   songEvent == Media.SONG_EVENT_SKIP_FORWARD ||
                   songEvent == Media.SONG_EVENT_SKIP_BACKWARD) {
            _isPlaying = true;
            _logPosition(position);
            PlaybackState.setPlaying(true);
        }
    }

    // ================================================================
    // Episode completion
    // ================================================================

    //! Called when the native player reaches the end of a track.
    private function _onEpisodeComplete(position as Number) as Void {
        if (_currentUuid.length() == 0) { return; }

        System.println("YoCasts: episode completed " + _currentUuid);

        var podUuid = StorageManager.getEpisodePodcastUuid(_currentUuid);
        var podUuidStr = (podUuid != null) ? podUuid as String : "";

        // Log completion to ChangeLog for PocketCasts sync
        ChangeLog.logStatusChange(_currentUuid, podUuidStr,
                                   DataKeys.STATUS_COMPLETED);

        // Update cached position to full duration
        var duration = _getDuration();
        var completedPosition = duration > 0 ? duration : position;
        var completedDuration = duration > 0 ? duration : position;
        CacheManager.savePlaybackPosition(
            _currentUuid,
            completedPosition,
            completedDuration
        );
        DownloadQueue.updatePlayback(
            _currentUuid,
            completedPosition,
            DataKeys.STATUS_COMPLETED
        );
        _currentCompleted = true;
        PlaybackState.updatePosition(completedPosition);
        PlaybackState.setPlaying(false);
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
        DownloadQueue.updatePlayback(
            _currentUuid,
            position,
            DataKeys.STATUS_IN_PROGRESS
        );

        // Keep PlaybackState in sync
        PlaybackState.updatePosition(position);
    }

    // ================================================================
    // Helpers
    // ================================================================

    //! Look up episode UUID from a ContentRef ID via StorageManager.
    private function _resolveUuid(refId as Object) as String {
        var downloads = StorageManager.getDownloadedEpisodes();
        for (var i = 0; i < downloads.size(); i++) {
            var d = downloads[i] as Dictionary;
            var r = d.get("refId");
            if (r != null && (r as Object).equals(refId)) {
                var uuid = d.get("episodeUuid");
                return (uuid != null) ? uuid as String : "";
            }
        }
        return "";
    }

    private function _getResumeOffset(refId as Object) as Number {
        if (_iterator != null) {
            return (_iterator as YoCastsContentIterator)
                .getResumeOffsetForRefId(refId);
        }
        if (_currentUuid.length() > 0) {
            var cached = CacheManager.loadPlaybackPosition(_currentUuid);
            if (cached != null) {
                var position = (cached as Dictionary).get("position");
                return (position != null && position instanceof Number)
                    ? position as Number : 0;
            }
        }
        return 0;
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
