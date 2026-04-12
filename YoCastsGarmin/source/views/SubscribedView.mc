import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

//! Subscribed Podcasts list view.
//! Shows all podcasts the user is subscribed to via PocketCasts.
//! Selecting a podcast navigates to its episode list.
class SubscribedView extends WatchUi.Menu2 {

    private var _service as MockPodcastService;

    function initialize(service as MockPodcastService) {
        Menu2.initialize({:title => "Podcasts"});
        _service = service;
        loadPodcasts();
    }

    private function loadPodcasts() as Void {
        var podcasts = _service.getSubscribedPodcasts();

        if (podcasts.size() == 0) {
            addItem(new WatchUi.MenuItem("No subscriptions", "Sync from phone", :empty, {}));
            return;
        }

        // Cap at 30 podcasts per memory budget
        var limit = podcasts.size() < 30 ? podcasts.size() : 30;
        for (var i = 0; i < limit; i++) {
            var pod = podcasts[i] as Dictionary;
            var title = pod[DataKeys.P_TITLE] as String;
            var author = pod[DataKeys.P_AUTHOR] as String;
            var uuid = pod[DataKeys.P_UUID] as String;

            addItem(new WatchUi.MenuItem(title, author, uuid, {}));
        }
    }
}

//! Handles selection in the Subscribed Podcasts list.
//! Selecting a podcast pushes the EpisodeListView for that podcast.
class SubscribedDelegate extends WatchUi.Menu2InputDelegate {

    private var _service as MockPodcastService;

    function initialize(service as MockPodcastService) {
        Menu2InputDelegate.initialize();
        _service = service;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :empty) {
            return;
        }

        var podcastUuid = id as String;
        var podcastTitle = item.getLabel();

        var episodeView = new EpisodeListView(_service, podcastUuid, podcastTitle);
        WatchUi.pushView(episodeView,
                         new EpisodeListDelegate(_service, podcastUuid),
                         WatchUi.SLIDE_UP);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
