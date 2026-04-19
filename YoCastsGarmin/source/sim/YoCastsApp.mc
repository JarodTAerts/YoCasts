import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;

//! Simulator-mode entry point for YoCasts.
//! Extends AppBase (watch-app type) so the CIQ simulator can run it.
//! Identical logic to the device build except no Media/audio APIs.
class YoCastsApp extends Application.AppBase {

    private var _service as IPodcastService?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        _service = createService();
        var svc = _service as IPodcastService;
        svc.fetchAll();
    }

    //! Standard watch-app entry point.
    //! Three-state gate: unauthenticated → login, otherwise → home menu.
    function getInitialView() {
        if (hasCredentials() || shouldUseMockData()) {
            var service = getService();
            var view = new HomeMenuView(service);
            return [view, new HomeMenuDelegate(view, service)];
        } else {
            return [new LoginPromptView(), new LoginPromptDelegate()];
        }
    }

    function onStop(state) {
    }

    //! Called when settings are changed via Garmin Connect Mobile or simulator.
    function onSettingsChanged() as Void {
        System.println("YoCasts: settings changed, recreating service");
        _service = createService();
        var svc = _service as IPodcastService;
        svc.fetchAll();
        WatchUi.requestUpdate();
    }

    //! Check if PocketCasts credentials are available (always true in sim with hardcoded fallback)
    function hasCredentials() as Boolean {
        return true;
    }

    //! Check whether mock data mode is enabled (default: false for simulator testing)
    function shouldUseMockData() as Boolean {
        try {
            var useMock = Application.Properties.getValue("useMockData");
            if (useMock != null && useMock instanceof Boolean) {
                return useMock as Boolean;
            }
        } catch (e) {
            // Property not available
        }
        return false; // default to real API in simulator
    }

    //! Create the appropriate service based on settings.
    //! SIMULATOR ONLY: hardcoded credentials for testing when settings UI is unavailable.
    private function createService() as IPodcastService {
        var email = "";
        var password = "";
        var useMock = false;

        // Try properties first (in case settings ever work in sim)
        try {
            var e = Application.Properties.getValue("PocketCastsEmail");
            if (e != null && !e.equals("")) { email = e as String; }
        } catch (ex) {}
        try {
            var p = Application.Properties.getValue("PocketCastsPassword");
            if (p != null && !p.equals("")) { password = p as String; }
        } catch (ex) {}
        try {
            var m = Application.Properties.getValue("useMockData");
            if (m != null && m instanceof Boolean) { useMock = m as Boolean; }
        } catch (ex) {}

        // Hardcoded fallback for simulator testing (from gitignored LocalCredentials.mc)
        if (email.equals("")) { email = LocalCredentials.EMAIL; }
        if (password.equals("")) { password = LocalCredentials.PASSWORD; }

        if (!useMock) {
            try {
                System.println("YoCasts: creating real service with " + email);
                var realService = new PocketCastsPodcastService(email, password);
                return new CachedPodcastService(realService);
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
