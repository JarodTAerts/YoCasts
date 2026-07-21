import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

//! Downloads view — shows all downloaded and in-progress episodes.
//! Custom View with readable two-line items, scrollable via swipe/buttons.
//! Uses podcast brand color tinting (same pattern as QueueView/EpisodeListView).
class DownloadsView extends WatchUi.View {

    private var _scrollOffset as Number = 0;
    private var _selectedIndex as Number = 0;
    private var _toastMessage as String? = null;
    private var _toastTimer as Timer.Timer? = null;
    private var _podcasts as Array<Dictionary>?;

    // Layout constants matching HomeMenuView spec
    private const ITEM_HEIGHT = 108;
    private const ITEM_GAP = 8;
    private const ITEM_STRIDE = 116;
    private const ITEM_X = 40;
    private const ITEM_WIDTH = 310;
    private const ITEM_CORNER_R = 18;
    private const TITLE_Y_OFFSET = 72;
    private const SCROLL_STEP = 116;
    private const VISIBLE_TOP = 62;
    private const VISIBLE_BOTTOM = 378;

    function initialize() {
        View.initialize();
        _podcasts = CacheManager.loadPodcasts();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var downloads = DownloadQueue.getDownloads();
        var cx = 195;

        // Title
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_TINY, "Downloads",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (downloads.size() == 0) {
            drawEmptyState(dc, cx);
            return;
        }

        var podcasts = _podcasts != null ? _podcasts as Array<Dictionary> : [] as Array<Dictionary>;

        // Clip to content area (below title, above bottom curve)
        dc.setClip(0, VISIBLE_TOP, 390, VISIBLE_BOTTOM - VISIBLE_TOP);

        for (var i = 0; i < downloads.size(); i++) {
            var itemY = TITLE_Y_OFFSET + (i * ITEM_STRIDE) - _scrollOffset;

            // Skip items outside visible area
            if (itemY + ITEM_HEIGHT < VISIBLE_TOP || itemY > VISIBLE_BOTTOM) {
                continue;
            }

            var dl = downloads[i] as Dictionary;
            var isSelected = (i == _selectedIndex);

            // Look up podcast brand colors
            var podUuidVal = dl.get(DownloadQueue.DL_PODCAST_UUID);
            var podUuid = (podUuidVal != null) ? podUuidVal as String : "";
            var colors = DataFormat.lookupPodcastColors(podcasts, podUuid);
            var artColor = colors[0] as Number;
            var artTint = colors[1] as Number;

            drawDownloadItem(dc, dl, ITEM_X, itemY, isSelected, artColor, artTint);
        }

        dc.clearClip();

        // Scroll indicators
        drawScrollIndicators(dc, cx, downloads.size());

        // Toast overlay
        if (_toastMessage != null) {
            drawToast(dc, cx, _toastMessage as String);
        }
    }

    //! Draw a single download item pill with podcast brand color tinting
    private function drawDownloadItem(dc as Graphics.Dc, dl as Dictionary,
                                       x as Number, y as Number,
                                       isSelected as Boolean,
                                       artColor as Number,
                                       artTint as Number) as Void {
        var status = dl[DownloadQueue.DL_STATUS] as Number;

        // Background pill — brand-tinted (same pattern as QueueEpisodeMenuItem)
        var boosted = DataFormat.brightenColor(artColor, 80);
        var factor = isSelected ? 0.55 : 0.30;
        var bgColor = DataFormat.dimColor(boosted, factor);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, ITEM_WIDTH, ITEM_HEIGHT, ITEM_CORNER_R);

        // Selection border — brightened brand color
        if (isSelected) {
            var borderColor = DataFormat.brightenColor(artColor, 160);
            dc.setColor(borderColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, ITEM_WIDTH, ITEM_HEIGHT, ITEM_CORNER_R);
            dc.setPenWidth(1);
        }

        // Status icon on the left
        var iconX = x + 16;
        var iconCY = y + ITEM_HEIGHT / 2;
        drawStatusIcon(dc, status, iconX, iconCY,
                       dl[DownloadQueue.DL_PROGRESS] as Number);

        // Text content
        var textX = x + 44;
        var maxTextW = ITEM_WIDTH - 60;

