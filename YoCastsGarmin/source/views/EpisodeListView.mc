import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Graphics;

// ============================================================================
// Episode list (v2.0) — Custom View with manual scroll + tap hit-testing.
// ============================================================================
// Replaces CustomMenu approach which didn't reliably fire onSelect() in the
// simulator. Follows the same pattern as HomeMenuView.

class EpisodeListView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _podcastUuid as String;
    private var _menuTitle as String;

    private var _episodes as Array<Dictionary>;
    private var _artColor as Number = 0x55AAFF;
    private var _artTint as Number = 0xCCCCCC;
    private var _scrollOffset as Number = 0;
    private var _selectedIndex as Number = 0;

    private const TITLE_H = 60;
    private const ITEM_H = 88;
    private const MAX_EPISODES = 15;

    function initialize(service as IPodcastService, podcastUuid as String, podcastTitle as String) {
        View.initialize();
        _service = service;
        _podcastUuid = podcastUuid;
        _menuTitle = podcastTitle;
        if (_menuTitle.length() > 18) {
            _menuTitle = (_menuTitle.substring(0, 15) as String) + "...";
        }
        _episodes = [] as Array<Dictionary>;
        loadEpisodes();
        System.println("YoCasts: EpisodeListView initialized (View v2.0) for '" + podcastTitle + "'");
    }

    private function loadEpisodes() as Void {
        if (!_service.hasEpisodesForPodcast(_podcastUuid)) {
            _service.requestEpisodesForPodcast(_podcastUuid);
        }

        var episodes = _service.getEpisodesForPodcast(_podcastUuid);
        System.println("YoCasts: loadEpisodes() — " + episodes.size() + " episodes for " + _podcastUuid);

        var limit = episodes.size() < MAX_EPISODES ? episodes.size() : MAX_EPISODES;
        _episodes = episodes.slice(0, limit) as Array<Dictionary>;
        if (_selectedIndex >= _episodes.size()) {
            _selectedIndex = _episodes.size() > 0 ? _episodes.size() - 1 : 0;
        }
        clampScroll();

        // Look up parent podcast brand colors
        var podcasts = _service.getSubscribedPodcasts();
        var colors = DataFormat.lookupPodcastColors(podcasts, _podcastUuid);
        _artColor = colors[0] as Number;
        _artTint = colors[1] as Number;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Refresh episode data each render (catches async loads)
        loadEpisodes();
        var count = _episodes.size();

        // --- Title area (scrolls with content) ---
        var titleY = -_scrollOffset;
        if (titleY + TITLE_H > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                w / 2,
                titleY + 28,
                Graphics.FONT_TINY,
                DataFormat.truncateText(
                    dc,
                    _menuTitle,
                    Graphics.FONT_TINY,
                    190
                ),
                Graphics.TEXT_JUSTIFY_CENTER |
                Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        // --- Empty state ---
        if (count == 0) {
            var error = _service.getLastError();
            var label = error.length() > 0
                ? error
                : (_service.hasEpisodesForPodcast(_podcastUuid)
                    ? "No episodes" : "Loading...");
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                        Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // --- Episode items (scrollable, clipped to screen) ---
        dc.setClip(0, 0, w, h);
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < count; i++) {
            var itemY = itemsStartY + i * ITEM_H;
            if (itemY + ITEM_H < 0 || itemY >= h) { continue; }
            drawEpisodeItem(dc, _episodes[i], itemY, w,
                            i == _selectedIndex);
        }
        dc.clearClip();
        drawScrollIndicators(dc);
    }

    //! Draw a single episode item pill
    private function drawEpisodeItem(dc as Graphics.Dc, ep as Dictionary,
                                      y as Number, w as Number,
                                      selected as Boolean) as Void {
        var title = ep[DataKeys.E_TITLE] as String;
        var duration = ep[DataKeys.E_DURATION] as Number;
        var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;
        var status = ep[DataKeys.E_PLAYING_STATUS] as Number;
        var uuid = ep[DataKeys.E_UUID] as String;

        // Build subtitle
        var sub = "";
        if (status == DataKeys.STATUS_COMPLETED) {
            sub = "Played | " + DataFormat.formatDuration(duration);
        } else if (status == DataKeys.STATUS_IN_PROGRESS) {
            sub = DataFormat.formatDuration(playedUpTo) + " / " + DataFormat.formatDuration(duration);
        } else {
            sub = DataFormat.formatDuration(duration) + " | New";
        }
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

        // Pill layout
        var marginX = 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = ITEM_H - 2 * marginY;
        var radius = 14;

        // Brand-tinted rounded rect background
        var boosted = DataFormat.brightenColor(_artColor, 80);
        var bgColor = DataFormat.dimColor(boosted, 0.25);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, y + marginY, itemW, itemH, radius);
        if (selected) {
            dc.setColor(DataFormat.brightenColor(_artColor, 180),
                        Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(
                marginX, y + marginY, itemW, itemH, radius
            );
            dc.setPenWidth(1);
        }

        // Status indicator dot
        var dotCX = marginX + 14;
        var dotCY = y + ITEM_H / 2;
        if (status == DataKeys.STATUS_IN_PROGRESS) {
            dc.setColor(DataFormat.brightenColor(_artColor, 160), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dotCX, dotCY, 4);
        } else if (status == DataKeys.STATUS_NOT_PLAYED) {
            dc.setColor(_artTint, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dotCX, dotCY, 4);
        } else {
            dc.setColor(DataFormat.brightenColor(_artColor, 100), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawArc(dotCX, dotCY, 4, Graphics.ARC_CLOCKWISE, 0, 360);
        }

        // Title + subtitle text
        var textX = dotCX + 12;
        var maxTextW = (marginX + itemW) - textX - 12;
        var titleFH = dc.getFontHeight(Graphics.FONT_TINY);
        var subFH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = y + (ITEM_H - titleFH - 2 - subFH) / 2;

        var titleColor = DataFormat.ensureContrast(_artTint, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        var subColor = DataFormat.dimColor(_artTint, 0.55);
        subColor = DataFormat.ensureContrast(subColor, bgColor);
        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleFH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, sub, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Scroll management (called by delegate) ---

    function scroll(deltaPixels as Number) as Void {
        _scrollOffset = _scrollOffset + deltaPixels;
        clampScroll();
        WatchUi.requestUpdate();
    }

    function moveSelection(delta as Number) as Void {
        if (_episodes.size() == 0) { return; }
        _selectedIndex += delta;
        if (_selectedIndex < 0) {
            _selectedIndex = _episodes.size() - 1;
        } else if (_selectedIndex >= _episodes.size()) {
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
        if (index >= 0 && index < _episodes.size()) {
            _selectedIndex = index;
        }
    }

    function getSelectedIndex() as Number {
        return _selectedIndex;
    }

    private function clampScroll() as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var contentH = TITLE_H + _episodes.size() * ITEM_H;
        var maxScroll = contentH - screenH;
        if (maxScroll < 0) { maxScroll = 0; }
        if (_scrollOffset > maxScroll) { _scrollOffset = maxScroll; }
        if (_scrollOffset < 0) { _scrollOffset = 0; }
    }

    private function drawScrollIndicators(dc as Graphics.Dc) as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var maxScroll = TITLE_H + _episodes.size() * ITEM_H - screenH;
        if (maxScroll < 0) { maxScroll = 0; }
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (_scrollOffset > 0) {
            dc.fillPolygon([[265, 25], [277, 25], [271, 16]]);
        }
        if (_scrollOffset < maxScroll) {
            dc.fillPolygon([[265, 363], [277, 363], [271, 372]]);
        }
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

    //! Get episode dictionary by index, or null if out of range.
    function getEpisode(idx as Number) as Dictionary? {
        if (idx < 0 || idx >= _episodes.size()) {
            return null;
        }
        return _episodes[idx];
    }
}

// ============================================================================
// EpisodeListDelegate — handles scroll, tap, and back for the episode list.
// ============================================================================

class EpisodeListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as EpisodeListView;
    private var _service as IPodcastService;
    private var _podcastUuid as String;

    function initialize(view as EpisodeListView, service as IPodcastService, podcastUuid as String) {
        BehaviorDelegate.initialize();
        _view = view;
        _service = service;
        _podcastUuid = podcastUuid;
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
        System.println("YoCasts: EpisodeList onTap at y=" + y);

        var idx = _view.itemIndexAtY(y);
        System.println("YoCasts: EpisodeList tap hit-test -> idx=" + idx);
        if (idx >= 0) {
            _view.setSelectedIndex(idx);
            return openEpisode(idx);
        }
        return false;
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
            return openEpisode(_view.getSelectedIndex());
        }
        if (key == WatchUi.KEY_ESC) {
            return onBack();
        }
        return false;
    }

    private function openEpisode(index as Number) as Boolean {
        var ep = _view.getEpisode(index);
        if (ep == null) { return false; }
        var detailView = new EpisodeDetailView(
            ep as Dictionary,
            _service
        );
        var detailDelegate = new EpisodeDetailDelegate(
            ep as Dictionary,
            _service
        );
        detailDelegate.setView(detailView);
        WatchUi.pushView(detailView, detailDelegate, WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
