import Toybox.Media;
import Toybox.Lang;
import Toybox.System;

//! Iterates over downloaded episodes for the native media player.
//! Builds playlist from DownloadQueue (STATUS_DOWNLOADED) in queue order.
//! Each call to get()/next()/previous() returns a ContentObj via
//! Media.getCachedContentObj().
//!
//! Maintains parallel refId → UUID mapping for track identification.
//! Empty playlist is safe — native player shows "No Media" when get()
//! returns null.
class YoCastsContentIterator extends Media.ContentIterator {

    private var _refIds as Array<Object> = [] as Array<Object>;
    private var _uuids as Array<String> = [] as Array<String>;
    private var _resumeOffsets as Dictionary = {} as Dictionary;
    private var _currentIndex as Number = -1;

    function initialize() {
        ContentIterator.initialize();
        _buildPlaylist();
    }

    //! Build playlist from downloaded episodes in DownloadQueue order.
    private function _buildPlaylist() as Void {
        _refIds = [] as Array<Object>;
        _uuids = [] as Array<String>;
        _resumeOffsets = {} as Dictionary;
        _currentIndex = -1;

        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var dl = downloads[i] as Dictionary;
            var status = dl.get(DownloadQueue.DL_STATUS);
            if (status == null || (status as Number) != DownloadQueue.STATUS_DOWNLOADED) {
                continue;
            }

            var uuid = dl.get(DownloadQueue.DL_UUID);
            if (uuid == null) { continue; }

            var refId = StorageManager.getEpisodeRefId(uuid as String);
            if (refId == null) { continue; }

            _refIds.add(refId as Object);
            _uuids.add(uuid as String);
        }

        if (_refIds.size() > 0) {
            _currentIndex = 0;
            var selected = StorageManager.getSelectedEpisode();
            if (selected != null) {
                setCurrentByUuid(selected as String);
            }
        }

