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
    private var _scrollOffset as Number = 0;  // pixels scrolled up

    // Layout constants
    private const TITLE_H = 60;
    private const ITEM_H = 80;
    private const DOCK_H = 110;
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
        dc.setClip(0, 0, w, dockY);
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _items.size(); i++) {
            var itemY = itemsStartY + i * ITEM_H;
            if (itemY + ITEM_H < 0 || itemY >= dockY) { continue; }
            drawMenuItem(dc, _items[i], itemY, ITEM_H, w);
        }
        dc.clearClip();

        // --- Now Playing dock (fixed at bottom, drawn last) ---
        drawNowPlayingDock(dc, dockY, DOCK_H, w);
    }

    //! Draw a single menu item pill
    private function drawMenuItem(dc as Graphics.Dc, item as Dictionary,
                                   y as Number, h as Number, w as Number) as Void {
        var marginX = 20;
        var marginY = 5;
        var itemW = w - 2 * marginX;
        var itemH = h - 2 * marginY;
        var radius = 16;

        dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(marginX, y + marginY, itemW, itemH, radius);

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
        var screenH = System.getDeviceSettings().screenHeight;
        var cx = w / 2;
        var r = w / 2;  // radius for round display

        // Dark background for dock area
        dc.setColor(0x0A0A14, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, y, w, h);

        // Thin separator line with glow effect
        dc.setColor(0x2244AA, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(50, y, w - 100, 2);
        dc.setColor(0x112244, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(50, y + 2, w - 100, 1);

        if (!PlaybackState.hasActivePlayback()) {
            // Idle — outline arc with "Now Playing" label
            dc.setColor(0x888899, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + 16, Graphics.FONT_XTINY,
                        "No episode playing", Graphics.TEXT_JUSTIFY_CENTER);
            // Outline arc + play icon
            _drawArcOutline(dc, cx, screenH, r, 0x444466);
            var idleIconY = screenH - 22;
            dc.setColor(0x444466, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx - 7, idleIconY - 9], [cx - 7, idleIconY + 9], [cx + 9, idleIconY]]);
            return;
        }

        // --- Active playback ---

        // Episode title (centered, tight to separator)
        var titleY = y + 4;
        var maxTextW = w - 140;
        var fontH = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, PlaybackState.currentTitle, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Podcast name + position (spaced by full font height + gap)
        var position = PlaybackState.getEstimatedPosition();
        var duration = PlaybackState.currentDuration;
        var subText = PlaybackState.currentPodcastTitle;
        if (duration > 0) {
            subText = subText + " · " + DataFormat.formatTime(position);
        }
        var subY = titleY + fontH + 2;
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, subY, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, subText, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Progress bar (full available width, below subtitle with gap)
        var barY = subY + fontH + 4;
        var dy = barY - cx;
        var rSq = r * r;
        var dySq = dy * dy;
        var halfChord = 100;  // fallback
        if (dySq < rSq) {
            halfChord = Math.sqrt(rSq - dySq).toNumber() - 8;
        }
        var barX = cx - halfChord;
        var barW = halfChord * 2;
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(barX, barY, barW, 4, 2);
        if (duration > 0 && position > 0) {
            var progress = position.toFloat() / duration.toFloat();
            if (progress > 1.0) { progress = 1.0; }
            var fillW = (barW * progress).toNumber();
            if (fillW > 0) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(barX, barY, fillW, 4, 2);
            }
        }

        // Arc play/pause button at the very bottom (Garmin-style outline only)
        // drawArc clockwise from 315° (bottom-right) to 225° (bottom-left) = bottom 90°
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(cx, cx, r - 2, Graphics.ARC_CLOCKWISE, 315, 225);
        dc.setPenWidth(1);

        // Play/pause icon centered below the arc line
        var iconY = screenH - 20;
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        if (PlaybackState.isPlaying) {
            dc.fillRectangle(cx - 8, iconY - 8, 5, 16);
            dc.fillRectangle(cx + 3, iconY - 8, 5, 16);
        } else {
            dc.fillPolygon([[cx - 7, iconY - 9], [cx - 7, iconY + 9], [cx + 9, iconY]]);
        }
    }

    //! Draw a Garmin-style arc outline at the bottom of the round screen (idle state)
    private function _drawArcOutline(dc as Graphics.Dc, cx as Number,
                                       screenH as Number, r as Number,
                                       color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(cx, cx, r - 2, Graphics.ARC_CLOCKWISE, 315, 225);
        dc.setPenWidth(1);
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

    // --- Scroll management (called by delegate) ---

    //! Scroll the list by a number of pixels
    function scroll(deltaPixels as Number) as Void {
        _scrollOffset = _scrollOffset + deltaPixels;
        clampScroll();
        WatchUi.requestUpdate();
    }

    //! Clamp scroll offset to valid range
    private function clampScroll() as Void {
        var screenH = System.getDeviceSettings().screenHeight;
        var dockY = screenH - DOCK_H;
        // Total content height = title + all items
        var contentH = TITLE_H + _items.size() * ITEM_H;
        // Max scroll: last item's bottom aligns with dock top
        var maxScroll = contentH - dockY;
        if (maxScroll < 0) { maxScroll = 0; }
        if (_scrollOffset > maxScroll) { _scrollOffset = maxScroll; }
        if (_scrollOffset < 0) { _scrollOffset = 0; }
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
        var itemsStartY = TITLE_H - _scrollOffset;
        for (var i = 0; i < _items.size(); i++) {
            var top = itemsStartY + i * ITEM_H;
            if (y >= top && y < top + ITEM_H) {
                return i;
            }
        }
        return -1;
    }

    //! Get the item ID for a given index
    function getItemId(index as Number) as Symbol {
        return _items[index]["id"] as Symbol;
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

    //! Up/down scrolling via buttons or crown — scroll by one item height
    function onNextPage() as Boolean {
        _view.scroll(50);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.scroll(-50);
        return true;
    }

    //! Select fires for both button press AND screen tap on Garmin.
    //! We return false to let onTap handle touch events with coordinates.
    function onSelect() as Boolean {
        System.println("YoCasts: HomeMenu onSelect (ignored — onTap handles taps)");
        return false;
    }

    //! Handle screen tap — tap on item navigates directly
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var x = coords[0];
        var y = coords[1];
        System.println("YoCasts: HomeMenu onTap at (" + x + ", " + y + ")");

        // Dock area tap — split into info zone (top) and arc button zone (bottom)
        var dockY = _view.getDockY();
        var screenH = System.getDeviceSettings().screenHeight;
        var arcZoneY = screenH - 40;  // bottom 40px is the play/pause arc button
        if (y >= dockY) {
            if (y >= arcZoneY) {
                // Arc button zone — toggle play/pause
                System.println("YoCasts: HomeMenu dock arc tapped — toggling play/pause");
                PlaybackState.isPlaying = !PlaybackState.isPlaying;
                WatchUi.requestUpdate();
            } else {
                // Info zone — open NowPlaying screen
                System.println("YoCasts: HomeMenu dock info tapped — opening NowPlaying");
                navigateToNowPlaying();
            }
            return true;
        }

        // Item area tap — navigate directly to tapped item
        var idx = _view.itemIndexAtY(y);
        System.println("YoCasts: HomeMenu tap hit-test → idx=" + idx);
        if (idx >= 0) {
            var id = _view.getItemId(idx);
            System.println("YoCasts: HomeMenu tap → navigating to " + id);
            navigateTo(id);
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
            WatchUi.pushView(queueView, new QueueDelegate(queueView, _service), WatchUi.SLIDE_UP);
        } else if (id == :podcasts) {
            System.println("YoCasts: HomeMenu → Podcasts");
            var podView = new SubscribedView(_service);
            WatchUi.pushView(podView, new SubscribedDelegate(podView, _service), WatchUi.SLIDE_UP);
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
