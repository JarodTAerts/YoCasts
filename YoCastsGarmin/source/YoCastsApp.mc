import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;

//! Main application entry point for YoCasts.
//! Manages lifecycle and determines initial view based on auth state.
class YoCastsApp extends Application.AppBase {

    private var _service as MockPodcastService?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        _service = new MockPodcastService();
    }

    //! Returns the initial view — no explicit return type annotation per SDK rules.
    //! Shows login prompt if no credentials, otherwise shows the home menu.
    function getInitialView() {
        if (hasCredentials()) {
            var menu = buildHomeMenu(getService());
            return [menu, new MainMenuDelegate(getService())];
        } else {
            return [new LoginPromptView(), new LoginPromptDelegate()];
        }
    }

    function onStop(state) {
    }

    //! Check if PocketCasts credentials have been entered via Garmin Connect Mobile
    function hasCredentials() as Boolean {
        // Mock: always has credentials for testing
        try {
            var email = Application.Properties.getValue("PocketCastsEmail");
            var password = Application.Properties.getValue("PocketCastsPassword");
            return (email != null && !email.equals("") &&
                    password != null && !password.equals(""));
        } catch (e) {
            // Properties may not be available; show home menu anyway for testing
            return true;
        }
    }

    //! Get the podcast service singleton
    function getService() as MockPodcastService {
        if (_service == null) {
            _service = new MockPodcastService();
        }
        return _service as MockPodcastService;
    }

    //! Build the home Menu2 with Queue, Podcasts, Now Playing items
    function buildHomeMenu(service as MockPodcastService) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "YoCasts"});
        menu.addItem(new WatchUi.MenuItem("Queue", "Up Next", :queue, {}));
        menu.addItem(new WatchUi.MenuItem("Podcasts", "Subscriptions", :podcasts, {}));
        menu.addItem(new WatchUi.MenuItem("Now Playing", "Current episode", :nowPlaying, {}));
        return menu;
    }
}
