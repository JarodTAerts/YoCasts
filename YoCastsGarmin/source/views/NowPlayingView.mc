using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Math;

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

    function onUpdate(dc as Gfx.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;

        // Clear background
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        var duration = _episode[DataKeys.E_DURATION] as Number;
        var podcastTitle = _episode[DataKeys.E_PODCAST_TITLE] as String;
        var episodeTitle = _episode[DataKeys.E_TITLE] as String;

        // Draw progress arc around screen edge
        drawProgressArc(dc, cx, cy, width, height, duration);

        // Podcast name (top, small, gray)
        dc.setColor(0xAAAAAA, Gfx.COLOR_TRANSPARENT);
        var podDisplay = podcastTitle;
        if (podDisplay.length() > 22) {
            podDisplay = podDisplay.substring(0, 19) + "...";
        }
        dc.drawText(cx, cy - 55, Gfx.FONT_XTINY, podDisplay,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // Episode title (center, white)
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var epDisplay = episodeTitle;
        if (epDisplay.length() > 30) {
            epDisplay = epDisplay.substring(0, 27) + "...";
        }
        dc.drawText(cx, cy - 15, Gfx.FONT_SMALL, epDisplay,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // Play/Pause indicator
        if (_isPlaying) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 20, Gfx.FONT_MEDIUM, "||",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 20, Gfx.FONT_MEDIUM, ">",
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        // Time display (bottom)
        dc.setColor(0xAAAAAA, Gfx.COLOR_TRANSPARENT);
        var timeStr = DataFormat.formatTime(_currentPosition) + " / " + DataFormat.formatTime(duration);
        dc.drawText(cx, cy + 55, Gfx.FONT_XTINY, timeStr,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    //! Draw a progress arc around the edge of the screen
    private function drawProgressArc(dc as Gfx.Dc, cx as Number, cy as Number,
                                      width as Number, height as Number,
                                      duration as Number) as Void {
        var radius = cx - 4;

        // Background arc (dark gray)
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, 90, -270);

        // Progress arc (blue)
        if (duration > 0 && _currentPosition > 0) {
            var progress = _currentPosition.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var endAngle = 90 - (progress * 360.0).toNumber();
            dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, 90, endAngle);
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
