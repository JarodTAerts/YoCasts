import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Compact podcast landing page with a scrollable description and a clear
//! route into episodes. This mirrors the hierarchy users expect in a podcast
//! player without forcing long metadata into a list row.
class PodcastDetailView extends WatchUi.View {

    private const CX = 195;
    private const ABOUT_TOP = 164;
    private const ABOUT_BOTTOM = 294;
    private const ACTION_CENTER_Y = 460;
    private const ACTION_RADIUS = 168;

    private var _service as IPodcastService;
    private var _podcast as Dictionary;
    private var _brandColor as Number = 0x55AAFF;
    private var _brandTint as Number = 0xFFFFFF;
    private var _descriptionLines as Array<String> = [] as Array<String>;
    private var _scrollLine as Number = 0;

    function initialize(service as IPodcastService,
                        podcast as Dictionary) {
        View.initialize();
        _service = service;
        _podcast = podcast;
        var color = podcast.get(DataKeys.P_ART_COLOR);
        var tint = podcast.get(DataKeys.P_ART_TINT);
        if (color != null && color instanceof Number) {
            _brandColor = color as Number;
        }
        if (tint != null && tint instanceof Number) {
            _brandTint = tint as Number;
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var background = DataFormat.dimColor(
            DataFormat.brightenColor(_brandColor, 50),
            0.09
        );
        dc.setColor(background, background);
        dc.clear();

        var title = _stringValue(
            _podcast.get(DataKeys.P_TITLE),
            "Podcast"
        );
        var author = _stringValue(
            _podcast.get(DataKeys.P_AUTHOR),
            ""
        );
        var description = _stringValue(
            _podcast.get(DataKeys.P_DESCRIPTION),
            ""
        );

        dc.setColor(
            DataFormat.brightenColor(_brandColor, 200),
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            CX,
            30,
            Graphics.FONT_XTINY,
            "PODCAST",
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(
            DataFormat.ensureContrast(_brandTint, background),
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            CX,
            67,
            Graphics.FONT_SMALL,
            DataFormat.truncateText(
                dc,
                title,
                Graphics.FONT_SMALL,
                280
            ),
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            CX,
            99,
            Graphics.FONT_XTINY,
            DataFormat.truncateText(
                dc,
                author,
                Graphics.FONT_XTINY,
                270
            ),
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.setColor(
            DataFormat.dimColor(
                DataFormat.brightenColor(_brandColor, 150),
                0.55
            ),
            Graphics.COLOR_TRANSPARENT
        );
        dc.fillRectangle(85, 123, 220, 2);
        dc.drawText(
            CX,
            145,
            Graphics.FONT_XTINY,
            "ABOUT",
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );

        if (_descriptionLines.size() == 0) {
            _descriptionLines = DataFormat.wrapText(
                dc,
                description.length() > 0
                    ? description : "No podcast description available.",
                Graphics.FONT_XTINY,
                300,
                40
            );
        }
        _drawDescription(dc);
        _drawEpisodesButton(dc);
    }

    function scrollDescription(delta as Number) as Void {
        var maxScroll = _descriptionLines.size() - 5;
        if (maxScroll < 0) { maxScroll = 0; }
        _scrollLine += delta;
        if (_scrollLine < 0) { _scrollLine = 0; }
        if (_scrollLine > maxScroll) { _scrollLine = maxScroll; }
        WatchUi.requestUpdate();
    }

    function openEpisodes() as Void {
        var uuid = _podcast[DataKeys.P_UUID] as String;
        var title = _podcast[DataKeys.P_TITLE] as String;
        var episodeView = new EpisodeListView(_service, uuid, title);
        WatchUi.pushView(
            episodeView,
            new EpisodeListDelegate(episodeView, _service, uuid),
            WatchUi.SLIDE_UP
        );
    }

    private function _drawDescription(dc as Graphics.Dc) as Void {
        var lineHeight = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        var visible = (ABOUT_BOTTOM - ABOUT_TOP) / lineHeight;
        dc.setClip(38, ABOUT_TOP, 314, ABOUT_BOTTOM - ABOUT_TOP);
        dc.setColor(0xDDDDDD, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < visible; i++) {
            var index = _scrollLine + i;
            if (index >= _descriptionLines.size()) { break; }
            dc.drawText(
                48,
                ABOUT_TOP + i * lineHeight,
                Graphics.FONT_XTINY,
                _descriptionLines[index],
                Graphics.TEXT_JUSTIFY_LEFT
            );
        }
        dc.clearClip();

        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (_scrollLine > 0) {
            dc.fillPolygon([[350, 170], [360, 170], [355, 163]]);
        }
        if (_scrollLine + visible < _descriptionLines.size()) {
            dc.fillPolygon([[350, 264], [360, 264], [355, 271]]);
        }
    }

    private function _drawEpisodesButton(dc as Graphics.Dc) as Void {
        var color = DataFormat.brightenColor(_brandColor, 180);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(CX, ACTION_CENTER_Y, ACTION_RADIUS);
        dc.setColor(
            DataFormat.brightenColor(_brandColor, 230),
            Graphics.COLOR_TRANSPARENT
        );
        dc.setPenWidth(2);
        dc.drawCircle(CX, ACTION_CENTER_Y, ACTION_RADIUS);
        dc.setPenWidth(1);
        dc.setColor(
            DataFormat.ensureContrast(_brandTint, color),
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            CX,
            344,
            Graphics.FONT_TINY,
            "Browse Episodes",
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.fillPolygon([
            [CX - 7, 365],
            [CX + 7, 365],
            [CX, 374]
        ]);
    }

    private function _stringValue(value as Object?,
                                  fallback as String) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return fallback;
    }
}

class PodcastDetailDelegate extends WatchUi.InputDelegate {

    private var _view as PodcastDetailView;

    function initialize(view as PodcastDetailView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var point = evt.getCoordinates();
        var x = point[0] as Number;
        var y = point[1] as Number;
        var dx = x - 195;
        var dy = y - 460;
        if (dx * dx + dy * dy <= 168 * 168) {
            _view.openEpisodes();
            return true;
        }
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            _view.scrollDescription(-2);
            return true;
        }
        if (key == WatchUi.KEY_DOWN) {
            _view.scrollDescription(2);
            return true;
        }
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            _view.openEpisodes();
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
            _view.scrollDescription(2);
            return true;
        }
        if (direction == WatchUi.SWIPE_DOWN) {
            _view.scrollDescription(-2);
            return true;
        }
        if (direction == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }
}