        // Episode title — two stable lines are easier to scan than marquee text.
        var title = dl[DownloadQueue.DL_TITLE] as String;
        var titleColor = DataFormat.ensureContrast(artTint, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        var titleLines = DataFormat.wrapText(
            dc,
            title,
            Graphics.FONT_XTINY,
            maxTextW,
            2
        );
        var titleH = dc.getFontHeight(Graphics.FONT_XTINY);
        if (titleLines.size() > 0) {
            dc.drawText(
                textX,
                y + 12,
                Graphics.FONT_XTINY,
                titleLines[0],
                Graphics.TEXT_JUSTIFY_LEFT
            );
        }
        if (titleLines.size() > 1) {
            var secondLine = titleLines[1];
            if (titleLines[0].length() + secondLine.length() + 1 <
                title.length()) {
                secondLine = DataFormat.truncateText(
                    dc,
                    secondLine + "...",
                    Graphics.FONT_XTINY,
                    maxTextW
                );
            }
            dc.drawText(
                textX,
                y + 12 + titleH,
                Graphics.FONT_XTINY,
                secondLine,
                Graphics.TEXT_JUSTIFY_LEFT
            );
        }

        // Podcast name + status (gray, bottom of pill)
        var podTitle = dl[DownloadQueue.DL_PODCAST_TITLE] as String;
        var statusStr = getStatusLabel(status, dl[DownloadQueue.DL_PROGRESS] as Number);

        // Color-code the status portion
        var subColor = 0xAAAAAA;
        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            subColor = 0x55FF55;
        } else if (status == DownloadQueue.STATUS_FAILED) {
            subColor = 0xFF5555;
        } else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            subColor = 0x55AAFF;
        } else if (status == DownloadQueue.STATUS_PENDING) {
            subColor = 0xFFAA55;
        }

        // Metadata is neutral so brand colors do not reduce readability.
        dc.setColor(0xBBBBBB, Graphics.COLOR_TRANSPARENT);
        var statusWidth = dc.getTextWidthInPixels(
            statusStr,
            Graphics.FONT_XTINY
        );
        var podcastWidth = maxTextW - statusWidth - 14;
        if (podcastWidth < 50) { podcastWidth = 50; }
        var truncPod = DataFormat.truncateText(
            dc,
            podTitle,
            Graphics.FONT_XTINY,
            podcastWidth
        );
        dc.drawText(textX, y + 78, Graphics.FONT_XTINY, truncPod,
                    Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x + ITEM_WIDTH - 12,
            y + 78,
            Graphics.FONT_XTINY,
            statusStr,
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        // Progress bar for downloading items
        if (status == DownloadQueue.STATUS_DOWNLOADING) {
            var barX = textX;
            var barY = y + 100;
            var barW = maxTextW - 10;
            var barH = 3;
            var progress = dl[DownloadQueue.DL_PROGRESS] as Number;

            dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(barX, barY, barW, barH, 1);

            if (progress > 0) {
                var fillW = (barW * progress / 100);
                if (fillW < 1) { fillW = 1; }
                var barAccent = DataFormat.brightenColor(artColor, 160);
                dc.setColor(barAccent, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(barX, barY, fillW, barH, 1);
            }
        }
    }

    //! Draw the status icon (left side of each item)
    private function drawStatusIcon(dc as Graphics.Dc, status as Number,
                                     x as Number, cy as Number,
                                     progress as Number) as Void {
        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            // Checkmark
            dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x, cy, x + 6, cy + 6);
            dc.drawLine(x + 6, cy + 6, x + 14, cy - 6);
            dc.setPenWidth(1);
        } else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            // Down arrow with circle progress
            dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawArc(x + 7, cy, 10, Graphics.ARC_CLOCKWISE, 0, 360);
            if (progress > 0) {
                var degrees = (progress * 360 / 100);
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(x + 7, cy, 10, Graphics.ARC_CLOCKWISE, 90, 90 - degrees);
            }
            dc.setPenWidth(1);
            // Down arrow inside
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x + 7, cy - 5, x + 7, cy + 4);
            dc.fillPolygon([[x + 2, cy + 1], [x + 12, cy + 1], [x + 7, cy + 6]]);
        } else if (status == DownloadQueue.STATUS_PENDING) {
            // Hourglass / clock icon
            dc.setColor(0xFFAA55, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawArc(x + 7, cy, 9, Graphics.ARC_CLOCKWISE, 0, 360);
            dc.drawLine(x + 7, cy - 4, x + 7, cy);
            dc.drawLine(x + 7, cy, x + 11, cy);
            dc.setPenWidth(1);
        } else if (status == DownloadQueue.STATUS_FAILED) {
            // X mark
            dc.setColor(0xFF5555, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x, cy - 6, x + 14, cy + 6);
            dc.drawLine(x + 14, cy - 6, x, cy + 6);
            dc.setPenWidth(1);
        }
    }

    //! Get human-readable status label
    private function getStatusLabel(status as Number, progress as Number) as String {
        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            return "Ready";
        } else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            return progress.toString() + "%";
        } else if (status == DownloadQueue.STATUS_PENDING) {
            return "Pending";
        } else if (status == DownloadQueue.STATUS_FAILED) {
            return "Failed";
        }
        return "Unknown";
    }

    //! Empty state when no downloads exist
    private function drawEmptyState(dc as Graphics.Dc, cx as Number) as Void {
        // Download icon (large, centered)
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawArc(cx, 160, 30, Graphics.ARC_CLOCKWISE, 0, 360);
        dc.setPenWidth(1);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, 140, cx, 170);
        dc.fillPolygon([[cx - 8, 165], [cx + 8, 165], [cx, 175]]);

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 210, Graphics.FONT_SMALL, "No downloads yet",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 250, Graphics.FONT_XTINY, "Browse episodes and",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 272, Graphics.FONT_XTINY, "tap to download.",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Scroll indicators (up/down arrows)
    private function drawScrollIndicators(dc as Graphics.Dc, cx as Number,
                                           itemCount as Number) as Void {
        var maxScroll = getMaxScroll(itemCount);
        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);

        if (_scrollOffset > 0) {
            dc.fillPolygon([[cx - 8, VISIBLE_TOP + 3],
                            [cx + 8, VISIBLE_TOP + 3],
                            [cx, VISIBLE_TOP - 7]]);
        }
        if (_scrollOffset < maxScroll) {
            dc.fillPolygon([[cx - 8, VISIBLE_BOTTOM - 5],
                            [cx + 8, VISIBLE_BOTTOM - 5],
                            [cx, VISIBLE_BOTTOM + 5]]);
        }
    }

    //! Toast notification overlay
    private function drawToast(dc as Graphics.Dc, cx as Number, message as String) as Void {
        var toastY = 320;
        var toastH = 40;
        var toastW = 280;
        var toastX = cx - toastW / 2;

        // Semi-transparent dark background
        dc.setColor(0x222233, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(toastX, toastY, toastW, toastH, 12);

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(toastX, toastY, toastW, toastH, 12);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, toastY + toastH / 2, Graphics.FONT_XTINY, message,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Calculate max scroll based on item count
    private function getMaxScroll(itemCount as Number) as Number {
        var totalHeight = TITLE_Y_OFFSET + (itemCount * ITEM_STRIDE);
        var viewportHeight = VISIBLE_BOTTOM - VISIBLE_TOP;
        var max = totalHeight - viewportHeight - VISIBLE_TOP;
        if (max < 0) { max = 0; }
        return max;
    }

    // --- Public API for delegate ---

    function scrollDown() as Void {
        var downloads = DownloadQueue.getDownloads();
        var max = getMaxScroll(downloads.size());
        _scrollOffset = _scrollOffset + SCROLL_STEP;
        if (_scrollOffset > max) { _scrollOffset = max; }
        WatchUi.requestUpdate();
    }

    function scrollUp() as Void {
        _scrollOffset = _scrollOffset - SCROLL_STEP;
        if (_scrollOffset < 0) { _scrollOffset = 0; }
        WatchUi.requestUpdate();
    }

    function getScrollOffset() as Number {
        return _scrollOffset;
    }

    function getSelectedIndex() as Number {
        return _selectedIndex;
    }

    function setSelectedIndex(idx as Number) as Void {
        var downloads = DownloadQueue.getDownloads();
        _selectedIndex = idx;
        if (_selectedIndex < 0) { _selectedIndex = downloads.size() - 1; }
        if (_selectedIndex >= downloads.size()) { _selectedIndex = 0; }
        var itemTop = TITLE_Y_OFFSET + _selectedIndex * ITEM_STRIDE;
        var itemBottom = itemTop + ITEM_HEIGHT;
        if (itemTop < _scrollOffset + VISIBLE_TOP) {
            _scrollOffset = itemTop - VISIBLE_TOP;
        } else if (itemBottom > _scrollOffset + VISIBLE_BOTTOM) {
            _scrollOffset = itemBottom - VISIBLE_BOTTOM;
        }
        if (_scrollOffset < 0) { _scrollOffset = 0; }
        var max = getMaxScroll(downloads.size());
        if (_scrollOffset > max) { _scrollOffset = max; }
        WatchUi.requestUpdate();
    }

    function itemIndexAtY(y as Number) as Number {
        if (y < VISIBLE_TOP || y > VISIBLE_BOTTOM) {
            return -1;
        }
        var downloads = DownloadQueue.getDownloads();
        for (var i = 0; i < downloads.size(); i++) {
            var itemY = TITLE_Y_OFFSET + i * ITEM_STRIDE - _scrollOffset;
            if (y >= itemY && y < itemY + ITEM_HEIGHT) {
                return i;
            }
        }
        return -1;
    }

    //! Show a toast message that auto-dismisses after 1.5 seconds
    function showToast(message as String) as Void {
        _toastMessage = message;
        if (_toastTimer != null) {
            (_toastTimer as Timer.Timer).stop();
        }
        _toastTimer = new Timer.Timer();
        (_toastTimer as Timer.Timer).start(method(:onToastDismiss), 1500, false);
        WatchUi.requestUpdate();
    }

    //! Timer callback to dismiss toast
    function onToastDismiss() as Void {
        _toastMessage = null;
        _toastTimer = null;
        WatchUi.requestUpdate();
    }
}

//! Input delegate for DownloadsView.
//! Tap on item → play (if downloaded) or retry (if failed).
//! Swipe left or long-press → remove download.
class DownloadsDelegate extends WatchUi.InputDelegate {

    private var _view as DownloadsView;

    function initialize(view as DownloadsView) {
        InputDelegate.initialize();
        _view = view;
    }

    //! Tap handler — hit test against download item Y positions
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var tapY = coords[1] as Number;

        var downloads = DownloadQueue.getDownloads();
        if (downloads.size() == 0) {
            return false;
        }

        var index = _view.itemIndexAtY(tapY);
        if (index >= 0) {
            _view.setSelectedIndex(index);
            handleItemTap(index);
            return true;
        }
        return false;
    }

    //! Handle tap on a specific download item
    private function handleItemTap(index as Number) as Void {
        var downloads = DownloadQueue.getDownloads();
        if (index < 0 || index >= downloads.size()) {
            return;
        }

        var dl = downloads[index] as Dictionary;
        var status = dl[DownloadQueue.DL_STATUS] as Number;

        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            var uuid = dl[DownloadQueue.DL_UUID] as String;
            (Application.getApp() as YoCastsApp).requestPlayback(uuid);
        } else if (status == DownloadQueue.STATUS_FAILED) {
            var uuid = dl[DownloadQueue.DL_UUID] as String;
            DownloadQueue.retry(uuid);
            (Application.getApp() as YoCastsApp).requestMediaSync();
            _view.showToast("Queued for retry");
        } else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            _view.showToast("Downloading...");
        } else {
            _view.showToast("Queued for download");
        }
    }

    //! Swipe left to show remove confirmation, up/down to scroll
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_UP) {
            _view.scrollDown();
            return true;
        } else if (dir == WatchUi.SWIPE_DOWN) {
            _view.scrollUp();
            return true;
        } else if (dir == WatchUi.SWIPE_LEFT) {
            // Remove selected download
            removeSelectedDownload();
            return true;
        } else if (dir == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    //! Physical button support
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();

        if (key == WatchUi.KEY_DOWN) {
            _view.setSelectedIndex(_view.getSelectedIndex() + 1);
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            _view.setSelectedIndex(_view.getSelectedIndex() - 1);
            return true;
        }
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            handleItemTap(_view.getSelectedIndex());
            return true;
        }
        if (key == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }

        return false;
    }

    //! Remove the currently selected download
    private function removeSelectedDownload() as Void {
        var downloads = DownloadQueue.getDownloads();
        var idx = _view.getSelectedIndex();
        if (idx >= 0 && idx < downloads.size()) {
            var dl = downloads[idx] as Dictionary;
            var uuid = dl[DownloadQueue.DL_UUID] as String;
            (Application.getApp() as YoCastsApp).deleteDownloadedEpisode(uuid);

            // Adjust selection if needed
            var newDownloads = DownloadQueue.getDownloads();
            if (idx >= newDownloads.size() && newDownloads.size() > 0) {
                _view.setSelectedIndex(newDownloads.size() - 1);
            }
            _view.showToast("Removed");
        }
    }
}
