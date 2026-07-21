import Toybox.Lang;

//! Interface contract for podcast data services.
//! Implementations can provide mock data or real API data.
//!
//! Synchronous getters return cached data (immediately available for mock,
//! populated asynchronously for the real API service). Async methods trigger
//! network fetches; when data arrives, WatchUi.requestUpdate() is called
//! so views redraw with fresh data.
class IPodcastService {

    //! Whether the service has authenticated with PocketCasts
    function isAuthenticated() as Boolean {
        return false;
    }

    //! Whether initial data (podcasts + queue) has been loaded
    function isDataReady() as Boolean {
        return false;
    }

    function isLoading() as Boolean {
        return false;
    }

    function getLastError() as String {
        return "";
    }

    function hasLoadedPodcasts() as Boolean {
        return false;
    }

    function hasLoadedQueue() as Boolean {
        return false;
    }

    //! Whether episode data for a specific podcast is cached
    function hasEpisodesForPodcast(podcastUuid as String) as Boolean {
        return getEpisodesForPodcast(podcastUuid).size() > 0;
    }

    //! Trigger async fetch of all data (login → podcasts → queue).
    //! Calls WatchUi.requestUpdate() when each stage completes.
    function fetchAll() as Void {
    }

    //! Trigger async fetch of episodes for a specific podcast.
    //! Results populate the cache returned by getEpisodesForPodcast().
    function requestEpisodesForPodcast(podcastUuid as String) as Void {
    }

    //! Fetch extended show notes for one episode on demand.
    function requestEpisodeDetails(episodeUuid as String) as Void {
    }

    function getEpisodeDetails(episodeUuid as String) as Dictionary? {
        return null;
    }

    //! Push cached offline changes when foreground connectivity is available.
    function syncPendingChanges() as Void {
    }

    //! Get cached list of subscribed podcasts.
    //! Returns: Array of Dictionary with keys from DataKeys.P_*
    function getSubscribedPodcasts() as Array<Dictionary> {
        return [] as Array<Dictionary>;
    }

    //! Get cached episodes for a specific podcast.
    //! @param podcastUuid UUID of the podcast
    //! Returns: Array of Dictionary with keys from DataKeys.E_*
    function getEpisodesForPodcast(podcastUuid as String) as Array<Dictionary> {
        return [] as Array<Dictionary>;
    }

    //! Get cached Up Next queue (user-curated play queue).
    //! Returns: Array of Dictionary with keys from DataKeys.E_*
    function getQueue() as Array<Dictionary> {
        return [] as Array<Dictionary>;
    }

    //! Get the currently playing episode info.
    //! Returns: Dictionary with episode data, or null if nothing playing
    function getNowPlaying() as Dictionary? {
        return null;
    }

    //! Get the current access token for authenticated API calls.
    //! Returns empty string if not authenticated.
    function getAccessToken() as String {
        return "";
    }
}
