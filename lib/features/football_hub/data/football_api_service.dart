// lib/features/football_hub/data/football_api_service.dart

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/config/backend_config.dart';
import '../models/football_fixture.dart';
import '../models/football_league.dart';
import '../models/football_player.dart';
import '../models/football_standing.dart';

/// Client for Football Hub's data, proxied through the Cloudflare Worker
/// (worker/src/index.js's /football/* routes) rather than calling
/// api-football.com directly -- the API key must never ship in the app,
/// and the Worker is what applies the edge caching that keeps this app
/// inside API-Football's free-tier 100 requests/day cap.
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

  Future<Map<String, dynamic>> _get(
    Uri? endpoint,
    Map<String, String> queryParams,
  ) async {
    if (endpoint == null) {
      throw StateError('Football Hub is not configured (EH_WORKER_BASE_URL missing).');
    }
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
      return data.cast<String, dynamic>();
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

  /// Fixtures for a given date (YYYY-MM-DD), optionally scoped to a league.
  Future<List<FootballFixture>> getFixturesByDate({
    required String date,
    int? leagueId,
    int? season,
  }) async {
    final params = <String, String>{'date': date};
    if (leagueId != null) params['league'] = '$leagueId';
    if (season != null) params['season'] = '$season';

    final body = await _get(BackendConfig.footballFixturesUrl(), params);
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

    final body = await _get(BackendConfig.footballFixturesUrl(), params);
    return _responseList(body).map(FootballFixture.fromJson).toList(growable: false);
  }

  Future<FootballStandingsTable?> getStandings({
    required int leagueId,
    required int season,
  }) async {
    final body = await _get(BackendConfig.footballStandingsUrl(), {
      'league': '$leagueId',
      'season': '$season',
    });
    final list = _responseList(body);
    if (list.isEmpty) return null;
    return FootballStandingsTable.fromApiResponseEntry(list.first);
  }

  Future<List<FootballLeagueInfo>> searchLeagues({String? search, String? country}) async {
    final params = <String, String>{};
    if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
    if (country != null && country.trim().isNotEmpty) params['country'] = country.trim();

    final body = await _get(BackendConfig.footballLeaguesUrl(), params);
    return _responseList(body).map(FootballLeagueInfo.fromJson).toList(growable: false);
  }

  Future<List<FootballSquadPlayer>> getSquad({required int teamId}) async {
    final body = await _get(BackendConfig.footballSquadUrl(), {'team': '$teamId'});
    final list = _responseList(body);
    if (list.isEmpty) return const [];
    final players = (list.first['players'] as List?)?.whereType<Map>().toList() ?? const [];
    return players
        .map((p) => FootballSquadPlayer.fromJson(p.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<FootballPlayerProfile?> getPlayer({required int playerId, required int season}) async {
    final body = await _get(BackendConfig.footballPlayerUrl(), {
      'id': '$playerId',
      'season': '$season',
    });
    final list = _responseList(body);
    if (list.isEmpty) return null;
    return FootballPlayerProfile.fromApiResponseEntry(list.first);
  }
}
