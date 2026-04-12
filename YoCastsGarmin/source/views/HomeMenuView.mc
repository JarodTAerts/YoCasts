import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;

//! Custom home menu with tap-to-select pills and marquee text.
//! Three items: Queue, Podcasts, Now Playing.
//! Tap any item to navigate directly — no selection highlight.
//! Swipe up/down or buttons scroll the list smoothly.
class HomeMenuView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _isPlaying as Boolean = false;
    private var _scrollOffset as Number = 0;

    // Cached screen Y positions for hit testing (set each onUpdate)
    private var _queueScreenY as Number = 0;
    private var _podScreenY as Number = 0;
    private var _npScreenY as Number = 0;
    private var _settingsScreenY as Number = 0;
    private var _playBtnCx as Number = 0;
    private var _playBtnCy as Number = 0;

    // Layout metrics for 390x390 round AMOLED
    private var _pillH as Number = 68;
    private var _npH as Number = 105;
    private var _settingsH as Number = 52;
    private var _gap as Number = 14;
    private var _margin as Number = 28;
    private var _viewportTop as Number = 55;
    private var _viewportH as Number = 310;
    private var _scrollStep as Number = 60;
    private var _pillR as Number = 16;
    private var _contentHeight as Number = 0;
    private var _maxScroll as Number = 0;

    // Marquee state for NP episode title
    private var _marqueeTimer as Timer.Timer? = null;
    private var _npTitleOffset as Number = 0;
    private var _npTitleMaxScroll as Number = 0;
    private var _npTitlePhase as Number = 0;
    private var _npTitlePause as Number = 15;
    // Marquee state for NP podcast subtitle
    private var _npSubOffset as Number = 0;
    private var _npSubMaxScroll as Number = 0;
    private var _npSubPhase as Number = 0;
    private var _npSubPause as Number = 15;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
        _contentHeight = _pillH + _gap + _pillH + _gap + _npH + _gap + _settingsH + 15;
        _maxScroll = _contentHeight - _viewportH;
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

    //! Marquee timer callback — animates overflowing text
    function onMarqueeTick() as Void {
        var needsUpdate = false;

        // NP title track
        if (_npTitleMaxScroll > 0) {
            if (_npTitlePhase == 0) {
                _npTitlePause = _npTitlePause - 1;
                if (_npTitlePause <= 0) { _npTitlePhase = 1; }
            } else if (_npTitlePhase == 1) {
                _npTitleOffset = _npTitleOffset + 2;
                needsUpdate = true;
                if (_npTitleOffset >= _npTitleMaxScroll) {
                    _npTitleOffset = _npTitleMaxScroll;
                    _npTitlePhase = 2;
                    _npTitlePause = 10;
                }
            } else {
                _npTitlePause = _npTitlePause - 1;
                if (_npTitlePause <= 0) {
                    _npTitleOffset = 0;
                    _npTitlePhase = 0;
                    _npTitlePause = 15;
                    needsUpdate = true;
                }
            }
        }

        // NP subtitle track
        if (_npSubMaxScroll > 0) {
            if (_npSubPhase == 0) {
                _npSubPause = _npSubPause - 1;
                if (_npSubPause <= 0) { _npSubPhase = 1; }
            } else if (_npSubPhase == 1) {
                _npSubOffset = _npSubOffset + 2;
                needsUpdate = true;
                if (_npSubOffset >= _npSubMaxScroll) {
                    _npSubOffset = _npSubMaxScroll;
                    _npSubPhase = 2;
                    _npSubPause = 10;
                }
            } else {
                _npSubPause = _npSubPause - 1;
                if (_npSubPause <= 0) {
                    _npSubOffset = 0;
                    _npSubPhase = 0;
                    _npSubPause = 15;
                    needsUpdate = true;
                }
            }
        }

        if (needsUpdate) {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var pillW = w - _margin * 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Fixed title area
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 28, Graphics.FONT_MEDIUM, "YoCasts",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 40, 46, cx + 40, 46);

        // Compute screen positions from scroll offset
        _queueScreenY = _viewportTop - _scrollOffset;
        _podScreenY = _queueScreenY + _pillH + _gap;
        _npScreenY = _podScreenY + _pillH + _gap;
        _settingsScreenY = _npScreenY + _npH + _gap;

        // Clip to scroll viewport
        dc.setClip(0, _viewportTop, w, _viewportH);

        // Queue pill
        if (_queueScreenY + _pillH > _viewportTop && _queueScreenY < _viewportTop + _viewportH) {
            drawPillBg(dc, _margin, _queueScreenY, pillW, _pillH, _pillR);
            drawQueueContent(dc, _margin, _queueScreenY, pillW, _pillH, cx);
        }

        // Podcasts pill
        if (_podScreenY + _pillH > _viewportTop && _podScreenY < _viewportTop + _viewportH) {
            drawPillBg(dc, _margin, _podScreenY, pillW, _pillH, _pillR);
            drawPodcastsContent(dc, _margin, _podScreenY, pillW, _pillH, cx);
        }

        // Now Playing pill
        if (_npScreenY + _npH > _viewportTop && _npScreenY < _viewportTop + _viewportH) {
            drawNowPlayingPill(dc, _margin, _npScreenY, pillW, _npH, _pillR, cx, w);
        }

        // Settings pill
        if (_settingsScreenY + _settingsH > _viewportTop && _settingsScreenY < _viewportTop + _viewportH) {
            drawSettingsPill(dc, _margin, _settingsScreenY, pillW, _settingsH, _pillR, cx);
        }

        dc.clearClip();

        if (_maxScroll > 0) {
            drawScrollIndicator(dc, w);
        }
    }

    // --- Pill Background (uniform, no selection highlight) ---

    private function drawPillBg(dc as Graphics.Dc, x as Number, y as Number,
                                 w as Number, h as Number, r as Number) as Void {
        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, r);
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
                                         cx as Number, screenW as Number) as Void {
        dc.setColor(0x162038, Graphics.COLOR_TRANSPARENT);
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
            _npTitleMaxScroll = 0;
            _npSubMaxScroll = 0;
            return;
        }

        var epTitle = ep[DataKeys.E_TITLE] as String;
        var podTitle = ep[DataKeys.E_PODCAST_TITLE] as String;
        var duration = ep[DataKeys.E_DURATION] as Number;
        var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;

        var textPad = 14;
        var containerX = x + textPad;
        var containerW = w - textPad * 2;

        // "NOW PLAYING" label
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 12, Graphics.FONT_XTINY, "NOW PLAYING",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Episode title (marquee if overflows)
        drawMarqueeText(dc, epTitle, Graphics.FONT_SMALL,
                        containerX, y + 31, containerW, screenW,
                        _npTitleOffset, true);

        // Podcast name (marquee if overflows)
        drawMarqueeText(dc, podTitle, Graphics.FONT_XTINY,
                        containerX, y + 50, containerW, screenW,
                        _npSubOffset, false);

        // Progress bar
        var barX = x + textPad;
        var barW = w - textPad * 2;
        var barY = y + 64;
        var barH = 3;

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

        // Play/Pause button
        var btnR = 13;
        _playBtnCx = cx - 45;
        _playBtnCy = y + 85;

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_playBtnCx, _playBtnCy, btnR);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (_isPlaying) {
            dc.fillRectangle(_playBtnCx - 5, _playBtnCy - 6, 4, 12);
            dc.fillRectangle(_playBtnCx + 2, _playBtnCy - 6, 4, 12);
        } else {
            var pts = [[_playBtnCx - 4, _playBtnCy - 7],
                       [_playBtnCx - 4, _playBtnCy + 7],
                       [_playBtnCx + 7, _playBtnCy]];
            dc.fillPolygon(pts);
        }

        // Time display
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var timeStr = DataFormat.formatTime(playedUpTo) + " / " + DataFormat.formatTime(duration);
        dc.drawText(cx + 18, _playBtnCy, Graphics.FONT_XTINY, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw text with marquee scrolling if it overflows its container
    private function drawMarqueeText(dc as Graphics.Dc, text as String,
                                      font as Graphics.FontDefinition,
                                      containerX as Number, y as Number,
                                      containerW as Number, screenW as Number,
                                      offset as Number, isTitle as Boolean) as Void {
        var fullW = dc.getTextWidthInPixels(text, font);
        var color = isTitle ? Graphics.COLOR_WHITE : 0x777777;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (fullW <= containerW) {
            dc.drawText(containerX + containerW / 2, y, font, text,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (isTitle) { _npTitleMaxScroll = 0; } else { _npSubMaxScroll = 0; }
            return;
        }

        var overflow = fullW - containerW;
        if (isTitle) { _npTitleMaxScroll = overflow; } else { _npSubMaxScroll = overflow; }

        var fontH = dc.getFontHeight(font);
        dc.setClip(containerX, y - fontH / 2, containerW, fontH);
        dc.drawText(containerX - offset, y, font, text,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // Restore viewport clip
        dc.setClip(0, _viewportTop, screenW, _viewportH);
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

    //! Draw a simple gear/cog icon for settings
    private function drawGearIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + 8, y, 7);
        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + 8, y, 3);
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        // Gear teeth (4 small rectangles at cardinal directions)
        dc.fillRectangle(x + 6, y - 10, 4, 5);
        dc.fillRectangle(x + 6, y + 5, 4, 5);
        dc.fillRectangle(x - 2, y - 2, 5, 4);
        dc.fillRectangle(x + 13, y - 2, 5, 4);
    }

    // --- Settings Pill ---

    private function drawSettingsPill(dc as Graphics.Dc, x as Number, y as Number,
                                      w as Number, h as Number, r as Number,
                                      cx as Number) as Void {
        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, r);

        var iconX = x + 20;
        var iconY = y + h / 2;
        drawGearIcon(dc, iconX, iconY);

        var textX = cx + 8;
        dc.setColor(0xBBBBBB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + h / 2, Graphics.FONT_SMALL, "Settings",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- Public API ---

    function togglePlayPause() as Void {
        _isPlaying = !_isPlaying;
        WatchUi.requestUpdate();
    }

    //! Scroll the viewport down (content moves up)
    function scrollDown() as Void {
        _scrollOffset = _scrollOffset + _scrollStep;
        if (_scrollOffset > _maxScroll) { _scrollOffset = _maxScroll; }
        WatchUi.requestUpdate();
    }

    //! Scroll the viewport up (content moves down)
    function scrollUp() as Void {
        _scrollOffset = _scrollOffset - _scrollStep;
        if (_scrollOffset < 0) { _scrollOffset = 0; }
        WatchUi.requestUpdate();
    }

    //! Hit-test a tap. Returns: 0=queue, 1=podcasts, 2=NP, 3=playBtn, 4=settings, -1=miss
    function hitTest(tapX as Number, tapY as Number) as Number {
        var w = System.getDeviceSettings().screenWidth;

        if (tapY < _viewportTop || tapY > _viewportTop + _viewportH) {
            return -1;
        }
        if (tapX < 20 || tapX > w - 20) {
            return -1;
        }

        if (tapY >= _queueScreenY && tapY < _queueScreenY + _pillH) {
            return 0;
        }
        if (tapY >= _podScreenY && tapY < _podScreenY + _pillH) {
            return 1;
        }
        if (tapY >= _npScreenY && tapY < _npScreenY + _npH) {
            var dx = tapX - _playBtnCx;
            var dy = tapY - _playBtnCy;
            if (dx * dx + dy * dy <= 20 * 20) {
                return 3;
            }
            return 2;
        }
        if (tapY >= _settingsScreenY && tapY < _settingsScreenY + _settingsH) {
            return 4;
        }

        return -1;
    }

    function getService() as IPodcastService {
        return _service;
    }
}

//! Delegate for the home menu. Tap to navigate, swipe/buttons to scroll.
//! Uses InputDelegate (NOT BehaviorDelegate) because BehaviorDelegate's
//! behavior translator converts ALL screen taps into onSelect() calls,
//! which prevents onTap() from ever receiving touch coordinates.
//! With InputDelegate, onTap() fires directly for touch events.
class HomeMenuDelegate extends WatchUi.InputDelegate {

    private var _view as HomeMenuView;
    private var _service as IPodcastService;
    // Tracks which item the physical button SELECT activates.
    // Cycles via KEY_UP/KEY_DOWN. 0=Queue, 1=Podcasts, 2=NowPlaying, 3=Settings.
    private var _selectedIndex as Number = 0;

    function initialize(view as HomeMenuView, service as IPodcastService) {
        InputDelegate.initialize();
        _view = view;
        _service = service;
    }

    //! Touch: map tap coordinates to the menu item under the finger
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
        } else if (hit == 4) {
            navigateToSettings();
            return true;
        }

        return false;
    }

    //! Swipe gestures for scrolling the viewport
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

        // SELECT / ACTION button — navigate to the tracked item
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            navigateByIndex(_selectedIndex);
            return true;
        }

        // DOWN — cycle selected index forward
        if (key == WatchUi.KEY_DOWN) {
            _selectedIndex = _selectedIndex + 1;
            if (_selectedIndex > 3) { _selectedIndex = 0; }
            _view.scrollDown();
            return true;
        }

        // UP — cycle selected index backward
        if (key == WatchUi.KEY_UP) {
            _selectedIndex = _selectedIndex - 1;
            if (_selectedIndex < 0) { _selectedIndex = 3; }
            _view.scrollUp();
            return true;
        }

        // BACK button
        if (key == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }

        return false;
    }

    private function navigateByIndex(index as Number) as Void {
        if (index == 0) {
            navigateToQueue();
        } else if (index == 1) {
            navigateToPodcasts();
        } else if (index == 2) {
            navigateToNowPlaying();
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

    private function navigateToSettings() as Void {
        var settingsView = new SettingsView();
        WatchUi.pushView(settingsView, new SettingsDelegate(settingsView), WatchUi.SLIDE_UP);
    }
}
