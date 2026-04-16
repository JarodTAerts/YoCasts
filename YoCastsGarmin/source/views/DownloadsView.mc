import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

//! Downloads view — shows all downloaded and in-progress episodes.
//! Custom View with 80px items, scrollable via swipe/buttons.
//! Follows the same visual language as HomeMenuView (dark bg, accent blue,
//! rounded pill items).
class DownloadsView extends WatchUi.View {

    private var _scrollOffset as Number = 0;
    private var _selectedIndex as Number = 0;
    private var _toastMessage as String? = null;
    private var _toastTimer as Timer.Timer? = null;

    // Layout constants matching HomeMenuView spec
    private const ITEM_HEIGHT = 80;
    private const ITEM_GAP = 8;
    private const ITEM_STRIDE = 88; // ITEM_HEIGHT + ITEM_GAP
    private const ITEM_X = 40;
    private const ITEM_WIDTH = 310;
    private const ITEM_CORNER_R = 14;
    private const TITLE_Y_OFFSET = 80;
    private const SCROLL_STEP = 88;
    private const VISIBLE_TOP = 65;
    private const VISIBLE_BOTTOM = 375;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var downloads = DownloadQueue.getDownloads();
        var cx = 195;

        // Title
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_MEDIUM, "Downloads",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (downloads.size() == 0) {
            drawEmptyState(dc, cx);
            return;
        }

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
            drawDownloadItem(dc, dl, ITEM_X, itemY, isSelected);
        }

        dc.clearClip();

        // Scroll indicators
        drawScrollIndicators(dc, cx, downloads.size());

        // Toast overlay
        if (_toastMessage != null) {
            drawToast(dc, cx, _toastMessage as String);
        }
    }

    //! Draw a single download item pill
    private function drawDownloadItem(dc as Graphics.Dc, dl as Dictionary,
                                       x as Number, y as Number,
                                       isSelected as Boolean) as Void {
        var status = dl[DownloadQueue.DL_STATUS] as Number;

        // Background pill
        var bg = isSelected ? 0x252545 : 0x1A1A2E;
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, ITEM_WIDTH, ITEM_HEIGHT, ITEM_CORNER_R);

        // Selection border
        if (isSelected) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, ITEM_WIDTH, ITEM_HEIGHT, ITEM_CORNER_R);
            dc.setPenWidth(1);
        }

        // Status icon on the left
        var iconX = x + 16;
        var iconCY = y + 40;
        drawStatusIcon(dc, status, iconX, iconCY,
                       dl[DownloadQueue.DL_PROGRESS] as Number);

        // Text content
        var textX = x + 44;
        var maxTextW = ITEM_WIDTH - 60;

        // Episode title (white, top of pill)
        var title = dl[DownloadQueue.DL_TITLE] as String;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var truncTitle = DataFormat.truncateText(dc, title, Graphics.FONT_SMALL, maxTextW);
        dc.drawText(textX, y + 14, Graphics.FONT_SMALL, truncTitle,
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Podcast name + status (gray, bottom of pill)
        var podTitle = dl[DownloadQueue.DL_PODCAST_TITLE] as String;
        var statusStr = getStatusLabel(status, dl[DownloadQueue.DL_PROGRESS] as Number);
        var subText = podTitle + " | " + statusStr;

        // Color-code the status portion
        var subColor = 0xAAAAAA;
        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            subColor = 0x55FF55;
        } else if (status == DownloadQueue.STATUS_FAILED) {
            subColor = 0xFF5555;
        } else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            subColor = 0x55AAFF;
        }

        // Draw podcast title in gray, then status in its color
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var truncPod = DataFormat.truncateText(dc, podTitle, Graphics.FONT_XTINY, maxTextW - 80);
        dc.drawText(textX, y + 46, Graphics.FONT_XTINY, truncPod + " | ",
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Status label overlaid after the pipe
        var podPartW = dc.getTextWidthInPixels(truncPod + " | ", Graphics.FONT_XTINY);
        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX + podPartW, y + 46, Graphics.FONT_XTINY, statusStr,
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Progress bar for downloading items
        if (status == DownloadQueue.STATUS_DOWNLOADING) {
            var barX = textX;
            var barY = y + 66;
            var barW = maxTextW - 10;
            var barH = 3;
            var progress = dl[DownloadQueue.DL_PROGRESS] as Number;

            dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(barX, barY, barW, barH, 1);

            if (progress > 0) {
                var fillW = (barW * progress / 100);
                if (fillW < 1) { fillW = 1; }
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
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
        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(toastX, toastY, toastW, toastH, 12);

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
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
        WatchUi.requestUpdate();
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

        var scrollOffset = _view.getScrollOffset();
        for (var i = 0; i < downloads.size(); i++) {
            var itemY = 80 + (i * 88) - scrollOffset;
            if (tapY >= itemY && tapY < itemY + 80) {
                _view.setSelectedIndex(i);
                handleItemTap(i);
                return true;
            }
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
            // Navigate to Now Playing
            var ep = DownloadQueue.toEpisodeDict(dl);
            var npView = new NowPlayingView(ep);
            var npDelegate = new NowPlayingDelegate(ep);
            npDelegate.setView(npView);
            WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
        } else if (status == DownloadQueue.STATUS_FAILED) {
            _view.showToast("Retry not available yet");
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
            var title = dl[DownloadQueue.DL_TITLE] as String;
            DownloadQueue.removeFromQueue(dl[DownloadQueue.DL_UUID] as String);

            // Adjust selection if needed
            var newDownloads = DownloadQueue.getDownloads();
            if (idx >= newDownloads.size() && newDownloads.size() > 0) {
                _view.setSelectedIndex(newDownloads.size() - 1);
            }
            _view.showToast("Removed");
        }
    }
}
