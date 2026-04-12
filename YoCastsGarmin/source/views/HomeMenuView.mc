import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;

//! Custom home menu with scrolling, proper spacing, and pixel-based text truncation.
//! Three scrollable pills: Queue, Podcasts, Now Playing.
//! Supports touch tap, swipe (via onNextPage/onPreviousPage), and button navigation.
//! Scroll offset is applied to all drawing and hit detection.
class HomeMenuView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _isPlaying as Boolean = false;
    private var _selectedIndex as Number = 0;
    private var _scrollOffset as Number = 0;

    // Cached screen Y positions (updated each onUpdate for hit testing)
    private var _queueScreenY as Number = 0;
    private var _podScreenY as Number = 0;
    private var _npScreenY as Number = 0;
    private var _playBtnCx as Number = 0;
    private var _playBtnCy as Number = 0;

    // Layout metrics
    private var _pillH as Number = 72;
    private var _npH as Number = 140;
    private var _gap as Number = 20;
    private var _margin as Number = 42;
    private var _viewportTop as Number = 65;
    private var _viewportH as Number = 290;
    private var _contentHeight as Number = 0;
    private var _maxScroll as Number = 0;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
        // Content: Queue + gap + Podcasts + gap + NP + bottom padding
        _contentHeight = _pillH + _gap + _pillH + _gap + _npH + 15;
        _maxScroll = _contentHeight - _viewportH;
        if (_maxScroll < 0) { _maxScroll = 0; }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var pillW = w - _margin * 2;
        var pillR = 16;

        // Clear to black (AMOLED)
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // --- Fixed title area (above scroll viewport) ---
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 33, Graphics.FONT_MEDIUM, "YoCasts",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 40, 53, cx + 40, 53);

        // --- Compute screen positions from logical layout + scroll ---
        _queueScreenY = _viewportTop - _scrollOffset;
        _podScreenY = _queueScreenY + _pillH + _gap;
        _npScreenY = _podScreenY + _pillH + _gap;

        // --- Clip drawing to the scroll viewport ---
        dc.setClip(0, _viewportTop, w, _viewportH);

        // Queue pill (only draw if visible)
        if (_queueScreenY + _pillH > _viewportTop && _queueScreenY < _viewportTop + _viewportH) {
            drawPillBg(dc, _margin, _queueScreenY, pillW, _pillH, pillR, _selectedIndex == 0);
            drawQueueContent(dc, _margin, _queueScreenY, pillW, _pillH, cx);
        }

        // Podcasts pill
        if (_podScreenY + _pillH > _viewportTop && _podScreenY < _viewportTop + _viewportH) {
            drawPillBg(dc, _margin, _podScreenY, pillW, _pillH, pillR, _selectedIndex == 1);
            drawPodcastsContent(dc, _margin, _podScreenY, pillW, _pillH, cx);
        }

        // Now Playing pill
        if (_npScreenY + _npH > _viewportTop && _npScreenY < _viewportTop + _viewportH) {
            drawNowPlayingPill(dc, _margin, _npScreenY, pillW, _npH, pillR, cx);
        }

        dc.clearClip();

        // Scroll indicator (outside clip region)
        if (_maxScroll > 0) {
            drawScrollIndicator(dc, w);
        }
    }

    // --- Pill Background ---

    private function drawPillBg(dc as Graphics.Dc, x as Number, y as Number,
                                 w as Number, h as Number, r as Number,
                                 selected as Boolean) as Void {
        if (selected) {
            dc.setColor(0x222244, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRoundedRectangle(x, y, w, h, r);

        if (selected) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, w, h, r);
            dc.setPenWidth(1);
        }
    }

    // --- Queue Content ---

    private function drawQueueContent(dc as Graphics.Dc, x as Number, y as Number,
                                       w as Number, h as Number, cx as Number) as Void {
        var queue = _service.getQueue();
        var count = queue.size();

        var iconX = x + 28;
        var iconY = y + h / 2;
        drawMusicNote(dc, iconX, iconY);

        var textX = cx + 8;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + h / 2 - 12, Graphics.FONT_SMALL, "Queue",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + h / 2 + 14, Graphics.FONT_XTINY,
                    count.toString() + " episodes",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- Podcasts Content ---

    private function drawPodcastsContent(dc as Graphics.Dc, x as Number, y as Number,
                                          w as Number, h as Number, cx as Number) as Void {
        var podcasts = _service.getSubscribedPodcasts();
        var count = podcasts.size();

        var iconX = x + 28;
        var iconY = y + h / 2;
        drawHeadphones(dc, iconX, iconY);

        var textX = cx + 8;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + h / 2 - 12, Graphics.FONT_SMALL, "Podcasts",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + h / 2 + 14, Graphics.FONT_XTINY,
                    count.toString() + " subscriptions",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- Now Playing Pill ---

    private function drawNowPlayingPill(dc as Graphics.Dc, x as Number, y as Number,
                                         w as Number, h as Number, r as Number,
                                         cx as Number) as Void {
        // Distinct darker background
        if (_selectedIndex == 2) {
            dc.setColor(0x1C2541, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(0x162038, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRoundedRectangle(x, y, w, h, r);

        // Accent top border
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x + r, y, x + w - r, y);
        dc.setPenWidth(1);

        // Selection border
        if (_selectedIndex == 2) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, w, h, r);
            dc.setPenWidth(1);
        }

        var ep = _service.getNowPlaying();
        if (ep == null) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + h / 2, Graphics.FONT_SMALL, "Nothing playing",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var epTitle = ep[DataKeys.E_TITLE] as String;
        var podTitle = ep[DataKeys.E_PODCAST_TITLE] as String;
        var duration = ep[DataKeys.E_DURATION] as Number;
        var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;
        var maxTextW = w - 30;

        // "NOW PLAYING" label
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 15, Graphics.FONT_XTINY, "NOW PLAYING",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Episode title (pixel-truncated)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var epDisplay = DataFormat.truncateText(dc, epTitle, Graphics.FONT_SMALL, maxTextW);
        dc.drawText(cx, y + 40, Graphics.FONT_SMALL, epDisplay,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Podcast name (pixel-truncated)
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        var podDisplay = DataFormat.truncateText(dc, podTitle, Graphics.FONT_XTINY, maxTextW);
        dc.drawText(cx, y + 62, Graphics.FONT_XTINY, podDisplay,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Progress bar
        var barX = x + 20;
        var barW = w - 40;
        var barY = y + 82;
        var barH = 4;

        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, barW, barH, 2);

        if (duration > 0 && playedUpTo > 0) {
            var progress = playedUpTo.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var progW = (barW.toFloat() * progress).toNumber();
            if (progW > 0) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(barX, barY, progW, barH, 2);
            }
        }

        // Play/Pause button circle
        var btnR = 16;
        _playBtnCx = cx - 50;
        _playBtnCy = y + 110;

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_playBtnCx, _playBtnCy, btnR);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (_isPlaying) {
            dc.fillRectangle(_playBtnCx - 6, _playBtnCy - 7, 4, 14);
            dc.fillRectangle(_playBtnCx + 2, _playBtnCy - 7, 4, 14);
        } else {
            var pts = [[_playBtnCx - 5, _playBtnCy - 8],
                       [_playBtnCx - 5, _playBtnCy + 8],
                       [_playBtnCx + 8, _playBtnCy]];
            dc.fillPolygon(pts);
        }

        // Time display
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var timeStr = DataFormat.formatTime(playedUpTo) + " / " + DataFormat.formatTime(duration);
        dc.drawText(cx + 20, _playBtnCy, Graphics.FONT_XTINY, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- Scroll Indicator ---

    private function drawScrollIndicator(dc as Graphics.Dc, w as Number) as Void {
        var trackH = _viewportH - 20;
        var trackTop = _viewportTop + 10;
        var trackX = w - 8;

        dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(trackX, trackTop, 4, trackH, 2);

        var thumbH = 20;
        var thumbRange = trackH - thumbH;
        var thumbY = trackTop;
        if (_maxScroll > 0) {
            thumbY = trackTop + ((_scrollOffset.toFloat() / _maxScroll.toFloat()) * thumbRange).toNumber();
        }
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(trackX, thumbY, 4, thumbH, 2);
    }

    // --- Icon Drawing Helpers ---

    private function drawMusicNote(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 4, 5);
        dc.setPenWidth(2);
        dc.drawLine(x + 5, y + 4, x + 5, y - 10);
        dc.drawLine(x + 5, y - 10, x + 10, y - 6);
        dc.setPenWidth(1);
    }

    private function drawHeadphones(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x + 8, y + 2, 10, Graphics.ARC_CLOCKWISE, 190, 350);
        dc.fillRoundedRectangle(x - 3, y, 6, 12, 2);
        dc.fillRoundedRectangle(x + 13, y, 6, 12, 2);
        dc.setPenWidth(1);
    }

    // --- Public API ---

    function togglePlayPause() as Void {
        _isPlaying = !_isPlaying;
        WatchUi.requestUpdate();
    }

    function getSelectedIndex() as Number {
        return _selectedIndex;
    }

    //! Select previous item and auto-scroll to keep it visible
    function selectPrevious() as Void {
        _selectedIndex = _selectedIndex - 1;
        if (_selectedIndex < 0) { _selectedIndex = 2; }
        _ensureSelectedVisible();
        WatchUi.requestUpdate();
    }

    //! Select next item and auto-scroll to keep it visible
    function selectNext() as Void {
        _selectedIndex = _selectedIndex + 1;
        if (_selectedIndex > 2) { _selectedIndex = 0; }
        _ensureSelectedVisible();
        WatchUi.requestUpdate();
    }

    //! Adjust scroll offset so the selected item is fully within the viewport
    private function _ensureSelectedVisible() as Void {
        var logY = 0;
        var itemH = _pillH;
        if (_selectedIndex == 0) {
            logY = 0;
        } else if (_selectedIndex == 1) {
            logY = _pillH + _gap;
        } else {
            logY = _pillH + _gap + _pillH + _gap;
            itemH = _npH;
        }
        // If item top is above viewport
        if (logY < _scrollOffset) {
            _scrollOffset = logY;
        }
        // If item bottom is below viewport
        if (logY + itemH > _scrollOffset + _viewportH) {
            _scrollOffset = logY + itemH - _viewportH;
        }
        _clampScroll();
    }

    private function _clampScroll() as Void {
        if (_scrollOffset < 0) { _scrollOffset = 0; }
        if (_scrollOffset > _maxScroll) { _scrollOffset = _maxScroll; }
    }

    //! Hit-test a tap against menu items using cached screen positions.
    //! Screen positions already incorporate scrollOffset from last draw.
    //! Returns: 0=queue, 1=podcasts, 2=nowPlaying, 3=playPauseBtn, -1=miss
    function hitTest(tapX as Number, tapY as Number) as Number {
        var w = System.getDeviceSettings().screenWidth;

        // Must be within viewport vertically
        if (tapY < _viewportTop || tapY > _viewportTop + _viewportH) {
            return -1;
        }
        // Must be within horizontal bounds (allow a bit of bezel tolerance)
        if (tapX < 25 || tapX > w - 25) {
            return -1;
        }

        // Check against screen positions set during onUpdate
        if (tapY >= _queueScreenY && tapY < _queueScreenY + _pillH) {
            return 0;
        }
        if (tapY >= _podScreenY && tapY < _podScreenY + _pillH) {
            return 1;
        }
        if (tapY >= _npScreenY && tapY < _npScreenY + _npH) {
            // Play/pause button (generous 24px hit radius)
            var dx = tapX - _playBtnCx;
            var dy = tapY - _playBtnCy;
            if (dx * dx + dy * dy <= 24 * 24) {
                return 3;
            }
            return 2;
        }

        return -1;
    }

    function getService() as IPodcastService {
        return _service;
    }
}

