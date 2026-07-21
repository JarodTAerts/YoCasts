import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Long-form episode content gets its own low-density reading surface.
class EpisodeShowNotesView extends WatchUi.View {

    private const CX = 195;
    private const BODY_TOP = 105;
    private const BODY_BOTTOM = 350;

    private var _episode as Dictionary;
    private var _service as IPodcastService;
    private var _lastSummary as String = "";
    private var _lines as Array<String> = [] as Array<String>;
    private var _scrollLine as Number = 0;
    private var _visibleLines as Number = 9;

    function initialize(episode as Dictionary, service as IPodcastService) {
        View.initialize();
        _episode = episode;
        _service = service;
    }

    function onShow() as Void {
        var uuid = _stringValue(_episode.get(DataKeys.E_UUID), "");
        if (uuid.length() > 0) {
            _service.requestEpisodeDetails(uuid);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        _refreshDetails();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            CX,
            32,
            Graphics.FONT_SMALL,
            "Show Notes",
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );

        var title = _stringValue(
            _episode.get(DataKeys.E_TITLE),
            "Episode"
        );
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            CX,
            70,
            Graphics.FONT_XTINY,
            DataFormat.truncateText(
                dc,
                title,
                Graphics.FONT_XTINY,
                270
            ),
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(0x224466, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(80, 91, 230, 2);

        var summary = _stringValue(
            _episode.get(DataKeys.E_SUMMARY),
            ""
        );
        if (!summary.equals(_lastSummary)) {
            _lastSummary = summary;
            _scrollLine = 0;
            _lines = [] as Array<String>;
        }
        if (_lines.size() == 0 && summary.length() > 0) {
            _lines = DataFormat.wrapText(
                dc,
                summary,
                Graphics.FONT_XTINY,
                300,
                180
            );
        }

        if (_lines.size() == 0) {
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                CX,
                170,
                Graphics.FONT_TINY,
                _service.getEpisodeDetails(
                    _stringValue(_episode.get(DataKeys.E_UUID), "")
                ) == null
                    ? "Loading..." : "No show notes available",
                Graphics.TEXT_JUSTIFY_CENTER |
                Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        var lineHeight = dc.getFontHeight(Graphics.FONT_XTINY) + 3;
        var visible = (BODY_BOTTOM - BODY_TOP) / lineHeight;
        _visibleLines = visible;
        dc.setClip(38, BODY_TOP, 314, BODY_BOTTOM - BODY_TOP);
        dc.setColor(0xEEEEEE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < visible; i++) {
            var index = _scrollLine + i;
            if (index >= _lines.size()) { break; }
            dc.drawText(
                48,
                BODY_TOP + i * lineHeight,
                Graphics.FONT_XTINY,
                _lines[index],
                Graphics.TEXT_JUSTIFY_LEFT
            );
        }
        dc.clearClip();

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (_scrollLine > 0) {
            dc.fillPolygon([[348, 118], [360, 118], [354, 109]]);
        }
        if (_scrollLine + visible < _lines.size()) {
            dc.fillPolygon([[348, 333], [360, 333], [354, 342]]);
        }
    }

    function scroll(delta as Number) as Void {
        var maxScroll = _lines.size() - _visibleLines;
        if (maxScroll < 0) { maxScroll = 0; }
        _scrollLine += delta;
        if (_scrollLine < 0) { _scrollLine = 0; }
        if (_scrollLine > maxScroll) { _scrollLine = maxScroll; }
        WatchUi.requestUpdate();
    }

    private function _refreshDetails() as Void {
        var details = _service.getEpisodeDetails(
            _stringValue(_episode.get(DataKeys.E_UUID), "")
        );
        if (details != null) {
            _episode = details as Dictionary;
        }
    }

    private function _stringValue(value as Object?,
                                  fallback as String) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return fallback;
    }
}

class EpisodeShowNotesDelegate extends WatchUi.InputDelegate {

    private var _view as EpisodeShowNotesView;

    function initialize(view as EpisodeShowNotesView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_DOWN) {
            _view.scroll(2);
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            _view.scroll(-2);
            return true;
        }
        if (key == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var direction = evt.getDirection();
        if (direction == WatchUi.SWIPE_UP) {
            _view.scroll(2);
            return true;
        }
        if (direction == WatchUi.SWIPE_DOWN) {
            _view.scroll(-2);
            return true;
        }
        if (direction == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }
}
