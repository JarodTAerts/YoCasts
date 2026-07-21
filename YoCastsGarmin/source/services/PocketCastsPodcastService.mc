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
//!
//! == Proxy Architecture ==
//! Login goes DIRECT to api.pocketcasts.com — we need to get the token.
//! All other API calls route through an Azure Function proxy (PROXY_BASE)
//! that strips heavy fields (description, descriptionHtml, etc.) to keep
//! responses under the Garmin CIQ ~32KB limit. The proxy forwards the
//! Bearer token as-is — no credentials are stored server-side.
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
    private var _loading as Boolean = false;
    private var _lastError as String = "";
    private var _podcastsLoaded as Boolean = false;
    private var _queueLoaded as Boolean = false;
    private var _changeSync as PocketCastsChangeSync?;
    private var _fetchAfterChangeSync as Boolean = false;

    // ---- Queue Enrichment Pipeline State ----
    private var _queueEnrichIndex as Number = 0;
    private var _queueEnrichRetried as Boolean = false;

    // ---- Token Refresh Serialization ----
    // Prevents concurrent token-refresh + API request (CIQ -402 race condition).
    // When a refresh is in-flight, the API call is queued and replayed after
    // the refresh completes with the new token.
    private var _tokenRefreshInProgress as Boolean = false;
    private var _loginInProgress as Boolean = false;
    private var _syncAfterAuth as Boolean = false;
    private var _pendingRequestPath as String = "";
    private var _pendingRequestBody as Dictionary<Object, Object>? = null;
    private var _pendingRequestCallback as Method? = null;

    // ---- Episode Fetch Pipeline State ----
    private var _pendingEpPodcastUuid as String = "";
    private var _episodeFetchBusy as Boolean = false;
    private var _episodeRetried as Boolean = false;
    private var _episodeDetails as Dictionary = {} as Dictionary;
    private var _pendingDetailUuid as String = "";
    private var _queuedDetailUuid as String = "";

    // ---- Constants ----
    // Direct PocketCasts API — used ONLY for login and token refresh
    private const API_BASE = "https://api.pocketcasts.com";
    // Azure Function proxy — strips large fields to stay under CIQ ~32KB limit.
    // Update this URL after deploying the Azure Function.
    // For local testing: "http://localhost:7071/api/pocketcasts"
    // For Azure:         "https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts"
    private const PROXY_BASE = "https://yocasts-proxy-personal.azurewebsites.net/api/pocketcasts";
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

    function getAccessToken() as String {
        return _accessToken;
    }

    function isDataReady() as Boolean {
        return _dataReady;
    }

    function isLoading() as Boolean {
        return _loading;
    }

    function getLastError() as String {
        return _lastError;
    }

    function hasLoadedPodcasts() as Boolean {
        return _podcastsLoaded;
    }

    function hasLoadedQueue() as Boolean {
        return _queueLoaded;
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

    function hasEpisodesForPodcast(podcastUuid as String) as Boolean {
        return _episodes.hasKey(podcastUuid);
    }

    function getQueue() as Array<Dictionary> {
        return _queue;
    }

    function getNowPlaying() as Dictionary? {
        return _nowPlaying;
    }

    function getEpisodeDetails(episodeUuid as String) as Dictionary? {
        var details = _episodeDetails.get(episodeUuid);
        return (details != null && details instanceof Dictionary)
            ? details as Dictionary : null;
    }

    // ================================================================
    // IPodcastService — async triggers
    // ================================================================

    //! Start the full data pipeline: login → podcasts → queue → enrich
    function fetchAll() as Void {
        System.println("YoCasts: fetchAll() — starting login");
        _loading = true;
        _dataReady = false;
        _lastError = "";
        _podcastsLoaded = false;
        _queueLoaded = false;
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
            "/yocasts/podcast/episodes",
            { "uuid" => podcastUuid },
            method(:onEpisodeListResponse)
        );
    }

    function requestEpisodeDetails(episodeUuid as String) as Void {
        if (!_authenticated) {
            _queuedDetailUuid = episodeUuid;
            _login();
            return;
        }
        if (_pendingDetailUuid.length() > 0) {
            if (!_pendingDetailUuid.equals(episodeUuid)) {
                _queuedDetailUuid = episodeUuid;
            }
            return;
        }
        _pendingDetailUuid = episodeUuid;
        System.println(
            "YoCasts: fetching extended episode details " + episodeUuid
        );
        _makeAuthPost(
            "/yocasts/episode/details",
            { "uuid" => episodeUuid },
            method(:onExtendedEpisodeResponse)
        );
    }

    function onExtendedEpisodeResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        var uuid = _pendingDetailUuid;
        _pendingDetailUuid = "";
        var nextUuid = _queuedDetailUuid;
        _queuedDetailUuid = "";
        System.println(
            "YoCasts: extended episode response " + responseCode
        );
        if (responseCode == 200 && data != null &&
            data instanceof Dictionary && uuid.length() > 0) {
            var details = _transformEpisodeDetail(
                data as Dictionary,
                uuid,
                ""
            );
            _episodeDetails.put(uuid, details);
            WatchUi.requestUpdate();
        }
        if (nextUuid.length() > 0 && !nextUuid.equals(uuid)) {
            requestEpisodeDetails(nextUuid);
        }
    }

    // ================================================================
    // Auth — Login
    // ================================================================

    private function _login() as Void {
        if (_loginInProgress) { return; }
        _loginInProgress = true;
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
        _loginInProgress = false;
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

                if (_pendingRequestCallback != null) {
                    _replayPendingRequest();
                } else if (_syncAfterAuth) {
                    _syncAfterAuth = false;
                    _syncPendingChanges(false);
                } else {
                    _syncPendingChanges(true);
                }
            } else {
                System.println("YoCasts: login response missing expected fields");
                _lastError = "Invalid login response";
                _clearPendingRequest();
                _markDataReady();
            }
        } else {
            System.println("YoCasts: login FAILED — HTTP " + responseCode);
            _lastError = "Pocket Casts login failed";
            _clearPendingRequest();
            _markDataReady();
        }
    }

    // ================================================================
    // Cached mutation sync
    // ================================================================

    function syncPendingChanges() as Void {
        if (_changeSync != null || ChangeLog.getEntryCount() == 0 ||
            _episodeFetchBusy || _pendingDetailUuid.length() > 0 ||
            _queueEnrichIndex < _queue.size()) {
            return;
        }
        if (!_authenticated) {
            _syncAfterAuth = true;
            _login();
            return;
        }
        if (_tokenRefreshInProgress) {
            _syncAfterAuth = true;
            return;
        }
        if (_isTokenExpiringSoon()) {
            _syncAfterAuth = true;
            _doTokenRefresh();
            return;
        }
        _syncPendingChanges(false);
    }

    private function _syncPendingChanges(fetchAfter as Boolean) as Void {
        _fetchAfterChangeSync = fetchAfter;
        if (ChangeLog.getEntryCount() == 0) {
            if (fetchAfter) { _fetchPodcasts(); }
            return;
        }

        System.println("YoCasts: syncing cached playback/queue changes");
        _changeSync = new PocketCastsChangeSync(
            _accessToken,
            method(:onPendingChangesSynced)
        );
        (_changeSync as PocketCastsChangeSync).start();
    }

    function onPendingChangesSynced(failures as Number) as Void {
        var authenticationFailed = _changeSync != null &&
            (_changeSync as PocketCastsChangeSync)
                .hadAuthenticationFailure();
        _changeSync = null;
        if (authenticationFailed) {
            _authenticated = false;
            _syncAfterAuth = true;
            _login();
            return;
        }
        if (failures > 0) {
            System.println(
                "YoCasts: " + failures + " cached changes remain pending"
            );
        }
        if (_fetchAfterChangeSync) {
            _fetchAfterChangeSync = false;
            _fetchPodcasts();
        } else {
            WatchUi.requestUpdate();
            _startQueuedDetailIfIdle();
        }
    }

    // ================================================================
    // Auth — Token Refresh
    // ================================================================

    private function _isTokenExpiringSoon() as Boolean {
        return (Time.now().value() > (_tokenExpiresAt - TOKEN_REFRESH_BUFFER));
    }

    private function _doTokenRefresh() as Void {
        _tokenRefreshInProgress = true;
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
        _tokenRefreshInProgress = false;

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
                if (_pendingRequestCallback != null) {
                    _replayPendingRequest();
                } else if (_syncAfterAuth) {
                    _syncAfterAuth = false;
                    _syncPendingChanges(false);
                }
                return;
            } else {
                _authenticated = false;
                System.println("YoCasts: token refresh response missing fields");
            }
        } else {
            _authenticated = false;
            System.println("YoCasts: token refresh FAILED — HTTP " + responseCode);
        }

        _accessToken = "";
        _refreshToken = "";
        _tokenExpiresAt = 0;
        _login();
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
                if (arr.size() > 0) {
                    System.println("YoCasts: raw podcast[0] keys: " + (arr[0] as Dictionary).keys().toString());
                }
                _podcasts = [] as Array<Dictionary>;
                var limit = arr.size() < MAX_PODCASTS ? arr.size() : MAX_PODCASTS;
                for (var i = 0; i < limit; i++) {
                    var p = arr[i] as Dictionary;
                    _podcasts.add(_transformPodcast(p));
                }
                System.println("YoCasts: loaded " + _podcasts.size() + " podcasts");
            }
            _podcastsLoaded = true;
            WatchUi.requestUpdate();

            // Chain → fetch queue
            _fetchQueue();
        } else if (responseCode == 401) {
            System.println("YoCasts: podcast list 401 — re-authenticating");
            _authenticated = false;
            _login();
        } else {
            System.println("YoCasts: podcast list FAILED — HTTP " + responseCode);
            _lastError = "Could not load podcasts";
            // Continue to queue fetch so UI isn't stuck
            _fetchQueue();
        }
    }

    //! Map API podcast dict → DataKeys-keyed dict
    private function _transformPodcast(p as Dictionary) as Dictionary {
        var artColorStr = _strOr(p.get("artColor"), "");
        var artTintStr = _strOr(p.get("artTint"), "");
        var artColor = artColorStr.length() >= 7 ? DataFormat.parseHexColor(artColorStr) : 0x333333;
        var artTint = artTintStr.length() >= 7 ? DataFormat.parseHexColor(artTintStr) : 0xAAAAAA;
        var title = _strOr(p.get("title"), "Untitled");
        System.println("YoCasts: _transformPodcast '" + title + "' artColorStr='" + artColorStr + "' parsed=0x" + artColor.format("%06X") + " artTintStr='" + artTintStr + "' parsed=0x" + artTint.format("%06X"));
        return {
            DataKeys.P_UUID => _strOr(p.get("uuid"), ""),
            DataKeys.P_TITLE => _strOr(p.get("title"), "Untitled"),
            DataKeys.P_AUTHOR => _strOr(p.get("author"), ""),
            DataKeys.P_DESCRIPTION => _strOr(p.get("description"), ""),
            DataKeys.P_LAST_EPISODE => _strOr(p.get("lastEpisodePublished"), ""),
            DataKeys.P_LAST_EPISODE_UUID => _strOr(p.get("lastEpisodeUuid"), ""),
            DataKeys.P_ART_COLOR => artColor,
            DataKeys.P_ART_TINT => artTint,
            DataKeys.P_ART_URL => _strOr(p.get("artUrl"), "")
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
                            DataKeys.E_IS_DELETED => false,
                            DataKeys.E_SUMMARY => "",
                            DataKeys.E_PUBLISHED => "",
                            DataKeys.E_URL => "",
                            DataKeys.E_FILE_TYPE => "",
                            DataKeys.E_SIZE => ""
                        } as Dictionary);
                    }
                }
            }

            if (_queue.size() > 0) {
                _nowPlaying = _queue[0];
            }

            System.println("YoCasts: loaded " + _queue.size() + " queue items");
            _queueLoaded = true;
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
            _lastError = "Could not load Up Next";
            _markDataReady();
            _startQueuedDetailIfIdle();
        }
    }

    // ================================================================
    // Queue Enrichment — fetch /user/episode for each queue item
    // ================================================================

    private function _enrichNextQueueItem() as Void {
        if (_queueEnrichIndex >= _queue.size()) {
            System.println("YoCasts: queue enrichment complete");
            CacheManager.saveQueue(_queue);
            var added = AutoSyncManager.reconcileQueue(_queue, true);
            if (added > 0) {
                System.println(
                    "YoCasts: auto-queued " + added + " Up Next episodes"
                );
            }
            _startQueuedDetailIfIdle();
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
            _queueEnrichRetried = false;
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
                ep.put(
                    DataKeys.E_SUMMARY,
                    _strOr(d.get("summary"), "")
                );
                ep.put(
                    DataKeys.E_PUBLISHED,
                    _strOr(d.get("published"), "")
                );
                ep.put(DataKeys.E_URL, _strOr(d.get("url"), ""));
                ep.put(
                    DataKeys.E_FILE_TYPE,
                    _strOr(d.get("fileType"), "")
                );
                ep.put(DataKeys.E_SIZE, _strOr(d.get("size"), ""));
                // Update now playing if first queue item
                if (_queueEnrichIndex == 0) {
                    _nowPlaying = ep;
                }
            }
        } else if (responseCode == 401) {
            if (!_queueEnrichRetried &&
                _queueEnrichIndex < _queue.size()) {
                _queueEnrichRetried = true;
                var retryEpisode =
                    _queue[_queueEnrichIndex] as Dictionary;
                var retryUuid = retryEpisode.get(DataKeys.E_UUID) as String;
                _pendingRequestPath = "/user/episode";
                _pendingRequestBody = {
                    "uuid" => retryUuid
                } as Dictionary<Object, Object>;
                _pendingRequestCallback = method(:onQueueEnrichResponse);
                if (_refreshToken.length() > 0) {
                    _doTokenRefresh();
                } else {
                    _authenticated = false;
                    _login();
                }
                return;
            }
            _queueEnrichRetried = false;
            System.println(
                "YoCasts: queue enrich authentication retry failed"
            );
        } else if (responseCode == -402) {
            System.println(
                "YoCasts: queue enrich response too large; skipping item"
            );
        } else {
            System.println("YoCasts: queue enrich failed for item " + _queueEnrichIndex + " — HTTP " + responseCode);
        }

        _queueEnrichRetried = false;
        _queueEnrichIndex++;
        _enrichNextQueueItem();
    }

    // ================================================================
    // Episode List Fetch (server-capped and enriched by the proxy)
    // ================================================================

    //! @hide
    function onEpisodeListResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var raw = dict.get("episodes");
            if (raw != null && raw instanceof Array) {
                var arr = raw as Array;
                var details = [] as Array<Dictionary>;
                var limit = arr.size() < MAX_EPISODES
                    ? arr.size() : MAX_EPISODES;
                for (var i = 0; i < limit; i++) {
                    var episode = arr[i] as Dictionary;
                    details.add(_transformEpisodeDetail(
                        episode,
                        _strOr(episode.get("uuid"), ""),
                        _pendingEpPodcastUuid
                    ));
                }
                _episodes.put(_pendingEpPodcastUuid, details);
                _episodeFetchBusy = false;
                _episodeRetried = false;
                System.println(
                    "YoCasts: loaded " + details.size() +
                    " compact episode details"
                );
                WatchUi.requestUpdate();
                return;
            }
        }
        // Fetch failed
        _episodeFetchBusy = false;
        if (responseCode == 401) {
            if (!_episodeRetried) {
                System.println("YoCasts: episode list 401 — retrying with refreshed token");
                _episodeRetried = true;
                _episodeFetchBusy = true;
                _pendingRequestPath = "/yocasts/podcast/episodes";
                _pendingRequestBody = {
                    "uuid" => _pendingEpPodcastUuid
                } as Dictionary<Object, Object>;
                _pendingRequestCallback = method(:onEpisodeListResponse);
                if (_refreshToken.length() > 0) {
                    _doTokenRefresh();
                } else {
                    _authenticated = false;
                    _login();
                }
                return;
            }
            _episodeRetried = false;
            System.println("YoCasts: episode list 401 — retry also failed, giving up");
        } else if (responseCode == -402) {
            System.println(
                "YoCasts: compact episode response exceeded device limit"
            );
            _lastError = "Episode response too large";
        } else {
            System.println("YoCasts: episode list FAILED — HTTP " + responseCode);
            _lastError = "Could not load episodes";
        }
    }

    // ================================================================
    // Helpers
    // ================================================================

    //! Make an authenticated POST request through the Azure proxy with Bearer token.
    //! All data-fetching calls go through the proxy; login/token refresh go direct.
    //!
    //! Token refresh serialization: if a refresh is needed, the API request is
    //! queued and deferred until the refresh completes. This prevents concurrent
    //! makeWebRequest() calls that trigger CIQ -402 (NETWORK_RESPONSE_TOO_LARGE).
    private function _makeAuthPost(path as String, body as Dictionary<Object, Object>,
                                    callback as Method(responseCode as Number, data as Dictionary or String or Null) as Void) as Void {
        // If a token refresh is already in-flight, queue this request
        if (_tokenRefreshInProgress) {
            System.println("YoCasts: token refresh in progress — queueing " + path);
            _pendingRequestPath = path;
            _pendingRequestBody = body;
            _pendingRequestCallback = callback;
            return;
        }

        // Proactive token refresh — defer the API call until refresh completes
        if (_isTokenExpiringSoon()) {
            System.println("YoCasts: token expiring soon — deferring " + path + " until refresh");
            _pendingRequestPath = path;
            _pendingRequestBody = body;
            _pendingRequestCallback = callback;
            _doTokenRefresh();
            return;
        }

        Communications.makeWebRequest(
            PROXY_BASE + path,
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

    //! Replay a queued API request after token refresh completes.
    //! If no request is queued, this is a no-op.
    private function _replayPendingRequest() as Void {
        if (_pendingRequestCallback == null) {
            return;
        }
        var path = _pendingRequestPath;
        var body = _pendingRequestBody as Dictionary<Object, Object>;
        var cb = _pendingRequestCallback as Method(responseCode as Number, data as Dictionary or String or Null) as Void;

        // Clear queued state before firing to avoid infinite loops
        _pendingRequestPath = "";
        _pendingRequestBody = null;
        _pendingRequestCallback = null;

        System.println("YoCasts: replaying deferred request " + path);
        _makeAuthPost(path, body, cb);
    }

    private function _clearPendingRequest() as Void {
        _pendingRequestPath = "";
        _pendingRequestBody = null;
        _pendingRequestCallback = null;
    }

    private function _startQueuedDetailIfIdle() as Void {
        if (!_authenticated || _pendingDetailUuid.length() > 0 ||
            _queuedDetailUuid.length() == 0) {
            return;
        }
        var nextUuid = _queuedDetailUuid;
        _queuedDetailUuid = "";
        requestEpisodeDetails(nextUuid);
    }

    //! Mark data as ready and request UI update
    private function _markDataReady() as Void {
        _dataReady = true;
        _loading = false;
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

    private function _transformEpisodeDetail(
        data as Dictionary,
        fallbackUuid as String,
        podcastUuid as String
    ) as Dictionary {
        var actualPodcastUuid = podcastUuid.length() > 0
            ? podcastUuid
            : _strOr(data.get("podcastUuid"), "");
        return {
            DataKeys.E_UUID =>
                _strOr(data.get("uuid"), fallbackUuid),
            DataKeys.E_TITLE =>
                _strOr(data.get("title"), "Episode"),
            DataKeys.E_DURATION =>
                (data.get("duration") != null &&
                 data.get("duration") instanceof Number)
                    ? data.get("duration") as Number : 0,
            DataKeys.E_PLAYED_UP_TO =>
                (data.get("playedUpTo") != null &&
                 data.get("playedUpTo") instanceof Number)
                    ? data.get("playedUpTo") as Number : 0,
            DataKeys.E_PLAYING_STATUS =>
                (data.get("playingStatus") != null &&
                 data.get("playingStatus") instanceof Number)
                    ? data.get("playingStatus") as Number
                    : DataKeys.STATUS_NOT_PLAYED,
            DataKeys.E_PODCAST_UUID => actualPodcastUuid,
            DataKeys.E_PODCAST_TITLE =>
                _strOr(
                    data.get("podcastTitle"),
                    _lookupPodcastTitle(actualPodcastUuid)
                ),
            DataKeys.E_STARRED =>
                (data.get("starred") != null &&
                 data.get("starred") instanceof Boolean)
                    ? data.get("starred") as Boolean : false,
            DataKeys.E_IS_DELETED =>
                (data.get("isDeleted") != null &&
                 data.get("isDeleted") instanceof Boolean)
                    ? data.get("isDeleted") as Boolean : false,
            DataKeys.E_SUMMARY => _strOr(data.get("summary"), ""),
            DataKeys.E_PUBLISHED => _strOr(data.get("published"), ""),
            DataKeys.E_URL => _strOr(data.get("url"), ""),
            DataKeys.E_FILE_TYPE => _strOr(data.get("fileType"), ""),
            DataKeys.E_SIZE => _strOr(data.get("size"), "")
        } as Dictionary;
    }
}
