// lib/features/football_hub/data/football_api_service.dart

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/config/backend_config.dart';
import '../models/football_fixture.dart';
import '../models/football_league.dart';
import '../models/football_match_event.dart';
import '../models/football_news_article.dart';
import '../models/football_player.dart';
import '../models/football_standing.dart';
import 'football_cache_service.dart';

/// Client for Football Hub's data, proxied through the Cloudflare Worker
/// (worker/src/index.js's /football/* routes) rather than calling
/// api-football.com directly -- the API key must never ship in the app,
/// and the Worker is what applies the edge caching that keeps this app
/// inside API-Football's free-tier 100 requests/day cap.
///
/// Every call also goes through FootballCacheService (persisted via
/// SharedPreferences, survives app restart) with a stale-while-revalidate
/// policy: a fresh cache hit returns instantly with NO network call at
/// all; a stale hit still returns instantly but kicks off a background
/// refresh for next time; only a true cache miss blocks on the network.
/// This exists because api-football enforces a requests-per-minute cap on
/// top of its daily cap, and prior to this the app had zero client-side
/// caching -- every cold app start, and every re-tap of an
/// already-visited date in the Matches tab, was a guaranteed fresh network
/// hit regardless of how recently the same data had already been fetched.
class FootballApiService {
  FootballApiService({Dio? dio, FirebaseAuth? auth})
      : _dio = dio ?? Dio(),
        _auth = auth ?? FirebaseAuth.instance;

  final Dio _dio;
  final FirebaseAuth _auth;

