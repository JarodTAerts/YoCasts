import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Application;

//! In-app settings screen showing configuration status.
//! Allows toggling mock data mode and shows credential status.
//! Provides a fallback when simulator "Trigger App Settings" isn't available
//! (it's grayed out for watch-app types — that's a known CIQ limitation).
class SettingsView extends WatchUi.View {

    private var _selectedIndex as Number = 0;
    private const NUM_ITEMS = 2;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 40, Graphics.FONT_MEDIUM, "Settings",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 50, 58, cx + 50, 58);

        // --- Credentials status ---
        var hasEmail = false;
        var emailDisplay = "Not set";
        try {
            var email = Application.Properties.getValue("PocketCastsEmail");
            if (email != null && !email.equals("")) {
                hasEmail = true;
                var emailStr = email as String;
                if (emailStr.length() > 20) {
                    emailDisplay = (emailStr.substring(0, 17) as String) + "...";
                } else {
                    emailDisplay = emailStr;
                }
            }
        } catch (e) {
            // Property not set
        }

        var hasPassword = false;
        try {
            var pwd = Application.Properties.getValue("PocketCastsPassword");
            if (pwd != null && !pwd.equals("")) {
                hasPassword = true;
            }
        } catch (e) {
            // Property not set
        }

        var useMock = true;
        try {
            var mock = Application.Properties.getValue("useMockData");
            if (mock != null && mock instanceof Boolean) {
                useMock = mock as Boolean;
            }
        } catch (e) {
            // Default to mock
        }

        var margin = 30;
        var pillW = w - margin * 2;
        var pillH = 62;
        var pillR = 14;
        var startY = 80;
        var gap = 12;

        // --- Item 0: Account Status ---
        var accountY = startY;
        var accountBg = _selectedIndex == 0 ? 0x252545 : 0x1A1A2E;
        dc.setColor(accountBg, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(margin, accountY, pillW, pillH, pillR);

        // Selection indicator
        if (_selectedIndex == 0) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(margin, accountY, pillW, pillH, pillR);
            dc.setPenWidth(1);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(margin + 16, accountY + 18, Graphics.FONT_SMALL, "Account",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (hasEmail && hasPassword) {
            dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
            dc.drawText(margin + 16, accountY + 42, Graphics.FONT_XTINY, emailDisplay,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (hasEmail) {
            dc.setColor(0xFFAA55, Graphics.COLOR_TRANSPARENT);
            dc.drawText(margin + 16, accountY + 42, Graphics.FONT_XTINY, "Password not set",
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(0xFF5555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(margin + 16, accountY + 42, Graphics.FONT_XTINY, "Not configured",
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- Item 1: Mock Data Toggle ---
        var mockY = accountY + pillH + gap;
        var mockBg = _selectedIndex == 1 ? 0x252545 : 0x1A1A2E;
        dc.setColor(mockBg, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(margin, mockY, pillW, pillH, pillR);

        if (_selectedIndex == 1) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(margin, mockY, pillW, pillH, pillR);
            dc.setPenWidth(1);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(margin + 16, mockY + 18, Graphics.FONT_SMALL, "Demo Mode",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Toggle indicator
        var toggleX = margin + pillW - 52;
        var toggleY = mockY + 18;
        var toggleW = 36;
        var toggleH = 18;
        var toggleR = 9;

        if (useMock) {
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(toggleX, toggleY - toggleH / 2, toggleW, toggleH, toggleR);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(toggleX + toggleW - toggleR, toggleY, toggleR - 3);
        } else {
            dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(toggleX, toggleY - toggleH / 2, toggleW, toggleH, toggleR);
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(toggleX + toggleR, toggleY, toggleR - 3);
        }

        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(margin + 16, mockY + 42, Graphics.FONT_XTINY,
                    useMock ? "Using demo data" : "Using PocketCasts API",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- Instructions at bottom ---
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 75, Graphics.FONT_XTINY,
                    "Set credentials in",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, h - 55, Graphics.FONT_XTINY,
                    "Garmin Connect Mobile",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function setSelectedIndex(index as Number) as Void {
        _selectedIndex = index;
        if (_selectedIndex < 0) { _selectedIndex = NUM_ITEMS - 1; }
        if (_selectedIndex >= NUM_ITEMS) { _selectedIndex = 0; }
        WatchUi.requestUpdate();
    }

    function getSelectedIndex() as Number {
        return _selectedIndex;
    }
}

//! Delegate for SettingsView. Handles mock data toggle and navigation.
class SettingsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SettingsView;

    function initialize(view as SettingsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        var idx = _view.getSelectedIndex();
        if (idx == 1) {
            toggleMockData();
        }
        // Index 0 (Account) is display-only — credentials set via phone
        return true;
    }

    function onNextPage() as Boolean {
        _view.setSelectedIndex(_view.getSelectedIndex() + 1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.setSelectedIndex(_view.getSelectedIndex() - 1);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var coords = evt.getCoordinates();
        var tapY = coords[1] as Number;

        // Rough hit zones
        if (tapY >= 80 && tapY < 142) {
            _view.setSelectedIndex(0);
            return true;
        } else if (tapY >= 154 && tapY < 216) {
            _view.setSelectedIndex(1);
            toggleMockData();
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Toggle useMockData property and restart service
    private function toggleMockData() as Void {
        var current = true;
        try {
            var val = Application.Properties.getValue("useMockData");
            if (val != null && val instanceof Boolean) {
                current = val as Boolean;
            }
        } catch (e) {
            // defaults to true
        }

        var newVal = !current;
        Application.Properties.setValue("useMockData", newVal);
        System.println("YoCasts: mock data toggled to " + newVal.toString());

        // Recreate the service with new settings
        var app = Application.getApp() as YoCastsApp;
        app.onSettingsChanged();
        WatchUi.requestUpdate();
    }
}
