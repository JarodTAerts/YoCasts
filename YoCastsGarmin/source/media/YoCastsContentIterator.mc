import Toybox.Media;

//! Stub ContentIterator for browsing downloaded episodes.
//! Returns null for all content methods since no episodes are downloaded yet.
//! Real implementation will walk the download queue in Phase D.
class YoCastsContentIterator extends Media.ContentIterator {

    function initialize() {
        ContentIterator.initialize();
    }

    //! Returns the current track (null — nothing downloaded yet).
    function get() {
        return null;
    }

    //! Advance to next track.
    function next() {
        return null;
    }

    //! Go to previous track.
    function previous() {
        return null;
    }

    //! Preview next without advancing.
    function peekNext() {
        return null;
    }

    //! Preview previous without going back.
    function peekPrevious() {
        return null;
    }

    //! All podcast episodes are skippable.
    function canSkip() {
        return true;
    }

    //! Podcast playback profile — skip intervals, notification thresholds.
    function getPlaybackProfile() {
        var profile = new Media.PlaybackProfile();
        profile.playbackControls = [
            Media.PLAYBACK_CONTROL_SKIP_BACKWARD,
            Media.PLAYBACK_CONTROL_PLAYBACK,
            Media.PLAYBACK_CONTROL_SKIP_FORWARD
        ];
        profile.skipForwardTimeDelta = 30;
        profile.skipBackwardTimeDelta = 15;
        profile.requirePlaybackNotification = true;
        profile.playbackNotificationThreshold = 30;
        return profile;
    }

    //! Podcasts don't shuffle.
    function shuffling() {
        return false;
    }
}
