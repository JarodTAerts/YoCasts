import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Media;

//! Main application entry point for YoCasts.
//! Extends AudioContentProviderApp so the app appears in the watch's
//! Music Providers list and can use the native media player for audio.
//! Entry point is getPlaybackConfigurationView(), NOT getInitialView().
class YoCastsApp extends Application.AudioContentProviderApp {

    private var _service as IPodcastService?;

    function initialize() {
        AudioContentProviderApp.initialize();
    }

    function onStart(state) {
        _service = createService();
        var svc = _service as IPodcastService;
        svc.fetchAll();
    }

    //! Primary entry point for audio content providers.
    //! Called when the user selects YoCasts from Music Providers.
    //! Three-state gate: unauthenticated → login, otherwise → home menu.
    function getPlaybackConfigurationView() {
        if (hasCredentials() || shouldUseMockData()) {
            var service = getService();
            var view = new HomeMenuView(service);
            return [view, new HomeMenuDelegate(view, service)];
        } else {
            return [new LoginPromptView(), new LoginPromptDelegate()];
        }
    }

    //! Sync entry point — returns the same HomeMenuView.
    //! On some devices this is called instead of playback config.
    function getSyncConfigurationView() {
        return getPlaybackConfigurationView();
    }

    //! Returns the content delegate that the native player uses for playback.
    function getContentDelegate(arg) {
        return new YoCastsContentDelegate();
    }

    //! Returns the sync delegate for system-triggered media downloads.
    function getSyncDelegate() {
        return new YoCastsSyncDelegate();
    }

    //! Provides icon and accent color for the Music Provider picker.
    function getProviderIconInfo() {
        return new Media.ProviderIconInfo(Rez.Drawables.LauncherIcon, 0x55AAFF);
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
    private function createService() as IPodcastService {
        if (!shouldUseMockData() && hasCredentials()) {
            try {
                var email = Application.Properties.getValue("PocketCastsEmail") as String;
                var password = Application.Properties.getValue("PocketCastsPassword") as String;
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
