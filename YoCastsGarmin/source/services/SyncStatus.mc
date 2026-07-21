import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

//! Persistent sync telemetry shared by foreground metadata sync and Garmin's
//! system media sync lifecycle.
module SyncStatus {

    const KEY_LAST_SUCCESS = "yc_sync_last_success";
    const KEY_LAST_ERROR = "yc_sync_last_error";
    const KEY_LAST_ATTEMPT = "yc_sync_last_attempt";

    function markStarted() as Void {
        Application.Storage.setValue(
            KEY_LAST_ATTEMPT,
            Time.now().value() as Application.Storage.ValueType
        );
    }

    function markSuccess() as Void {
        Application.Storage.setValue(
            KEY_LAST_SUCCESS,
            Time.now().value() as Application.Storage.ValueType
        );
        Application.Storage.deleteValue(KEY_LAST_ERROR);
    }

    function markFailure(message as String) as Void {
        Application.Storage.setValue(
            KEY_LAST_ERROR,
            message as Application.Storage.ValueType
        );
    }

    function getLastSuccess() as Number {
        var value = Application.Storage.getValue(KEY_LAST_SUCCESS);
        return (value != null && value instanceof Number)
            ? value as Number : 0;
    }

    function getLastError() as String {
        var value = Application.Storage.getValue(KEY_LAST_ERROR);
        return (value != null && value instanceof String)
            ? value as String : "";
    }

    function getSummary() as String {
        var pending = ChangeLog.getEntryCount();
        if (pending > 0) {
            return pending + (pending == 1
                ? " change waiting" : " changes waiting");
        }

        var error = getLastError();
        if (error.length() > 0) {
            return error;
        }

        var lastSuccess = getLastSuccess();
        if (lastSuccess == 0) {
            return "Not synced yet";
        }

        var age = Time.now().value() - lastSuccess;
        if (age < 60) { return "Synced just now"; }
        if (age < 3600) {
            return "Synced " + (age / 60) + "m ago";
        }
        if (age < 86400) {
            return "Synced " + (age / 3600) + "h ago";
        }
        return "Synced " + (age / 86400) + "d ago";
    }
}
