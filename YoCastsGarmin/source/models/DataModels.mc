import Toybox.Lang;
import Toybox.Graphics;

//! Constants for Dictionary keys used in podcast/episode data models.
//! Data is stored as Dictionaries (not classes) to match makeWebRequest JSON parsing
//! and minimize memory usage on constrained devices.
module DataKeys {
    // Podcast fields (from /user/podcast/list)
    const P_UUID = "uuid";
    const P_TITLE = "title";
    const P_AUTHOR = "author";
    const P_DESCRIPTION = "description";
    const P_URL = "url";
    const P_LAST_EPISODE = "lastEpisodePublished";
    const P_LAST_EPISODE_UUID = "lastEpisodeUuid";

    // Episode fields (from /user/podcast/episodes, /up_next/list)
    const E_UUID = "uuid";
    const E_TITLE = "title";
    const E_URL = "url";
    const E_PUBLISHED = "published";
    const E_DURATION = "duration";
    const E_FILE_TYPE = "fileType";
    const E_SIZE = "size";
    const E_PLAYED_UP_TO = "playedUpTo";
    const E_STARRED = "starred";
    const E_PODCAST_UUID = "podcastUuid";
    const E_PODCAST_TITLE = "podcastTitle";
    const E_PLAYING_STATUS = "playingStatus";
    const E_IS_DELETED = "isDeleted";

    // Playing status values
    const STATUS_NOT_PLAYED = 0;
    const STATUS_IN_PROGRESS = 2;
    const STATUS_COMPLETED = 3;
}

//! Helper module for formatting data for display
module DataFormat {
    //! Format seconds into "Xh Ym" or "Ym" string for display
    function formatDuration(seconds as Number) as String {
        if (seconds <= 0) {
            return "0m";
        }
        var hours = seconds / 3600;
        var minutes = (seconds % 3600) / 60;
        if (hours > 0) {
            return hours.toString() + "h " + minutes.toString() + "m";
        }
        return minutes.toString() + "m";
    }

    //! Format seconds into "MM:SS" for now playing display
    function formatTime(seconds as Number) as String {
        if (seconds < 0) { seconds = 0; }
        var mins = seconds / 60;
        var secs = seconds % 60;
        var secsStr = secs < 10 ? "0" + secs.toString() : secs.toString();
        return mins.toString() + ":" + secsStr;
    }

    //! Truncate text to fit within maxWidth pixels, appending "..." if needed.
    //! Uses binary search for efficiency on long strings.
    function truncateText(dc as Graphics.Dc, text as String, font as Graphics.FontDefinition, maxWidth as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var ellipsis = "...";
        var ellipsisW = dc.getTextWidthInPixels(ellipsis, font);
        var availW = maxWidth - ellipsisW;
        if (availW <= 0) {
            return ellipsis;
        }
        var lo = 1;
        var hi = text.length() - 1;
        var best = 0;
        while (lo <= hi) {
            var mid = (lo + hi) / 2;
            var sub = text.substring(0, mid) as String;
            if (dc.getTextWidthInPixels(sub, font) <= availW) {
                best = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        if (best == 0) {
            return ellipsis;
        }
        return (text.substring(0, best) as String) + ellipsis;
    }
}
