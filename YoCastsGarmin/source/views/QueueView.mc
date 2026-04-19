import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;

//! Queue view showing the user's Up Next episodes.
//! Uses CustomMenu so CustomMenuItem.draw() is invoked by the runtime.
//! Selecting an episode navigates to Now Playing.
class QueueView extends WatchUi.CustomMenu {

    private var _service as IPodcastService;

    function initialize(service as IPodcastService) {
        CustomMenu.initialize(80, Graphics.COLOR_BLACK, {:titleItemHeight => 50});
        _service = service;
        loadQueue();
        System.println("YoCasts: QueueView initialized (CustomMenu)");
    }

    //! Draw the "Queue" title area — centered for round display
    function drawTitle(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2 - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                    Graphics.FONT_SMALL, "Queue", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function loadQueue() as Void {
        var queue = _service.getQueue();
        System.println("YoCasts: loadQueue() — " + queue.size() + " episodes available");

        if (queue.size() == 0) {
            var label = _service.isDataReady() ? "Queue is empty" : "Loading...";
            System.println("YoCasts: loadQueue() — empty state: " + label);
            addItem(new EmptyStateMenuItem(label));
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
            System.println("YoCasts: queue[" + i + "] '" + title + "' color=0x" + artColor.format("%06X") + " tint=0x" + artTint.format("%06X"));

            addItem(new QueueEpisodeMenuItem(
                ep[DataKeys.E_UUID] as String, title, sub, artColor, artTint));
        }
        System.println("YoCasts: loadQueue() — added " + limit + " QueueEpisodeMenuItems to CustomMenu");
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
        CustomMenuItem.initialize(id, {});
        _title = title;
        _subtitle = subtitle;
        _brandColor = brandColor;
        _tintColor = tintColor;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // AMOLED black surround
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Rounded pill layout
        var marginX = isFocused() ? 12 : 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        // Brand-tinted rounded rect background
        var boosted = DataFormat.brightenColor(_brandColor, 80);
        var factor = isFocused() ? 0.55 : 0.30;
        var bgColor = DataFormat.dimColor(boosted, factor);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, marginY, itemW, itemH, radius);

        // Subtle focus border
        if (isFocused()) {
            var borderColor = DataFormat.brightenColor(_brandColor, 160);
            dc.setColor(borderColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(marginX, marginY, itemW, itemH, radius);
        }

        // Accent bar inside the rounded rect (left side)
        var barColor = DataFormat.brightenColor(_brandColor, 160);
        dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, marginY, 5, itemH, 3);

        // Title and subtitle — positioned within the rounded rect
        var textX = marginX + 14;
        var maxTextW = (marginX + itemW) - textX - 12;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var subH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = (h - titleH - 2 - subH) / 2;

        var titleColor = DataFormat.ensureContrast(_tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, _title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        var subColor = DataFormat.dimColor(_tintColor, 0.6);
        subColor = DataFormat.ensureContrast(subColor, bgColor);
        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, _subtitle, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }
}
