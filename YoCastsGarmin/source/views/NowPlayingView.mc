import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Math;
import Toybox.Timer;

//! Now Playing — full-screen playback view per layout reference §7.
//! Progress arc, podcast name, episode title (marquee), 3 control buttons,
//! and time display. Uses consistent design language with HomeMenuView.
class NowPlayingView extends WatchUi.View {

    private var _episode as Dictionary;
    private var _isPlaying as Boolean = false;
    private var _currentPosition as Number;
    private var _positionTracker as PositionTracker;

    // Brand colors looked up from podcast data
    private var _brandColor as Number = 0x55AAFF;
    private var _brandTint as Number = 0xFFFFFF;

    // --- Layout constants from spec §7.2 ---
    private const CX = 195;
    private const CY = 195;
    private const ARC_RADIUS = 185;
    private const ARC_PEN = 6;

    private const PODCAST_Y = 80;
    private const TITLE_Y = 140;
    private const CONTROLS_Y = 245;
    private const TIME_Y = 300;

    private const SKIP_BACK_CX = 110;
    private const PLAY_CX = 195;
    private const SKIP_FWD_CX = 280;
    private const SKIP_R = 24;
    private const PLAY_R = 32;

    // Touch radii (larger than visual for comfortable tapping)
    public const SKIP_TOUCH_R = 30;
    public const PLAY_TOUCH_R = 38;

    // Max text widths from spec §7.5
    private const PODCAST_MAX_W = 275;
    private const TITLE_MAX_W = 331;

    // Marquee state for episode title
    private var _marqueeTimer as Timer.Timer? = null;
    private var _titleOffset as Number = 0;
    private var _titleMaxScroll as Number = 0;
    private var _titlePhase as Number = 0;
    private var _titlePause as Number = 15;
    // Marquee state for podcast name
    private var _podOffset as Number = 0;
    private var _podMaxScroll as Number = 0;
    private var _podPhase as Number = 0;
    private var _podPause as Number = 15;

    function initialize(episode as Dictionary) {
        View.initialize();
        _episode = episode;
        _currentPosition = (episode[DataKeys.E_PLAYED_UP_TO] as Number);

        var podUuidVal = episode.get(DataKeys.E_PODCAST_UUID);
        var podUuid = (podUuidVal != null) ? podUuidVal as String : "";
        _positionTracker = new PositionTracker(
            episode[DataKeys.E_UUID] as String,
            podUuid,
            episode[DataKeys.E_DURATION] as Number
        );

        // Initialize shared PlaybackState so HomeMenuView dock stays current
        PlaybackState.update(
            episode[DataKeys.E_UUID] as String,
            podUuid,
            episode[DataKeys.E_TITLE] as String,
            (episode.get(DataKeys.E_PODCAST_TITLE) != null)
                ? episode[DataKeys.E_PODCAST_TITLE] as String : "",
            _currentPosition,
            episode[DataKeys.E_DURATION] as Number,
            false
        );

        // Look up podcast brand colors from cache
        var podcasts = CacheManager.loadPodcasts();
        if (podcasts != null && !podUuid.equals("")) {
            var colors = DataFormat.lookupPodcastColors(podcasts as Array<Dictionary>, podUuid);
            _brandColor = colors[0] as Number;
            _brandTint = colors[1] as Number;
        }
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
        _positionTracker.stopTracking();
    }

