import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;
import Toybox.Math;

// ============================================================================
// Home menu (v4.0) — Custom View with manual scroll + fixed Now Playing dock.
// ============================================================================
// CustomMenu limitations (no onUpdate override, no Layer API, scrollable footer)
// prevent a fixed dock. This View gives full layout control:
//   - Top zone: "YoCasts" title
//   - Middle zone: scrollable list of 4 nav items (pill style)
//   - Bottom zone: fixed Now Playing dock (always visible)

class HomeMenuView extends WatchUi.View {

    private var _service as IPodcastService;
    private var _refreshTimer as Timer.Timer? = null;

    // Menu items
    private var _items as Array<Dictionary>;
    private var _focusIndex as Number = 0;
    private var _scrollOffset as Number = 0;  // pixels scrolled up

    // Layout constants
    private const TITLE_H = 70;
    private const ITEM_H = 70;
    private const DOCK_H = 80;
    private const ITEM_COUNT = 4;

    function initialize(service as IPodcastService) {
        View.initialize();
        _service = service;
        _items = [
            { "id" => :queue,     "title" => "Queue" },
            { "id" => :podcasts,  "title" => "Podcasts" },
            { "id" => :downloads, "title" => "Downloads" },
            { "id" => :settings,  "title" => "Settings" }
        ] as Array<Dictionary>;
        System.println("YoCasts: HomeMenuView initialized (View v4.0)");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var dockY = h - DOCK_H;

        // Black background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // --- Title area (scrolls with items) ---
        var titleY = -_scrollOffset;
        if (titleY + TITLE_H > 0) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            var titleFH = dc.getFontHeight(Graphics.FONT_MEDIUM);
            dc.drawText(w / 2, titleY + TITLE_H - titleFH - 2,
                         Graphics.FONT_MEDIUM, "YoCasts", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // --- Menu items (scroll, clipped above dock) ---
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _items.size(); i++) {
            var itemY = itemsStartY + i * ITEM_H;
            // Skip items fully above or below visible area
            if (itemY + ITEM_H < 0 || itemY >= dockY) { continue; }
            var focused = (i == _focusIndex);
            drawMenuItem(dc, _items[i], itemY, ITEM_H, w, focused);
        }

        // --- Now Playing dock (fixed at bottom, drawn last) ---
        drawNowPlayingDock(dc, dockY, DOCK_H, w);
    }

    //! Draw a single menu item pill
    private function drawMenuItem(dc as Graphics.Dc, item as Dictionary,
                                   y as Number, h as Number, w as Number,
                                   focused as Boolean) as Void {
        var marginX = focused ? 12 : 20;
        var marginY = 3;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 14;

        var bgColor = focused ? 0x2A2A4E : 0x1A1A2E;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, y + marginY, itemW, itemH, radius);

