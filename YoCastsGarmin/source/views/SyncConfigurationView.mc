import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Native Garmin menu used when the system enters sync configuration mode.
class SyncConfigurationView extends WatchUi.Menu2 {

    private var _accountItem as WatchUi.MenuItem;
    private var _autoItem as WatchUi.MenuItem;
    private var _syncItem as WatchUi.MenuItem;
    private var _demoItem as WatchUi.MenuItem;

    function initialize() {
        Menu2.initialize({ :title => "Settings" });

        _accountItem = new WatchUi.MenuItem(
            "Pocket Casts",
            _accountSummary(),
            :account,
            null
        );
        _syncItem = new WatchUi.MenuItem(
            "Sync Now",
            SyncStatus.getSummary(),
            :sync,
            null
        );
        _autoItem = new WatchUi.MenuItem(
            "Auto-download",
            AutoSyncManager.getLabel(),
            :auto,
            null
        );
        _demoItem = new WatchUi.MenuItem(
            "Demo Mode",
            _demoSummary(),
            :demo,
            null
        );
        addItem(_accountItem);
        addItem(_autoItem);
        addItem(_syncItem);
        addItem(_demoItem);
    }

    function refreshLabels() as Void {
        _accountItem.setSubLabel(_accountSummary());
        _syncItem.setSubLabel(SyncStatus.getSummary());
        _autoItem.setSubLabel(AutoSyncManager.getLabel());
        _demoItem.setSubLabel(_demoSummary());
        updateItem(_accountItem, 0);
        updateItem(_autoItem, 1);
        updateItem(_syncItem, 2);
        updateItem(_demoItem, 3);
        WatchUi.requestUpdate();
    }

    private function _accountSummary() as String {
        try {
            var email = Application.Properties.getValue("PocketCastsEmail");
            var password =
                Application.Properties.getValue("PocketCastsPassword");
            if (email != null && password != null &&
                email instanceof String && password instanceof String &&
                (email as String).length() > 0 &&
                (password as String).length() > 0) {
                return "Configured";
            }
        } catch (e) {
            // Fall through to the concise native-menu status.
        }
        return "Not configured";
    }

    private function _demoSummary() as String {
        try {
            var value = Application.Properties.getValue("useMockData");
            if (value != null && value instanceof Boolean &&
                value as Boolean) {
                return "On - sample data";
            }
        } catch (e) {
            // Real Pocket Casts data is the default.
        }
        return "Off - Pocket Casts";
    }
}

class SyncConfigurationDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as SyncConfigurationView;

    function initialize(view as SyncConfigurationView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var app = Application.getApp() as YoCastsApp;
        if (id == :sync) {
            AutoSyncManager.forceRefresh();
            app.requestMediaSync();
        } else if (id == :auto) {
            AutoSyncManager.cycleCount();
            AutoSyncManager.forceRefresh();
        } else if (id == :demo) {
            var current = false;
            try {
                var value =
                    Application.Properties.getValue("useMockData");
                if (value != null && value instanceof Boolean) {
                    current = value as Boolean;
                }
            } catch (e) {
                // Keep false.
            }
            Application.Properties.setValue("useMockData", !current);
            app.onSettingsChanged();
        }
        _view.refreshLabels();
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
