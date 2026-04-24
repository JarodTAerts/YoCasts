import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;

//! Queue view showing the user's Up Next episodes.
//! Custom View with manual scroll and tap hit-testing (matches HomeMenuView pattern).
class QueueView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _episodes as Array<Dictionary> = [] as Array<Dictionary>;
    private var _podcasts as Array<Dictionary> = [] as Array<Dictionary>;
    private var _scrollOffset as Number = 0;

    private const TITLE_H = 60;
    private const ITEM_H = 80;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
        loadQueue();
        System.println("YoCasts: QueueView initialized (View)");
    }

    private function loadQueue() as Void {
        var queue = _service.getQueue();
        _podcasts = _service.getSubscribedPodcasts();
        System.println("YoCasts: loadQueue() — " + queue.size() + " episodes available");

        // Cap at 20 episodes per memory budget
        var limit = queue.size() < 20 ? queue.size() : 20;
        _episodes = [] as Array<Dictionary>;
        for (var i = 0; i < limit; i++) {
            _episodes.add(queue[i] as Dictionary);
        }
        System.println("YoCasts: loadQueue() — loaded " + _episodes.size() + " episodes");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Black background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Empty state
        if (_episodes.size() == 0) {
            var label = _service.isDataReady() ? "Queue is empty" : "Loading...";
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                        Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // --- Title area (scrolls with items) ---
        var titleY = -_scrollOffset;
        if (titleY + TITLE_H > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var titleFH = dc.getFontHeight(Graphics.FONT_SMALL);
            dc.drawText(w / 2, titleY + TITLE_H - titleFH - 6,
                        Graphics.FONT_SMALL, "Queue", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // --- Episode items (scrollable, clipped to screen) ---
        dc.setClip(0, 0, w, h);
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _episodes.size(); i++) {
            var itemY = itemsStartY + i * ITEM_H;
            if (itemY + ITEM_H < 0 || itemY >= h) { continue; }
            drawEpisodeItem(dc, _episodes[i], itemY, ITEM_H, w);
        }
        dc.clearClip();
    }

    //! Draw a single episode item pill
    private function drawEpisodeItem(dc as Graphics.Dc, ep as Dictionary,
                                      y as Number, h as Number, w as Number) as Void {
        var podUuid = ep[DataKeys.E_PODCAST_UUID] as String;
        var colors = DataFormat.lookupPodcastColors(_podcasts, podUuid);
        var brandColor = colors[0] as Number;
        var tintColor = colors[1] as Number;

        var title = ep[DataKeys.E_TITLE] as String;
        var podTitle = ep[DataKeys.E_PODCAST_TITLE] as String;
        var duration = ep[DataKeys.E_DURATION] as Number;
        var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;

        // Build subtitle
        var sub = podTitle;
        if (playedUpTo > 0 && playedUpTo < duration) {
            sub = sub + " | " + DataFormat.formatDuration(playedUpTo) + "/" + DataFormat.formatDuration(duration);
        } else if (playedUpTo >= duration && duration > 0) {
            sub = sub + " | Played";
        } else {
            sub = sub + " | " + DataFormat.formatDuration(duration);
        }

        // Rounded pill layout
        var marginX = 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        // Brand-tinted rounded rect background
        var boosted = DataFormat.brightenColor(brandColor, 80);
        var bgColor = DataFormat.dimColor(boosted, 0.30);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, y + marginY, itemW, itemH, radius);

        // Accent bar inside the rounded rect (left side)
        var barColor = DataFormat.brightenColor(brandColor, 160);
        dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, y + marginY, 5, itemH, 3);

        // Title and subtitle — positioned within the rounded rect
        var textX = marginX + 14;
        var maxTextW = (marginX + itemW) - textX - 12;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var subH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = y + (h - titleH - 2 - subH) / 2;

        var titleColor = DataFormat.ensureContrast(tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        var subColor = DataFormat.dimColor(tintColor, 0.6);
        subColor = DataFormat.ensureContrast(subColor, bgColor);
        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, sub, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Scroll management (called by delegate) ---

    //! Scroll the list by a number of pixels
    function scroll(deltaPixels as Number) as Void {
        _scrollOffset = _scrollOffset + deltaPixels;
        clampScroll();
        WatchUi.requestUpdate();
    }

    //! Clamp scroll offset to valid range
    private function clampScroll() as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var contentH = TITLE_H + _episodes.size() * ITEM_H;
        var maxScroll = contentH - screenH;
        if (maxScroll < 0) { maxScroll = 0; }
        if (_scrollOffset > maxScroll) { _scrollOffset = maxScroll; }
        if (_scrollOffset < 0) { _scrollOffset = 0; }
    }

    //! Hit-test: which episode index is at screen Y? Returns -1 if none.
    function itemIndexAtY(y as Number) as Number {
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _episodes.size(); i++) {
            var top = itemsStartY + i * ITEM_H;
            if (y >= top && y < top + ITEM_H) {
                return i;
            }
        }
        return -1;
    }

    //! Get episode dictionary by index, or null if out of range
    function getEpisode(idx as Number) as Dictionary? {
        if (idx >= 0 && idx < _episodes.size()) {
            return _episodes[idx];
        }
        return null;
    }
}

// ============================================================================
// QueueDelegate — handles scroll, tap, and back for the custom View
// ============================================================================

class QueueDelegate extends WatchUi.BehaviorDelegate {

    private var _view as QueueView;
    private var _service as IPodcastService;

    function initialize(view as QueueView, service as IPodcastService) {
        BehaviorDelegate.initialize();
        _view = view;
        _service = service;
    }

    function onNextPage() as Boolean {
        _view.scroll(50);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.scroll(-50);
        return true;
    }

    function onSelect() as Boolean {
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var y = coords[1];
        System.println("YoCasts: Queue onTap at y=" + y);

        var idx = _view.itemIndexAtY(y);
        System.println("YoCasts: Queue tap hit-test → idx=" + idx);
        if (idx >= 0) {
            var ep = _view.getEpisode(idx);
            if (ep != null) {
                var detailView = new EpisodeDetailView(ep);
                var detailDelegate = new EpisodeDetailDelegate(ep);
                detailDelegate.setView(detailView);
                WatchUi.pushView(detailView, detailDelegate, WatchUi.SLIDE_UP);
                return true;
            }
        }

        return false;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