        if (focused) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(marginX, y + marginY, itemW, itemH, radius);
            dc.setPenWidth(1);
        }

        // Icon
        var iconX = marginX + 16;
        var iconCY = y + h / 2;
        drawIcon(dc, item["id"] as Symbol, iconX, iconCY - 12);

        // Title + subtitle
        var textX = marginX + 48;
        var maxTextW = (marginX + itemW) - textX - 12;
        var title = item["title"] as String;
        var subtitle = getSubtitle(item["id"] as Symbol);

        if (subtitle != null) {
            var titleFH = dc.getFontHeight(Graphics.FONT_SMALL);
            var subFH = dc.getFontHeight(Graphics.FONT_XTINY);
            var totalTextH = titleFH + 2 + subFH;
            var topY = y + (h - totalTextH) / 2;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, topY, Graphics.FONT_SMALL,
                        DataFormat.truncateText(dc, title, Graphics.FONT_SMALL, maxTextW),
                        Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, topY + titleFH + 2, Graphics.FONT_XTINY,
                        DataFormat.truncateText(dc, subtitle as String, Graphics.FONT_XTINY, maxTextW),
                        Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, iconCY - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                        Graphics.FONT_SMALL, title, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Draw the fixed Now Playing dock at the bottom
    private function drawNowPlayingDock(dc as Graphics.Dc, y as Number,
                                         h as Number, w as Number) as Void {
        // Dark background
        dc.setColor(0x0A0A14, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, y, w, h);

        // Separator
        dc.setColor(0x333344, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(40, y, w - 40, y);

        var cx = w / 2;
        var cy = y + h / 2;

        if (!PlaybackState.hasActivePlayback()) {
            // Idle — play triangle + label
            dc.setColor(0x333355, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx - 6, cy - 8], [cx - 6, cy + 8], [cx + 6, cy]]);
            dc.setColor(0x555577, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 12, Graphics.FONT_XTINY,
                        "Now Playing", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Active playback
        var iconCX = 50;
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (PlaybackState.isPlaying) {
            dc.fillRectangle(iconCX - 6, cy - 7, 4, 14);
            dc.fillRectangle(iconCX + 2, cy - 7, 4, 14);
        } else {
            dc.fillPolygon([[iconCX - 5, cy - 7], [iconCX - 5, cy + 7], [iconCX + 7, cy]]);
        }

        var textX = 70;
        var maxTextW = w - textX - 20;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + 10, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, PlaybackState.currentTitle, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        var position = PlaybackState.getEstimatedPosition();
        var duration = PlaybackState.currentDuration;
        var subText = PlaybackState.currentPodcastTitle;
        if (duration > 0) {
            subText = subText + " · " + DataFormat.formatTime(position);
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, y + 30, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, subText, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Mini progress bar
        var barY = y + 52;
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(textX, barY, maxTextW, 3, 1);
        if (duration > 0 && position > 0) {
            var progress = position.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var fillW = (maxTextW * progress).toNumber();
            if (fillW > 0) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(textX, barY, fillW, 3, 1);
            }
        }
    }

    //! Build subtitle for a menu item
    private function getSubtitle(id as Symbol) as String? {
        if (id == :queue) {
            var count = _service.getQueue().size();
            return count.toString() + (count == 1 ? " episode" : " episodes");
        } else if (id == :podcasts) {
            var count = _service.getSubscribedPodcasts().size();
            return count.toString() + (count == 1 ? " subscription" : " subscriptions");
        } else if (id == :downloads) {
            var count = DownloadQueue.getDownloadCount();
            return count.toString() + (count == 1 ? " episode" : " episodes");
        }
        return null;
    }

    //! Draw icon for the given item ID
    private function drawIcon(dc as Graphics.Dc, id as Symbol, x as Number, y as Number) as Void {
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (id == :queue) {
            // Music note
            dc.fillCircle(x, y + 14, 5);
            dc.setPenWidth(2);
            dc.drawLine(x + 5, y + 14, x + 5, y);
            dc.drawLine(x + 5, y, x + 10, y + 4);
            dc.setPenWidth(1);
        } else if (id == :podcasts) {
            // Headphones
            dc.setPenWidth(2);
            dc.drawArc(x + 8, y + 12, 10, Graphics.ARC_CLOCKWISE, 190, 350);
            dc.fillRoundedRectangle(x - 3, y + 10, 6, 12, 2);
            dc.fillRoundedRectangle(x + 13, y + 10, 6, 12, 2);
            dc.setPenWidth(1);
        } else if (id == :downloads) {
            // Download arrow
            dc.setPenWidth(2);
            dc.drawLine(x + 8, y, x + 8, y + 14);
            dc.setPenWidth(1);
            dc.fillPolygon([[x + 2, y + 10], [x + 14, y + 10], [x + 8, y + 18]]);
            dc.setPenWidth(2);
            dc.drawLine(x, y + 18, x, y + 24);
            dc.drawLine(x, y + 24, x + 16, y + 24);
            dc.drawLine(x + 16, y + 24, x + 16, y + 18);
            dc.setPenWidth(1);
        } else if (id == :settings) {
            // Gear
            var cx = x + 11;
            var cy = y + 11;
            dc.fillCircle(cx, cy, 11);
            dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 5);
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < 6; i++) {
                var angle = i * 60.0 * Math.PI / 180.0;
                var tx = cx + (11.0 * Math.cos(angle)).toNumber() - 2;
                var ty = cy - (11.0 * Math.sin(angle)).toNumber() - 2;
                dc.fillRectangle(tx, ty, 4, 4);
            }
        }
    }

    // --- Focus management (called by delegate) ---

    function moveFocus(delta as Number) as Void {
        _focusIndex = _focusIndex + delta;
        if (_focusIndex < 0) { _focusIndex = _items.size() - 1; }
        if (_focusIndex >= _items.size()) { _focusIndex = 0; }
        ensureFocusVisible();
        WatchUi.requestUpdate();
    }

    //! Adjust scroll so the focused item is fully visible between title and dock
    private function ensureFocusVisible() as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var dockY = screenH - DOCK_H;

        // Item's absolute position (before scroll)
        var itemAbsTop = TITLE_H + _focusIndex * ITEM_H;
        var itemAbsBottom = itemAbsTop + ITEM_H;

        // Ensure bottom of focused item is above dock
        if (itemAbsBottom - _scrollOffset > dockY) {
            _scrollOffset = itemAbsBottom - dockY;
        }
        // Ensure top of focused item is below screen top (with some title room)
        if (itemAbsTop - _scrollOffset < 30) {
            _scrollOffset = itemAbsTop - 30;
        }
        // Don't scroll negative
        if (_scrollOffset < 0) { _scrollOffset = 0; }
    }

    function getSelectedId() as Symbol {
        return _items[_focusIndex]["id"] as Symbol;
    }

    function getFocusIndex() as Number {
        return _focusIndex;
    }

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

    function onRefreshTick() as Void {
        WatchUi.requestUpdate();
    }

    function getService() as IPodcastService {
        return _service;
    }

    //! Get Y coordinate where dock starts (for tap detection)
    function getDockY() as Number {
        return System.getDeviceSettings().screenHeight - DOCK_H;
    }

    //! Hit-test: which item index is at screen Y? Returns -1 if none.
    function itemIndexAtY(y as Number) as Number {
        var itemsStartY = TITLE_H;
        for (var i = 0; i < _items.size(); i++) {
            var top = itemsStartY + i * ITEM_H;
            if (y >= top && y < top + ITEM_H) {
                return i;
            }
        }
        return -1;
    }
}

