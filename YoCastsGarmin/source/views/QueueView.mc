import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;

//! Queue view showing the user's Up Next episodes.
//! Uses Menu2 with custom colored items per podcast brand.
//! Selecting an episode navigates to Now Playing.
class QueueView extends WatchUi.Menu2 {

    private var _service as IPodcastService;

    function initialize(service as IPodcastService) {
        Menu2.initialize({:title => "Queue"});
        _service = service;
        loadQueue();
    }

    private function loadQueue() as Void {
        var queue = _service.getQueue();

        if (queue.size() == 0) {
            var sub = _service.isDataReady() ? "Sync from phone" : "Loading...";
            addItem(new WatchUi.MenuItem(
                _service.isDataReady() ? "Queue is empty" : "Loading...",
                sub, :empty, {}));
            return;
        }

        var podcasts = _service.getSubscribedPodcasts();

        // Cap at 20 episodes per memory budget
        var limit = queue.size() < 20 ? queue.size() : 20;
        for (var i = 0; i < limit; i++) {
            var ep = queue[i] as Dictionary;
            var title = ep[DataKeys.E_TITLE] as String;
            var podTitle = ep[DataKeys.E_PODCAST_TITLE] as String;
            var duration = ep[DataKeys.E_DURATION] as Number;
            var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;
            var podUuid = ep[DataKeys.E_PODCAST_UUID] as String;

            // Build sublabel with podcast name, progress, and status
            var sub = podTitle;
            if (playedUpTo > 0 && playedUpTo < duration) {
                sub = sub + " | " + DataFormat.formatDuration(playedUpTo) + "/" + DataFormat.formatDuration(duration);
            } else if (playedUpTo >= duration && duration > 0) {
                sub = sub + " | Played";
            } else {
                sub = sub + " | " + DataFormat.formatDuration(duration);
            }

            // Look up parent podcast brand colors
            var colors = DataFormat.lookupPodcastColors(podcasts, podUuid);
            var artColor = colors[0] as Number;
            var artTint = colors[1] as Number;

            addItem(new QueueEpisodeMenuItem(
                ep[DataKeys.E_UUID] as String, title, sub, artColor, artTint));
        }
    }
}

//! Handles selection in the Queue list.
//! Selecting an episode opens Now Playing for that episode.
class QueueDelegate extends WatchUi.Menu2InputDelegate {

    private var _service as IPodcastService;

    function initialize(service as IPodcastService) {
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

//! Custom menu item for queue episodes with podcast brand color tinting.
class QueueEpisodeMenuItem extends WatchUi.CustomMenuItem {

    private var _title as String;
    private var _subtitle as String;
    private var _brandColor as Number;
    private var _tintColor as Number;

    function initialize(id as String, title as String, subtitle as String,
                        brandColor as Number, tintColor as Number) {
        CustomMenuItem.initialize(id, {:height => 80});
        setLabel(title);
        _title = title;
        _subtitle = subtitle;
        _brandColor = brandColor;
        _tintColor = tintColor;
    }

    function draw(dc as Graphics.Dc) as Void {
        System.println("YoCasts: QueueEpisodeMenuItem.draw() called — " + _title);
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Brightened brand color for visible background tint
        var boosted = DataFormat.brightenColor(_brandColor, 80);
        var factor = isFocused() ? 0.55 : 0.30;
        var bgColor = DataFormat.dimColor(boosted, factor);
        dc.setColor(Graphics.COLOR_WHITE, bgColor);
        dc.clear();

        // Accent bar on left edge (boosted for visibility)
        var barColor = DataFormat.brightenColor(_brandColor, 160);
        dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, 4, h);

        // Title and subtitle layout
        var textX = 14;
        var maxTextW = w - textX - 8;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var subH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = (h - titleH - 2 - subH) / 2;

        // Title in tint color (contrast-checked)
        var titleColor = DataFormat.ensureContrast(_tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, _title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Subtitle in dimmed tint
        var subColor = DataFormat.dimColor(_tintColor, 0.6);
        subColor = DataFormat.ensureContrast(subColor, bgColor);
        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, _subtitle, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }
}
