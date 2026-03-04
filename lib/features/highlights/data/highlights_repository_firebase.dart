import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../leagues/models/enums.dart';
import '../../leagues/models/fixture_match.dart';
import '../../leagues/models/membership.dart';
import '../domain/match_highlight.dart';

/// Highlights-specific user-facing exception.
///
/// NOTE:
/// This is intentionally NOT named `UserFriendlyException` to avoid clashing with
/// other modules that also define `UserFriendlyException` (e.g. ConnectivityService).
class HighlightsUserFriendlyException implements Exception {
  final String message;
  const HighlightsUserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// Firebase/Firestore repository for match highlights.
///
/// Firestore structure (REQUIRED):
/// matches/{matchId}/highlights/{highlightId}
///
/// Notes:
/// - We intentionally store highlights under a top-level `matches` collection
///   as per specification, independent of your `leagues/{leagueId}/matches`.
/// - The highlight document includes leagueId/matchId/teamId for security rules.
class HighlightsRepositoryFirebase {
  HighlightsRepositoryFirebase({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Cache streams by matchId to avoid recreating streams inside build().
  final Map<String, Stream<List<MatchHighlight>>> _highlightsStreamCache = {};

  String _requireUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const HighlightsUserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _highlightsCol(String matchId) {
    final mid = matchId.trim();
    if (mid.isEmpty) throw const HighlightsUserFriendlyException('Invalid match id.');
    return _firestore.collection('matches').doc(mid).collection('highlights');
  }

  /// Watches highlights for a match.
  /// Stream is cached per matchId (performance requirement).
  Stream<List<MatchHighlight>> watchHighlightsForMatch(String matchId) {
    final key = matchId.trim();
    if (key.isEmpty) return const Stream<List<MatchHighlight>>.empty();

    final cached = _highlightsStreamCache[key];
    if (cached != null) return cached;

    final stream = _highlightsCol(key)
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      return snap.docs.map((d) => MatchHighlight.fromDoc(d)).toList(growable: false);
    });

    _highlightsStreamCache[key] = stream;
    return stream;
  }

  /// Loads membership server-side (authoritative).
  Future<Membership?> _loadMembershipServer({
    required String leagueId,
    required String userId,
  }) async {
    final lid = leagueId.trim();
    final uid = userId.trim();
    if (lid.isEmpty || uid.isEmpty) return null;

    final doc = await _firestore
        .collection('leagues')
        .doc(lid)
        .collection('memberships')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;

    // Backfill expected fields for older docs.
    final map = <String, dynamic>{...data};
    map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true ? map['id'] : doc.id;
    map['leagueId'] = (map['leagueId'] as String?)?.trim().isNotEmpty == true ? map['leagueId'] : lid;
    map['userId'] = (map['userId'] as String?)?.trim().isNotEmpty == true ? map['userId'] : uid;

    try {
      return Membership.fromRemoteMap(map);
    } catch (_) {
      return null;
    }
  }

  bool _isMatchFinishedForHighlights(FixtureMatch match) {
    // IMPORTANT:
    // FixtureMatch.isPlayed requires scores not null.
    // For highlight eligibility we consider "finished" when status indicates completion.
    return match.status == MatchStatus.completed || match.status == MatchStatus.played || match.isPlayed;
  }

  /// Determines if user can upload highlight for this match.
  ///
  /// REQUIREMENTS:
  /// - match must be FINISHED (here: status completed/played; NOT strictly requiring scores)
  /// - user must be a league member
  /// - membership.teamId must be set
  /// - membership.teamId must be homeTeamId or awayTeamId
  ///
  /// This method is also used by UI to explain why upload is hidden.
  Future<String> requireUploadTeamIdOrThrow({
    required FixtureMatch match,
  }) async {
    final uid = _requireUid();

    if (!_isMatchFinishedForHighlights(match)) {
      throw const HighlightsUserFriendlyException(
        'Highlights can only be uploaded after the match is finished.',
      );
    }

    final membership = await _loadMembershipServer(
      leagueId: match.leagueId,
      userId: uid,
    );

    if (membership == null) {
      throw const HighlightsUserFriendlyException(
        'You must be a league member to upload highlights.',
      );
    }

    final teamId = (membership.teamId ?? '').trim();
    if (teamId.isEmpty) {
      // This is the #1 real-world reason the upload button is hidden.
      // It means the user joined the league but was never assigned to a team.
      throw const HighlightsUserFriendlyException(
        'Your account is not assigned to a team in this league. Ask the organizer to assign your membership to the home or away team.',
      );
    }

    final homeId = match.homeTeamId.trim();
    final awayId = match.awayTeamId.trim();
    final isParticipant = teamId == homeId || teamId == awayId;

    if (!isParticipant) {
      throw const HighlightsUserFriendlyException(
        'Only home/away team members can upload highlights for this match.',
      );
    }

    return teamId;
  }

