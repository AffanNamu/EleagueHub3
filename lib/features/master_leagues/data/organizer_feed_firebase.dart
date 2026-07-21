///data/organizer_feed_firebase
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/organizer_feed_event.dart';

class OrganizerFeedFirebase {
  OrganizerFeedFirebase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _feedCol =>
      _firestore.collection('organizer_feed');

  void _log(Object error, [StackTrace? st]) {
    if (!kDebugMode) return;
    debugPrint('[OrganizerFeedFirebase] $error');
    if (st != null) {
      debugPrint('$st');
    }
  }

  Stream<List<OrganizerFeedEvent>> watchWorkspaceFeed(String masterLeagueId) {
    final id = masterLeagueId.trim();
    if (id.isEmpty) {
      return Stream<List<OrganizerFeedEvent>>.value(const <OrganizerFeedEvent>[]);
    }

    try {
      return _feedCol
          .where('masterLeagueId', isEqualTo: id)
          .orderBy('createdAtMs', descending: true)
          .limit(50)
          .snapshots()
          .map((snap) {
        return snap.docs
            .map((d) => OrganizerFeedEvent.fromMap(d.data()))
            .toList(growable: false);
      }).handleError((error, st) {
        _log(error, st);
      });
    } catch (e, st) {
      _log(e, st);
      return Stream<List<OrganizerFeedEvent>>.value(const <OrganizerFeedEvent>[]);
    }
  }

  Stream<List<OrganizerFeedEvent>> watchFollowedOrganizerFeed(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) {
      return Stream<List<OrganizerFeedEvent>>.value(const <OrganizerFeedEvent>[]);
    }

    try {
      return _firestore
          .collectionGroup('followers')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .asyncMap((followSnap) async {
        try {
          final workspaceIds = followSnap.docs
              .map((d) => d.reference.parent.parent?.id ?? '')
              .map((e) => e.trim())
              .where((id) => id.isNotEmpty)
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

            try {
              final feedSnap = await _feedCol
                  .where('masterLeagueId', whereIn: chunk)
                  .orderBy('createdAtMs', descending: true)
                  .limit(50)
                  .get()
                  .timeout(const Duration(seconds: 12));

              results.addAll(
                feedSnap.docs.map((d) => OrganizerFeedEvent.fromMap(d.data())),
              );
            } catch (e, st) {
              _log(e, st);
            }
          }

          results.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
          return results.take(100).toList(growable: false);
        } catch (e, st) {
          _log(e, st);
          return <OrganizerFeedEvent>[];
        }
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          sink.add(const <OrganizerFeedEvent>[]);
          sink.close();
        },
      ).handleError((error, st) {
        _log(error, st);
      });
    } catch (e, st) {
      _log(e, st);
      return Stream<List<OrganizerFeedEvent>>.value(const <OrganizerFeedEvent>[]);
    }
  }

  Stream<List<OrganizerFeedEvent>> watchFollowedOrganizerFeedPreview(
    String userId,
  ) {
    return watchFollowedOrganizerFeed(userId).map(
      (items) => items.take(6).toList(growable: false),
    );
  }

  Future<List<OrganizerFeedEvent>> fetchFollowedOrganizerFeedOnce(
    String userId,
  ) async {
    final uid = userId.trim();
    if (uid.isEmpty) return const <OrganizerFeedEvent>[];

    try {
      final followSnap = await _firestore
          .collectionGroup('followers')
          .where('userId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 12));

      final workspaceIds = followSnap.docs
          .map((d) => d.reference.parent.parent?.id ?? '')
          .map((e) => e.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (workspaceIds.isEmpty) return const <OrganizerFeedEvent>[];

      final results = <OrganizerFeedEvent>[];

      const chunkSize = 10;
      for (int i = 0; i < workspaceIds.length; i += chunkSize) {
        final chunk = workspaceIds.sublist(
          i,
          (i + chunkSize < workspaceIds.length)
              ? i + chunkSize
              : workspaceIds.length,
        );

        try {
          final feedSnap = await _feedCol
              .where('masterLeagueId', whereIn: chunk)
              .orderBy('createdAtMs', descending: true)
              .limit(50)
              .get()
              .timeout(const Duration(seconds: 12));

          results.addAll(
            feedSnap.docs.map((d) => OrganizerFeedEvent.fromMap(d.data())),
          );
        } catch (e, st) {
          _log(e, st);
        }
      }

      results.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return results.take(100).toList(growable: false);
    } catch (e, st) {
      _log(e, st);
      return const <OrganizerFeedEvent>[];
    }
  }

  Future<void> addEvent(OrganizerFeedEvent event) async {
    final id = event.id.trim().isEmpty ? _uuid.v4() : event.id.trim();
    final safe = event.copyWith(id: id);

    try {
      await _feedCol.doc(id).set(safe.toMap()).timeout(const Duration(seconds: 12));
    } catch (e, st) {
      _log(e, st);
      rethrow;
    }
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
