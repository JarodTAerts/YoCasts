import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;
import Toybox.Math;

//! Split-dock home menu (v2.0).
//! Zone 1: Scrollable pill menu (Y=0–260) — Queue, Podcasts, Settings.
//! Zone 2: Fixed Now Playing dock (Y=260–390) — playback info + play/pause.
class HomeMenuView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _isPlaying as Boolean = false;
    private var _scrollOffset as Number = 0;

    // --- Layout constants from Section 5 spec ---
    private const DOCK_TOP = 260;
    private const DOCK_BOTTOM = 390;
    private const DOCK_DIVIDER_Y = 260;
    private const DOCK_PODCAST_Y = 268;
    private const DOCK_EPISODE_Y = 302;
    private const DOCK_PROGRESS_Y = 338;
    private const DOCK_TIME_Y = 346;
    private const DOCK_PLAYPAUSE_CY = 378;
    private const DOCK_PLAYPAUSE_ZONE_TOP = 365;
    private const PROGRESS_BAR_WIDTH = 200;
    private const PROGRESS_BAR_HEIGHT = 4;

    // Content-space Y for the title (scrolls with pills)
    private const TITLE_Y = 25;

    private const PILL_HEIGHT = 80;
    private const PILL_GAP = 16;
    private const PILL_CORNER_RADIUS = 16;
    private const PILL_INNER_PAD_X = 16;

    // Uniform pill sizing — all pills identical width, centered
    private const PILL_WIDTH = 280;
    private const PILL_X = 55; // (390 - 280) / 2

    // Content-space Y positions for each pill
    private const QUEUE_Y = 80;
    private const PODCASTS_Y = 176;    // 80 + 80 + 16
    private const DOWNLOADS_Y = 272;   // 176 + 80 + 16
    private const SETTINGS_Y = 368;    // 272 + 80 + 16

    private const SCROLL_STEP = 80;
    private const TOTAL_MENU_HEIGHT = 478; // 368 + 80 + 30 bottom pad

    // Dock text max widths
    private const DOCK_PODCAST_MAX_W = 322;
    private const DOCK_EPISODE_MAX_W = 286;

    private var _maxScroll as Number = 0;

    // Marquee state for dock podcast name
    private var _marqueeTimer as Timer.Timer? = null;
    private var _dockPodOffset as Number = 0;
    private var _dockPodMaxScroll as Number = 0;
    private var _dockPodPhase as Number = 0;
    private var _dockPodPause as Number = 15;
    // Marquee state for dock episode title
    private var _dockEpOffset as Number = 0;
    private var _dockEpMaxScroll as Number = 0;
    private var _dockEpPhase as Number = 0;
    private var _dockEpPause as Number = 15;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
        _maxScroll = TOTAL_MENU_HEIGHT - DOCK_TOP;
        if (_maxScroll < 0) { _maxScroll = 0; }
    }

    function onShow() as Void {
        if (_marqueeTimer == null) {
            _marqueeTimer = new Timer.Timer();
        }
        (_marqueeTimer as Timer.Timer).start(method(:onMarqueeTick), 150, true);
    }

    function onHide() as Void {
        if (_marqueeTimer != null) {
            (_marqueeTimer as Timer.Timer).stop();
        }
    }

    //! Marquee timer callback — animates overflowing dock text
    function onMarqueeTick() as Void {
        var needsUpdate = false;

        // Dock podcast name track
        if (_dockPodMaxScroll > 0) {
            if (_dockPodPhase == 0) {
                _dockPodPause = _dockPodPause - 1;
                if (_dockPodPause <= 0) { _dockPodPhase = 1; }
            } else if (_dockPodPhase == 1) {
                _dockPodOffset = _dockPodOffset + 2;
                needsUpdate = true;
                if (_dockPodOffset >= _dockPodMaxScroll) {
                    _dockPodOffset = _dockPodMaxScroll;
                    _dockPodPhase = 2;
                    _dockPodPause = 10;
                }
            } else {
                _dockPodPause = _dockPodPause - 1;
                if (_dockPodPause <= 0) {
                    _dockPodOffset = 0;
                    _dockPodPhase = 0;
                    _dockPodPause = 15;
                    needsUpdate = true;
                }
            }
        }

        // Dock episode title track
        if (_dockEpMaxScroll > 0) {
            if (_dockEpPhase == 0) {
                _dockEpPause = _dockEpPause - 1;
                if (_dockEpPause <= 0) { _dockEpPhase = 1; }
            } else if (_dockEpPhase == 1) {
                _dockEpOffset = _dockEpOffset + 2;
                needsUpdate = true;
                if (_dockEpOffset >= _dockEpMaxScroll) {
                    _dockEpOffset = _dockEpMaxScroll;
                    _dockEpPhase = 2;
                    _dockEpPause = 10;
                }
            } else {
                _dockEpPause = _dockEpPause - 1;
                if (_dockEpPause <= 0) {
                    _dockEpOffset = 0;
                    _dockEpPhase = 0;
                    _dockEpPause = 15;
                    needsUpdate = true;
                }
            }
        }

        if (needsUpdate) {
            WatchUi.requestUpdate();
        }
    }

    //! Compute usable circle width at a given Y position on 390x390 round display
    private function getWidthAtY(y as Number) as Number {
        var dy = y - 195;
        if (dy < -195 || dy > 195) { return 0; }
        var r2 = 195 * 195;
        var w = Math.sqrt(r2 - dy * dy).toNumber() * 2;
        return w;
    }

    //! Compute left margin at a given Y position
    private function getMarginAtY(y as Number) as Number {
        return (390 - getWidthAtY(y)) / 2;
    }

    // ========================================================================
    // DRAW ORDER (Section 5.8)
    // ========================================================================

    function onUpdate(dc as Graphics.Dc) as Void {
        var cx = 195;

        // 1. Clear screen (black)
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // 2. Set clip to scrollable zone (0 to dock top)
        dc.setClip(0, 0, 390, DOCK_TOP);

        // 3. Draw "YoCasts" title — scrolls with content
        var titleDrawY = TITLE_Y - _scrollOffset;
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleDrawY, Graphics.FONT_MEDIUM, "YoCasts",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 4. Draw menu pills adjusted for scroll offset
        drawMenuPills(dc, cx);

        // 5. Clear clip
        dc.clearClip();

        // 6. Draw scroll indicators
        drawScrollIndicators(dc, cx);

        // 7–12. Draw dock
        drawDock(dc, cx);
    }

    // --- Scrollable Menu Pills (Zone 1) ---

    private function drawMenuPills(dc as Graphics.Dc, cx as Number) as Void {
        var queueDrawY = QUEUE_Y - _scrollOffset;
        var podDrawY = PODCASTS_Y - _scrollOffset;
        var dlDrawY = DOWNLOADS_Y - _scrollOffset;
        var settDrawY = SETTINGS_Y - _scrollOffset;

        // Queue pill
        if (queueDrawY + PILL_HEIGHT > 0 && queueDrawY < DOCK_TOP) {
            drawPillBg(dc, PILL_X, queueDrawY, PILL_WIDTH, PILL_HEIGHT);
            drawQueueContent(dc, PILL_X, queueDrawY);
        }

        // Podcasts pill
        if (podDrawY + PILL_HEIGHT > 0 && podDrawY < DOCK_TOP) {
            drawPillBg(dc, PILL_X, podDrawY, PILL_WIDTH, PILL_HEIGHT);
            drawPodcastsContent(dc, PILL_X, podDrawY);
        }

        // Downloads pill
        if (dlDrawY + PILL_HEIGHT > 0 && dlDrawY < DOCK_TOP) {
            drawPillBg(dc, PILL_X, dlDrawY, PILL_WIDTH, PILL_HEIGHT);
            drawDownloadsContent(dc, PILL_X, dlDrawY);
        }

        // Settings pill
        if (settDrawY + PILL_HEIGHT > 0 && settDrawY < DOCK_TOP) {
            drawPillBg(dc, PILL_X, settDrawY, PILL_WIDTH, PILL_HEIGHT);
            drawSettingsContent(dc, PILL_X, settDrawY);
        }
    }

    private function drawPillBg(dc as Graphics.Dc, x as Number, y as Number,
                                 w as Number, h as Number) as Void {
        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, PILL_CORNER_RADIUS);
    }

    private function drawQueueContent(dc as Graphics.Dc, pillX as Number, pillY as Number) as Void {
        var queue = _service.getQueue();
        var count = queue.size();

        // Icon vertically centered for two-line content
        drawMusicNote(dc, pillX + PILL_INNER_PAD_X, pillY + 16);

        var textX = pillX + 48;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, pillY + 14, Graphics.FONT_SMALL, "Queue",
                    Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, pillY + 44, Graphics.FONT_XTINY,
                    count.toString() + " episodes",
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawPodcastsContent(dc as Graphics.Dc, pillX as Number, pillY as Number) as Void {
        var podcasts = _service.getSubscribedPodcasts();
        var count = podcasts.size();

        drawHeadphones(dc, pillX + PILL_INNER_PAD_X, pillY + 16);

        var textX = pillX + 48;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, pillY + 14, Graphics.FONT_SMALL, "Podcasts",
                    Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, pillY + 44, Graphics.FONT_XTINY,
                    count.toString() + " subscriptions",
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawSettingsContent(dc as Graphics.Dc, pillX as Number, pillY as Number) as Void {
        // Single line — vertically centered in pill
        drawGearIcon(dc, pillX + PILL_INNER_PAD_X, pillY + 24);

        var textX = pillX + 48;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, pillY + 22, Graphics.FONT_SMALL, "Settings",
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawDownloadsContent(dc as Graphics.Dc, pillX as Number, pillY as Number) as Void {
        var count = DownloadQueue.getDownloadCount();

        drawDownloadIcon(dc, pillX + PILL_INNER_PAD_X, pillY + 16);

        var textX = pillX + 48;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, pillY + 14, Graphics.FONT_SMALL, "Downloads",
                    Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var subtitle = count.toString() + " episode";
        if (count != 1) { subtitle = subtitle + "s"; }
        dc.drawText(textX, pillY + 44, Graphics.FONT_XTINY, subtitle,
                    Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Now Playing Dock (Zone 2, Y=260–390) ---

    private function drawDock(dc as Graphics.Dc, cx as Number) as Void {
        // 6. Draw dock background (solid black, Y=260–390)
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, DOCK_TOP, 390, DOCK_BOTTOM - DOCK_TOP);

        // 7. Draw dock divider line
        var divMargin = getMarginAtY(DOCK_DIVIDER_Y);
        var divWidth = getWidthAtY(DOCK_DIVIDER_Y);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(divMargin, DOCK_DIVIDER_Y, divWidth, 1);

        var ep = _service.getNowPlaying();
        if (ep == null) {
            // No episode playing — show placeholder
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, DOCK_EPISODE_Y, Graphics.FONT_XTINY, "No episode",
                        Graphics.TEXT_JUSTIFY_CENTER);
            _dockPodMaxScroll = 0;
            _dockEpMaxScroll = 0;
            return;
        }

        var podTitle = ep[DataKeys.E_PODCAST_TITLE] as String;
        var epTitle = ep[DataKeys.E_TITLE] as String;
        var duration = ep[DataKeys.E_DURATION] as Number;
        var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;

        // 8. Draw podcast name (Y=268)
        drawDockMarqueeText(dc, podTitle, Graphics.FONT_XTINY,
                            0xAAAAAA, cx, DOCK_PODCAST_Y,
                            DOCK_PODCAST_MAX_W, _dockPodOffset, false);

        // 9. Draw episode title (Y=302)
        drawDockMarqueeText(dc, epTitle, Graphics.FONT_XTINY,
                            0xFFFFFF, cx, DOCK_EPISODE_Y,
                            DOCK_EPISODE_MAX_W, _dockEpOffset, true);

        // 10. Draw progress bar (Y=338)
        var barX = 95;
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, DOCK_PROGRESS_Y, PROGRESS_BAR_WIDTH, PROGRESS_BAR_HEIGHT, 2);

        if (duration > 0 && playedUpTo > 0) {
            var progress = playedUpTo.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var fillW = (PROGRESS_BAR_WIDTH.toFloat() * progress).toNumber();
            if (fillW > 0) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(barX, DOCK_PROGRESS_Y, fillW, PROGRESS_BAR_HEIGHT, 2);
            }
        }

        // 11. Draw time display (Y=346)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var timeStr = DataFormat.formatTime(playedUpTo) + " / " + DataFormat.formatTime(duration);
        dc.drawText(cx, DOCK_TIME_Y, Graphics.FONT_XTINY, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 12. Draw play/pause icon (centered at 195, 378)
        drawPlayPauseIcon(dc, cx, DOCK_PLAYPAUSE_CY);
    }

    //! Draw dock marquee text with clipping for overflow
    private function drawDockMarqueeText(dc as Graphics.Dc, text as String,
                                          font as Graphics.FontDefinition,
                                          color as Number, cx as Number,
                                          y as Number, maxW as Number,
                                          offset as Number, isEpisode as Boolean) as Void {
        var fullW = dc.getTextWidthInPixels(text, font);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (fullW <= maxW) {
            // Fits — draw centered, no marquee needed
            dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            if (isEpisode) { _dockEpMaxScroll = 0; } else { _dockPodMaxScroll = 0; }
            return;
        }

        // Overflows — set up marquee
        var overflow = fullW - maxW;
        if (isEpisode) { _dockEpMaxScroll = overflow; } else { _dockPodMaxScroll = overflow; }

        var containerX = cx - maxW / 2;
        var fontH = dc.getFontHeight(font);
        dc.setClip(containerX, y, maxW, fontH);
        dc.drawText(containerX - offset, y, font, text,
                    Graphics.TEXT_JUSTIFY_LEFT);
        dc.clearClip();
    }

    //! Draw play (triangle) or pause (two bars) icon
    private function drawPlayPauseIcon(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        var sz = 8;
        if (_isPlaying) {
            // Pause bars
            dc.fillRectangle(cx - 7, cy - 8, 5, 16);
            dc.fillRectangle(cx + 2, cy - 8, 5, 16);
        } else {
            // Play triangle
            dc.fillPolygon([[cx - sz, cy - sz], [cx - sz, cy + sz], [cx + sz, cy]]);
        }
    }

    // --- Icon Drawing Helpers ---

    private function drawMusicNote(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 14, 5);
        dc.setPenWidth(2);
        dc.drawLine(x + 5, y + 14, x + 5, y);
        dc.drawLine(x + 5, y, x + 10, y + 4);
        dc.setPenWidth(1);
    }

    private function drawHeadphones(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x + 8, y + 12, 10, Graphics.ARC_CLOCKWISE, 190, 350);
        dc.fillRoundedRectangle(x - 3, y + 10, 6, 12, 2);
        dc.fillRoundedRectangle(x + 13, y + 10, 6, 12, 2);
        dc.setPenWidth(1);
    }

    //! Download arrow icon — arrow pointing down into a tray
    private function drawDownloadIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        // Down arrow shaft
        dc.setPenWidth(2);
        dc.drawLine(x + 8, y, x + 8, y + 14);
        dc.setPenWidth(1);
        // Arrowhead
        dc.fillPolygon([[x + 2, y + 10], [x + 14, y + 10], [x + 8, y + 18]]);
        // Tray (U shape)
        dc.setPenWidth(2);
        dc.drawLine(x, y + 18, x, y + 24);
        dc.drawLine(x, y + 24, x + 16, y + 24);
        dc.drawLine(x + 16, y + 24, x + 16, y + 18);
        dc.setPenWidth(1);
    }

    //! Draw a gear/cog icon per Section 5.5.6
    private function drawGearIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var iconCx = x + 11;
        var iconCy = y + 11;
        var outerR = 11;
        var innerR = 5;
        var toothW = 4;
        var toothH = 4;

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(iconCx, iconCy, outerR);

        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(iconCx, iconCy, innerR);

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 6; i++) {
            var angle = i * 60.0 * Math.PI / 180.0;
            var tx = iconCx + (outerR * Math.cos(angle)).toNumber() - toothW / 2;
            var ty = iconCy - (outerR * Math.sin(angle)).toNumber() - toothH / 2;
            dc.fillRectangle(tx, ty, toothW, toothH);
        }
    }

    //! Draw scroll indicators when content extends beyond viewport
    private function drawScrollIndicators(dc as Graphics.Dc, cx as Number) as Void {
        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);

        // Up arrow when scrolled down
        if (_scrollOffset > 0) {
            dc.fillPolygon([[cx - 8, 18], [cx + 8, 18], [cx, 6]]);
        }

        // Down arrow when more content below
        if (_scrollOffset < _maxScroll) {
            var arrowY = DOCK_TOP - 10;
            dc.fillPolygon([[cx - 8, arrowY - 8], [cx + 8, arrowY - 8], [cx, arrowY + 4]]);
        }
    }

    // --- Public API ---

    function togglePlayPause() as Void {
        _isPlaying = !_isPlaying;
        WatchUi.requestUpdate();
    }

    function scrollDown() as Void {
        _scrollOffset = _scrollOffset + SCROLL_STEP;
        if (_scrollOffset > _maxScroll) { _scrollOffset = _maxScroll; }
        WatchUi.requestUpdate();
    }

    function scrollUp() as Void {
        _scrollOffset = _scrollOffset - SCROLL_STEP;
        if (_scrollOffset < 0) { _scrollOffset = 0; }
        WatchUi.requestUpdate();
    }

    function getService() as IPodcastService {
        return _service;
    }

    function getScrollOffset() as Number {
        return _scrollOffset;
    }
}

