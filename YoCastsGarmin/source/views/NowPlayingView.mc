import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Math;

//! Now Playing screen — custom View showing current episode info.
//! Displays podcast name, episode title, progress arc, and time.
//! This is the only fully custom-drawn screen in the app.
class NowPlayingView extends WatchUi.View {

    private var _episode as Dictionary;
    private var _isPlaying as Boolean = false;
    private var _currentPosition as Number;

    function initialize(episode as Dictionary) {
        View.initialize();
        _episode = episode;
        _currentPosition = (episode[DataKeys.E_PLAYED_UP_TO] as Number);
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

        // Podcast name (top, small, gray — pixel-truncated)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var maxTextW = width - 60;
        var podDisplay = DataFormat.truncateText(dc, podcastTitle, Graphics.FONT_XTINY, maxTextW);
        dc.drawText(cx, cy - 55, Graphics.FONT_XTINY, podDisplay,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Episode title (center, white — pixel-truncated)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var epDisplay = DataFormat.truncateText(dc, episodeTitle, Graphics.FONT_SMALL, maxTextW);
        dc.drawText(cx, cy - 15, Graphics.FONT_SMALL, epDisplay,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

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
