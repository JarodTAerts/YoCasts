import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Graphics;

//! Subscribed Podcasts list view.
//! Shows all podcasts the user is subscribed to via PocketCasts.
//! Selecting a podcast navigates to its episode list.
class SubscribedView extends WatchUi.Menu2 {

    private var _service as IPodcastService;

    function initialize(service as IPodcastService) {
        Menu2.initialize({:title => "Podcasts"});
        _service = service;
        loadPodcasts();
    }

    private function loadPodcasts() as Void {
        var podcasts = _service.getSubscribedPodcasts();

        if (podcasts.size() == 0) {
            var sub = _service.isDataReady() ? "Sync from phone" : "Loading...";
            addItem(new WatchUi.MenuItem(
                _service.isDataReady() ? "No subscriptions" : "Loading...",
                sub, :empty, {}));
            return;
        }

        // Cap at 30 podcasts per memory budget
        var limit = podcasts.size() < 30 ? podcasts.size() : 30;
        for (var i = 0; i < limit; i++) {
            var pod = podcasts[i] as Dictionary;
            var title = pod[DataKeys.P_TITLE] as String;
            var author = pod[DataKeys.P_AUTHOR] as String;
            var uuid = pod[DataKeys.P_UUID] as String;

            var artColorVal = pod.get(DataKeys.P_ART_COLOR);
            var artTintVal = pod.get(DataKeys.P_ART_TINT);
            var color = (artColorVal != null && artColorVal instanceof Number) ? (artColorVal as Number) : 0x333333;
            var tint = (artTintVal != null && artTintVal instanceof Number) ? (artTintVal as Number) : 0xFFFFFF;
            addItem(new PodcastMenuItem(uuid, title, author, color, tint));
        }
    }
}

//! Handles selection in the Subscribed Podcasts list.
//! Selecting a podcast pushes the EpisodeListView for that podcast.
class SubscribedDelegate extends WatchUi.Menu2InputDelegate {

    private var _service as IPodcastService;

    function initialize(service as IPodcastService) {
        Menu2InputDelegate.initialize();
        _service = service;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :empty) {
            return;
        }

        var podcastUuid = id as String;
        var podcastTitle = item.getLabel();

        var episodeView = new EpisodeListView(_service, podcastUuid, podcastTitle);
        WatchUi.pushView(episodeView,
                         new EpisodeListDelegate(_service, podcastUuid),
                         WatchUi.SLIDE_UP);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

//! Custom menu item with podcast brand color background tint
//! and colored initial circle for visual identity.
class PodcastMenuItem extends WatchUi.CustomMenuItem {

    private var _title as String;
    private var _author as String;
    private var _brandColor as Number;
    private var _tintColor as Number;

    function initialize(id as String, title as String, author as String, brandColor as Number, tintColor as Number) {
        CustomMenuItem.initialize(id, {});
        setLabel(title);
        _title = title;
        _author = author;
        _brandColor = brandColor;
        _tintColor = tintColor;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Dimmed brand color background — brighter when focused
        var factor = isFocused() ? 0.35 : 0.20;
        var bgColor = DataFormat.dimColor(_brandColor, factor);
        dc.setColor(Graphics.COLOR_WHITE, bgColor);
        dc.clear();

        // Brand-colored initial circle
        var iconCX = 26;
        var iconCY = h / 2;
        dc.setColor(_brandColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(iconCX, iconCY, 15);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var initial = _title.substring(0, 1);
        if (initial != null) {
            dc.drawText(iconCX, iconCY - dc.getFontHeight(Graphics.FONT_XTINY) / 2,
                        Graphics.FONT_XTINY, initial as String,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Title and author — vertically centered to the right of icon
        var textX = 50;
        var maxTextW = w - textX - 8;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var authorH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = (h - titleH - 2 - authorH) / 2;

        // Use tint color for title (with contrast check against dimmed bg)
        var titleColor = DataFormat.ensureContrast(_tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, _title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Dimmed tint for author subtitle
        var authorColor = DataFormat.dimColor(_tintColor, 0.65);
        authorColor = DataFormat.ensureContrast(authorColor, bgColor);
        dc.setColor(authorColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, _author, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }
}
