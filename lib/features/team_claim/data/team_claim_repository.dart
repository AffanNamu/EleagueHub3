// lib/features/team_claim/data/team_claim_repository.dart
//
// Client for the Worker's /teams/claim/* endpoints (worker/src/index.js).
// All authorization/validation happens server-side there -- this repository
// is a thin HTTP wrapper, never trusting any locally-cached claim status.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_config.dart';

class TeamClaimUserFriendlyException implements Exception {
  final String message;
  const TeamClaimUserFriendlyException(this.message);
  @override
  String toString() => message;
}

class TeamClaimLink {
  final String token;
  final int expiresAtMs;
  final String teamName;
  const TeamClaimLink({required this.token, required this.expiresAtMs, required this.teamName});
}

class TeamClaimPreview {
  final String teamName;
  final String teamLogoUrl;
  final String leagueName;
  final String organizerName;
  const TeamClaimPreview({
    required this.teamName,
    required this.teamLogoUrl,
    required this.leagueName,
    required this.organizerName,
  });
}

class TeamClaimResult {
  final String teamId;
  final String teamName;
  final String teamLogoUrl;
  final String leagueId;
  const TeamClaimResult({
    required this.teamId,
    required this.teamName,
    required this.teamLogoUrl,
    required this.leagueId,
  });
}

class TeamClaimRepository {
  TeamClaimRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static const _timeout = Duration(seconds: 15);

  Future<String> _requireIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const TeamClaimUserFriendlyException('Please sign in and try again.');
    }
    final token = (await user.getIdToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw const TeamClaimUserFriendlyException('Authentication token unavailable. Please try again.');
    }
    return token;
  }

  Map<String, dynamic> _decodeBody(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Never _throwFromResponse(http.Response res, String fallback) {
    final body = _decodeBody(res);
    final msg = (body['error'] as String?)?.trim();
    throw TeamClaimUserFriendlyException(msg?.isNotEmpty == true ? msg! : fallback);
  }

  /// Organizer-only. Mints a fresh claim link/token for [teamId] in
  /// [leagueId] -- supersedes any prior pending claim for the same team.
  Future<TeamClaimLink> generate({required String leagueId, required String teamId}) async {
    final url = BackendConfig.teamClaimGenerateUrl();
    if (url == null) {
      throw const TeamClaimUserFriendlyException('Claim links are not configured on this build.');
    }
    final idToken = await _requireIdToken();

    final res = await http
        .post(
          url,
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $idToken'},
          body: jsonEncode({'leagueId': leagueId, 'teamId': teamId}),
        )
        .timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwFromResponse(res, 'Could not create a claim link. Please try again.');
    }

    final body = _decodeBody(res);
    final token = (body['token'] as String?)?.trim() ?? '';
    if (token.isEmpty) {
      throw const TeamClaimUserFriendlyException('Could not create a claim link. Please try again.');
    }
    return TeamClaimLink(
      token: token,
      expiresAtMs: (body['expiresAtMs'] as num?)?.toInt() ?? 0,
      teamName: (body['teamName'] as String?)?.trim() ?? '',
    );
  }

  /// Public -- no auth required, so the claim preview renders before the
  /// claimant signs in (Section 12/16 of the claim spec).
  Future<TeamClaimPreview> preview(String token) async {
    final url = BackendConfig.teamClaimPreviewUrl(token);
    if (url == null) {
      throw const TeamClaimUserFriendlyException('Claim links are not configured on this build.');
    }

    final res = await http.get(url).timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwFromResponse(res, 'This claim link could not be loaded.');
    }

    final body = _decodeBody(res);
    return TeamClaimPreview(
      teamName: (body['teamName'] as String?)?.trim() ?? '',
      teamLogoUrl: (body['teamLogoUrl'] as String?)?.trim() ?? '',
      leagueName: (body['leagueName'] as String?)?.trim() ?? '',
      organizerName: (body['organizerName'] as String?)?.trim() ?? '',
    );
  }

  /// Requires the claimant to be signed in. Server re-validates the token
  /// and the team's claim status independently -- never trusts any client
  /// state about whether this claim is still open.
  Future<TeamClaimResult> confirm(String token) async {
    final url = BackendConfig.teamClaimConfirmUrl();
    if (url == null) {
      throw const TeamClaimUserFriendlyException('Claim links are not configured on this build.');
    }
    final idToken = await _requireIdToken();

    final res = await http
        .post(
          url,
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $idToken'},
          body: jsonEncode({'token': token}),
        )
        .timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwFromResponse(res, 'Could not complete the claim. Please try again.');
    }

    final body = _decodeBody(res);
    return TeamClaimResult(
      teamId: (body['teamId'] as String?)?.trim() ?? '',
      teamName: (body['teamName'] as String?)?.trim() ?? '',
      teamLogoUrl: (body['teamLogoUrl'] as String?)?.trim() ?? '',
      leagueId: (body['leagueId'] as String?)?.trim() ?? '',
    );
  }

  /// Organizer-only. The external team itself is untouched -- only the
  /// pending invitation's authorization is revoked.
  Future<void> revoke({required String leagueId, required String teamId}) async {
    final url = BackendConfig.teamClaimRevokeUrl();
    if (url == null) {
      throw const TeamClaimUserFriendlyException('Claim links are not configured on this build.');
    }
    final idToken = await _requireIdToken();

    final res = await http
        .post(
          url,
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $idToken'},
          body: jsonEncode({'leagueId': leagueId, 'teamId': teamId}),
        )
        .timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwFromResponse(res, 'Could not revoke this claim link. Please try again.');
    }
  }
}
