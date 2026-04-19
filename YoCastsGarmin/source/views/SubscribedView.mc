import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Graphics;

//! Subscribed Podcasts list view.
//! Shows all podcasts the user is subscribed to via PocketCasts.
//! Uses CustomMenu so CustomMenuItem.draw() is invoked by the runtime.
//! Selecting a podcast navigates to its episode list.
class SubscribedView extends WatchUi.CustomMenu {

    private var _service as IPodcastService;

    function initialize(service as IPodcastService) {
        CustomMenu.initialize(80, Graphics.COLOR_BLACK, {:titleItemHeight => 50});
        _service = service;
        loadPodcasts();
        System.println("YoCasts: SubscribedView initialized (CustomMenu)");
    }

    //! Draw the "Podcasts" title area — centered for round display
    function drawTitle(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2 - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                    Graphics.FONT_SMALL, "Podcasts", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function loadPodcasts() as Void {
        var podcasts = _service.getSubscribedPodcasts();
        System.println("YoCasts: loadPodcasts() — " + podcasts.size() + " podcasts available");

        if (podcasts.size() == 0) {
            var label = _service.isDataReady() ? "No subscriptions" : "Loading...";
            System.println("YoCasts: loadPodcasts() — empty state: " + label);
            addItem(new EmptyStateMenuItem(label));
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
            System.println("YoCasts: podcast '" + title + "' color=0x" + color.format("%06X") + " tint=0x" + tint.format("%06X"));
            addItem(new PodcastMenuItem(uuid, title, author, color, tint));
        }
        System.println("YoCasts: loadPodcasts() — added " + limit + " PodcastMenuItems to CustomMenu");
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

//! Simple empty-state item for CustomMenu (no custom drawing needed)
class EmptyStateMenuItem extends WatchUi.CustomMenuItem {

    private var _text as String;

    function initialize(text as String) {
        CustomMenuItem.initialize(:empty, {});
        _text = text;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(w / 2, h / 2 - dc.getFontHeight(Graphics.FONT_TINY) / 2,
                    Graphics.FONT_TINY, _text, Graphics.TEXT_JUSTIFY_CENTER);
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

        // AMOLED black surround
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Rounded pill layout
        var marginX = isFocused() ? 12 : 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        // Brand-tinted rounded rect background
        var boosted = DataFormat.brightenColor(_brandColor, 80);
        var factor = isFocused() ? 0.60 : 0.35;
        var bgColor = DataFormat.dimColor(boosted, factor);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, marginY, itemW, itemH, radius);

        // Subtle focus border
        if (isFocused()) {
            var borderColor = DataFormat.brightenColor(_brandColor, 160);
            dc.setColor(borderColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(marginX, marginY, itemW, itemH, radius);
        }

        // Polished initial circle — large, with ring border
        // TODO: Future work — load actual cover art via Communications.makeImageRequest()
        // using DataKeys.P_ART_URL. For now, show a styled initial circle.
        var iconCX = marginX + 32;
        var iconCY = h / 2;
        var circleR = 20;
        var circleColor = DataFormat.brightenColor(_brandColor, 140);
        dc.setColor(circleColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(iconCX, iconCY, circleR);
        // Outer ring for polish
        dc.setColor(DataFormat.brightenColor(_brandColor, 200), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(iconCX, iconCY, circleR);
        // Initial letter
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var initial = _title.substring(0, 1);
        if (initial != null) {
            dc.drawText(iconCX, iconCY - dc.getFontHeight(Graphics.FONT_TINY) / 2,
                        Graphics.FONT_TINY, initial as String,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Title and author — positioned within the rounded rect
        var textX = iconCX + circleR + 10;
        var maxTextW = (marginX + itemW) - textX - 12;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var authorH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = (h - titleH - 2 - authorH) / 2;

        var titleColor = DataFormat.ensureContrast(_tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, _title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        var authorColor = DataFormat.dimColor(_tintColor, 0.65);
        authorColor = DataFormat.ensureContrast(authorColor, bgColor);
        dc.setColor(authorColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, _author, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }
}
