import Toybox.Lang;
import Toybox.Communications;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.System;

//! Real PocketCasts API service. Authenticates via the modern
//! /user/login_pocket_casts endpoint and fetches data through
//! the phone companion via Communications.makeWebRequest().
//!
//! Data pipeline: login → fetch podcasts → fetch queue → enrich queue items.
//! Each stage is async; when a stage completes it chains into the next.
//! Views use synchronous getters that return cached data; the service
//! calls WatchUi.requestUpdate() whenever the cache is refreshed.
class PocketCastsPodcastService extends IPodcastService {

    // ---- Auth State ----
    private var _email as String;
    private var _password as String;
    private var _accessToken as String = "";
    private var _refreshToken as String = "";
    private var _tokenExpiresAt as Number = 0;
    private var _authenticated as Boolean = false;

    // ---- Cached Data ----
    private var _podcasts as Array<Dictionary> = [] as Array<Dictionary>;
    private var _queue as Array<Dictionary> = [] as Array<Dictionary>;
    private var _episodes as Dictionary = {} as Dictionary;
    private var _nowPlaying as Dictionary? = null;
    private var _dataReady as Boolean = false;

    // ---- Queue Enrichment Pipeline State ----
    private var _queueEnrichIndex as Number = 0;

    // ---- Episode Fetch Pipeline State ----
    private var _pendingEpPodcastUuid as String = "";
    private var _pendingEpUserState as Array<Dictionary> = [] as Array<Dictionary>;
    private var _pendingEpDetails as Array<Dictionary> = [] as Array<Dictionary>;
    private var _pendingEpIndex as Number = 0;
    private var _episodeFetchBusy as Boolean = false;

    // ---- Constants ----
    private const API_BASE = "https://api.pocketcasts.com";
    private const TOKEN_REFRESH_BUFFER = 300; // refresh 5 min before expiry
    private const MAX_PODCASTS = 30;
    private const MAX_QUEUE = 20;
    private const MAX_EPISODES = 15;

    function initialize(email as String, password as String) {
        IPodcastService.initialize();
        _email = email;
        _password = password;
        System.println("YoCasts: PocketCastsPodcastService created");
    }

    // ================================================================
    // IPodcastService — status
    // ================================================================

    function isAuthenticated() as Boolean {
        return _authenticated;
    }

    function isDataReady() as Boolean {
        return _dataReady;
    }

    // ================================================================
    // IPodcastService — synchronous cache getters
    // ================================================================

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

    // ================================================================
    // IPodcastService — async triggers
    // ================================================================

    //! Start the full data pipeline: login → podcasts → queue → enrich
    function fetchAll() as Void {
        System.println("YoCasts: fetchAll() — starting login");
        _login();
    }

    //! Fetch episodes for a specific podcast (on-demand, user navigated).
    //! Chains: /user/podcast/episodes → /user/episode per item.
    function requestEpisodesForPodcast(podcastUuid as String) as Void {
        if (!_authenticated || _episodeFetchBusy) {
            System.println("YoCasts: requestEpisodes skipped (auth=" + _authenticated + " busy=" + _episodeFetchBusy + ")");
            return;
        }
        System.println("YoCasts: fetching episodes for podcast " + podcastUuid);
        _episodeFetchBusy = true;
        _pendingEpPodcastUuid = podcastUuid;
        _makeAuthPost(
            "/user/podcast/episodes",
            { "uuid" => podcastUuid },
            method(:onEpisodeListResponse)
        );
    }

    // ================================================================
    // Auth — Login
    // ================================================================

    private function _login() as Void {
        System.println("YoCasts: POST /user/login_pocket_casts");
        Communications.makeWebRequest(
            API_BASE + "/user/login_pocket_casts",
            {
                "email" => _email,
                "password" => _password,
                "scope" => "webplayer"
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onLoginResponse)
        );
    }

