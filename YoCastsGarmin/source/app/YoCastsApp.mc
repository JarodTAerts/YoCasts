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
    private var _contentDelegate as YoCastsContentDelegate?;
    private var _fetchStarted as Boolean = false;

    function initialize() {
        AudioContentProviderApp.initialize();
    }

    function onStart(state) {
        AutoSyncManager.applyDisabledSetting();
        DownloadQueue.recoverInterruptedDownloads();
        PlaybackState.restore();
        _service = createService();
    }

    //! Primary entry point for audio content providers.
    //! Called when the user selects YoCasts from Music Providers.
    //! Three-state gate: unauthenticated → login, otherwise → home menu.
    function getPlaybackConfigurationView() {
        if (hasCredentials() || shouldUseMockData()) {
            validateDownloadedMedia();
            var service = getService();
            ensureMetadataFetch(service);
            var view = new HomeMenuView(service);
            return [view, new HomeMenuDelegate(view, service)];
        } else {
            return [new LoginPromptView(), new LoginPromptDelegate()];
        }
    }

    //! Native sync configuration entry point.
    function getSyncConfigurationView() {
        var view = new SyncConfigurationView();
        return [view, new SyncConfigurationDelegate(view)];
    }

    //! Returns the content delegate that the native player uses for playback.
    //! Cached singleton — preserves timer and state between system calls.
    function getContentDelegate(arg) {
        if (_contentDelegate == null) {
            _contentDelegate = new YoCastsContentDelegate();
        }
        return _contentDelegate;
    }

    //! Returns the sync delegate for system-triggered media downloads.
    function getSyncDelegate() {
        return new YoCastsSyncDelegate();
    }

    //! Provides icon and accent color for the Music Provider picker.
    function getProviderIconInfo() {
        return new Media.ProviderIconInfo(Rez.Drawables.LauncherIcon, 0x55AAFF);
    }

    //! Select downloaded content and transfer control to Garmin's native player.
    function requestPlayback(uuid as String) as Void {
        if (!StorageManager.isEpisodeDownloaded(uuid)) {
            System.println("YoCasts: cannot play undownloaded episode " + uuid);
            return;
        }

        StorageManager.setSelectedEpisode(uuid);
        if (_contentDelegate == null) {
            _contentDelegate = new YoCastsContentDelegate();
        } else {
            (_contentDelegate as YoCastsContentDelegate).resetContentIterator();
        }

        System.println("YoCasts: starting native playback for " + uuid);
        Media.startPlayback(null);
    }

    //! Ask the system to enter its managed Wi-Fi media sync flow.
    function requestMediaSync() as Void {
        if (DownloadQueue.getNextPending() == null &&
            ChangeLog.getEntryCount() == 0 &&
            !AutoSyncManager.isRefreshDue() &&
            !AutoSyncManager.hasMediaSyncRequest()) {
            return;
        }
        if (AutoSyncManager.hasMediaSyncRequest()) {
            AutoSyncManager.clearMediaSyncRequest();
            AutoSyncManager.forceRefresh();
        }
        System.println("YoCasts: requesting native media sync");
        Media.startSync();
    }

    //! Delete both the encrypted media item and its application metadata.
    function deleteDownloadedEpisode(uuid as String) as Void {
        var refId = StorageManager.getEpisodeRefId(uuid);
        if (refId != null) {
            try {
                Media.deleteCachedItem(new Media.ContentRef(
                    refId,
                    Media.CONTENT_TYPE_AUDIO
                ));
            } catch (e) {
                System.println("YoCasts: media cache delete failed for " + uuid);
            }
        }
        StorageManager.removeDownload(uuid);
        DownloadQueue.removeFromQueue(uuid);
        if (_contentDelegate != null) {
            (_contentDelegate as YoCastsContentDelegate).resetContentIterator();
        }
    }

    function isNativeMediaAvailable() as Boolean {
        return true;
    }

    function onStop(state) {
    }

    //! Called when settings are changed via Garmin Connect Mobile or simulator.
    function onSettingsChanged() as Void {
        System.println("YoCasts: settings changed, recreating service");
        AutoSyncManager.onSettingsChanged();
        _service = createService();
        _fetchStarted = false;
        var svc = _service as IPodcastService;
        ensureMetadataFetch(svc);
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

    private function ensureMetadataFetch(service as IPodcastService) as Void {
        if (_fetchStarted || !ConnectivityManager.isConnected()) {
            return;
        }
        _fetchStarted = true;
        service.fetchAll();
    }

    private function validateDownloadedMedia() as Void {
        var downloads = StorageManager.getDownloadedEpisodes();
        for (var i = 0; i < downloads.size(); i++) {
            var entry = downloads[i] as Dictionary;
            var uuid = entry.get("episodeUuid");
            var refId = entry.get("refId");
            if (uuid == null || refId == null) {
                continue;
            }
            try {
                Media.getCachedContentObj(new Media.ContentRef(
                    refId,
                    Media.CONTENT_TYPE_AUDIO
                ));
            } catch (e) {
                System.println("YoCasts: stale media reference " + uuid);
                DownloadQueue.markMediaMissing(uuid as String);
            }
        }
    }

    //! Build the home menu view + delegate pair
    function buildHomeView(service as IPodcastService) as Array {
        var view = new HomeMenuView(service);
        var delegate = new HomeMenuDelegate(view, service);
        return [view, delegate] as Array;
    }
}