//! Delegate for the split-dock home menu.
//! Uses InputDelegate (NOT BehaviorDelegate) — BehaviorDelegate converts
//! all taps to onSelect(), preventing coordinate-based hit testing.
class HomeMenuDelegate extends WatchUi.InputDelegate {

    private var _view as HomeMenuView;
    private var _service as IPodcastService;
    private var _selectedIndex as Number = 0;

    function initialize(view as HomeMenuView, service as IPodcastService) {
        InputDelegate.initialize();
        _view = view;
        _service = service;
    }

    //! Touch zones per Section 5.4.9:
    //! Y >= 365: toggle play/pause
    //! Y >= 260 and Y < 365: navigate to full Now Playing screen
    //! Y < 260: hit test against pills
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var tapX = coords[0] as Number;
        var tapY = coords[1] as Number;

        // Bottom dead zone: play/pause toggle
        if (tapY >= 365) {
            _view.togglePlayPause();
            return true;
        }

        // Dock info zone: navigate to Now Playing
        if (tapY >= 260) {
            navigateToNowPlaying();
            return true;
        }

        // Scrollable zone: hit test against pill Y positions
        var scrollOffset = getScrollOffset();
        var queueDrawY = 80 - scrollOffset;
        var podDrawY = 176 - scrollOffset;
        var dlDrawY = 272 - scrollOffset;
        var settDrawY = 368 - scrollOffset;