        System.println("YoCasts Iterator: " + _refIds.size() + " episodes in playlist");
    }

    //! Returns the current track as a ContentObj, or null if empty.
    function get() as Media.Content? {
        return _getContentAt(_currentIndex);
    }

    //! Advance to the next track.
    function next() as Media.Content? {
        if (_currentIndex < _refIds.size() - 1) {
            _currentIndex = _currentIndex + 1;
            return _getContentAt(_currentIndex);
        }
        return null;
    }

    //! Go back to the previous track.
    function previous() as Media.Content? {
        if (_currentIndex > 0) {
            _currentIndex = _currentIndex - 1;
            return _getContentAt(_currentIndex);
        }
        return null;
    }

    //! Preview the next track without advancing.
    function peekNext() as Media.Content? {
        return _getContentAt(_currentIndex + 1);
    }

    //! Preview the previous track without going back.
    function peekPrevious() as Media.Content? {
        return _getContentAt(_currentIndex - 1);
    }

    //! All podcast episodes are skippable.
    function canSkip() as Boolean {
        return true;
    }

    //! Podcast playback profile — skip intervals, notification thresholds.
    function getPlaybackProfile() as Media.PlaybackProfile? {
        var profile = new Media.PlaybackProfile();
        profile.playbackControls = [
            Media.PLAYBACK_CONTROL_PREVIOUS,
            Media.PLAYBACK_CONTROL_SKIP_BACKWARD,
            Media.PLAYBACK_CONTROL_PLAYBACK,
            Media.PLAYBACK_CONTROL_SKIP_FORWARD,
            Media.PLAYBACK_CONTROL_NEXT
        ] as Array<Media.PlaybackControl>;
        profile.skipForwardTimeDelta = 30;
        profile.skipBackwardTimeDelta = 15;
        profile.requirePlaybackNotification = true;
        profile.playbackNotificationThreshold = 30;
        return profile;
    }

    //! Podcasts don't shuffle.
    function shuffling() as Boolean {
        return false;
    }

    // ================================================================
    // Episode selection & lookup (Phase D additions)
    // ================================================================

    //! Jump to a specific episode by UUID. Returns true if found.
    function setCurrentByUuid(uuid as String) as Boolean {
        for (var i = 0; i < _uuids.size(); i++) {
            if (_uuids[i].equals(uuid)) {
                _currentIndex = i;
                StorageManager.setSelectedEpisode(uuid);
                System.println("YoCasts Iterator: set current to " + uuid +
                    " (index " + i + ")");
                return true;
            }
        }
        System.println("YoCasts Iterator: uuid not in playlist " + uuid);
        return false;
    }

    //! Get the episode UUID of the current track.
    function getCurrentEpisodeUuid() as String {
        if (_currentIndex >= 0 && _currentIndex < _uuids.size()) {
            return _uuids[_currentIndex];
        }
        return "";
    }

    //! Get the ContentRef ID of the current track.
    function getCurrentRefId() as Object? {
        if (_currentIndex >= 0 && _currentIndex < _refIds.size()) {
            return _refIds[_currentIndex];
        }
        return null;
    }

    //! Number of playable episodes in the playlist.
    function getPlaylistSize() as Number {
        return _refIds.size();
    }

    //! Look up UUID for a given ContentRef ID (reverse mapping).
    function getUuidForRefId(refId as Object) as String {
        for (var i = 0; i < _refIds.size(); i++) {
            if (_refIds[i].equals(refId)) {
                return _uuids[i];
            }
        }
        return "";
    }

    //! ActiveContent reports playback positions relative to its configured
    //! start offset. ContentDelegate uses this to recover absolute position.
    function getResumeOffsetForRefId(refId as Object) as Number {
        var uuid = getUuidForRefId(refId);
        if (uuid.length() == 0) {
            return 0;
        }
        var offset = _resumeOffsets.get(uuid);
        return (offset != null && offset instanceof Number)
            ? offset as Number : 0;
    }

    // ================================================================
    // Internal
    // ================================================================

    //! Get a ContentObj at the given index from the media cache.
    //! Returns null if index is out of bounds or content is unavailable.
    private function _getContentAt(index as Number) as Media.Content? {
        if (index < 0 || index >= _refIds.size()) {
            return null;
        }
        try {
            var ref = new Media.ContentRef(_refIds[index],
                                           Media.CONTENT_TYPE_AUDIO);
            var cached = Media.getCachedContentObj(ref);
            var metadata = cached.getMetadata();
            var download = _findDownload(_uuids[index]);
            var startPosition = 0;
            var resumeDuration = 0;

            if (download != null) {
                var item = download as Dictionary;
                var title = item.get(DownloadQueue.DL_TITLE);
                var podcastTitle = item.get(DownloadQueue.DL_PODCAST_TITLE);
                if (title != null) {
                    metadata.title = title as String;
                }
                if (podcastTitle != null) {
                    metadata.artist = podcastTitle as String;
                    metadata.album = podcastTitle as String;
                }
                metadata.genre = "Podcast";
                metadata.trackNumber = index + 1;

                var queuePosition = item.get(DownloadQueue.DL_PLAYED_UP_TO);
                var queueDuration = item.get(DownloadQueue.DL_DURATION);
                if (queuePosition != null &&
                    queuePosition instanceof Number) {
                    startPosition = queuePosition as Number;
                }
                if (queueDuration != null &&
                    queueDuration instanceof Number) {
                    resumeDuration = queueDuration as Number;
                }
            }

            var position = CacheManager.loadPlaybackPosition(_uuids[index]);
            if (position != null) {
                var saved = (position as Dictionary).get("position");
                var duration = (position as Dictionary).get("duration");
                if (saved != null && saved instanceof Number &&
                    (saved as Number) > startPosition) {
                    startPosition = saved as Number;
                }
                if (duration != null && duration instanceof Number &&
                    (duration as Number) > resumeDuration) {
                    resumeDuration = duration as Number;
                }
            }
            if (resumeDuration > 0 &&
                startPosition >= resumeDuration - 5) {
                startPosition = 0;
            }
            _resumeOffsets.put(_uuids[index], startPosition);

            return new Media.ActiveContent(ref, metadata, startPosition);
        } catch (e) {
            System.println("YoCasts Iterator: getCachedContentObj failed at " +
                index);
            DownloadQueue.markMediaMissing(_uuids[index]);
            return null;
        }
    }

    private function _findDownload(uuid as String) as Dictionary? {
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var item = downloads[i] as Dictionary;
            var itemUuid = item.get(DownloadQueue.DL_UUID);
            if (itemUuid != null && (itemUuid as String).equals(uuid)) {
                return item;
            }
        }
        return null;
    }
}
