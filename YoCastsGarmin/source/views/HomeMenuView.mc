import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;
import Toybox.Math;

//! Home menu (v3.0) — CustomMenu rewrite for native smooth scrolling.
//! Menu items: Queue, Podcasts, Downloads, Settings (80px pills).
//! Now Playing: compact card as last item, tap to open full NowPlayingView.
//! Title: "YoCasts" drawn via drawTitle().
class HomeMenuView extends WatchUi.CustomMenu {

    private var _service as IPodcastService;
    private var _refreshTimer as Timer.Timer? = null;

    function initialize(service as IPodcastService) {
        CustomMenu.initialize(80, Graphics.COLOR_BLACK, {:titleItemHeight => 50});
        _service = service;

        addItem(new HomeMenuItem(:queue, "Queue", service));
        addItem(new HomeMenuItem(:podcasts, "Podcasts", service));
        addItem(new HomeMenuItem(:downloads, "Downloads", service));
        addItem(new HomeMenuItem(:settings, "Settings", null));
        addItem(new NowPlayingMenuItem());

        System.println("YoCasts: HomeMenuView initialized (CustomMenu v3)");
    }

    //! Draw the "YoCasts" branded title area
    function drawTitle(dc as Graphics.Dc) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(dc.getWidth() / 2,
                     dc.getHeight() / 2 - dc.getFontHeight(Graphics.FONT_MEDIUM) / 2,
                     Graphics.FONT_MEDIUM, "YoCasts", Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Start periodic refresh for Now Playing progress updates
    function onShow() as Void {
        if (_refreshTimer == null) {
            _refreshTimer = new Timer.Timer();
        }
        (_refreshTimer as Timer.Timer).start(method(:onRefreshTick), 1000, true);
    }

    function onHide() as Void {
        if (_refreshTimer != null) {
            (_refreshTimer as Timer.Timer).stop();
        }
    }

    //! Refresh timer — redraws to update Now Playing progress
    function onRefreshTick() as Void {
        WatchUi.requestUpdate();
    }

    function getService() as IPodcastService {
        return _service;
    }
}

// ============================================================================
// HomeMenuItem — pill-style custom menu item for navigation entries
// ============================================================================

//! Renders a rounded pill with icon, title, and optional dynamic subtitle.
//! Used for Queue, Podcasts, Downloads, and Settings items.
class HomeMenuItem extends WatchUi.CustomMenuItem {

    private var _title as String;
    private var _service as IPodcastService?;

    function initialize(id as Symbol, title as String, service as IPodcastService?) {
        CustomMenuItem.initialize(id, {});
        setLabel(title);
        _title = title;
        _service = service;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Pill background — expands when focused
        var marginX = isFocused() ? 12 : 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        var bgColor = isFocused() ? 0x2A2A4E : 0x1A1A2E;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, marginY, itemW, itemH, radius);

        // Accent border when focused
        if (isFocused()) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(marginX, marginY, itemW, itemH, radius);
            dc.setPenWidth(1);
        }

        // Icon area
        var iconX = marginX + 16;
        drawIcon(dc, iconX, h / 2 - 12);

        // Text area
        var textX = marginX + 48;
        var maxTextW = (marginX + itemW) - textX - 12;
        var subtitle = getSubtitle();

        if (subtitle != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, h / 2 - 20, Graphics.FONT_SMALL,
                        DataFormat.truncateText(dc, _title, Graphics.FONT_SMALL, maxTextW),
                        Graphics.TEXT_JUSTIFY_LEFT);

            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, h / 2 + 4, Graphics.FONT_XTINY,
                        DataFormat.truncateText(dc, subtitle as String, Graphics.FONT_XTINY, maxTextW),
                        Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, h / 2 - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                        Graphics.FONT_SMALL, _title, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Build dynamic subtitle string based on item type
    private function getSubtitle() as String? {
        if (_service == null) { return null; }
        var svc = _service as IPodcastService;
        var id = getId();
        if (id == :queue) {
            var count = svc.getQueue().size();
            return count.toString() + (count == 1 ? " episode" : " episodes");
        } else if (id == :podcasts) {
            var count = svc.getSubscribedPodcasts().size();
            return count.toString() + (count == 1 ? " subscription" : " subscriptions");
        } else if (id == :downloads) {
            var count = DownloadQueue.getDownloadCount();
            return count.toString() + (count == 1 ? " episode" : " episodes");
        }
        return null;
    }

    //! Draw the appropriate icon based on item ID
    private function drawIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        var id = getId();
        if (id == :queue) {
            drawMusicNote(dc, x, y);
        } else if (id == :podcasts) {
            drawHeadphones(dc, x, y);
        } else if (id == :downloads) {
            drawDownloadIcon(dc, x, y);
        } else if (id == :settings) {
            drawGearIcon(dc, x, y);
        }
    }

    // --- Icon Drawing Helpers (same visual spec as v2) ---

    private function drawMusicNote(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.fillCircle(x, y + 14, 5);
        dc.setPenWidth(2);
        dc.drawLine(x + 5, y + 14, x + 5, y);
        dc.drawLine(x + 5, y, x + 10, y + 4);
        dc.setPenWidth(1);
    }

    private function drawHeadphones(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setPenWidth(2);
        dc.drawArc(x + 8, y + 12, 10, Graphics.ARC_CLOCKWISE, 190, 350);
        dc.fillRoundedRectangle(x - 3, y + 10, 6, 12, 2);
        dc.fillRoundedRectangle(x + 13, y + 10, 6, 12, 2);
        dc.setPenWidth(1);
    }

    private function drawDownloadIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setPenWidth(2);
        dc.drawLine(x + 8, y, x + 8, y + 14);
        dc.setPenWidth(1);
        dc.fillPolygon([[x + 2, y + 10], [x + 14, y + 10], [x + 8, y + 18]]);
        dc.setPenWidth(2);
        dc.drawLine(x, y + 18, x, y + 24);
        dc.drawLine(x, y + 24, x + 16, y + 24);
        dc.drawLine(x + 16, y + 24, x + 16, y + 18);
        dc.setPenWidth(1);
    }

    private function drawGearIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var iconCx = x + 11;
        var iconCy = y + 11;
        dc.fillCircle(iconCx, iconCy, 11);
        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(iconCx, iconCy, 5);
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 6; i++) {
            var angle = i * 60.0 * Math.PI / 180.0;
            var tx = iconCx + (11.0 * Math.cos(angle)).toNumber() - 2;
            var ty = iconCy - (11.0 * Math.sin(angle)).toNumber() - 2;
            dc.fillRectangle(tx, ty, 4, 4);
        }
    }
}

