import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../domain/organizer_feed_event.dart';

class OrganizerFeedFirebase {
  OrganizerFeedFirebase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _feedCol =>
      _firestore.collection('organizer_feed');

  CollectionReference<Map<String, dynamic>> _followersCol(String masterLeagueId) {
    return _firestore
        .collection('master_leagues')
        .doc(masterLeagueId.trim())
        .collection('followers');
  }

  Stream<List<OrganizerFeedEvent>> watchWorkspaceFeed(String masterLeagueId) {
    return _feedCol
        .where('masterLeagueId', isEqualTo: masterLeagueId.trim())
        .orderBy('createdAtMs', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrganizerFeedEvent.fromMap(d.data()))
            .toList(growable: false));
  }

  Stream<List<OrganizerFeedEvent>> watchFollowedOrganizerFeed(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) {
      return const Stream<List<OrganizerFeedEvent>>.empty();
    }

    return _firestore
        .collectionGroup('followers')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .asyncMap((followSnap) async {
      final workspaceIds = followSnap.docs
          .map((d) => d.reference.parent.parent?.id ?? '')
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (workspaceIds.isEmpty) return <OrganizerFeedEvent>[];

      final results = <OrganizerFeedEvent>[];

      const chunkSize = 10;
      for (int i = 0; i < workspaceIds.length; i += chunkSize) {
        final chunk = workspaceIds.sublist(
          i,
          (i + chunkSize < workspaceIds.length)
              ? i + chunkSize
              : workspaceIds.length,
        );

        final feedSnap = await _feedCol
            .where('masterLeagueId', whereIn: chunk)
            .orderBy('createdAtMs', descending: true)
            .limit(50)
            .get();

        results.addAll(
          feedSnap.docs.map((d) => OrganizerFeedEvent.fromMap(d.data())),
        );
      }

      results.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return results.take(100).toList(growable: false);
    });
  }

  Stream<List<OrganizerFeedEvent>> watchFollowedOrganizerFeedPreview(
    String userId,
  ) {
    return watchFollowedOrganizerFeed(userId).map(
      (items) => items.take(6).toList(growable: false),
    );
  }

  Future<void> addEvent(OrganizerFeedEvent event) async {
    final id = event.id.trim().isEmpty ? _uuid.v4() : event.id.trim();
    await _feedCol.doc(id).set(event.copyWith(id: id).toMap());
  }

  Future<void> addAnnouncementPostedEvent({
    required String masterLeagueId,
    required String actorId,
    required String actorName,
    required String title,
  }) async {
    await addEvent(
      OrganizerFeedEvent(
        id: '',
        masterLeagueId: masterLeagueId.trim(),
        type: 'announcement',
        title: 'Organizer announcement posted',
        message: title.trim(),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        actorId: actorId.trim(),
        actorName: actorName.trim(),
        leagueId: '',
      ),
    );
  }

  Future<void> addCompetitionCreatedEvent({
    required String masterLeagueId,
    required String leagueId,
    required String actorId,
    required String actorName,
    required String competitionName,
  }) async {
    await addEvent(
      OrganizerFeedEvent(
        id: '',
        masterLeagueId: masterLeagueId.trim(),
        type: 'competition_created',
        title: 'New competition created',
        message: competitionName.trim(),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        actorId: actorId.trim(),
        actorName: actorName.trim(),
        leagueId: leagueId.trim(),
      ),
    );
  }

  Future<void> addVerificationApprovedEvent({
    required String masterLeagueId,
    required String actorId,
    required String actorName,
    required bool isRenewal,
  }) async {
    await addEvent(
      OrganizerFeedEvent(
        id: '',
        masterLeagueId: masterLeagueId.trim(),
        type: isRenewal ? 'verification_renewed' : 'verification_approved',
        title: isRenewal
            ? 'Organizer verification renewed'
            : 'Organizer verified',
        message: isRenewal
            ? 'Verification has been renewed after admin review.'
            : 'Organizer verification has been approved.',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        actorId: actorId.trim(),
        actorName: actorName.trim(),
        leagueId: '',
      ),
    );
  }

  Future<String> currentUserIdOrThrow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Please sign in and try again.');
    }
    return uid;
  }
}
