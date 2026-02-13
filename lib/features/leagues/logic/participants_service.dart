import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// ONLINE-ONLY Participants service.
///
/// Replaces the legacy local DB participants storage + sync.
/// Source of truth is Firestore:
/// - League access list: leagues/{leagueId}.memberIds
/// - Participant records: leagues/{leagueId}/memberships/*
class ParticipantsService {
  ParticipantsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _leagueRef(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId);
  }

  CollectionReference<Map<String, dynamic>> _membershipsCol(String leagueId) {
    return _leagueRef(leagueId).collection('memberships');
  }

  bool _isOwnerFromLeagueDoc(Map<String, dynamic> leagueData, String authUid) {
    final organizerUid = (leagueData['organizerUid'] as String?)?.trim() ?? '';
    final ownerUid = (leagueData['ownerUid'] as String?)?.trim() ?? '';
    return organizerUid == authUid || ownerUid == authUid;
  }

  /// Get all participants (Firebase UIDs) for a league.
  ///
  /// Online-only: reads from Firestore server.
  Future<List<String>> getParticipants(String leagueId) async {
    try {
      _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      // Prefer membership docs for a canonical participant list.
      final snap = await _membershipsCol(leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final ids = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final uid = (data['userId'] as String?)?.trim() ?? '';
        if (uid.isNotEmpty) ids.add(uid);
      }

      // Fallback to league.memberIds if membership collection is empty.
      if (ids.isEmpty) {
        final leagueSnap =
            await _leagueRef(leagueId).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 12));
        final data = leagueSnap.data() ?? <String, dynamic>{};
        final memberIds = data['memberIds'];
        if (memberIds is List) {
          for (final v in memberIds) {
            final s = (v ?? '').toString().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      }

      return ids.toList(growable: false);
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't load participants right now. Please try again.");
    }
  }

  /// Add participant by Firebase UID.
  ///
  /// Legacy params kept for API compatibility; they are ignored in online-only mode.
  ///
  /// Requires organizer/owner permissions by Firestore rules.
  Future<bool> addParticipant(
    String leagueId,
    String participantId, {
    String? name,
    bool joinedOnline = false,
  }) async {
    try {
      final authUid = _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final pid = participantId.trim();
      if (pid.isEmpty) {
        throw const UserFriendlyException('Please enter a valid user id.');
      }

      await _firestore.runTransaction((tx) async {
        final leagueRef = _leagueRef(leagueId);
        final leagueSnap = await tx.get(leagueRef);
        if (!leagueSnap.exists) {
          throw const UserFriendlyException("We couldn't find this league. Please try again.");
        }

        final leagueData = (leagueSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        if (!_isOwnerFromLeagueDoc(leagueData, authUid)) {
          throw const UserFriendlyException('You don’t have permission to do that right now.');
        }

        final List<dynamic> memberIdsRaw = (leagueData['memberIds'] is List) ? (leagueData['memberIds'] as List) : [];
        final memberIds = memberIdsRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet();

        final bool alreadyMember = memberIds.contains(pid);

        // Always upsert membership doc for the participant (id is deterministic to prevent duplicates).
        final now = DateTime.now().millisecondsSinceEpoch;
        final membershipRef = _membershipsCol(leagueId).doc(pid);

        if (!alreadyMember) {
          // Update league memberIds and counters (best-effort, used for UI).
          final int prevRegistered = (leagueData['registeredCount'] as num?)?.toInt() ?? memberIds.length;
          final int nextRegistered = prevRegistered + 1;

          final int? maxTeams = (leagueData['maxTeams'] as num?)?.toInt();
          final bool isFull = (maxTeams != null && maxTeams > 0) ? (nextRegistered >= maxTeams) : false;

          tx.update(leagueRef, <String, dynamic>{
            'memberIds': FieldValue.arrayUnion([pid]),
            'registeredCount': nextRegistered,
            'isFull': isFull,
            'updatedAtMs': now,
          });
        } else {
          // Touch updatedAtMs only (optional).
          tx.update(leagueRef, <String, dynamic>{'updatedAtMs': now});
        }

        tx.set(
          membershipRef,
          <String, dynamic>{
            'id': pid,
            'leagueId': leagueId,
            'userId': pid,
            'teamId': null,
            'role': 0, // LeagueRole.member (matches rules hardening)
            'updatedAtMs': now,
            'version': 1,
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 25));

      return true;
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't add this participant right now. Please try again.");
    }
  }

  /// Remove participant by Firebase UID.
  ///
  /// Requires organizer/owner permissions by Firestore rules.
  Future<bool> removeParticipant(String leagueId, String participantId) async {
    try {
      final authUid = _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final pid = participantId.trim();
      if (pid.isEmpty) return false;

      await _firestore.runTransaction((tx) async {
        final leagueRef = _leagueRef(leagueId);
        final leagueSnap = await tx.get(leagueRef);
        if (!leagueSnap.exists) {
          throw const UserFriendlyException("We couldn't find this league. Please try again.");
        }

        final leagueData = (leagueSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        if (!_isOwnerFromLeagueDoc(leagueData, authUid)) {
          throw const UserFriendlyException('You don’t have permission to do that right now.');
        }

        final now = DateTime.now().millisecondsSinceEpoch;

        final List<dynamic> memberIdsRaw = (leagueData['memberIds'] is List) ? (leagueData['memberIds'] as List) : [];
        final memberIds = memberIdsRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet();
        final bool wasMember = memberIds.contains(pid);

        // Best-effort counters maintenance.
        final int prevRegistered = (leagueData['registeredCount'] as num?)?.toInt() ?? memberIds.length;
        final int nextRegistered = wasMember ? (prevRegistered > 0 ? prevRegistered - 1 : 0) : prevRegistered;

        final int? maxTeams = (leagueData['maxTeams'] as num?)?.toInt();
        final bool isFull = (maxTeams != null && maxTeams > 0) ? (nextRegistered >= maxTeams) : false;

        tx.update(leagueRef, <String, dynamic>{
          'memberIds': FieldValue.arrayRemove([pid]),
          'registeredCount': nextRegistered,
          'isFull': isFull,
          'updatedAtMs': now,
        });
      }).timeout(const Duration(seconds: 25));

      // Delete any membership docs for this user (including legacy random ids).
      final qs = await _membershipsCol(leagueId)
          .where('userId', isEqualTo: pid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (qs.docs.isNotEmpty) {
        const chunkSize = 450;
        for (var i = 0; i < qs.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = qs.docs.sublist(i, (i + chunkSize > qs.docs.length) ? qs.docs.length : i + chunkSize);
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 20));
        }
      }

      return true;
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't remove this participant right now. Please try again.");
    }
  }

  /// ONLINE-ONLY: offline participant sync is removed.
  Future<void> syncParticipants(String leagueId) async {
    return;
  }

  Future<bool> participantExists(String leagueId, String participantId) async {
    try {
      _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final pid = participantId.trim();
      if (pid.isEmpty) return false;

      final qs = await _membershipsCol(leagueId)
          .where('userId', isEqualTo: pid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      return qs.docs.isNotEmpty;
    } catch (_) {
      // Online-only: if we can't verify, treat as not existing.
      return false;
    }
  }
}