        if (tapY >= queueDrawY && tapY < queueDrawY + 80) {
            navigateToQueue();
            return true;
        }
        if (tapY >= podDrawY && tapY < podDrawY + 80) {
            navigateToPodcasts();
            return true;
        }
        if (tapY >= dlDrawY && tapY < dlDrawY + 80) {
            navigateToDownloads();
            return true;
        }
        if (tapY >= settDrawY && tapY < settDrawY + 80) {
            navigateToSettings();
            return true;
        }

        return false;
    }

    //! Swipe gestures for scrolling the menu zone
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_UP) {
            _view.scrollDown();
            return true;
        } else if (dir == WatchUi.SWIPE_DOWN) {
            _view.scrollUp();
            return true;
        }
        return false;
    }

    //! Physical buttons: ENTER=select, UP/DOWN=cycle, ESC=back
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();

        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            navigateByIndex(_selectedIndex);
            return true;
        }

        if (key == WatchUi.KEY_DOWN) {
            _selectedIndex = _selectedIndex + 1;
            if (_selectedIndex > 3) { _selectedIndex = 0; }
            _view.scrollDown();
            return true;
        }

        if (key == WatchUi.KEY_UP) {
            _selectedIndex = _selectedIndex - 1;
            if (_selectedIndex < 0) { _selectedIndex = 3; }
            _view.scrollUp();
            return true;
        }

        if (key == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }

        return false;
    }

    private function getScrollOffset() as Number {
        return _view.getScrollOffset();
    }

    private function navigateByIndex(index as Number) as Void {
        if (index == 0) {
            navigateToQueue();
        } else if (index == 1) {
            navigateToPodcasts();
        } else if (index == 2) {
            navigateToDownloads();
        } else {
            navigateToSettings();
        }
    }

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

    private function navigateToDownloads() as Void {
        var dlView = new DownloadsView();
        WatchUi.pushView(dlView, new DownloadsDelegate(dlView), WatchUi.SLIDE_UP);
    }

    private function navigateToSettings() as Void {
        var settingsView = new SettingsView();
        WatchUi.pushView(settingsView, new SettingsDelegate(settingsView), WatchUi.SLIDE_UP);
    }
}
