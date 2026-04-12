using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;

//! Login prompt shown when no PocketCasts credentials are configured.
//! Instructs the user to enter credentials via Garmin Connect Mobile.
class LoginPromptView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        // App name at top
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 60, Gfx.FONT_MEDIUM, "YoCasts",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // Instructions
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, Gfx.FONT_XTINY,
                    "Open Garmin Connect\non your phone and\nenter PocketCasts\ncredentials in settings.",
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }
}

//! Delegate for LoginPromptView — BACK exits the app.
class LoginPromptDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
