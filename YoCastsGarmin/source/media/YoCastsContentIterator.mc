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

    private var _refIds as Array<String> = [] as Array<String>;
    private var _uuids as Array<String> = [] as Array<String>;
    private var _currentIndex as Number = -1;

    function initialize() {
        ContentIterator.initialize();
        _buildPlaylist();
    }

    //! Build playlist from downloaded episodes in DownloadQueue order.
    private function _buildPlaylist() as Void {
        _refIds = [] as Array<String>;
        _uuids = [] as Array<String>;

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

            _refIds.add(refId as String);
            _uuids.add(uuid as String);
        }

        if (_refIds.size() > 0) {
            _currentIndex = 0;
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
            Media.PLAYBACK_CONTROL_SKIP_BACKWARD,
            Media.PLAYBACK_CONTROL_PLAYBACK,
            Media.PLAYBACK_CONTROL_SKIP_FORWARD
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
    function getCurrentRefId() as String {
        if (_currentIndex >= 0 && _currentIndex < _refIds.size()) {
            return _refIds[_currentIndex];
        }
        return "";
    }

    //! Number of playable episodes in the playlist.
    function getPlaylistSize() as Number {
        return _refIds.size();
    }

    //! Look up UUID for a given ContentRef ID (reverse mapping).
    function getUuidForRefId(refId as String) as String {
        for (var i = 0; i < _refIds.size(); i++) {
            if (_refIds[i].equals(refId)) {
                return _uuids[i];
            }
        }
        return "";
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
            return Media.getCachedContentObj(ref);
        } catch (e) {
            System.println("YoCasts Iterator: getCachedContentObj failed at " +
                index);
            return null;
        }
    }
}
