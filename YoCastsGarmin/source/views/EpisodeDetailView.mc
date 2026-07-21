import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Compact episode summary. Long-form show notes live on a separate page so
//! playback state and actions remain readable at a glance.
class EpisodeDetailView extends WatchUi.View {

    private const CX = 195;
    private const PODCAST_Y = 29;
    private const TITLE_Y = 60;
    private const META_Y = 111;
    private const PROGRESS_Y = 139;
    private const PROGRESS_W = 246;
    private const TIME_Y = 159;
    private const STATUS_Y = 185;
    private const NOTES_Y = 229;
    private const NOTES_X = 58;
    private const NOTES_W = 274;
    private const NOTES_H = 54;
    private const PLAY_BTN_CX = 135;
    private const DOWNLOAD_BTN_CX = 255;
    private const BTN_Y = 316;
    private const BTN_R = 31;

    private var _episode as Dictionary;
    private var _service as IPodcastService;
    private var _brandColor as Number = 0x55AAFF;
    private var _brandTint as Number = 0xFFFFFF;

    function initialize(episode as Dictionary, service as IPodcastService) {
        View.initialize();
        _episode = episode;
        _service = service;
        _loadBrandColors();
    }

    function onShow() as Void {
        var uuid = _stringValue(_episode.get(DataKeys.E_UUID), "");
        System.println(
            "YoCasts: EpisodeDetailView onShow uuid=" + uuid
        );
        if (uuid.length() > 0) {
            _service.requestEpisodeDetails(uuid);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        _refreshDetails();

        var background = DataFormat.dimColor(
            DataFormat.brightenColor(_brandColor, 40),
            0.08
        );
        dc.setColor(background, background);
        dc.clear();

        var title = _stringValue(
            _episode.get(DataKeys.E_TITLE),
            "Episode"
        );
        var podcastTitle = _stringValue(
            _episode.get(DataKeys.E_PODCAST_TITLE),
            ""
        );
        var duration = _numberValue(
            _episode.get(DataKeys.E_DURATION),
            0
        );
        var playedUpTo = _numberValue(
            _episode.get(DataKeys.E_PLAYED_UP_TO),
            0
        );
        var status = _numberValue(
            _episode.get(DataKeys.E_PLAYING_STATUS),
            DataKeys.STATUS_NOT_PLAYED
        );
        var uuid = _stringValue(_episode.get(DataKeys.E_UUID), "");

        dc.setColor(
            DataFormat.brightenColor(_brandTint, 180),
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            CX,
            PODCAST_Y,
            Graphics.FONT_XTINY,
            DataFormat.truncateText(
                dc,
                podcastTitle,
                Graphics.FONT_XTINY,
                190
            ),
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );

        _drawEpisodeTitle(dc, title);
        _drawProgress(dc, duration, playedUpTo, status);
        _drawDownloadStatus(dc, uuid);
        _drawShowNotesButton(dc);
        _drawActions(dc, uuid);
    }

    function getEpisode() as Dictionary {
        return _episode;
    }

    function openShowNotes() as Void {
        var view = new EpisodeShowNotesView(_episode, _service);
        WatchUi.pushView(
            view,
            new EpisodeShowNotesDelegate(view),
            WatchUi.SLIDE_UP
        );
    }

    private function _refreshDetails() as Void {
        var uuid = _stringValue(_episode.get(DataKeys.E_UUID), "");
        var details = _service.getEpisodeDetails(uuid);
        if (details != null) {
            _episode = details as Dictionary;
        }
    }

    private function _loadBrandColors() as Void {
        var podcastUuid = _stringValue(
            _episode.get(DataKeys.E_PODCAST_UUID),
            ""
        );
        var podcasts = CacheManager.loadPodcasts();
        if (podcasts != null && podcastUuid.length() > 0) {
            var colors = DataFormat.lookupPodcastColors(
                podcasts as Array<Dictionary>,
                podcastUuid
            );
            _brandColor = colors[0] as Number;
            _brandTint = colors[1] as Number;
        }
    }

    private function _drawEpisodeTitle(dc as Graphics.Dc,
                                       title as String) as Void {
        var font = Graphics.FONT_TINY;
        var maxWidth = 280;
        var lines = DataFormat.wrapText(
            dc,
            title,
            font,
            maxWidth,
            2
        );
        dc.setColor(
            DataFormat.ensureContrast(_brandTint, 0x000000),
            Graphics.COLOR_TRANSPARENT
        );
        if (lines.size() == 0) {
            return;
        }
        if (lines.size() == 1) {
            dc.drawText(
                CX,
                TITLE_Y + 9,
                font,
                lines[0],
                Graphics.TEXT_JUSTIFY_CENTER |
                Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        dc.drawText(
            CX,
            TITLE_Y - 4,
            font,
            lines[0],
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        var secondLine = lines[1];
        if (lines[0].length() + secondLine.length() + 1 <
            title.length()) {
            secondLine = DataFormat.truncateText(
                dc,
                secondLine + "...",
                font,
                maxWidth
            );
        }
        dc.drawText(
            CX,
            TITLE_Y + 19,
            font,
            secondLine,
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    private function _drawProgress(dc as Graphics.Dc,
                                   duration as Number,
                                   playedUpTo as Number,
                                   status as Number) as Void {
        var text = DataFormat.formatDuration(duration);
        if (status == DataKeys.STATUS_COMPLETED) {
            text = "Completed - " + text;
        } else if (status == DataKeys.STATUS_IN_PROGRESS) {
            text = "In progress - " + text;
        } else {
            text += " - New";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            CX,
            META_Y,
            Graphics.FONT_XTINY,
            text,
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );

        var progress = 0.0;
        if (duration > 0 && playedUpTo > 0) {
            progress = playedUpTo.toFloat() / duration.toFloat();
        }
        if (status == DataKeys.STATUS_COMPLETED) {
            progress = 1.0;
        }
        if (progress > 1.0) { progress = 1.0; }

        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(
            CX - PROGRESS_W / 2,
            PROGRESS_Y,
            PROGRESS_W,
            8,
            4
        );
        if (progress > 0.0) {
            dc.setColor(
                DataFormat.brightenColor(_brandColor, 200),
                Graphics.COLOR_TRANSPARENT
            );
            dc.fillRoundedRectangle(
                CX - PROGRESS_W / 2,
                PROGRESS_Y,
                (PROGRESS_W * progress).toNumber(),
                8,
                4
            );
        }

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            CX - PROGRESS_W / 2,
            TIME_Y,
            Graphics.FONT_XTINY,
            DataFormat.formatTime(playedUpTo),
            Graphics.TEXT_JUSTIFY_LEFT |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.drawText(
            CX + PROGRESS_W / 2,
            TIME_Y,
            Graphics.FONT_XTINY,
            DataFormat.formatTime(duration),
            Graphics.TEXT_JUSTIFY_RIGHT |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    private function _drawDownloadStatus(dc as Graphics.Dc,
                                         uuid as String) as Void {
        var app = Application.getApp() as YoCastsApp;
        var status = DownloadQueue.getStatus(uuid);
        var text = "Not downloaded";
        var color = 0x888888;
        if (!app.isNativeMediaAvailable()) {
            text = "Physical watch required";
        } else if (status == DownloadQueue.STATUS_DOWNLOADED) {
            text = "Ready to play";
            color = 0x55FF55;
        } else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            text = "Downloading " + DownloadQueue.getProgress(uuid) + "%";
            color = 0x55AAFF;
        } else if (status == DownloadQueue.STATUS_PENDING) {
            text = "Queued for sync";
            color = 0xFFAA55;
        } else if (status == DownloadQueue.STATUS_FAILED) {
            text = "Download failed - tap retry";
            color = 0xFF5555;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            CX,
            STATUS_Y,
            Graphics.FONT_XTINY,
            DataFormat.truncateText(
                dc,
                text,
                Graphics.FONT_XTINY,
                290
            ),
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    private function _drawShowNotesButton(dc as Graphics.Dc) as Void {
        var top = NOTES_Y - NOTES_H / 2;
        var accent = DataFormat.brightenColor(_brandColor, 180);
        dc.setColor(0x171727, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(
            NOTES_X,
            top,
            NOTES_W,
            NOTES_H,
            16
        );
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(
            NOTES_X,
            top,
            NOTES_W,
            NOTES_H,
            16
        );
        dc.setPenWidth(1);

        dc.drawText(
            NOTES_X + 24,
            NOTES_Y,
            Graphics.FONT_TINY,
            "Show Notes",
            Graphics.TEXT_JUSTIFY_LEFT |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.fillPolygon([
            [NOTES_X + NOTES_W - 29, NOTES_Y - 7],
            [NOTES_X + NOTES_W - 19, NOTES_Y],
            [NOTES_X + NOTES_W - 29, NOTES_Y + 7]
        ]);
    }

    private function _drawActions(dc as Graphics.Dc, uuid as String) as Void {
        var app = Application.getApp() as YoCastsApp;
        var nativeMedia = app.isNativeMediaAvailable();
        var status = DownloadQueue.getStatus(uuid);
        var downloaded = status == DownloadQueue.STATUS_DOWNLOADED &&
                         StorageManager.isEpisodeDownloaded(uuid);
        var accent = DataFormat.brightenColor(_brandColor, 200);
        var playColor = nativeMedia && downloaded ? accent : 0x444444;
        var downloadColor = nativeMedia ? accent : 0x444444;
        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            downloadColor = 0x55FF55;
        } else if (status == DownloadQueue.STATUS_PENDING ||
                   status == DownloadQueue.STATUS_DOWNLOADING) {
            downloadColor = 0xFFAA55;
        } else if (status == DownloadQueue.STATUS_FAILED) {
            downloadColor = 0xFF5555;
        }

        dc.setColor(playColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(PLAY_BTN_CX, BTN_Y, BTN_R);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [PLAY_BTN_CX - 9, BTN_Y - 13],
            [PLAY_BTN_CX - 9, BTN_Y + 13],
            [PLAY_BTN_CX + 13, BTN_Y]
        ]);

        dc.setColor(downloadColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(DOWNLOAD_BTN_CX, BTN_Y, BTN_R);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (downloaded) {
            dc.setPenWidth(3);
            dc.drawLine(
                DOWNLOAD_BTN_CX - 9,
                BTN_Y,
                DOWNLOAD_BTN_CX - 2,
                BTN_Y + 8
            );
            dc.drawLine(
                DOWNLOAD_BTN_CX - 2,
                BTN_Y + 8,
                DOWNLOAD_BTN_CX + 11,
                BTN_Y - 9
            );
            dc.setPenWidth(1);
        } else {
            dc.setPenWidth(2);
            dc.drawLine(
                DOWNLOAD_BTN_CX,
                BTN_Y - 11,
                DOWNLOAD_BTN_CX,
                BTN_Y + 5
            );
            dc.fillPolygon([
                [DOWNLOAD_BTN_CX - 7, BTN_Y + 1],
                [DOWNLOAD_BTN_CX + 7, BTN_Y + 1],
                [DOWNLOAD_BTN_CX, BTN_Y + 11]
            ]);
            dc.setPenWidth(1);
        }

        dc.setColor(playColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            PLAY_BTN_CX,
            BTN_Y + 40,
            Graphics.FONT_XTINY,
            "PLAY",
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(downloadColor, Graphics.COLOR_TRANSPARENT);
        var label = "GET";
        if (!nativeMedia) { label = "DEVICE"; }
        else if (downloaded) { label = "READY"; }
        else if (status == DownloadQueue.STATUS_PENDING) { label = "QUEUED"; }
        else if (status == DownloadQueue.STATUS_DOWNLOADING) {
            label = DownloadQueue.getProgress(uuid) + "%";
        } else if (status == DownloadQueue.STATUS_FAILED) { label = "RETRY"; }
        dc.drawText(
            DOWNLOAD_BTN_CX,
            BTN_Y + 40,
            Graphics.FONT_XTINY,
            label,
            Graphics.TEXT_JUSTIFY_CENTER |
            Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    private function _stringValue(value as Object?,
                                  fallback as String) as String {
        if (value != null && value instanceof String) {
            return value as String;
        }
        return fallback;
    }

    private function _numberValue(value as Object?,
                                  fallback as Number) as Number {
        if (value != null && value instanceof Number) {
            return value as Number;
        }
        return fallback;
    }
}

class EpisodeDetailDelegate extends WatchUi.InputDelegate {

    private var _episode as Dictionary;
    private var _view as EpisodeDetailView?;

    function initialize(episode as Dictionary, service as IPodcastService) {
        InputDelegate.initialize();
        _episode = episode;
    }

    function setView(view as EpisodeDetailView) as Void {
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var point = evt.getCoordinates();
        var x = point[0] as Number;
        var y = point[1] as Number;
        if (y >= 198 && y <= 260 && x >= 48 && x <= 342) {
            _openShowNotes();
            return true;
        }
        if (_insideCircle(x, y, 135, 316, 42)) {
            _play();
            return true;
        }
        if (_insideCircle(x, y, 255, 316, 42)) {
            _download();
            return true;
        }
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_DOWN) {
            _openShowNotes();
            return true;
        }
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            _play();
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
            _openShowNotes();
            return true;
        }
        if (direction == WatchUi.SWIPE_RIGHT) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    private function _currentEpisode() as Dictionary {
        return _view != null
            ? (_view as EpisodeDetailView).getEpisode()
            : _episode;
    }

    private function _openShowNotes() as Void {
        if (_view != null) {
            (_view as EpisodeDetailView).openShowNotes();
        }
    }

    private function _play() as Void {
        var episode = _currentEpisode();
        var uuid = episode[DataKeys.E_UUID] as String;
        if (DownloadQueue.getStatus(uuid) !=
                DownloadQueue.STATUS_DOWNLOADED ||
            !StorageManager.isEpisodeDownloaded(uuid)) {
            _download();
            return;
        }
        (Application.getApp() as YoCastsApp).requestPlayback(uuid);
    }

    private function _download() as Void {
        var app = Application.getApp() as YoCastsApp;
        if (!app.isNativeMediaAvailable()) {
            return;
        }
        var episode = _currentEpisode();
        var uuid = episode[DataKeys.E_UUID] as String;
        var status = DownloadQueue.getStatus(uuid);
        if (status == DownloadQueue.STATUS_DOWNLOADED) {
            app.requestPlayback(uuid);
        } else if (status == DownloadQueue.STATUS_FAILED) {
            DownloadQueue.retry(uuid);
            app.requestMediaSync();
        } else if (status < 0 && DownloadQueue.addToQueue(episode)) {
            app.requestMediaSync();
        }
        WatchUi.requestUpdate();
    }

    private function _insideCircle(x as Number, y as Number,
                                   cx as Number, cy as Number,
                                   radius as Number) as Boolean {
        var dx = x - cx;
        var dy = y - cy;
        return dx * dx + dy * dy <= radius * radius;
    }
}