    //! @hide (public only because makeWebRequest requires it)
    function onLoginResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var at = dict.get("accessToken");
            var rt = dict.get("refreshToken");
            var ei = dict.get("expiresIn");
            if (at != null && at instanceof String &&
                rt != null && rt instanceof String &&
                ei != null) {
                _accessToken = at as String;
                _refreshToken = rt as String;
                _tokenExpiresAt = Time.now().value() + (ei as Number);
                _authenticated = true;
                System.println("YoCasts: login SUCCESS — token expires in " + ei + "s");

                // Chain → fetch podcasts
                _fetchPodcasts();
            } else {
                System.println("YoCasts: login response missing expected fields");
                _markDataReady();
            }
        } else {
            System.println("YoCasts: login FAILED — HTTP " + responseCode);
            _markDataReady();
        }
    }

    // ================================================================
    // Auth — Token Refresh
    // ================================================================

    private function _isTokenExpiringSoon() as Boolean {
        return (Time.now().value() > (_tokenExpiresAt - TOKEN_REFRESH_BUFFER));
    }

    private function _doTokenRefresh() as Void {
        System.println("YoCasts: POST /user/token (refresh)");
        Communications.makeWebRequest(
            API_BASE + "/user/token",
            {
                "grantType" => "refresh_token",
                "refreshToken" => _refreshToken
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onRefreshResponse)
        );
    }

    //! @hide
    function onRefreshResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var at = dict.get("accessToken");
            var rt = dict.get("refreshToken");
            var ei = dict.get("expiresIn");
            if (at != null && at instanceof String &&
                rt != null && rt instanceof String &&
                ei != null) {
                _accessToken = at as String;
                _refreshToken = rt as String;
                _tokenExpiresAt = Time.now().value() + (ei as Number);
                System.println("YoCasts: token refresh SUCCESS");
            } else {
                _authenticated = false;
                System.println("YoCasts: token refresh response missing fields, will re-login");
            }
        } else {
            // Refresh failed — force re-login on next request
            _authenticated = false;
            System.println("YoCasts: token refresh FAILED — HTTP " + responseCode + ", will re-login");
        }
    }

    // ================================================================
    // Fetch Podcasts
    // ================================================================

    private function _fetchPodcasts() as Void {
        System.println("YoCasts: POST /user/podcast/list");
        _makeAuthPost("/user/podcast/list", {}, method(:onPodcastsResponse));
    }

    //! @hide
    function onPodcastsResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var raw = dict.get("podcasts");
            if (raw != null && raw instanceof Array) {
                var arr = raw as Array;
                _podcasts = [] as Array<Dictionary>;
                var limit = arr.size() < MAX_PODCASTS ? arr.size() : MAX_PODCASTS;
                for (var i = 0; i < limit; i++) {
                    var p = arr[i] as Dictionary;
                    _podcasts.add(_transformPodcast(p));
                }
                System.println("YoCasts: loaded " + _podcasts.size() + " podcasts");
            }
            WatchUi.requestUpdate();

            // Chain → fetch queue
            _fetchQueue();
        } else if (responseCode == 401) {
            System.println("YoCasts: podcast list 401 — re-authenticating");
            _authenticated = false;
            _login();
        } else {
            System.println("YoCasts: podcast list FAILED — HTTP " + responseCode);
            // Continue to queue fetch so UI isn't stuck
            _fetchQueue();
        }
    }

    //! Map API podcast dict → DataKeys-keyed dict
    private function _transformPodcast(p as Dictionary) as Dictionary {
        return {
            DataKeys.P_UUID => _strOr(p.get("uuid"), ""),
            DataKeys.P_TITLE => _strOr(p.get("title"), "Untitled"),
            DataKeys.P_AUTHOR => _strOr(p.get("author"), ""),
            DataKeys.P_DESCRIPTION => _strOr(p.get("description"), ""),
            DataKeys.P_LAST_EPISODE => _strOr(p.get("lastEpisodePublished"), ""),
            DataKeys.P_LAST_EPISODE_UUID => _strOr(p.get("lastEpisodeUuid"), "")
        } as Dictionary;
    }

    // ================================================================
    // Fetch Queue
    // ================================================================

    private function _fetchQueue() as Void {
        System.println("YoCasts: POST /up_next/list");
        _makeAuthPost("/up_next/list", {}, method(:onQueueResponse));
    }

    //! @hide
    function onQueueResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var order = dict.get("order");
            var episodesMap = dict.get("episodes");

            _queue = [] as Array<Dictionary>;

            if (order != null && order instanceof Array &&
                episodesMap != null && episodesMap instanceof Dictionary) {
                var orderArr = order as Array;
                var epsMap = episodesMap as Dictionary;
                var limit = orderArr.size() < MAX_QUEUE ? orderArr.size() : MAX_QUEUE;

                for (var i = 0; i < limit; i++) {
                    var uuid = orderArr[i] as String;
                    var epRaw = epsMap.get(uuid);
                    if (epRaw != null && epRaw instanceof Dictionary) {
                        var ep = epRaw as Dictionary;
                        var podUuid = _strOr(ep.get("podcast"), "");
                        _queue.add({
                            DataKeys.E_UUID => uuid,
                            DataKeys.E_TITLE => _strOr(ep.get("title"), "Unknown"),
                            DataKeys.E_DURATION => 0,
                            DataKeys.E_PLAYED_UP_TO => 0,
                            DataKeys.E_PLAYING_STATUS => DataKeys.STATUS_NOT_PLAYED,
                            DataKeys.E_PODCAST_UUID => podUuid,
                            DataKeys.E_PODCAST_TITLE => _lookupPodcastTitle(podUuid),
                            DataKeys.E_STARRED => false,
                            DataKeys.E_IS_DELETED => false
                        } as Dictionary);
                    }
                }
            }

            if (_queue.size() > 0) {
                _nowPlaying = _queue[0];
            }

            System.println("YoCasts: loaded " + _queue.size() + " queue items");
            _markDataReady();

            // Chain → enrich queue items with duration/progress
            _queueEnrichIndex = 0;
            _enrichNextQueueItem();
        } else if (responseCode == 401) {
            System.println("YoCasts: queue 401 — re-authenticating");
            _authenticated = false;
            _login();
        } else {
            // Queue fetch failed — mark ready anyway so UI isn't stuck
            System.println("YoCasts: queue fetch FAILED — HTTP " + responseCode);
            _markDataReady();
        }
    }

    // ================================================================
    // Queue Enrichment — fetch /user/episode for each queue item
    // ================================================================

    private function _enrichNextQueueItem() as Void {
        if (_queueEnrichIndex >= _queue.size()) {
            System.println("YoCasts: queue enrichment complete");
            WatchUi.requestUpdate();
            return;
        }
        var ep = _queue[_queueEnrichIndex] as Dictionary;
        var uuid = ep.get(DataKeys.E_UUID) as String;
        _makeAuthPost("/user/episode", { "uuid" => uuid }, method(:onQueueEnrichResponse));
    }

    //! @hide
    function onQueueEnrichResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var d = data as Dictionary;
            if (_queueEnrichIndex < _queue.size()) {
                var ep = _queue[_queueEnrichIndex] as Dictionary;
                if (d.get("duration") != null) {
                    ep.put(DataKeys.E_DURATION, d.get("duration") as Number);
                }
                if (d.get("playedUpTo") != null) {
                    ep.put(DataKeys.E_PLAYED_UP_TO, d.get("playedUpTo") as Number);
                }
                if (d.get("playingStatus") != null) {
                    ep.put(DataKeys.E_PLAYING_STATUS, d.get("playingStatus") as Number);
                }
                if (d.get("title") != null) {
                    ep.put(DataKeys.E_TITLE, d.get("title") as String);
                }
                if (d.get("podcastTitle") != null) {
                    ep.put(DataKeys.E_PODCAST_TITLE, d.get("podcastTitle") as String);
                }
                if (d.get("starred") != null) {
                    ep.put(DataKeys.E_STARRED, d.get("starred") as Boolean);
                }
                // Update now playing if first queue item
                if (_queueEnrichIndex == 0) {
                    _nowPlaying = ep;
                }
            }
        } else if (responseCode == 401) {
            System.println("YoCasts: queue enrich 401 — stopping enrichment");
            WatchUi.requestUpdate();
            return;
        } else {
            System.println("YoCasts: queue enrich failed for item " + _queueEnrichIndex + " — HTTP " + responseCode);
        }

        _queueEnrichIndex++;
        _enrichNextQueueItem();
    }

    // ================================================================
    // Episode List Fetch (on-demand, two-stage pipeline)
    // Stage 1: /user/podcast/episodes → lightweight list (no titles)
    // Stage 2: /user/episode per item → full metadata
    // ================================================================

    //! @hide
    function onEpisodeListResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var raw = dict.get("episodes");
            if (raw != null && raw instanceof Array) {
                var arr = raw as Array;
                _pendingEpUserState = [] as Array<Dictionary>;
                var limit = arr.size() < MAX_EPISODES ? arr.size() : MAX_EPISODES;
                for (var i = 0; i < limit; i++) {
                    _pendingEpUserState.add(arr[i] as Dictionary);
                }
                System.println("YoCasts: episode list returned " + _pendingEpUserState.size() + " items, fetching details");

                _pendingEpDetails = [] as Array<Dictionary>;
                _pendingEpIndex = 0;
                _fetchNextEpisodeDetail();
                return;
            }
        }
        // Fetch failed
        _episodeFetchBusy = false;
        if (responseCode == 401) {
            System.println("YoCasts: episode list 401 — token may be expired");
        } else {
            System.println("YoCasts: episode list FAILED — HTTP " + responseCode);
        }
    }

    private function _fetchNextEpisodeDetail() as Void {
        if (_pendingEpIndex >= _pendingEpUserState.size()) {
            // All details fetched — cache and notify
            _episodes.put(_pendingEpPodcastUuid, _pendingEpDetails);
            _episodeFetchBusy = false;
            WatchUi.requestUpdate();
            return;
        }
        var st = _pendingEpUserState[_pendingEpIndex] as Dictionary;
        var uuid = _strOr(st.get("uuid"), "");
        if (uuid.equals("")) {
            _pendingEpIndex++;
            _fetchNextEpisodeDetail();
            return;
        }
        _makeAuthPost("/user/episode", { "uuid" => uuid }, method(:onEpisodeDetailResponse));
    }

    //! @hide
    function onEpisodeDetailResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var d = data as Dictionary;
            var userState = _pendingEpUserState[_pendingEpIndex] as Dictionary;
            _pendingEpDetails.add({
                DataKeys.E_UUID => _strOr(d.get("uuid"), _strOr(userState.get("uuid"), "")),
                DataKeys.E_TITLE => _strOr(d.get("title"), "Episode"),
                DataKeys.E_DURATION => d.get("duration") != null ? d.get("duration") as Number : 0,
                DataKeys.E_PLAYED_UP_TO => userState.get("playedUpTo") != null ? userState.get("playedUpTo") as Number : 0,
                DataKeys.E_PLAYING_STATUS => userState.get("playingStatus") != null ? userState.get("playingStatus") as Number : 0,
                DataKeys.E_PODCAST_UUID => _pendingEpPodcastUuid,
                DataKeys.E_PODCAST_TITLE => _lookupPodcastTitle(_pendingEpPodcastUuid),
                DataKeys.E_STARRED => userState.get("starred") != null ? userState.get("starred") as Boolean : false,
                DataKeys.E_IS_DELETED => userState.get("isDeleted") != null ? userState.get("isDeleted") as Boolean : false
            } as Dictionary);
        } else if (responseCode == 401) {
            System.println("YoCasts: episode detail 401 — stopping fetch pipeline");
            // Save what we have so far
            if (_pendingEpDetails.size() > 0) {
                _episodes.put(_pendingEpPodcastUuid, _pendingEpDetails);
            }
            _episodeFetchBusy = false;
            WatchUi.requestUpdate();
            return;
        }

        _pendingEpIndex++;
        _fetchNextEpisodeDetail();
    }

    // ================================================================
    // Helpers
    // ================================================================

    //! Make an authenticated POST request with Bearer token
    private function _makeAuthPost(path as String, body as Dictionary<Object, Object>,
                                    callback as Method(responseCode as Number, data as Dictionary or String or Null) as Void) as Void {
        // Proactive token refresh
        if (_isTokenExpiringSoon()) {
            _doTokenRefresh();
        }

        Communications.makeWebRequest(
            API_BASE + path,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + _accessToken
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            callback
        );
    }

    //! Mark data as ready and request UI update
    private function _markDataReady() as Void {
        _dataReady = true;
        WatchUi.requestUpdate();
    }

    //! Look up podcast title from cached podcasts by UUID
    private function _lookupPodcastTitle(podcastUuid as String) as String {
        for (var i = 0; i < _podcasts.size(); i++) {
            var p = _podcasts[i] as Dictionary;
            if (podcastUuid.equals(p.get(DataKeys.P_UUID) as String)) {
                return p.get(DataKeys.P_TITLE) as String;
            }
        }
        return "";
    }

    //! Safe string extraction — returns fallback if value is null
    private function _strOr(val as Object?, fallback as String) as String {
        if (val != null && val instanceof String) {
            return val as String;
        }
        return fallback;
    }
}