// ============================================================================
// NowPlayingMenuItem — compact playback card at bottom of menu
// ============================================================================

//! Shows current playback state as a compact card.
//! Reads from PlaybackState module (singleton) for live data.
//! Tapping navigates to full NowPlayingView.
class NowPlayingMenuItem extends WatchUi.CustomMenuItem {

    function initialize() {
        CustomMenuItem.initialize(:nowPlaying, {});
        setLabel("Now Playing");
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Pill background with blue tint to distinguish from nav items
        var marginX = isFocused() ? 12 : 20;
        var marginY = 4;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        var bgColor = isFocused() ? 0x0D2844 : 0x0A1A2E;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, marginY, itemW, itemH, radius);

        if (isFocused()) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(marginX, marginY, itemW, itemH, radius);
            dc.setPenWidth(1);
        }

        if (!PlaybackState.hasActivePlayback()) {
            dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - dc.getFontHeight(Graphics.FONT_XTINY) / 2,
                        Graphics.FONT_XTINY, "No episode playing",
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Play/pause icon on the left
        var iconCX = marginX + 24;
        var iconCY = h / 2;
        drawPlayPauseIcon(dc, iconCX, iconCY);

        // Text content to the right of icon
        var textX = marginX + 48;
        var maxTextW = (marginX + itemW) - textX - 12;

        // Episode title (white, prominent)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, h / 2 - 20, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, PlaybackState.currentTitle, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Podcast name + time (gray, secondary)
        var position = PlaybackState.getEstimatedPosition();
        var duration = PlaybackState.currentDuration;
        var subText = PlaybackState.currentPodcastTitle;
        if (duration > 0) {
            subText = subText + " · " + DataFormat.formatTime(position);
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, h / 2 + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, subText, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Mini progress bar under text
        var barX = textX;
        var barW = maxTextW;
        var barH = 2;
        var barY = h / 2 + 24;
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, barW, barH, 1);

        if (duration > 0 && position > 0) {
            var progress = position.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var fillW = (barW * progress).toNumber();
            if (fillW > 0) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(barX, barY, fillW, barH, 1);
            }
        }
    }

    private function drawPlayPauseIcon(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (PlaybackState.isPlaying) {
            dc.fillRectangle(cx - 7, cy - 6, 4, 12);
            dc.fillRectangle(cx + 3, cy - 6, 4, 12);
        } else {
            dc.fillPolygon([[cx - 5, cy - 6], [cx - 5, cy + 6], [cx + 7, cy]]);
        }
    }
}

// ============================================================================
// HomeMenuDelegate — Menu2InputDelegate for CustomMenu item selection
// ============================================================================

//! Routes item selection to the appropriate sub-view.
//! Replaces the old InputDelegate with coordinate-based hit testing.
class HomeMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as HomeMenuView;
    private var _service as IPodcastService;

    function initialize(view as HomeMenuView, service as IPodcastService) {
        Menu2InputDelegate.initialize();
        _view = view;
        _service = service;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :queue) {
            System.println("YoCasts: HomeMenu → Queue");
            var queueView = new QueueView(_service);
            WatchUi.pushView(queueView, new QueueDelegate(_service), WatchUi.SLIDE_UP);
        } else if (id == :podcasts) {
            System.println("YoCasts: HomeMenu → Podcasts");
            var podView = new SubscribedView(_service);
            WatchUi.pushView(podView, new SubscribedDelegate(_service), WatchUi.SLIDE_UP);
        } else if (id == :downloads) {
            System.println("YoCasts: HomeMenu → Downloads");
            var dlView = new DownloadsView();
            WatchUi.pushView(dlView, new DownloadsDelegate(dlView), WatchUi.SLIDE_UP);
        } else if (id == :settings) {
            System.println("YoCasts: HomeMenu → Settings");
            var settingsView = new SettingsView();
            WatchUi.pushView(settingsView, new SettingsDelegate(settingsView), WatchUi.SLIDE_UP);
        } else if (id == :nowPlaying) {
            System.println("YoCasts: HomeMenu → Now Playing");
            navigateToNowPlaying();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    private function navigateToNowPlaying() as Void {
        if (!PlaybackState.hasActivePlayback()) { return; }
        var ep = _service.getNowPlaying();
        if (ep != null) {
            var npView = new NowPlayingView(ep);
            var npDelegate = new NowPlayingDelegate(ep);
            npDelegate.setView(npView);
            WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
        }
    }
}
