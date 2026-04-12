import Toybox.Media;
import Toybox.Communications;

//! Stub SyncDelegate for system-triggered episode downloads.
//! Returns immediately since no download logic is implemented yet.
//! Real implementation will chain makeWebRequest(AUDIO) calls in Phase C.
class YoCastsSyncDelegate extends Communications.SyncDelegate {

    function initialize() {
        SyncDelegate.initialize();
    }

    //! No sync needed yet — no episodes queued for download.
    function isSyncNeeded() {
        return false;
    }

    //! Called when the system triggers a sync. Complete immediately.
    function onStartSync() {
        Media.notifySyncComplete(null);
    }

    //! Called when the user cancels a sync.
    function onStopSync() {
        Communications.cancelAllRequests();
        Media.notifySyncComplete(null);
    }
}
