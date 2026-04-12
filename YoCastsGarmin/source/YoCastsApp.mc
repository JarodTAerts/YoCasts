import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;

//! Main application entry point for YoCasts.
//! Manages lifecycle and determines initial view based on auth state.
//! Service toggle: reads "useMockData" property to choose between
//! MockPodcastService and PocketCastsPodcastService.
class YoCastsApp extends Application.AppBase {

    private var _service as IPodcastService?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        _service = createService();

        // Kick off async data fetch for the real service
        var svc = _service as IPodcastService;
        svc.fetchAll();
    }

    //! Returns the initial view — no explicit return type annotation per SDK rules.
    //! Shows login prompt if no credentials, otherwise shows the home menu.
    function getInitialView() {
        if (hasCredentials() && !shouldUseMockData()) {
            var service = getService();
            var view = new HomeMenuView(service);
            return [view, new HomeMenuDelegate(view, service)];
        } else if (shouldUseMockData()) {
            var service = getService();
            var view = new HomeMenuView(service);
            return [view, new HomeMenuDelegate(view, service)];
        } else {
            return [new LoginPromptView(), new LoginPromptDelegate()];
        }
    }

    function onStop(state) {
    }

    //! Check if PocketCasts credentials have been entered via Garmin Connect Mobile
    function hasCredentials() as Boolean {
        try {
            var email = Application.Properties.getValue("PocketCastsEmail");
            var password = Application.Properties.getValue("PocketCastsPassword");
            return (email != null && !email.equals("") &&
                    password != null && !password.equals(""));
        } catch (e) {
            return false;
        }
    }

    //! Check whether mock data mode is enabled (default: true)
    function shouldUseMockData() as Boolean {
        try {
            var useMock = Application.Properties.getValue("useMockData");
            if (useMock != null && useMock instanceof Boolean) {
                return useMock as Boolean;
            }
        } catch (e) {
            // Property not available
        }
        return true; // default to mock
    }

    //! Create the appropriate service based on settings.
    //! Falls back to mock if credentials are missing or useMockData is true.
    private function createService() as IPodcastService {
        if (!shouldUseMockData() && hasCredentials()) {
            try {
                var email = Application.Properties.getValue("PocketCastsEmail") as String;
                var password = Application.Properties.getValue("PocketCastsPassword") as String;
                return new PocketCastsPodcastService(email, password);
            } catch (e) {
                System.println("YoCasts: failed to create real service, using mock");
            }
        }
        return new MockPodcastService();
    }

    //! Get the podcast service singleton
    function getService() as IPodcastService {
        if (_service == null) {
            _service = createService();
        }
        return _service as IPodcastService;
    }

    //! Build the home menu view + delegate pair
    function buildHomeView(service as IPodcastService) as Array {
        var view = new HomeMenuView(service);
        var delegate = new HomeMenuDelegate(view, service);
        return [view, delegate] as Array;
    }
}
