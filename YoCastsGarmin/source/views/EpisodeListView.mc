import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Graphics;

//! Episode list for a specific podcast.
//! Uses CustomMenu so CustomMenuItem.draw() is invoked by the runtime.
//! Shows episode titles with duration and play status, themed
//! with the parent podcast's brand colors.
//! Selecting an episode opens an action menu (Play / Download).
class EpisodeListView extends WatchUi.CustomMenu {

    private var _service as IPodcastService;
    private var _podcastUuid as String;
    private var _menuTitle as String;

    function initialize(service as IPodcastService, podcastUuid as String, podcastTitle as String) {
        CustomMenu.initialize(80, Graphics.COLOR_BLACK, {:titleItemHeight => 50});
        _service = service;
        _podcastUuid = podcastUuid;
        _menuTitle = podcastTitle;
        if (_menuTitle.length() > 18) {
            _menuTitle = (_menuTitle.substring(0, 15) as String) + "...";
        }
        loadEpisodes();
        System.println("YoCasts: EpisodeListView initialized (CustomMenu) for '" + podcastTitle + "'");
    }

    //! Draw the podcast title area
    function drawTitle(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(dc.getWidth() / 2, 8, Graphics.FONT_SMALL, _menuTitle,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function loadEpisodes() as Void {
        // Trigger async fetch if not already cached
        if (!_service.hasEpisodesForPodcast(_podcastUuid)) {
            _service.requestEpisodesForPodcast(_podcastUuid);
        }

        var episodes = _service.getEpisodesForPodcast(_podcastUuid);
        System.println("YoCasts: loadEpisodes() — " + episodes.size() + " episodes for " + _podcastUuid);

        if (episodes.size() == 0) {
            var label = _service.hasEpisodesForPodcast(_podcastUuid) ? "No episodes" : "Loading...";
            addItem(new EmptyStateMenuItem(label));
            return;
        }

        // Look up parent podcast brand colors
        var podcasts = _service.getSubscribedPodcasts();
        var colors = DataFormat.lookupPodcastColors(podcasts, _podcastUuid);
        var artColor = colors[0] as Number;
        var artTint = colors[1] as Number;

        // Cap at 15 episodes per memory budget
        var limit = episodes.size() < 15 ? episodes.size() : 15;
        for (var i = 0; i < limit; i++) {
            var ep = episodes[i] as Dictionary;
            var title = ep[DataKeys.E_TITLE] as String;
            var duration = ep[DataKeys.E_DURATION] as Number;
            var playedUpTo = ep[DataKeys.E_PLAYED_UP_TO] as Number;
            var status = ep[DataKeys.E_PLAYING_STATUS] as Number;
            var uuid = ep[DataKeys.E_UUID] as String;

            // Build sublabel with duration, play status, and download indicator
            var sub = "";
            if (status == DataKeys.STATUS_COMPLETED) {
                sub = "Played | " + DataFormat.formatDuration(duration);
            } else if (status == DataKeys.STATUS_IN_PROGRESS) {
                sub = DataFormat.formatDuration(playedUpTo) + " / " + DataFormat.formatDuration(duration);
            } else {
                sub = DataFormat.formatDuration(duration) + " | New";
            }

            // Append download status indicator
            var dlStatus = DownloadQueue.getStatus(uuid);
            if (dlStatus == DownloadQueue.STATUS_DOWNLOADED) {
                sub = sub + " | \u2705";
            } else if (dlStatus == DownloadQueue.STATUS_DOWNLOADING) {
                sub = sub + " | \u2193 " + DownloadQueue.getProgress(uuid).toString() + "%";
            } else if (dlStatus == DownloadQueue.STATUS_PENDING) {
                sub = sub + " | \u231B";
            } else if (dlStatus == DownloadQueue.STATUS_FAILED) {
                sub = sub + " | \u274C";
            }

            addItem(new EpisodeMenuItem(uuid, title, sub, status, artColor, artTint));
        }
    }
}

//! Handles selection in the Episode list.
//! Selecting an episode opens an action menu with Play and Download options.
class EpisodeListDelegate extends WatchUi.Menu2InputDelegate {

    private var _service as IPodcastService;
    private var _podcastUuid as String;

    function initialize(service as IPodcastService, podcastUuid as String) {
        Menu2InputDelegate.initialize();
        _service = service;
        _podcastUuid = podcastUuid;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :empty) {
            return;
        }

        // Find the episode data
        var episodes = _service.getEpisodesForPodcast(_podcastUuid);
        for (var i = 0; i < episodes.size(); i++) {
            var ep = episodes[i] as Dictionary;
            if ((ep[DataKeys.E_UUID] as String).equals(id)) {
                showEpisodeActionMenu(ep);
                return;
            }
        }
    }

    //! Show action menu for the selected episode
    private function showEpisodeActionMenu(episode as Dictionary) as Void {
        var uuid = episode[DataKeys.E_UUID] as String;
        var title = episode[DataKeys.E_TITLE] as String;

        // Truncate title for menu header
        var menuTitle = title;
        if (menuTitle.length() > 18) {
            menuTitle = menuTitle.substring(0, 15) + "...";
        }

        var menu = new WatchUi.Menu2({:title => menuTitle});

        // Play option
        menu.addItem(new WatchUi.MenuItem("Play", "Open Now Playing", :play, {}));

        // Download option (context-aware label)
        var dlStatus = DownloadQueue.getStatus(uuid);
        if (dlStatus == DownloadQueue.STATUS_DOWNLOADED) {
            menu.addItem(new WatchUi.MenuItem("Downloaded", "Ready to play", :downloaded, {}));
        } else if (dlStatus == DownloadQueue.STATUS_DOWNLOADING) {
            var pct = DownloadQueue.getProgress(uuid).toString() + "%";
            menu.addItem(new WatchUi.MenuItem("Downloading", pct, :downloading, {}));
        } else if (dlStatus == DownloadQueue.STATUS_PENDING) {
            menu.addItem(new WatchUi.MenuItem("In Queue", "Waiting to download", :inqueue, {}));
        } else {
            menu.addItem(new WatchUi.MenuItem("Download", "Save for offline", :download, {}));
        }

        WatchUi.pushView(menu, new EpisodeActionDelegate(episode), WatchUi.SLIDE_UP);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

//! Delegate for the episode action menu (Play / Download).
class EpisodeActionDelegate extends WatchUi.Menu2InputDelegate {

    private var _episode as Dictionary;

    function initialize(episode as Dictionary) {
        Menu2InputDelegate.initialize();
        _episode = episode;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :play || id == :downloaded) {
            // Pop action menu, then push Now Playing
            WatchUi.popView(WatchUi.SLIDE_DOWN);

            // If downloaded, load cached position for resume
            var uuid = _episode[DataKeys.E_UUID] as String;
            if (DownloadQueue.getStatus(uuid) == DownloadQueue.STATUS_DOWNLOADED) {
                var cached = CacheManager.loadPlaybackPosition(uuid);
                if (cached != null) {
                    var pos = (cached as Dictionary).get("position");
                    if (pos != null && pos instanceof Number) {
                        _episode.put(DataKeys.E_PLAYED_UP_TO, pos);
                    }
                }
            }

            var npView = new NowPlayingView(_episode);
            var npDelegate = new NowPlayingDelegate(_episode);
            npDelegate.setView(npView);
            WatchUi.pushView(npView, npDelegate, WatchUi.SLIDE_UP);
        } else if (id == :download) {
            DownloadQueue.addToQueue(_episode);
            System.println("YoCasts: download queued — " + (_episode[DataKeys.E_UUID] as String));
            // Pop back to episode list (user sees updated status on next visit)
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else {
            // :downloading, :inqueue — just dismiss
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

//! Custom menu item for episodes with parent podcast brand color tinting.
//! Shows a status indicator dot and episode info on a tinted background.
class EpisodeMenuItem extends WatchUi.CustomMenuItem {

    private var _title as String;
    private var _subtitle as String;
    private var _status as Number;
    private var _brandColor as Number;
    private var _tintColor as Number;

    function initialize(id as String, title as String, subtitle as String,
                        status as Number, brandColor as Number, tintColor as Number) {
        CustomMenuItem.initialize(id, {});
        _title = title;
        _subtitle = subtitle;
        _status = status;
        _brandColor = brandColor;
        _tintColor = tintColor;
    }

    function draw(dc as Graphics.Dc) as Void {
        System.println("YoCasts: EpisodeMenuItem.draw() CALLED — '" + _title + "' focused=" + isFocused());
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Brightened brand color for visible background tint
        var boosted = DataFormat.brightenColor(_brandColor, 80);
        var factor = isFocused() ? 0.50 : 0.25;
        var bgColor = DataFormat.dimColor(boosted, factor);
        dc.setColor(Graphics.COLOR_WHITE, bgColor);
        dc.clear();

        // Status indicator dot on the left (boosted for visibility)
        var dotCX = 12;
        var dotCY = h / 2;
        if (_status == DataKeys.STATUS_IN_PROGRESS) {
            dc.setColor(DataFormat.brightenColor(_brandColor, 160), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dotCX, dotCY, 4);
        } else if (_status == DataKeys.STATUS_NOT_PLAYED) {
            dc.setColor(_tintColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dotCX, dotCY, 4);
        } else {
            // Completed — dim ring
            dc.setColor(DataFormat.brightenColor(_brandColor, 100), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawArc(dotCX, dotCY, 4, Graphics.ARC_CLOCKWISE, 0, 360);
        }

        // Text layout
        var textX = 26;
        var maxTextW = w - textX - 8;
        var titleH = dc.getFontHeight(Graphics.FONT_TINY);
        var subH = dc.getFontHeight(Graphics.FONT_XTINY);
        var startY = (h - titleH - 2 - subH) / 2;

        // Title — accent tint color (contrast-checked)
        var titleColor = DataFormat.ensureContrast(_tintColor, bgColor);
        dc.setColor(titleColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY, Graphics.FONT_TINY,
                    DataFormat.truncateText(dc, _title, Graphics.FONT_TINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // Subtitle — dimmed
        var subColor = DataFormat.dimColor(_tintColor, 0.55);
        subColor = DataFormat.ensureContrast(subColor, bgColor);
        dc.setColor(subColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, startY + titleH + 2, Graphics.FONT_XTINY,
                    DataFormat.truncateText(dc, _subtitle, Graphics.FONT_XTINY, maxTextW),
                    Graphics.TEXT_JUSTIFY_LEFT);
    }
}
