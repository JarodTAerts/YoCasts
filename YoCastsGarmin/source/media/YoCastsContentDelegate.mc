import Toybox.Media;
import Toybox.System;

//! Stub ContentDelegate for the native media player.
//! Handles playback events (play, pause, skip, complete).
//! Real implementation will wire to PositionTracker in Phase D.
class YoCastsContentDelegate extends Media.ContentDelegate {

    private var _iterator as YoCastsContentIterator?;

    function initialize() {
        ContentDelegate.initialize();
    }

    //! Returns the content iterator for the native media player to traverse tracks.
    function getContentIterator() {
        if (_iterator == null) {
            _iterator = new YoCastsContentIterator();
        }
        return _iterator;
    }

    //! Resets the iterator to the beginning.
    function resetContentIterator() {
        _iterator = new YoCastsContentIterator();
        return _iterator;
    }

    //! Called by the system on every playback state change.
    //! Phase D will wire this to PositionTracker for PocketCasts sync.
    function onSong(contentRefId, songEvent, playbackPosition) {
        System.println("YoCasts: song event " + songEvent + " at position " + playbackPosition);
    }

    function onShuffle() {
        // Podcasts don't shuffle
    }

    function onRepeat() {
        // Podcasts don't repeat
    }

    function onThumbsUp(contentRefId) {
        System.println("YoCasts: thumbs up");
    }

    function onThumbsDown(contentRefId) {
        System.println("YoCasts: thumbs down");
    }
}
