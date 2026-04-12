import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Math;
import Toybox.Timer;

//! Now Playing screen — custom View showing current episode info.
//! Displays podcast name, episode title, progress arc, and time.
//! Uses marquee scrolling for overflowing text.
class NowPlayingView extends WatchUi.View {

    private var _episode as Dictionary;
    private var _isPlaying as Boolean = false;
    private var _currentPosition as Number;

    // Marquee state for episode title
    private var _marqueeTimer as Timer.Timer? = null;
    private var _epTitleOffset as Number = 0;
    private var _epTitleMaxScroll as Number = 0;
    private var _epTitlePhase as Number = 0;
    private var _epTitlePause as Number = 15;
    // Marquee state for podcast name
    private var _podNameOffset as Number = 0;
    private var _podNameMaxScroll as Number = 0;
    private var _podNamePhase as Number = 0;
    private var _podNamePause as Number = 15;

    function initialize(episode as Dictionary) {
        View.initialize();
        _episode = episode;
        _currentPosition = (episode[DataKeys.E_PLAYED_UP_TO] as Number);
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

    //! Marquee timer callback
    function onMarqueeTick() as Void {
        var needsUpdate = false;

        // Episode title track
        if (_epTitleMaxScroll > 0) {
            if (_epTitlePhase == 0) {
                _epTitlePause = _epTitlePause - 1;
                if (_epTitlePause <= 0) { _epTitlePhase = 1; }
            } else if (_epTitlePhase == 1) {
                _epTitleOffset = _epTitleOffset + 2;
                needsUpdate = true;
                if (_epTitleOffset >= _epTitleMaxScroll) {
                    _epTitleOffset = _epTitleMaxScroll;
                    _epTitlePhase = 2;
                    _epTitlePause = 10;
                }
            } else {
                _epTitlePause = _epTitlePause - 1;
                if (_epTitlePause <= 0) {
                    _epTitleOffset = 0;
                    _epTitlePhase = 0;
                    _epTitlePause = 15;
                    needsUpdate = true;
                }
            }
        }

        // Podcast name track
        if (_podNameMaxScroll > 0) {
            if (_podNamePhase == 0) {
                _podNamePause = _podNamePause - 1;
                if (_podNamePause <= 0) { _podNamePhase = 1; }
            } else if (_podNamePhase == 1) {
                _podNameOffset = _podNameOffset + 2;
                needsUpdate = true;
                if (_podNameOffset >= _podNameMaxScroll) {
                    _podNameOffset = _podNameMaxScroll;
                    _podNamePhase = 2;
                    _podNamePause = 10;
                }
            } else {
                _podNamePause = _podNamePause - 1;
                if (_podNamePause <= 0) {
                    _podNameOffset = 0;
                    _podNamePhase = 0;
                    _podNamePause = 15;
                    needsUpdate = true;
                }
            }
        }

        if (needsUpdate) {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;

        // Clear background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var duration = _episode[DataKeys.E_DURATION] as Number;
        var podcastTitle = _episode[DataKeys.E_PODCAST_TITLE] as String;
        var episodeTitle = _episode[DataKeys.E_TITLE] as String;

        // Draw progress arc around screen edge
        drawProgressArc(dc, cx, cy, width, height, duration);

        var maxTextW = width - 60;
        var containerX = 30;

        // Podcast name (top, gray — marquee if overflows)
        _drawMarquee(dc, podcastTitle, Graphics.FONT_XTINY,
                     containerX, cy - 55, maxTextW,
                     _podNameOffset, false);

        // Episode title (center, white — marquee if overflows)
        _drawMarquee(dc, episodeTitle, Graphics.FONT_SMALL,
                     containerX, cy - 15, maxTextW,
                     _epTitleOffset, true);

        // Play/Pause indicator — drawn with Graphics shapes
        var btnCx = cx;
        var btnCy = cy + 20;
        var btnR = 18;

        // Button circle background
        if (_isPlaying) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillCircle(btnCx, btnCy, btnR);

        // Icon inside button
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (_isPlaying) {
            // Pause: two vertical bars
            dc.fillRectangle(btnCx - 7, btnCy - 8, 5, 16);
            dc.fillRectangle(btnCx + 2, btnCy - 8, 5, 16);
        } else {
            // Play: right-pointing triangle
            var pts = [[btnCx - 6, btnCy - 10],
                       [btnCx - 6, btnCy + 10],
                       [btnCx + 10, btnCy]];
            dc.fillPolygon(pts);
        }

        // Time display (bottom)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var timeStr = DataFormat.formatTime(_currentPosition) + " / " + DataFormat.formatTime(duration);
        dc.drawText(cx, cy + 55, Graphics.FONT_XTINY, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw text with marquee if it overflows container width
    private function _drawMarquee(dc as Graphics.Dc, text as String,
                                   font as Graphics.FontDefinition,
                                   containerX as Number, y as Number,
                                   containerW as Number,
                                   offset as Number, isTitle as Boolean) as Void {
        var fullW = dc.getTextWidthInPixels(text, font);
        var color = isTitle ? Graphics.COLOR_WHITE : 0xAAAAAA;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (fullW <= containerW) {
            dc.drawText(containerX + containerW / 2, y, font, text,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (isTitle) { _epTitleMaxScroll = 0; } else { _podNameMaxScroll = 0; }
            return;
        }

        var overflow = fullW - containerW;
        if (isTitle) { _epTitleMaxScroll = overflow; } else { _podNameMaxScroll = overflow; }

        var fontH = dc.getFontHeight(font);
        dc.setClip(containerX, y - fontH / 2, containerW, fontH);
        dc.drawText(containerX - offset, y, font, text,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.clearClip();
    }

    //! Draw a progress arc around the edge of the screen
    private function drawProgressArc(dc as Graphics.Dc, cx as Number, cy as Number,
                                      width as Number, height as Number,
                                      duration as Number) as Void {
        var radius = cx - 4;

        // Background arc (dark gray)
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, -270);

        // Progress arc (blue)
        if (duration > 0 && _currentPosition > 0) {
            var progress = _currentPosition.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var endAngle = 90 - (progress * 360.0).toNumber();
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }

        dc.setPenWidth(1);
    }

    //! Toggle play/pause state
    function togglePlayPause() as Void {
        _isPlaying = !_isPlaying;
        WatchUi.requestUpdate();
    }

    //! Skip forward 30 seconds
    function skipForward() as Void {
        var duration = _episode[DataKeys.E_DURATION] as Number;
        _currentPosition = _currentPosition + 30;
        if (_currentPosition > duration) {
            _currentPosition = duration;
        }
        WatchUi.requestUpdate();
    }

    //! Skip back 30 seconds
    function skipBack() as Void {
        _currentPosition = _currentPosition - 30;
        if (_currentPosition < 0) {
            _currentPosition = 0;
        }
        WatchUi.requestUpdate();
    }
}

//! Input delegate for Now Playing screen.
//! SELECT = play/pause, UP = skip back, DOWN = skip forward, BACK = go back.
class NowPlayingDelegate extends WatchUi.BehaviorDelegate {

    private var _episode as Dictionary;
    private var _view as NowPlayingView?;

    function initialize(episode as Dictionary) {
        BehaviorDelegate.initialize();
        _episode = episode;
    }

    //! Store reference to view for controlling playback
    function setView(view as NowPlayingView) as Void {
        _view = view;
    }

    function onSelect() as Boolean {
        if (_view != null) {
            (_view as NowPlayingView).togglePlayPause();
        }
        return true;
    }

    function onNextPage() as Boolean {
        // DOWN button = skip forward 30s
        if (_view != null) {
            (_view as NowPlayingView).skipForward();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        // UP button = skip back 30s
        if (_view != null) {
            (_view as NowPlayingView).skipBack();
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
