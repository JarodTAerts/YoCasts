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
    private var _selectedIndex as Number = 0;

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
        _podcasts = [] as Array<Dictionary>;
        _emptyLabel = null;
        System.println("YoCasts: loadPodcasts() — " + raw.size() + " podcasts available");

        if (raw.size() == 0) {
            var error = _service.getLastError();
            _emptyLabel = error.length() > 0
                ? error
                : (_service.isDataReady() ? "No subscriptions" : "Loading...");
            System.println("YoCasts: loadPodcasts() — empty state: " + _emptyLabel);
            return;
        }

        // Cap at 30 podcasts per memory budget
        var limit = raw.size() < 30 ? raw.size() : 30;
        for (var i = 0; i < limit; i++) {
            var pod = raw[i] as Dictionary;
            _podcasts.add(pod);
        }
        if (_selectedIndex >= _podcasts.size()) {
            _selectedIndex = _podcasts.size() > 0 ? _podcasts.size() - 1 : 0;
        }
        clampScroll();
        System.println("YoCasts: loadPodcasts() — loaded " + limit + " podcasts");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        loadPodcasts();

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
            drawPodcastItem(dc, _podcasts[i], itemY, ITEM_H, w,
                            i == _selectedIndex);
        }
        dc.clearClip();
        drawScrollIndicators(dc);
    }

    //! Draw a single podcast item pill
    private function drawPodcastItem(dc as Graphics.Dc, pod as Dictionary,
                                      y as Number, h as Number, w as Number,
                                      selected as Boolean) as Void {
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
        if (selected) {
            dc.setColor(DataFormat.brightenColor(brandColor, 180),
                        Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(
                marginX, y + marginY, itemW, itemH, radius
            );
            dc.setPenWidth(1);
        }

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

    function moveSelection(delta as Number) as Void {
        if (_podcasts.size() == 0) { return; }
        _selectedIndex += delta;
        if (_selectedIndex < 0) {
            _selectedIndex = _podcasts.size() - 1;
        } else if (_selectedIndex >= _podcasts.size()) {
            _selectedIndex = 0;
        }

        var screenH = System.getDeviceSettings().screenHeight;
        var itemTop = TITLE_H + _selectedIndex * ITEM_H;
        var itemBottom = itemTop + ITEM_H;
        if (itemTop < _scrollOffset) {
            _scrollOffset = itemTop;
        } else if (itemBottom > _scrollOffset + screenH) {
            _scrollOffset = itemBottom - screenH;
        }
        clampScroll();
        WatchUi.requestUpdate();
    }

    function setSelectedIndex(index as Number) as Void {
        if (index >= 0 && index < _podcasts.size()) {
            _selectedIndex = index;
        }
    }

    function getSelectedIndex() as Number {
        return _selectedIndex;
    }

    private function clampScroll() as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var contentH = TITLE_H + _podcasts.size() * ITEM_H;
        var maxScroll = contentH - screenH;
        if (maxScroll < 0) { maxScroll = 0; }
        if (_scrollOffset > maxScroll) { _scrollOffset = maxScroll; }
        if (_scrollOffset < 0) { _scrollOffset = 0; }
    }

    private function drawScrollIndicators(dc as Graphics.Dc) as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var maxScroll = TITLE_H + _podcasts.size() * ITEM_H - screenH;
        if (maxScroll < 0) { maxScroll = 0; }
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (_scrollOffset > 0) {
            dc.fillPolygon([[265, 25], [277, 25], [271, 16]]);
        }
        if (_scrollOffset < maxScroll) {
            dc.fillPolygon([[265, 363], [277, 363], [271, 372]]);
        }
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
        _view.moveSelection(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.moveSelection(-1);
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

        _view.setSelectedIndex(idx);
        return openPodcast(idx);
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_DOWN) {
            _view.moveSelection(1);
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            _view.moveSelection(-1);
            return true;
        }
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            return openPodcast(_view.getSelectedIndex());
        }
        if (key == WatchUi.KEY_ESC) {
            return onBack();
        }
        return false;
    }

    private function openPodcast(index as Number) as Boolean {
        if (_service.getSubscribedPodcasts().size() == 0) {
            return false;
        }
        var pod = _view.getPodcast(index);
        var detailView = new PodcastDetailView(_service, pod);
        WatchUi.pushView(
            detailView,
            new PodcastDetailDelegate(detailView),
            WatchUi.SLIDE_UP
        );
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