// ============================================================================
// HomeMenuDelegate — handles scroll, tap, and key input for the custom View
// ============================================================================

class HomeMenuDelegate extends WatchUi.BehaviorDelegate {

    private var _view as HomeMenuView;
    private var _service as IPodcastService;

    function initialize(view as HomeMenuView, service as IPodcastService) {
        BehaviorDelegate.initialize();
        _view = view;
        _service = service;
    }

    //! Up/down scrolling via buttons or crown
    function onNextPage() as Boolean {
        _view.moveFocus(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.moveFocus(-1);
        return true;
    }

    //! Select focused item via tap or button press
    function onSelect() as Boolean {
        var id = _view.getSelectedId();
        System.println("YoCasts: HomeMenu select — id=" + id);
        navigateTo(id);
        return true;
    }

    //! Handle screen tap — tap on item or dock
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var y = coords[1];

        // Dock area tap
        if (y >= _view.getDockY()) {
            System.println("YoCasts: HomeMenu dock tapped");
            navigateToNowPlaying();
            return true;
        }

        // Item area tap
        var idx = _view.itemIndexAtY(y);
        if (idx >= 0) {
            _view.moveFocus(0); // no-op but could set focus
            var items = [":queue", ":podcasts", ":downloads", ":settings"];
            System.println("YoCasts: HomeMenu tap on item " + idx);
            if (idx == 0) { navigateTo(:queue); }
            else if (idx == 1) { navigateTo(:podcasts); }
            else if (idx == 2) { navigateTo(:downloads); }
            else if (idx == 3) { navigateTo(:settings); }
            return true;
        }

        return false;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    private function navigateTo(id as Symbol) as Void {
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
        }
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