  Future<String> _requireFirebaseIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in and try again.');
    }
    final raw = (await user.getIdToken()) ?? '';
    final token = raw.trim();
    if (token.isEmpty) {
      throw StateError('Authentication token unavailable. Please try again.');
    }
    return token;
  }

  String _cacheKeyFor(Uri endpoint, Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final qs = sortedKeys.map((k) => '$k=${params[k]}').join('&');
    return '${endpoint.toString()}?$qs';
  }

  Future<Map<String, dynamic>> _get(
    Uri? endpoint,
    Map<String, String> queryParams, {
    required Duration cacheTtl,
    bool forceRefresh = false,
  }) async {
    if (endpoint == null) {
      throw StateError('Football Hub is not configured (EH_WORKER_BASE_URL missing).');
    }

    final cacheKey = _cacheKeyFor(endpoint, queryParams);
    final cached = forceRefresh ? null : await FootballCacheService.instance.get(cacheKey);

    if (cached != null && cached.isFreshFor(cacheTtl)) {
      return cached.data;
    }

    if (cached != null) {
      // Stale-while-revalidate: the screen gets the stale copy instantly;
      // this refreshes the cache in the background for next time without
      // making the caller wait, and never surfaces a background error.
      unawaited(_fetchAndCache(endpoint, queryParams, cacheKey).catchError((_) => <String, dynamic>{}));
      return cached.data;
    }

    // True cache miss -- nothing to show yet, must await the real call.
    return _fetchAndCache(endpoint, queryParams, cacheKey);
  }

  Future<Map<String, dynamic>> _fetchAndCache(
    Uri endpoint,
    Map<String, String> queryParams,
    String cacheKey,
  ) async {
    final idToken = await _requireFirebaseIdToken();

    try {
      final res = await _dio
          .get<dynamic>(
            endpoint.toString(),
            queryParameters: queryParams,
            options: Options(
              headers: <String, String>{'authorization': 'Bearer $idToken'},
              responseType: ResponseType.json,
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          )
          .timeout(const Duration(seconds: 18));

      final data = res.data;
      if (data is! Map) throw StateError('Invalid response from Football Hub.');
      final body = data.cast<String, dynamic>();
      unawaited(FootballCacheService.instance.put(cacheKey, body));
      return body;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      String hint = '';
      if (data is Map) hint = (data['error'] ?? '').toString();
      hint = hint.trim().isNotEmpty ? hint.trim() : (e.message ?? 'Request failed');
      throw StateError(code != null ? 'Football Hub error ($code): $hint' : 'Football Hub error: $hint');
    } on TimeoutException {
      throw StateError('Football Hub request timed out. Please try again.');
    }
  }

  List<Map<String, dynamic>> _responseList(Map<String, dynamic> body) {
    final response = body['response'];
    if (response is! List) return const [];
    return response.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false);
  }

  // Mirrors the Worker's own per-operation edge-cache TTLs (worker/src/
  // index.js's _footballApiProxyRoute call sites) so client-side staleness
  // never outruns what the server would return fresh for anyway.
  static const _fixturesTtl = Duration(minutes: 5);
  static const _fixtureEventsTtl = Duration(minutes: 1);
  static const _standingsTtl = Duration(hours: 1);
  static const _squadTtl = Duration(days: 1);
  static const _playerTtl = Duration(hours: 6);
  static const _leaguesTtl = Duration(days: 1);
  static const _newsTtl = Duration(minutes: 30);

  /// Fixtures for a given date (YYYY-MM-DD), optionally scoped to a league.
  Future<List<FootballFixture>> getFixturesByDate({
    required String date,
    int? leagueId,
    int? season,
    bool forceRefresh = false,
  }) async {
    final params = <String, String>{'date': date};
    if (leagueId != null) params['league'] = '$leagueId';
    if (season != null) params['season'] = '$season';

    final body = await _get(
      BackendConfig.footballFixturesUrl(),
      params,
      cacheTtl: _fixturesTtl,
      forceRefresh: forceRefresh,
    );
    return _responseList(body).map(FootballFixture.fromJson).toList(growable: false);
  }

  /// A specific team's fixtures (for a team profile's "last 5"/"next match").
  Future<List<FootballFixture>> getFixturesForTeam({
    required int teamId,
    int? season,
    int? next,
    int? last,
  }) async {
    final params = <String, String>{'team': '$teamId'};
    if (season != null) params['season'] = '$season';
    if (next != null) params['next'] = '$next';
    if (last != null) params['last'] = '$last';

    final body = await _get(BackendConfig.footballFixturesUrl(), params, cacheTtl: _fixturesTtl);
    return _responseList(body).map(FootballFixture.fromJson).toList(growable: false);
  }

  Future<FootballStandingsTable?> getStandings({
    required int leagueId,
    required int season,
  }) async {
    final body = await _get(
      BackendConfig.footballStandingsUrl(),
      {'league': '$leagueId', 'season': '$season'},
      cacheTtl: _standingsTtl,
    );
    final list = _responseList(body);
    if (list.isEmpty) return null;
    return FootballStandingsTable.fromApiResponseEntry(list.first);
  }

  Future<List<FootballLeagueInfo>> searchLeagues({String? search, String? country}) async {
    final params = <String, String>{};
    if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
    if (country != null && country.trim().isNotEmpty) params['country'] = country.trim();

    final body = await _get(BackendConfig.footballLeaguesUrl(), params, cacheTtl: _leaguesTtl);
    return _responseList(body).map(FootballLeagueInfo.fromJson).toList(growable: false);
  }

  Future<List<FootballSquadPlayer>> getSquad({required int teamId}) async {
    final body = await _get(
      BackendConfig.footballSquadUrl(),
      {'team': '$teamId'},
      cacheTtl: _squadTtl,
    );
    final list = _responseList(body);
    if (list.isEmpty) return const [];
    final players = (list.first['players'] as List?)?.whereType<Map>().toList() ?? const [];
    return players
        .map((p) => FootballSquadPlayer.fromJson(p.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<FootballPlayerProfile?> getPlayer({required int playerId, required int season}) async {
    final body = await _get(
      BackendConfig.footballPlayerUrl(),
      {'id': '$playerId', 'season': '$season'},
      cacheTtl: _playerTtl,
    );
    final list = _responseList(body);
    if (list.isEmpty) return null;
    return FootballPlayerProfile.fromApiResponseEntry(list.first);
  }

  /// Fetches a single fixture by its provider id -- used only on a cold
  /// deep-link open (e.g. a future notification tap) where the caller
  /// doesn't already have the fixture in memory. In-app navigation should
  /// always prefer passing the already-fetched FootballFixture instead.
  Future<FootballFixture?> getFixtureById(int fixtureId) async {
    final body = await _get(
      BackendConfig.footballFixturesUrl(),
      {'id': '$fixtureId'},
      cacheTtl: _fixturesTtl,
    );
    final list = _responseList(body);
    if (list.isEmpty) return null;
    return FootballFixture.fromJson(list.first);
  }

  Future<List<FootballMatchEvent>> getFixtureEvents({required int fixtureId}) async {
    final body = await _get(
      BackendConfig.footballFixtureEventsUrl(),
      {'fixture': '$fixtureId'},
      cacheTtl: _fixtureEventsTtl,
    );
    return _responseList(body).map(FootballMatchEvent.fromJson).toList(growable: false);
  }

  /// Football news headlines (GNews, proxied/cached through the Worker).
  /// [query] defaults to 'football' -- pass a team/league name to narrow it.
  Future<List<FootballNewsArticle>> getFootballNews({
    String query = 'football',
    int max = 10,
    bool forceRefresh = false,
  }) async {
    final params = <String, String>{
      'q': query.trim().isEmpty ? 'football' : query.trim(),
      'max': '$max',
    };
    final body = await _get(
      BackendConfig.footballNewsUrl(),
      params,
      cacheTtl: _newsTtl,
      forceRefresh: forceRefresh,
    );
    final articles = body['articles'];
    if (articles is! List) return const [];
    return articles
        .whereType<Map>()
        .map((e) => FootballNewsArticle.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }
}