    //! Marquee timer callback — animates overflowing text
    function onMarqueeTick() as Void {
        var needsUpdate = false;

        // Episode title marquee
        if (_titleMaxScroll > 0) {
            if (_titlePhase == 0) {
                _titlePause = _titlePause - 1;
                if (_titlePause <= 0) { _titlePhase = 1; }
            } else if (_titlePhase == 1) {
                _titleOffset = _titleOffset + 2;
                needsUpdate = true;
                if (_titleOffset >= _titleMaxScroll) {
                    _titleOffset = _titleMaxScroll;
                    _titlePhase = 2;
                    _titlePause = 10;
                }
            } else {
                _titlePause = _titlePause - 1;
                if (_titlePause <= 0) {
                    _titleOffset = 0;
                    _titlePhase = 0;
                    _titlePause = 15;
                    needsUpdate = true;
                }
            }
        }

        // Podcast name marquee
        if (_podMaxScroll > 0) {
            if (_podPhase == 0) {
                _podPause = _podPause - 1;
                if (_podPause <= 0) { _podPhase = 1; }
            } else if (_podPhase == 1) {
                _podOffset = _podOffset + 2;
                needsUpdate = true;
                if (_podOffset >= _podMaxScroll) {
                    _podOffset = _podMaxScroll;
                    _podPhase = 2;
                    _podPause = 10;
                }
            } else {
                _podPause = _podPause - 1;
                if (_podPause <= 0) {
                    _podOffset = 0;
                    _podPhase = 0;
                    _podPause = 15;
                    needsUpdate = true;
                }
            }
        }

        if (needsUpdate) {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // Clear background — subtle brand color wash on AMOLED
        var bgWash = DataFormat.dimColor(DataFormat.brightenColor(_brandColor, 40), 0.10);
        dc.setColor(bgWash, bgWash);
        dc.clear();

        var duration = _episode[DataKeys.E_DURATION] as Number;
        var podcastTitle = _episode[DataKeys.E_PODCAST_TITLE] as String;
        var episodeTitle = _episode[DataKeys.E_TITLE] as String;

        // 1. Progress arc background (full circle, dark gray)
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(ARC_PEN);
        dc.drawArc(CX, CY, ARC_RADIUS, Graphics.ARC_CLOCKWISE, 0, 360);

        // 2. Progress arc fill — brand color, brightened for visibility
        if (duration > 0 && _currentPosition > 0) {
            var progress = _currentPosition.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var degrees = (progress * 360.0).toNumber();
            var arcColor = DataFormat.brightenColor(_brandColor, 200);
            dc.setColor(arcColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(CX, CY, ARC_RADIUS, Graphics.ARC_CLOCKWISE, 90, 90 - degrees);
        }
        dc.setPenWidth(1);

        // 3. Podcast name (top, brand-tinted)
        var podColor = DataFormat.dimColor(DataFormat.brightenColor(_brandTint, 180), 0.7);
        drawMarqueeText(dc, podcastTitle, Graphics.FONT_XTINY,
                        podColor, CX, PODCAST_Y, PODCAST_MAX_W,
                        _podOffset, false);

        // 4. Episode title (center, white, FONT_MEDIUM, marquee)
        drawMarqueeText(dc, episodeTitle, Graphics.FONT_MEDIUM,
                        0xFFFFFF, CX, TITLE_Y, TITLE_MAX_W,
                        _titleOffset, true);

        // 5. Control buttons
        drawControls(dc);

        // 6. Time display (bottom, dimmed tint)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var timeStr = DataFormat.formatTime(_currentPosition) + " / " + DataFormat.formatTime(duration);
        dc.drawText(CX, TIME_Y, Graphics.FONT_TINY, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw the three control buttons: skip back, play/pause, skip forward
    private function drawControls(dc as Graphics.Dc) as Void {
        var skipBg = DataFormat.dimColor(DataFormat.brightenColor(_brandColor, 60), 0.35);
        var skipFg = DataFormat.dimColor(DataFormat.brightenColor(_brandTint, 180), 0.7);
        var playBtnColor = DataFormat.brightenColor(_brandColor, 200);

        // --- Skip Back button (left, brand-tinted circle) ---
        dc.setColor(skipBg, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(SKIP_BACK_CX, CONTROLS_Y, SKIP_R);
        dc.setColor(skipFg, Graphics.COLOR_TRANSPARENT);
        // Rewind icon: two left-pointing triangles + bar
        var bx = SKIP_BACK_CX;
        var by = CONTROLS_Y;
        dc.fillPolygon([[bx + 2, by - 8], [bx + 2, by + 8], [bx - 8, by]]);
        dc.fillPolygon([[bx + 10, by - 8], [bx + 10, by + 8], [bx, by]]);
        dc.fillRectangle(bx - 10, by - 8, 2, 16);

        // --- Play/Pause button (center, brand accent circle) ---
        dc.setColor(playBtnColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(PLAY_CX, CONTROLS_Y, PLAY_R);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (_isPlaying) {
            // Pause bars
            dc.fillRectangle(PLAY_CX - 10, CONTROLS_Y - 12, 7, 24);
            dc.fillRectangle(PLAY_CX + 3, CONTROLS_Y - 12, 7, 24);
        } else {
            // Play triangle (right-pointing)
            dc.fillPolygon([[PLAY_CX - 10, CONTROLS_Y - 14],
                            [PLAY_CX - 10, CONTROLS_Y + 14],
                            [PLAY_CX + 14, CONTROLS_Y]]);
        }

        // --- Skip Forward button (right, brand-tinted circle) ---
        dc.setColor(skipBg, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(SKIP_FWD_CX, CONTROLS_Y, SKIP_R);
        dc.setColor(skipFg, Graphics.COLOR_TRANSPARENT);
        // Fast-forward icon: two right-pointing triangles + bar
        var fx = SKIP_FWD_CX;
        var fy = CONTROLS_Y;
        dc.fillPolygon([[fx - 10, fy - 8], [fx - 10, fy + 8], [fx, fy]]);
        dc.fillPolygon([[fx - 2, fy - 8], [fx - 2, fy + 8], [fx + 8, fy]]);
        dc.fillRectangle(fx + 8, fy - 8, 2, 16);
    }

    //! Draw text with marquee scrolling if it overflows the container width.
    //! isTitle: true for episode title, false for podcast name.
    private function drawMarqueeText(dc as Graphics.Dc, text as String,
                                      font as Graphics.FontDefinition,
                                      color as Number, cx as Number,
                                      y as Number, maxW as Number,
                                      offset as Number, isTitle as Boolean) as Void {
        var fullW = dc.getTextWidthInPixels(text, font);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (fullW <= maxW) {
            dc.drawText(cx, y, font, text,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (isTitle) { _titleMaxScroll = 0; } else { _podMaxScroll = 0; }
            return;
        }

        // Text overflows — marquee scroll
        var overflow = fullW - maxW;
        if (isTitle) { _titleMaxScroll = overflow; } else { _podMaxScroll = overflow; }

        var containerX = cx - maxW / 2;
        var fontH = dc.getFontHeight(font);
        dc.setClip(containerX, y - fontH / 2, maxW, fontH);
        dc.drawText(containerX - offset, y, font, text,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.clearClip();
    }

    //! Public accessor for PositionTracker to read current position.
    function getCurrentPosition() as Number {
        return _currentPosition;
    }

    //! Toggle play/pause state and start/stop position tracking.
    function togglePlayPause() as Void {
        _isPlaying = !_isPlaying;
        if (_isPlaying) {
            _positionTracker.startTracking(self);
        } else {
            _positionTracker.logNow();
            _positionTracker.stopTracking();
        }
        PlaybackState.setPlaying(_isPlaying);
        WatchUi.requestUpdate();
    }

    //! Skip forward 30 seconds
    function skipForward() as Void {
        var duration = _episode[DataKeys.E_DURATION] as Number;
        _currentPosition = _currentPosition + 30;
        if (_currentPosition > duration) {
            _currentPosition = duration;
        }
        if (_positionTracker.isTracking()) {
            _positionTracker.logNow();
        }
        PlaybackState.updatePosition(_currentPosition);
        WatchUi.requestUpdate();
    }

    //! Skip back 15 seconds
    function skipBack() as Void {
        _currentPosition = _currentPosition - 15;
        if (_currentPosition < 0) {
            _currentPosition = 0;
        }
        if (_positionTracker.isTracking()) {
            _positionTracker.logNow();
        }
        PlaybackState.updatePosition(_currentPosition);
        WatchUi.requestUpdate();
    }
}

//! Input delegate for Now Playing screen.
//! Uses InputDelegate (not BehaviorDelegate) for tap-coordinate hit testing
//! on play/pause and skip buttons, plus physical button support via onKey.
class NowPlayingDelegate extends WatchUi.InputDelegate {

    private var _episode as Dictionary;
    private var _view as NowPlayingView?;

    function initialize(episode as Dictionary) {
        InputDelegate.initialize();
        _episode = episode;
    }

    //! Store reference to view for controlling playback
    function setView(view as NowPlayingView) as Void {
        _view = view;
    }

    //! Tap handler with coordinate-based hit testing for control buttons
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (_view == null) { return false; }
        var view = _view as NowPlayingView;
        var coords = evt.getCoordinates();
        var tapX = coords[0] as Number;
        var tapY = coords[1] as Number;

        // Hit test against skip back button (110, 245)
        if (isInCircle(tapX, tapY, 110, 245, view.SKIP_TOUCH_R)) {
            view.skipBack();
            return true;
        }

        // Hit test against play/pause button (195, 245)
        if (isInCircle(tapX, tapY, 195, 245, view.PLAY_TOUCH_R)) {
            view.togglePlayPause();
            return true;
        }

        // Hit test against skip forward button (280, 245)
        if (isInCircle(tapX, tapY, 280, 245, view.SKIP_TOUCH_R)) {
            view.skipForward();
            return true;
        }

        return false;
    }

    //! Physical button support
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();

        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            if (_view != null) {
                (_view as NowPlayingView).togglePlayPause();
            }
            return true;
        }

        if (key == WatchUi.KEY_DOWN) {
            // DOWN = skip forward 30s
            if (_view != null) {
                (_view as NowPlayingView).skipForward();
            }
            return true;
        }

        if (key == WatchUi.KEY_UP) {
            // UP = skip back 15s
            if (_view != null) {
                (_view as NowPlayingView).skipBack();
            }
            return true;
        }

        if (key == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }

        return false;
    }

    //! Swipe right to go back
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        if (evt.getDirection() == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    //! Circle hit test helper
    private function isInCircle(x as Number, y as Number,
                                 cx as Number, cy as Number, r as Number) as Boolean {
        var dx = x - cx;
        var dy = y - cy;
        return (dx * dx + dy * dy) <= (r * r);
    }
}
