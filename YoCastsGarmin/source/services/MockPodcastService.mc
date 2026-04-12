import Toybox.Lang;

//! Mock implementation of IPodcastService with realistic data
//! modeled after PocketCasts API response structures.
//! This will be swapped for PocketCastsService when the real API is wired up.
class MockPodcastService extends IPodcastService {

    private var _podcasts as Array<Dictionary>;
    private var _episodes as Dictionary;  // podcastUuid -> Array<Dictionary>
    private var _queue as Array<Dictionary>;
    private var _nowPlaying as Dictionary?;

    function initialize() {
        IPodcastService.initialize();
        _podcasts = buildMockPodcasts();
        _episodes = buildMockEpisodes();
        _queue = buildMockQueue();
        _nowPlaying = buildMockNowPlaying();
    }

    function isAuthenticated() as Boolean {
        return true;
    }

    function isDataReady() as Boolean {
        return true;
    }

    function fetchAll() as Void {
        // No-op — mock data is pre-loaded
    }

    function requestEpisodesForPodcast(podcastUuid as String) as Void {
        // No-op — mock data is pre-loaded
    }

    function getSubscribedPodcasts() as Array<Dictionary> {
        return _podcasts;
    }

    function getEpisodesForPodcast(podcastUuid as String) as Array<Dictionary> {
        var eps = _episodes.get(podcastUuid);
        if (eps != null) {
            return eps as Array<Dictionary>;
        }
        return [] as Array<Dictionary>;
    }

    function getQueue() as Array<Dictionary> {
        return _queue;
    }

    function getNowPlaying() as Dictionary? {
        return _nowPlaying;
    }

    // ---- Mock Data Builders ----

    private function buildMockPodcasts() as Array<Dictionary> {
        return [
            {
                DataKeys.P_UUID => "a1b2c3d4-1111-2222-3333-444455556666",
                DataKeys.P_TITLE => "The Changelog",
                DataKeys.P_AUTHOR => "Changelog Media",
                DataKeys.P_DESCRIPTION => "Conversations with the hackers, leaders, and innovators of software.",
                DataKeys.P_LAST_EPISODE => "2026-04-10T14:00:00Z",
                DataKeys.P_LAST_EPISODE_UUID => "ep-chlog-001"
            },
            {
                DataKeys.P_UUID => "b2c3d4e5-2222-3333-4444-555566667777",
                DataKeys.P_TITLE => "Syntax FM",
                DataKeys.P_AUTHOR => "Wes Bos & Scott Tolinski",
                DataKeys.P_DESCRIPTION => "A Tasty Treats podcast for web developers.",
                DataKeys.P_LAST_EPISODE => "2026-04-09T10:00:00Z",
                DataKeys.P_LAST_EPISODE_UUID => "ep-syntax-001"
            },
            {
                DataKeys.P_UUID => "c3d4e5f6-3333-4444-5555-666677778888",
                DataKeys.P_TITLE => "Hardcore History",
                DataKeys.P_AUTHOR => "Dan Carlin",
                DataKeys.P_DESCRIPTION => "In-depth historical narratives.",
                DataKeys.P_LAST_EPISODE => "2026-03-15T08:00:00Z",
                DataKeys.P_LAST_EPISODE_UUID => "ep-hh-001"
            },
            {
                DataKeys.P_UUID => "d4e5f6a7-4444-5555-6666-777788889999",
                DataKeys.P_TITLE => "Running with the Pack",
                DataKeys.P_AUTHOR => "Trail Runners United",
                DataKeys.P_DESCRIPTION => "Tips, stories, and interviews from the trail running world.",
                DataKeys.P_LAST_EPISODE => "2026-04-08T06:00:00Z",
                DataKeys.P_LAST_EPISODE_UUID => "ep-rwtp-001"
            },
            {
                DataKeys.P_UUID => "e5f6a7b8-5555-6666-7777-888899990000",
                DataKeys.P_TITLE => "Garmin Unboxed",
                DataKeys.P_AUTHOR => "Wearable Weekly",
                DataKeys.P_DESCRIPTION => "Everything about Garmin devices, firmware, and fitness tech.",
                DataKeys.P_LAST_EPISODE => "2026-04-07T12:00:00Z",
                DataKeys.P_LAST_EPISODE_UUID => "ep-gunbox-001"
            }
        ] as Array<Dictionary>;
    }

