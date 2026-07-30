// lib/features/profile/data/player_photo_service.dart
//
// Free-tier player photo lookup + Cloudinary proxy/cache.
//
// Flow:
//  1. searchPlayers(name) hits TheSportsDB's free searchplayers.php
//     endpoint and returns candidate real players (name, team,
//     nationality, position, raw photo URL).
//  2. Once the user picks a candidate, resolvePhotoUrl() asks Cloudinary
//     to fetch that external image server-side and re-host it under our
//     own cloud — so the app never hotlinks TheSportsDB directly, and
//     the resulting Cloudinary URL is what gets saved onto the player's
//     Firestore doc. From that point on, this service is never called
//     again for that player: the stored Cloudinary URL is the cache.
//
// NOTE (flagged, not decided here): TheSportsDB's free tier is licensed
// for non-commercial use only. Per your instruction, we're shipping on
// the free tier now and revisiting commercial licensing (their $9/mo
// Patreon/Business tier) before scaling. Swapping tiers later is a
// config-only change — see _testApiKey below.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/cloudinary_upload_service.dart';

class PlayerSearchCandidate {
  const PlayerSearchCandidate({
    required this.id,
    required this.name,
    required this.team,
    required this.nationality,
    required this.position,
    required this.previewPhotoUrl,
    required this.bestPhotoUrl,
  });

  final String id;
  final String name;
  final String team;
  final String nationality;
  final String position;

  /// Raw TheSportsDB URL — fine to hotlink transiently for the search
  /// preview list only; never persisted.
  final String previewPhotoUrl;

  /// Highest-quality raw URL available (cutout preferred over thumb);
  /// this is what gets sent to Cloudinary for permanent re-hosting once
  /// the user picks this candidate.
  final String bestPhotoUrl;
}

class PlayerPhotoServiceException implements Exception {
  const PlayerPhotoServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PlayerPhotoService {
  PlayerPhotoService({CloudinaryUploadService? cloudinary})
      : _cloudinary = cloudinary ?? CloudinaryUploadService();

  final CloudinaryUploadService _cloudinary;

  // TheSportsDB's published free test key. Free tier = non-commercial;
  // swap to the paid key (from Patreon/Business tier) here when ready.
  static const String _testApiKey = '3';

  static const String _baseUrl = 'https://www.thesportsdb.com/api/v1/json';

  final Map<String, List<PlayerSearchCandidate>> _searchCache = {};
  final Map<String, String> _resolvedPhotoCache = {};

  Future<List<PlayerSearchCandidate>> searchPlayers(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final cacheKey = trimmed.toLowerCase();
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    // TheSportsDB's documented convention uses underscores for spaces.
    final encoded = Uri.encodeComponent(trimmed.replaceAll(' ', '_'));
    final uri = Uri.parse('$_baseUrl/$_testApiKey/searchplayers.php?p=$encoded');

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw PlayerPhotoServiceException(
          'Player search failed (HTTP ${resp.statusCode}).',
        );
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final rawList = decoded['player'];
      if (rawList is! List) return const [];

      final results = rawList
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .where((m) => ((m['strSport'] as String?) ?? '').toLowerCase() == 'soccer')
          .map(_toCandidate)
          .where((c) => c.name.isNotEmpty)
          .toList(growable: false);

      _searchCache[cacheKey] = results;
      return results;
    } on TimeoutException {
      throw const PlayerPhotoServiceException(
        'Player search timed out. Please try again.',
      );
    } catch (e) {
      if (e is PlayerPhotoServiceException) rethrow;
      throw const PlayerPhotoServiceException(
        'Could not search for players right now.',
      );
    }
  }

  PlayerSearchCandidate _toCandidate(Map<String, dynamic> m) {
    final cutout = ((m['strCutout'] as String?) ?? '').trim();
    final thumb = ((m['strThumb'] as String?) ?? '').trim();
    final best = cutout.isNotEmpty ? cutout : thumb;
    final preview = thumb.isNotEmpty ? thumb : cutout;

    return PlayerSearchCandidate(
      id: ((m['idPlayer'] as String?) ?? '').trim(),
      name: ((m['strPlayer'] as String?) ?? '').trim(),
      team: ((m['strTeam'] as String?) ?? '').trim(),
      nationality: ((m['strNationality'] as String?) ?? '').trim(),
      position: ((m['strPosition'] as String?) ?? '').trim(),
      previewPhotoUrl: preview,
      bestPhotoUrl: best,
    );
  }

  /// Re-hosts [sourceUrl] under our own Cloudinary cloud so the app never
  /// hotlinks TheSportsDB directly, and returns the resulting permanent
  /// secure_url. Returns '' if [sourceUrl] is empty (no photo available
  /// for this candidate) rather than throwing.
  Future<String> resolvePhotoUrl(String sourceUrl) async {
    final trimmed = sourceUrl.trim();
    if (trimmed.isEmpty) return '';

    final cached = _resolvedPhotoCache[trimmed];
    if (cached != null) return cached;

    final resolved = await _cloudinary.uploadRemoteImageUrl(
      sourceUrl: trimmed,
      folder: 'eleaguehub/players',
    );

    _resolvedPhotoCache[trimmed] = resolved;
    return resolved;
  }
}
