import Toybox.Lang;
import Toybox.Time;

//! Shared playback state module — single source of truth for what's playing.
//! Written by: ContentDelegate (device, real native playback events) or
//!             NowPlayingView (sim, mock local playback).
//! Read by:    HomeMenuView (dock display), NowPlayingView (initial state).
module PlaybackState {

    var isPlaying as Boolean = false;
    var currentUuid as String = "";
    var currentPodcastUuid as String = "";
    var currentTitle as String = "";
    var currentPodcastTitle as String = "";
    var currentPosition as Number = 0;
    var currentDuration as Number = 0;
    var lastEventTime as Number = 0;

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
    }

    //! Update position only (from timer tick or onSong event).
    function updatePosition(position as Number) as Void {
        currentPosition = position;
        lastEventTime = Time.now().value();
    }

    //! Toggle or set playing state.
    function setPlaying(playing as Boolean) as Void {
        isPlaying = playing;
        lastEventTime = Time.now().value();
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
    }
}
