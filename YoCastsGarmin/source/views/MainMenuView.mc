import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

//! Handles selection from the Home menu.
//! Routes to Queue, Podcasts, or Now Playing screens.
class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _service as MockPodcastService;

    function initialize(service as MockPodcastService) {
        Menu2InputDelegate.initialize();
        _service = service;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :queue) {
            var queueView = new QueueView(_service);
            WatchUi.pushView(queueView, new QueueDelegate(_service), WatchUi.SLIDE_UP);
        } else if (id == :podcasts) {
            var podView = new SubscribedView(_service);
            WatchUi.pushView(podView, new SubscribedDelegate(_service), WatchUi.SLIDE_UP);
        } else if (id == :nowPlaying) {
            var ep = _service.getNowPlaying();
            if (ep != null) {
                var npView = new NowPlayingView(ep);
                var npDelegate = new NowPlayingDelegate(ep);
                npDelegate.setView(npView);
                WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
            }
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
