import Toybox.Lang;
import Toybox.System;

//! Centralized three-state connectivity detection for YoCasts.
//! Replaces scattered phoneConnected checks with a unified model
//! that accounts for Wi-Fi direct connectivity (Venu 4).
//!
//! States:
//!   STATE_WIFI   — Wi-Fi direct, no phone needed (best for downloads)
//!   STATE_PHONE  — BT proxy through phone (good for metadata)
//!   STATE_OFFLINE — no connectivity (cache only)
module ConnectivityManager {

    // Connectivity states
    const STATE_WIFI = 0;
    const STATE_PHONE = 1;
    const STATE_OFFLINE = 2;

    //! Returns the current connectivity state by reading device settings.
    //! Uses connectionAvailable as the primary "can make HTTP requests?" signal
    //! and phoneConnected to distinguish Wi-Fi direct from BT proxy.
    function getState() as Number {
        var settings = System.getDeviceSettings();
        if (!settings.connectionAvailable) {
            // No internet path — offline regardless of phone status
            return STATE_OFFLINE;
        }
        if (!settings.phoneConnected) {
            // Internet available but no phone — must be Wi-Fi direct
            return STATE_WIFI;
        }
        // Internet available via phone (may also have Wi-Fi)
        return STATE_PHONE;
    }

    //! Returns true if any connectivity exists (Wi-Fi or phone).
    function isConnected() as Boolean {
        return System.getDeviceSettings().connectionAvailable;
    }

    //! Returns true only for Wi-Fi direct (connectionAvailable without phone).
    function isWifiDirect() as Boolean {
        var settings = System.getDeviceSettings();
        return settings.connectionAvailable && !settings.phoneConnected;
    }

    //! Alias for isConnected(). Can the app make HTTP requests right now?
    function canMakeRequests() as Boolean {
        return isConnected();
    }
}
