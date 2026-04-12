using Toybox.Lang;

//! Interface contract for podcast data services.
//! Implementations can provide mock data or real API data.
//! The real implementation will use Communications.makeWebRequest
//! to hit the PocketCasts API through the phone companion.
//!
//! All methods return data synchronously for mock, but the real
//! implementation will use callbacks. Views should handle both patterns.
class IPodcastService {

    //! Get list of subscribed podcasts.
    //! Returns: Array of Dictionary with keys from DataKeys.P_*
    function getSubscribedPodcasts() as Array<Dictionary> {
        return [] as Array<Dictionary>;
    }

    //! Get episodes for a specific podcast.
    //! @param podcastUuid UUID of the podcast
    //! Returns: Array of Dictionary with keys from DataKeys.E_*
    function getEpisodesForPodcast(podcastUuid as String) as Array<Dictionary> {
        return [] as Array<Dictionary>;
    }

    //! Get the Up Next queue (user-curated play queue).
    //! Returns: Array of Dictionary with keys from DataKeys.E_*
    function getQueue() as Array<Dictionary> {
        return [] as Array<Dictionary>;
    }

    //! Get the currently playing episode info.
    //! Returns: Dictionary with episode data, or null if nothing playing
    function getNowPlaying() as Dictionary? {
        return null;
    }
}
