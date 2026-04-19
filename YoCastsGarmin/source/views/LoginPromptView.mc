import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Application;

//! Welcome/login screen for YoCasts on 390x390 AMOLED (Venu 4 41mm).
//! Shows branding, login instructions, and a tap-to-skip option for demo mode.
class LoginPromptView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // --- App title / logo text ---
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 85, Graphics.FONT_LARGE, "YoCasts",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- Thin separator line ---
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 60, 115, cx + 60, 115);

        // --- Subtitle ---
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 140, Graphics.FONT_TINY, "Podcasts on your wrist",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- Login instructions ---
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 195, Graphics.FONT_XTINY,
                    "To sign in, open Garmin\nConnect on your phone\nand enter PocketCasts\ncredentials in settings.",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- Bottom separator ---
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 80, 260, cx + 80, 260);

        // --- Skip / Demo button area ---
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 290, Graphics.FONT_SMALL, "Tap to Continue",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 320, Graphics.FONT_XTINY, "Demo Mode",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

//! Delegate for LoginPromptView.
//! Tap or bottom button skips to home menu with mock data.
//! BACK exits the app.
class LoginPromptDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Tap anywhere skips to home menu with mock data
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _skipToHome();
        return true;
    }

    //! SELECT (bottom button) also skips
    function onSelect() as Boolean {
        _skipToHome();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    //! Navigate to the home menu with mock data
    private function _skipToHome() as Void {
        var app = Application.getApp() as YoCastsApp;
        var service = app.getService();
        var view = new HomeMenuView(service);
        var delegate = new HomeMenuDelegate(view, service);
        WatchUi.switchToView(view, delegate, WatchUi.SLIDE_UP);
    }
}