//! Input delegate for the custom home menu.
//! Handles taps on pills, play/pause button, and physical button navigation.
//! Swipe up/down (onNextPage/onPreviousPage) selects items and auto-scrolls.
class HomeMenuDelegate extends WatchUi.BehaviorDelegate {

    private var _view as HomeMenuView;
    private var _service as IPodcastService;

    function initialize(view as HomeMenuView, service as IPodcastService) {
        BehaviorDelegate.initialize();
        _view = view;
        _service = service;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var tapX = coords[0] as Number;
        var tapY = coords[1] as Number;

        var hit = _view.hitTest(tapX, tapY);

        if (hit == 0) {
            navigateToQueue();
            return true;
        } else if (hit == 1) {
            navigateToPodcasts();
            return true;
        } else if (hit == 2) {
            navigateToNowPlaying();
            return true;
        } else if (hit == 3) {
            _view.togglePlayPause();
            return true;
        }

        return false;
    }

    function onSelect() as Boolean {
        var idx = _view.getSelectedIndex();
        if (idx == 0) {
            navigateToQueue();
        } else if (idx == 1) {
            navigateToPodcasts();
        } else if (idx == 2) {
            navigateToNowPlaying();
        }
        return true;
    }

    //! DOWN button / swipe up = select next + auto-scroll
    function onNextPage() as Boolean {
        _view.selectNext();
        return true;
    }

    //! UP button / swipe down = select previous + auto-scroll
    function onPreviousPage() as Boolean {
        _view.selectPrevious();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    // --- Navigation Helpers ---

    private function navigateToQueue() as Void {
        var queueView = new QueueView(_service);
        WatchUi.pushView(queueView, new QueueDelegate(_service), WatchUi.SLIDE_UP);
    }

    private function navigateToPodcasts() as Void {
        var podView = new SubscribedView(_service);
        WatchUi.pushView(podView, new SubscribedDelegate(_service), WatchUi.SLIDE_UP);
    }

    private function navigateToNowPlaying() as Void {
        var ep = _service.getNowPlaying();
        if (ep != null) {
            var npView = new NowPlayingView(ep);
            var npDelegate = new NowPlayingDelegate(ep);
            npDelegate.setView(npView);
            WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
        }
    }
}
