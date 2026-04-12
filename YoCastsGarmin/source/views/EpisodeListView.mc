import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

//! Episode list for a specific podcast.
//! Shows episode titles with duration and play status.
//! Selecting an episode navigates to Now Playing.
class EpisodeListView extends WatchUi.Menu2 {

    private var _service as IPodcastService;
    private var _podcastUuid as String;

    function initialize(service as IPodcastService, podcastUuid as String, podcastTitle as String) {
        // Truncate title for menu header
        var menuTitle = podcastTitle;
        if (menuTitle.length() > 18) {
            menuTitle = menuTitle.substring(0, 15) + "...";
        }
        Menu2.initialize({:title => menuTitle});
        _service = service;
        _podcastUuid = podcastUuid;
        loadEpisodes();
    }

    private function loadEpisodes() as Void {
        // Trigger async fetch if not already cached
        if (!_service.hasEpisodesForPodcast(_podcastUuid)) {
            _service.requestEpisodesForPodcast(_podcastUuid);
        }

        var episodes = _service.getEpisodesForPodcast(_podcastUuid);

        if (episodes.size() == 0) {
            var label = _service.hasEpisodesForPodcast(_podcastUuid) ? "No episodes" : "Loading...";
            addItem(new WatchUi.MenuItem(label, "", :empty, {}));
            return;
        }

        // Cap at 15 episodes per memory budget
        var limit = episodes.size() < 15 ? episodes.size() : 15;
        for (var i = 0; i < limit; i++) {
            var ep = episodes[i] as Dictionary;
            var title = ep[DataKeys.E_TITLE] as String;
            var duration = ep[DataKeys.E_DURATION] as Number;
            var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;
            var status = ep[DataKeys.E_PLAYING_STATUS] as Number;

            // Build sublabel with duration and play status
            var sub = DataFormat.formatDuration(duration);
            if (status == DataKeys.STATUS_COMPLETED) {
                sub = sub + " • Played";
            } else if (status == DataKeys.STATUS_IN_PROGRESS) {
                sub = DataFormat.formatDuration(playedUpTo) + " / " + sub;
            }

            addItem(new WatchUi.MenuItem(title, sub, ep[DataKeys.E_UUID] as String, {}));
        }
    }
}

//! Handles selection in the Episode list.
//! Selecting an episode opens Now Playing for that episode.
class EpisodeListDelegate extends WatchUi.Menu2InputDelegate {

    private var _service as IPodcastService;
    private var _podcastUuid as String;

    function initialize(service as IPodcastService, podcastUuid as String) {
        Menu2InputDelegate.initialize();
        _service = service;
        _podcastUuid = podcastUuid;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :empty) {
            return;
        }

        // Find the episode data
        var episodes = _service.getEpisodesForPodcast(_podcastUuid);
        for (var i = 0; i < episodes.size(); i++) {
            var ep = episodes[i] as Dictionary;
            if ((ep[DataKeys.E_UUID] as String).equals(id)) {
                var npView = new NowPlayingView(ep);
                var npDelegate = new NowPlayingDelegate(ep);
                npDelegate.setView(npView);
                WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
                return;
            }
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
