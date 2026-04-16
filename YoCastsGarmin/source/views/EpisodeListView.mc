import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

//! Episode list for a specific podcast.
//! Shows episode titles with duration and play status.
//! Selecting an episode opens an action menu (Play / Download).
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
            var uuid = ep[DataKeys.E_UUID] as String;

            // Build sublabel with duration, play status, and download indicator
            var sub = "";
            if (status == DataKeys.STATUS_COMPLETED) {
                sub = "Played | " + DataFormat.formatDuration(duration);
            } else if (status == DataKeys.STATUS_IN_PROGRESS) {
                sub = DataFormat.formatDuration(playedUpTo) + " / " + DataFormat.formatDuration(duration);
            } else {
                sub = DataFormat.formatDuration(duration) + " | New";
            }

            // Append download status indicator
            var dlStatus = DownloadQueue.getStatus(uuid);
            if (dlStatus == DownloadQueue.STATUS_DOWNLOADED) {
                sub = sub + " | \u2705";
            } else if (dlStatus == DownloadQueue.STATUS_DOWNLOADING) {
                sub = sub + " | \u2193 " + DownloadQueue.getProgress(uuid).toString() + "%";
            } else if (dlStatus == DownloadQueue.STATUS_PENDING) {
                sub = sub + " | \u231B";
            } else if (dlStatus == DownloadQueue.STATUS_FAILED) {
                sub = sub + " | \u274C";
            }

            addItem(new WatchUi.MenuItem(title, sub, uuid, {}));
        }
    }
}

//! Handles selection in the Episode list.
//! Selecting an episode opens an action menu with Play and Download options.
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
                showEpisodeActionMenu(ep);
                return;
            }
        }
    }

    //! Show action menu for the selected episode
    private function showEpisodeActionMenu(episode as Dictionary) as Void {
        var uuid = episode[DataKeys.E_UUID] as String;
        var title = episode[DataKeys.E_TITLE] as String;

        // Truncate title for menu header
        var menuTitle = title;
        if (menuTitle.length() > 18) {
            menuTitle = menuTitle.substring(0, 15) + "...";
        }

        var menu = new WatchUi.Menu2({:title => menuTitle});

        // Play option
        menu.addItem(new WatchUi.MenuItem("Play", "Open Now Playing", :play, {}));

        // Download option (context-aware label)
        var dlStatus = DownloadQueue.getStatus(uuid);
        if (dlStatus == DownloadQueue.STATUS_DOWNLOADED) {
            menu.addItem(new WatchUi.MenuItem("Downloaded", "Ready to play", :downloaded, {}));
        } else if (dlStatus == DownloadQueue.STATUS_DOWNLOADING) {
            var pct = DownloadQueue.getProgress(uuid).toString() + "%";
            menu.addItem(new WatchUi.MenuItem("Downloading", pct, :downloading, {}));
        } else if (dlStatus == DownloadQueue.STATUS_PENDING) {
            menu.addItem(new WatchUi.MenuItem("In Queue", "Waiting to download", :inqueue, {}));
        } else {
            menu.addItem(new WatchUi.MenuItem("Download", "Save for offline", :download, {}));
        }

        WatchUi.pushView(menu, new EpisodeActionDelegate(episode), WatchUi.SLIDE_UP);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

//! Delegate for the episode action menu (Play / Download).
class EpisodeActionDelegate extends WatchUi.Menu2InputDelegate {

    private var _episode as Dictionary;

    function initialize(episode as Dictionary) {
        Menu2InputDelegate.initialize();
        _episode = episode;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :play || id == :downloaded) {
            // Pop action menu, then push Now Playing
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            var npView = new NowPlayingView(_episode);
            var npDelegate = new NowPlayingDelegate(_episode);
            npDelegate.setView(npView);
            WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
        } else if (id == :download) {
            DownloadQueue.addToQueue(_episode);
            System.println("YoCasts: download queued — " + (_episode[DataKeys.E_UUID] as String));
            // Pop back to episode list (user sees updated status on next visit)
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else {
            // :downloading, :inqueue — just dismiss
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