    private function buildMockEpisodes() as Dictionary {
        var episodes = {} as Dictionary;

        // The Changelog episodes
        episodes.put("a1b2c3d4-1111-2222-3333-444455556666", [
            makeEpisode("ep-chlog-001", "589: AI in the Terminal", 3240, 0, 0,
                        "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog"),
            makeEpisode("ep-chlog-002", "588: Postgres Everywhere", 2880, 1200, 2,
                        "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog"),
            makeEpisode("ep-chlog-003", "587: Open Source Funding", 3600, 3600, 3,
                        "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog"),
            makeEpisode("ep-chlog-004", "586: Rust in Production", 2700, 0, 0,
                        "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog"),
            makeEpisode("ep-chlog-005", "585: DevOps is Dead?", 3120, 0, 0,
                        "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog")
        ] as Array<Dictionary>);

        // Syntax FM episodes
        episodes.put("b2c3d4e5-2222-3333-4444-555566667777", [
            makeEpisode("ep-syntax-001", "842: CSS Container Queries", 1920, 0, 0,
                        "b2c3d4e5-2222-3333-4444-555566667777", "Syntax FM"),
            makeEpisode("ep-syntax-002", "841: TypeScript 6.0 First Look", 2340, 600, 2,
                        "b2c3d4e5-2222-3333-4444-555566667777", "Syntax FM"),
            makeEpisode("ep-syntax-003", "840: Bun vs Deno vs Node", 2100, 2100, 3,
                        "b2c3d4e5-2222-3333-4444-555566667777", "Syntax FM"),
            makeEpisode("ep-syntax-004", "839: Svelte 5 Deep Dive", 2760, 0, 0,
                        "b2c3d4e5-2222-3333-4444-555566667777", "Syntax FM")
        ] as Array<Dictionary>);

        // Hardcore History episodes
        episodes.put("c3d4e5f6-3333-4444-5555-666677778888", [
            makeEpisode("ep-hh-001", "71: The Fall of the Republic", 14400, 7200, 2,
                        "c3d4e5f6-3333-4444-5555-666677778888", "Hardcore History"),
            makeEpisode("ep-hh-002", "70: The Celtic Holocaust", 12600, 12600, 3,
                        "c3d4e5f6-3333-4444-5555-666677778888", "Hardcore History"),
            makeEpisode("ep-hh-003", "69: Twilight of the Aesir", 16200, 0, 0,
                        "c3d4e5f6-3333-4444-5555-666677778888", "Hardcore History")
        ] as Array<Dictionary>);

        // Running with the Pack episodes
        episodes.put("d4e5f6a7-4444-5555-6666-777788889999", [
            makeEpisode("ep-rwtp-001", "Training for Your First 50K", 2400, 0, 0,
                        "d4e5f6a7-4444-5555-6666-777788889999", "Running with the Pack"),
            makeEpisode("ep-rwtp-002", "Nutrition on the Trail", 1800, 900, 2,
                        "d4e5f6a7-4444-5555-6666-777788889999", "Running with the Pack"),
            makeEpisode("ep-rwtp-003", "Gear Review: Spring 2026", 2100, 0, 0,
                        "d4e5f6a7-4444-5555-6666-777788889999", "Running with the Pack")
        ] as Array<Dictionary>);

        // Garmin Unboxed episodes
        episodes.put("e5f6a7b8-5555-6666-7777-888899990000", [
            makeEpisode("ep-gunbox-001", "Fenix 8 First Impressions", 1500, 0, 0,
                        "e5f6a7b8-5555-6666-7777-888899990000", "Garmin Unboxed"),
            makeEpisode("ep-gunbox-002", "Connect IQ App Development", 2040, 0, 0,
                        "e5f6a7b8-5555-6666-7777-888899990000", "Garmin Unboxed"),
            makeEpisode("ep-gunbox-003", "Solar Charging: Worth It?", 1680, 1680, 3,
                        "e5f6a7b8-5555-6666-7777-888899990000", "Garmin Unboxed")
        ] as Array<Dictionary>);

        return episodes;
    }

    private function buildMockQueue() as Array<Dictionary> {
        return [
            makeEpisode("ep-chlog-001", "589: AI in the Terminal", 3240, 0, 0,
                        "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog"),
            makeEpisode("ep-syntax-001", "842: CSS Container Queries", 1920, 0, 0,
                        "b2c3d4e5-2222-3333-4444-555566667777", "Syntax FM"),
            makeEpisode("ep-rwtp-002", "Nutrition on the Trail", 1800, 900, 2,
                        "d4e5f6a7-4444-5555-6666-777788889999", "Running with the Pack"),
            makeEpisode("ep-hh-001", "71: The Fall of the Republic", 14400, 7200, 2,
                        "c3d4e5f6-3333-4444-5555-666677778888", "Hardcore History"),
            makeEpisode("ep-gunbox-001", "Fenix 8 First Impressions", 1500, 0, 0,
                        "e5f6a7b8-5555-6666-7777-888899990000", "Garmin Unboxed")
        ] as Array<Dictionary>;
    }

    private function buildMockNowPlaying() as Dictionary? {
        return makeEpisode("ep-chlog-002", "588: Postgres Everywhere", 2880, 1200, 2,
                           "a1b2c3d4-1111-2222-3333-444455556666", "The Changelog");
    }

    //! Helper to build an episode Dictionary matching PocketCasts API structure
    private function makeEpisode(uuid as String, title as String, duration as Number,
                                  playedUpTo as Number, playingStatus as Number,
                                  podcastUuid as String, podcastTitle as String) as Dictionary {
        return {
            DataKeys.E_UUID => uuid,
            DataKeys.E_TITLE => title,
            DataKeys.E_DURATION => duration,
            DataKeys.E_PLAYED_UP_TO => playedUpTo,
            DataKeys.E_PLAYING_STATUS => playingStatus,
            DataKeys.E_PODCAST_UUID => podcastUuid,
            DataKeys.E_PODCAST_TITLE => podcastTitle,
            DataKeys.E_STARRED => false,
            DataKeys.E_IS_DELETED => false
        } as Dictionary;
    }
}
