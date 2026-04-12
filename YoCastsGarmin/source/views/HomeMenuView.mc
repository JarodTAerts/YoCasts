import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;

//! Custom home menu view replacing Menu2 for full layout control.
//! Renders 3 centered pills: Queue, Podcasts, and an enhanced Now Playing.
//! All items are centered, properly margined for 390px round AMOLED.
class HomeMenuView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _isPlaying as Boolean = false;
    private var _selectedIndex as Number = 0;

    // Layout positions (computed in onUpdate for screen-size independence)
    private var _queueY as Number = 0;
    private var _podcastsY as Number = 0;
    private var _npY as Number = 0;
    private var _playBtnCx as Number = 0;
    private var _playBtnCy as Number = 0;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // Margins and sizes
        var margin = 30;
        var pillW = w - margin * 2;
        var pillH = 68;
        var npH = 124;
        var pillR = 14;
        var gap = 6;

        // Clear to black (AMOLED)
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // --- Title ---
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 38, Graphics.FONT_MEDIUM, "YoCasts",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Thin accent line under title
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 40, 58, cx + 40, 58);

        // --- Compute vertical positions ---
        _queueY = 68;
        _podcastsY = _queueY + pillH + gap;
        _npY = _podcastsY + pillH + gap;

        // --- Queue Pill ---
        drawPillBg(dc, margin, _queueY, pillW, pillH, pillR, _selectedIndex == 0);
        drawQueueContent(dc, margin, _queueY, pillW, pillH, cx);

        // --- Podcasts Pill ---
        drawPillBg(dc, margin, _podcastsY, pillW, pillH, pillR, _selectedIndex == 1);
        drawPodcastsContent(dc, margin, _podcastsY, pillW, pillH, cx);

        // --- Now Playing Pill (enhanced) ---
        drawNowPlayingPill(dc, margin, _npY, pillW, npH, pillR, cx);
    }

    //! Draw a rounded-rect pill background
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

    //! Draw Queue item content with music note icon and subtitle
    private function drawQueueContent(dc as Graphics.Dc, x as Number, y as Number,
                                       w as Number, h as Number, cx as Number) as Void {
        var queue = _service.getQueue();
        var count = queue.size();

        // Music note icon on the left
        var iconX = x + 30;
        var iconY = y + h / 2;
        drawMusicNote(dc, iconX, iconY);

        // Title centered
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 8, y + h / 2 - 11, Graphics.FONT_SMALL, "Queue",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Subtitle with count
        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 8, y + h / 2 + 13, Graphics.FONT_XTINY,
                    count.toString() + " episodes",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw Podcasts item content with headphone icon and subtitle
    private function drawPodcastsContent(dc as Graphics.Dc, x as Number, y as Number,
                                          w as Number, h as Number, cx as Number) as Void {
        var podcasts = _service.getSubscribedPodcasts();
        var count = podcasts.size();

        // Headphone icon on the left
        var iconX = x + 30;
        var iconY = y + h / 2;
        drawHeadphones(dc, iconX, iconY);

        // Title centered
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 8, y + h / 2 - 11, Graphics.FONT_SMALL, "Podcasts",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Subtitle with count
        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 8, y + h / 2 + 13, Graphics.FONT_XTINY,
                    count.toString() + " subscriptions",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw the enhanced Now Playing pill with play/pause, progress bar, and time
    private function drawNowPlayingPill(dc as Graphics.Dc, x as Number, y as Number,
                                         w as Number, h as Number, r as Number,
                                         cx as Number) as Void {
        // Distinct background
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

        // "Now Playing" label
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 14, Graphics.FONT_XTINY, "NOW PLAYING",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Episode title (truncate if too long)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var epDisplay = epTitle;
        if (epDisplay.length() > 26) {
            epDisplay = epDisplay.substring(0, 23) as String;
            epDisplay = epDisplay + "...";
        }
        dc.drawText(cx, y + 36, Graphics.FONT_SMALL, epDisplay,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Podcast title
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 56, Graphics.FONT_XTINY, podTitle,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Progress bar
        var barX = x + 20;
        var barW = w - 40;
        var barY = y + 72;
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
        _playBtnCx = cx - 55;
        _playBtnCy = y + 98;

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_playBtnCx, _playBtnCy, btnR);

        // Draw play triangle or pause bars inside the button
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (_isPlaying) {
            // Pause: two vertical bars
            dc.fillRectangle(_playBtnCx - 6, _playBtnCy - 7, 4, 14);
            dc.fillRectangle(_playBtnCx + 2, _playBtnCy - 7, 4, 14);
        } else {
            // Play: right-pointing triangle
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

    // --- Icon Drawing Helpers ---

    //! Draw a music note icon (filled circle + stem + flag)
    private function drawMusicNote(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        // Note head
        dc.fillCircle(x, y + 4, 5);
        // Stem
        dc.setPenWidth(2);
        dc.drawLine(x + 5, y + 4, x + 5, y - 10);
        // Flag
        dc.drawLine(x + 5, y - 10, x + 10, y - 6);
        dc.setPenWidth(1);
    }

    //! Draw a headphone icon (arc + ear cups)
    private function drawHeadphones(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        // Headband arc
        dc.drawArc(x + 8, y + 2, 10, Graphics.ARC_CLOCKWISE, 190, 350);
        // Left ear cup
        dc.fillRoundedRectangle(x - 3, y, 6, 12, 2);
        // Right ear cup
        dc.fillRoundedRectangle(x + 13, y, 6, 12, 2);
        dc.setPenWidth(1);
    }

    // --- Public API ---

    //! Toggle mock playback state
    function togglePlayPause() as Void {
        _isPlaying = !_isPlaying;
        WatchUi.requestUpdate();
    }

    //! Get currently selected item index
    function getSelectedIndex() as Number {
        return _selectedIndex;
    }

    //! Move selection up
    function selectPrevious() as Void {
        _selectedIndex = _selectedIndex - 1;
        if (_selectedIndex < 0) {
            _selectedIndex = 2;
        }
        WatchUi.requestUpdate();
    }

    //! Move selection down
    function selectNext() as Void {
        _selectedIndex = _selectedIndex + 1;
        if (_selectedIndex > 2) {
            _selectedIndex = 0;
        }
        WatchUi.requestUpdate();
    }

    //! Hit-test a tap coordinate against menu items
    //! Returns: 0=queue, 1=podcasts, 2=nowPlaying, 3=playPauseBtn, -1=miss
    function hitTest(tapX as Number, tapY as Number) as Number {
        var w = System.getDeviceSettings().screenWidth;
        var margin = 30;
        var pillH = 68;
        var npH = 124;

        if (tapX < margin || tapX > w - margin) {
            return -1;
        }

        if (tapY >= _queueY && tapY < _queueY + pillH) {
            return 0;
        }
        if (tapY >= _podcastsY && tapY < _podcastsY + pillH) {
            return 1;
        }
        if (tapY >= _npY && tapY < _npY + npH) {
            // Check play/pause button area (generous 24px radius hit zone)
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
class HomeMenuDelegate extends WatchUi.BehaviorDelegate {

    private var _view as HomeMenuView;
    private var _service as IPodcastService;

    function initialize(view as HomeMenuView, service as IPodcastService) {
        BehaviorDelegate.initialize();
        _view = view;
        _service = service;
    }

    //! Handle tap events with hit testing
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

    //! SELECT button activates the currently highlighted item
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

    //! DOWN = next item
    function onNextPage() as Boolean {
        _view.selectNext();
        return true;
    }

    //! UP = previous item
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
