using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;

//! Queue view showing the user's Up Next episodes.
//! Uses Menu2 for scrollable list with episode title + podcast name.
//! Selecting an episode navigates to Now Playing.
class QueueView extends WatchUi.Menu2 {

    private var _service as MockPodcastService;

    function initialize(service as MockPodcastService) {
        Menu2.initialize({:title => "Up Next"});
        _service = service;
        loadQueue();
    }

    private function loadQueue() as Void {
        var queue = _service.getQueue();

        if (queue.size() == 0) {
            addItem(new WatchUi.MenuItem("Queue is empty", "Sync from phone", :empty, {}));
            return;
        }

        // Cap at 20 episodes per memory budget
        var limit = queue.size() < 20 ? queue.size() : 20;
        for (var i = 0; i < limit; i++) {
            var ep = queue[i] as Dictionary;
            var title = ep[DataKeys.E_TITLE] as String;
            var podTitle = ep[DataKeys.E_PODCAST_TITLE] as String;
            var duration = ep[DataKeys.E_DURATION] as Number;
            var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;

            // Build sublabel with podcast name and progress
            var sub = podTitle;
            if (playedUpTo > 0) {
                sub = sub + " • " + DataFormat.formatDuration(playedUpTo) + "/" + DataFormat.formatDuration(duration);
            } else {
                sub = sub + " • " + DataFormat.formatDuration(duration);
            }

            addItem(new WatchUi.MenuItem(title, sub, ep[DataKeys.E_UUID], {}));
        }
    }
}

//! Handles selection in the Queue list.
//! Selecting an episode opens Now Playing for that episode.
class QueueDelegate extends WatchUi.Menu2InputDelegate {

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

        // Find the episode data by UUID from the queue
        var queue = _service.getQueue();
        for (var i = 0; i < queue.size(); i++) {
            var ep = queue[i] as Dictionary;
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
