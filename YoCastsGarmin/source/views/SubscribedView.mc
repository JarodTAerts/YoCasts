import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Graphics;

// ============================================================================
// Subscribed Podcasts list — Custom View with manual scroll + tap selection.
// ============================================================================
// Replaces the former CustomMenu approach which didn't reliably fire
// onSelect() in the simulator. Follows the same pattern as HomeMenuView.

class SubscribedView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _podcasts as Array<Dictionary> = [] as Array<Dictionary>;
    private var _emptyLabel as String? = null;
    private var _scrollOffset as Number = 0;

    private const TITLE_H = 60;
    private const ITEM_H = 80;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
        loadPodcasts();
        System.println("YoCasts: SubscribedView initialized (View)");
    }

    private function loadPodcasts() as Void {
        var raw = _service.getSubscribedPodcasts();
        System.println("YoCasts: loadPodcasts() — " + raw.size() + " podcasts available");

        if (raw.size() == 0) {
            _emptyLabel = _service.isDataReady() ? "No subscriptions" : "Loading...";
            System.println("YoCasts: loadPodcasts() — empty state: " + _emptyLabel);
            return;
        }

        // Cap at 30 podcasts per memory budget
        var limit = raw.size() < 30 ? raw.size() : 30;
        for (var i = 0; i < limit; i++) {
            var pod = raw[i] as Dictionary;
            _podcasts.add(pod);
        }
        System.println("YoCasts: loadPodcasts() — loaded " + limit + " podcasts");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Empty state
        if (_podcasts.size() == 0 && _emptyLabel != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - dc.getFontHeight(Graphics.FONT_TINY) / 2,
                        Graphics.FONT_TINY, _emptyLabel as String,
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Title (scrolls with content)
        var titleY = -_scrollOffset;
        if (titleY + TITLE_H > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var titleFH = dc.getFontHeight(Graphics.FONT_SMALL);
            dc.drawText(w / 2, titleY + TITLE_H - titleFH - 6,
                        Graphics.FONT_SMALL, "Podcasts", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Podcast items (clipped to screen)
        dc.setClip(0, 0, w, h);
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _podcasts.size(); i++) {
            var itemY = itemsStartY + i * ITEM_H;
            if (itemY + ITEM_H < 0 || itemY >= h) { continue; }
            drawPodcastItem(dc, _podcasts[i], itemY, ITEM_H, w);
        }
        dc.clearClip();
    }

    //! Draw a single podcast item pill
    private function drawPodcastItem(dc as Graphics.Dc, pod as Dictionary,
                                      y as Number, h as Number, w as Number) as Void {
        var title = pod[DataKeys.P_TITLE] as String;
        var author = pod[DataKeys.P_AUTHOR] as String;

        var artColorVal = pod.get(DataKeys.P_ART_COLOR);
        var artTintVal = pod.get(DataKeys.P_ART_TINT);
        var brandColor = (artColorVal != null && artColorVal instanceof Number)
                         ? (artColorVal as Number) : 0x333333;
        var tintColor = (artTintVal != null && artTintVal instanceof Number)
                        ? (artTintVal as Number) : 0xFFFFFF;

        // Pill background
        var marginX = 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        var boosted = DataFormat.brightenColor(brandColor, 80);
        var bgColor = DataFormat.dimColor(boosted, 0.35);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, y + marginY, itemW, itemH, radius);

        // Initial circle
        var iconCX = marginX + 32;
        var iconCY = y + h / 2;
        var circleR = 20;
        dc.setColor(DataFormat.brightenColor(brandColor, 140), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(iconCX, iconCY, circleR);
        dc.setColor(DataFormat.brightenColor(brandColor, 200), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(iconCX, iconCY, circleR);
        dc.setPenWidth(1);

        // Initial letter
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var initial = title.substring(0, 1);
        if (initial != null) {
            dc.drawText(iconCX, iconCY - dc.getFontHeight(Graphics.FONT_TINY) / 2,
                        Graphics.FONT_TINY, initial as String,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Title + author text
        var textX = iconCX + circleR + 10;
        var maxTextW = (marginX + itemW) - textX - 12;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var authorH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = y + (h - titleH - 2 - authorH) / 2;

        var titleColor = DataFormat.ensureContrast(tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        var authorColor = DataFormat.dimColor(tintColor, 0.65);
        authorColor = DataFormat.ensureContrast(authorColor, bgColor);
        dc.setColor(authorColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, author, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Scroll management (called by delegate) ---

    function scroll(deltaPixels as Number) as Void {
        _scrollOffset = _scrollOffset + deltaPixels;
        clampScroll();
        WatchUi.requestUpdate();
    }

    private function clampScroll() as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var contentH = TITLE_H + _podcasts.size() * ITEM_H;
        var maxScroll = contentH - screenH;
        if (maxScroll < 0) { maxScroll = 0; }
        if (_scrollOffset > maxScroll) { _scrollOffset = maxScroll; }
        if (_scrollOffset < 0) { _scrollOffset = 0; }
    }

    //! Hit-test: which podcast index is at screen Y? Returns -1 if none.
    function itemIndexAtY(y as Number) as Number {
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _podcasts.size(); i++) {
            var top = itemsStartY + i * ITEM_H;
            if (y >= top && y < top + ITEM_H) {
                return i;
            }
        }
        return -1;
    }

    //! Get podcast dictionary by index
    function getPodcast(idx as Number) as Dictionary {
        return _podcasts[idx];
    }
}

// ============================================================================
// SubscribedDelegate — handles scroll, tap, and back for the custom View
// ============================================================================

class SubscribedDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SubscribedView;
    private var _service as IPodcastService;

    function initialize(view as SubscribedView, service as IPodcastService) {
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
        System.println("YoCasts: SubscribedView onTap at y=" + y);

        var idx = _view.itemIndexAtY(y);
        if (idx < 0) {
            return false;
        }

        var pod = _view.getPodcast(idx);
        var podcastUuid = pod[DataKeys.P_UUID] as String;
        var podcastTitle = pod[DataKeys.P_TITLE] as String;
        System.println("YoCasts: SubscribedView tapped podcast " + podcastUuid);

        var episodeView = new EpisodeListView(_service, podcastUuid, podcastTitle);
        WatchUi.pushView(episodeView,
                         new EpisodeListDelegate(episodeView, _service, podcastUuid),
                         WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

//! Simple empty-state item for CustomMenu (used by QueueView)
class EmptyStateMenuItem extends WatchUi.CustomMenuItem {

    private var _text as String;

    function initialize(text as String) {
        CustomMenuItem.initialize(:empty, {});
        _text = text;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(w / 2, h / 2 - dc.getFontHeight(Graphics.FONT_TINY) / 2,
                    Graphics.FONT_TINY, _text, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