  /// Returns the existing highlight (if any) for a team in this match.
  ///
  /// We keep this cheap to minimize reads. Used for dedupe/idempotency.
  Future<MatchHighlight?> fetchExistingHighlightForTeam({
    required String matchId,
    required String teamId,
  }) async {
    final mid = matchId.trim();
    final tid = teamId.trim();
    if (mid.isEmpty || tid.isEmpty) return null;

    final snap = await _highlightsCol(mid)
        .where('teamId', isEqualTo: tid)
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (snap.docs.isEmpty) return null;
    return MatchHighlight.fromDoc(snap.docs.first);
  }

  /// Creates an optimistic highlight document (UPLOADING) BEFORE upload.
  ///
  /// Enables:
  /// - optimistic UI
  /// - idempotent uploads (stable highlightId)
  ///
  /// IMPORTANT:
  /// - createdAt MUST be written on create to support `orderBy('createdAt')` queries reliably.
  Future<String> getOrCreateUploadingHighlight({
    required FixtureMatch match,
  }) async {
    final uid = _requireUid();
    final teamId = await requireUploadTeamIdOrThrow(match: match);

    final existing = await fetchExistingHighlightForTeam(matchId: match.id, teamId: teamId);

    // Folder per spec:
    // match_highlights/{leagueId}/{matchId}/{teamId}
    final cloudFolder = 'match_highlights/${match.leagueId}/${match.id}/$teamId';

    if (existing != null) {
      // If someone else on the team started the upload, don't try to "take over" the doc,
      // because Firestore rules enforce uploadedBy == auth.uid.
      if (existing.uploadedBy.trim().isNotEmpty && existing.uploadedBy.trim() != uid) {
        throw const HighlightsUserFriendlyException(
          'A teammate already started uploading this highlight. Please wait or ask them to finish.',
        );
      }

      // If already uploaded (PROCESSING/APPROVED), block new uploads.
      final hasUrl = existing.secureUrl.trim().isNotEmpty;
      if (hasUrl && !existing.isUploading) {
        throw const HighlightsUserFriendlyException(
          'Your team has already uploaded a highlight for this match.',
        );
      }

      // Retry/resume: merge minimal fields.
      await _highlightsCol(match.id)
          .doc(existing.id)
          .set(
            <String, dynamic>{
              'matchId': match.id,
              'leagueId': match.leagueId,
              'teamId': teamId,
              'uploadedBy': uid,
              'cloudinaryPublicId': '$cloudFolder/${existing.id}',
              'status': MatchHighlight.statusUploading,
              'updatedAt': FieldValue.serverTimestamp(),
              // Do NOT touch createdAt on retry.
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 12));

      return existing.id;
    }

    final ref = _highlightsCol(match.id).doc(); // auto id
    final highlightId = ref.id;

    final doc = MatchHighlight(
      id: highlightId,
      matchId: match.id,
      leagueId: match.leagueId,
      teamId: teamId,
      uploadedBy: uid,
      cloudinaryPublicId: '$cloudFolder/$highlightId',
      secureUrl: '',
      thumbnailUrl: '',
      duration: 0,
      size: 0,
      format: '',
      status: MatchHighlight.statusUploading,
      createdAt: null,
      updatedAt: null,
    );

    final map = doc.toFirestoreMap();

    // Ensure createdAt exists for reliable ordering and feed queries.
    map['createdAt'] = FieldValue.serverTimestamp();
    map['updatedAt'] = FieldValue.serverTimestamp();

    await ref
        .set(
          map,
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));

    return highlightId;
  }

  /// Updates doc after Cloudinary upload succeeds.
  ///
  /// We intentionally move to PROCESSING (not APPROVED) to support moderation flows.
  Future<void> markUploadSucceeded({
    required String matchId,
    required String highlightId,
    required String cloudinaryPublicId,
    required String secureUrl,
    required String thumbnailUrl,
    required double duration,
    required int size,
    required String format,
  }) async {
    _requireUid();

    final ref = _highlightsCol(matchId).doc(highlightId);

    await ref
        .set(
          <String, dynamic>{
            'cloudinaryPublicId': cloudinaryPublicId,
            'secureUrl': secureUrl,
            'thumbnailUrl': thumbnailUrl,
            'duration': duration,
            'size': size,
            'format': format,
            'status': MatchHighlight.statusProcessing,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<void> markUploadFailed({
    required String matchId,
    required String highlightId,
  }) async {
    _requireUid();

    final ref = _highlightsCol(matchId).doc(highlightId);

    await ref
        .set(
          <String, dynamic>{
            'secureUrl': '',
            'thumbnailUrl': '',
            'status': MatchHighlight.statusUploading,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// Uploader can delete their own uploading highlight to retry cleanly.
  Future<void> deleteHighlight({
    required String matchId,
    required String highlightId,
  }) async {
    _requireUid();
    await _highlightsCol(matchId).doc(highlightId).delete().timeout(const Duration(seconds: 12));
  }
}
