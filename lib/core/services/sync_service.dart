import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../features/leagues/data/leagues_repository_local.dart';
import '../../features/leagues/models/fixture_match.dart';
import '../../features/leagues/models/knockout_match.dart';
import '../../features/leagues/models/league.dart';
import '../../features/leagues/models/league_announcement.dart';
import '../../features/leagues/models/league_space.dart';
import '../../features/leagues/models/membership.dart';
import '../../features/leagues/models/team.dart';
import '../persistence/prefs_service.dart';
import 'connectivity_service.dart';
import 'sync_queue_service.dart';

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final ConnectivityService _connectivity = ConnectivityService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSyncing = false;

  String _authUidOrEmpty() => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  /// IMPORTANT:
  /// - Never throw from syncAll(). Screens must not get stuck in loading forever.
  /// - Sync is best-effort: if anything fails, we keep working with local data.
  Future<void> syncAll() async {
    if (_isSyncing) return;

    await _connectivity.recheckConnection();
    if (!_connectivity.isConnected.value) {
      debugPrint('SyncService → Not syncing (offline)');
      return;
    }

    _isSyncing = true;
    try {
      await _syncLocalQueueToCloud();
      await _syncCloudToLocal();
    } catch (e, st) {
      debugPrint('SyncService → syncAll FAILED (non-fatal): $e');
      debugPrint('$st');
    } finally {
      _isSyncing = false;
    }
  }

  // --------------------------------------------------
  // LOCAL → CLOUD
  // --------------------------------------------------

  Future<void> _syncLocalQueueToCloud() async {
    // If user is not signed in, cloud writes will be denied by rules.
    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      debugPrint('SyncService → Local→Cloud skipped (not signed in)');
      return;
    }

    final queue = await SyncQueueService.instance.getPending();

    debugPrint('SyncService → Pending queue items: ${queue.length}');
    for (final q in queue) {
      debugPrint('QueueItem → type=${q.entityType} action=${q.action} id=${q.entityId}');
    }

    for (final item in queue) {
      try {
        await _uploadItem(item);
        await SyncQueueService.instance.markDone(item.id);
        debugPrint('SyncService → Synced ${item.entityType}:${item.entityId}');
      } catch (e, st) {
        // Do NOT rethrow. Leave item in queue for later retry.
        debugPrint('SyncService → FAILED type=${item.entityType} action=${item.action} entityId=${item.entityId}');
        debugPrint('Error: $e');
        debugPrint('$st');
        break;
      }
    }
  }

  Future<void> _uploadItem(SyncQueueItem item) async {
    switch (item.entityType) {
      case 'league':
        return _uploadLeague(item);
      case 'league_join':
        return _uploadLeagueJoin(item);
      case 'membership':
        return _uploadMembership(item);
      case 'teams_replace':
        return _uploadTeamsReplace(item);
      case 'matches_replace':
        return _uploadMatchesReplace(item);
      case 'matches_upsert':
        return _uploadMatchesUpsert(item);
      case 'knockout_replace':
        return _uploadKnockoutReplace(item);
      case 'announcement':
        return _uploadAnnouncement(item);
      case 'space_current':
        return _uploadSpaceCurrent(item);
      default:
        debugPrint('SyncService → Unknown entityType=${item.entityType} (skipped)');
        return;
    }
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  // ---------------------------
  // Upload: League
  // ---------------------------
  Future<void> _uploadLeague(SyncQueueItem item) async {
    final ref = _firestore.collection('leagues').doc(item.entityId);

    if (item.action == 'delete') {
      await ref.delete();
      return;
    }

    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for league');

    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      // Should never happen (caller checks), but keep it safe.
      throw StateError('Not signed in (auth uid missing)');
    }

    final data = Map<String, dynamic>.from(payload);
    data['id'] = item.entityId;

    // Normalize isPrivate as bool
    final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
    data['isPrivate'] = isPrivate;

    // ------------------------------------------------------------
    // CRITICAL FIX:
    // Never trust organizerUid from local payload unless it is a real
    // Firebase UID AND equals the currently authenticated user.
    // Otherwise Firestore rules will deny league create/update and
    // coupon subcollections will be inaccessible.
    // ------------------------------------------------------------
    final organizerUidRaw = (data['organizerUid'] as String?)?.trim() ?? '';
    final organizerUserIdRaw = (data['organizerUserId'] as String?)?.trim() ?? '';

    String resolvedOrganizerUid = authUid;

    // Only accept organizerUid from payload if it matches the current auth uid.
    if (organizerUidRaw.isNotEmpty && _looksLikeFirebaseUid(organizerUidRaw) && organizerUidRaw == authUid) {
      resolvedOrganizerUid = organizerUidRaw;
    } else if (_looksLikeFirebaseUid(organizerUserIdRaw) && organizerUserIdRaw == authUid) {
      // Back-compat: sometimes organizerUserId held the Firebase UID.
      resolvedOrganizerUid = organizerUserIdRaw;
    } else {
      resolvedOrganizerUid = authUid;
    }

    // Authoritative identity fields used by rules
    data['organizerUid'] = resolvedOrganizerUid;
    data['ownerUid'] = resolvedOrganizerUid;
    data['ownerId'] = resolvedOrganizerUid; // legacy field but must be Firebase UID if present

    // Ensure memberIds contains Firebase UID for rules membership checks
    final existing = (data['memberIds'] as List?)?.cast<dynamic>() ?? const [];
    final existingStrings = existing.map((e) => e.toString().trim()).where((s) => s.isNotEmpty);

    // Sanitize to Firebase UIDs only (prevents short/shareIds poisoning memberIds).
    final memberUids = <String>{
      ...existingStrings.where(_looksLikeFirebaseUid),
      authUid,
      resolvedOrganizerUid,
    };

    data['memberIds'] = memberUids.toList();

    await ref.set(data, SetOptions(merge: true));

    // NOTE: Coupons are handled via couponConfig + couponCodes (not /coupons).
  }

  // ---------------------------
  // Upload: Join League by code
  // ---------------------------
  Future<void> _uploadLeagueJoin(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for league_join');

    final code = (payload['code'] as String?)?.trim().toUpperCase();
    if (code == null || code.isEmpty) throw StateError('Invalid league_join payload (code)');

    // Prefer authUid included in payload (if you queued it), else current auth user.
    final authUid = (payload['authUid'] as String?)?.trim() ?? _authUidOrEmpty();
    if (authUid.isEmpty) throw StateError('Not signed in (authUid missing)');

    final snap = await _firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();
    if (snap.docs.isEmpty) throw StateError('League not found for Join ID: $code');

    final leagueId = snap.docs.first.id;

    await _firestore.collection('leagues').doc(leagueId).set(
      {
        // RULES AUTH: request.auth.uid must be added here
        'memberIds': FieldValue.arrayUnion([authUid]),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
  }

  // ---------------------------
  // Upload: Membership
  // ---------------------------
  Future<void> _uploadMembership(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for membership');

    final leagueId = payload['leagueId'] as String?;
    if (leagueId == null || leagueId.isEmpty) throw StateError('membership payload missing leagueId');

    // IMPORTANT: Membership userId should be Firebase UID in modern flows.
    final userId = (payload['userId'] as String?)?.trim() ?? '';
    if (userId.isEmpty) throw StateError('membership payload missing userId');

    final doc = _firestore.collection('leagues').doc(leagueId).collection('memberships').doc(item.entityId);
    await doc.set(payload, SetOptions(merge: true));
  }

  // ---------------------------
  // Upload: Teams
  // ---------------------------
  Future<void> _uploadTeamsReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for teams_replace');

    final leagueId = payload['leagueId'] as String?;
    final teams = payload['teams'] as List<dynamic>?;
    if (leagueId == null || teams == null) throw StateError('teams_replace payload invalid');

    final batch = _firestore.batch();
    final col = _firestore.collection('leagues').doc(leagueId).collection('teams');

    for (final t in teams) {
      final map = (t as Map).cast<String, dynamic>();
      final id = map['id'] as String;
      batch.set(col.doc(id), map, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------------------
  // Upload: Matches
  // ---------------------------
  Future<void> _uploadMatchesReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for matches_replace');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || matches == null) throw StateError('matches_replace payload invalid');

    final col = _firestore.collection('leagues').doc(leagueId).collection('matches');
    await _batchUpsertList(col: col, items: matches);
  }

  Future<void> _uploadMatchesUpsert(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for matches_upsert');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || matches == null) throw StateError('matches_upsert payload invalid');

    final col = _firestore.collection('leagues').doc(leagueId).collection('matches');
    await _batchUpsertList(col: col, items: matches);
  }

  // ---------------------------
  // Upload: Knockout
  // ---------------------------
  Future<void> _uploadKnockoutReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for knockout_replace');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || matches == null) throw StateError('knockout_replace payload invalid');

    final col = _firestore.collection('leagues').doc(leagueId).collection('knockout');
    await _batchUpsertList(col: col, items: matches);
  }

  // ---------------------------
  // Upload: Announcements
  // ---------------------------
  Future<void> _uploadAnnouncement(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for announcement');

    final leagueId = payload['leagueId'] as String?;
    final annId = payload['id'] as String?;
    if (leagueId == null || annId == null) throw StateError('announcement payload invalid');

    final doc = _firestore.collection('leagues').doc(leagueId).collection('announcements').doc(annId);
    await doc.set(payload, SetOptions(merge: true));
  }

  // ---------------------------
  // Upload: Space current
  // ---------------------------
  Future<void> _uploadSpaceCurrent(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for space_current');

    final leagueId = payload['leagueId'] as String?;
    if (leagueId == null || leagueId.isEmpty) throw StateError('space_current payload invalid');

    final doc = _firestore.collection('leagues').doc(leagueId).collection('space').doc('current');
    await doc.set(payload, SetOptions(merge: true));
  }

  Future<void> _batchUpsertList({
    required CollectionReference<Map<String, dynamic>> col,
    required List<dynamic> items,
  }) async {
    const chunkSize = 450;
    for (var i = 0; i < items.length; i += chunkSize) {
      final chunk = items.sublist(i, (i + chunkSize > items.length) ? items.length : i + chunkSize);
      final batch = _firestore.batch();
      for (final it in chunk) {
        final map = (it as Map).cast<String, dynamic>();
        final id = map['id'] as String;
        batch.set(col.doc(id), map, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  // --------------------------------------------------
  // CLOUD → LOCAL (member leagues only)
  // --------------------------------------------------

  Future<void> _syncCloudToLocal() async {
    // Rules require request.auth != null. Cached prefs uid is not enough.
    final authUid = _authUidOrEmpty();
    if (authUid.isEmpty) {
      debugPrint('SyncService → Cloud pull skipped (not signed in)');
      return;
    }

    final prefs = await PreferencesService.create();

    // Ensure prefs uid matches the *real* authenticated uid.
    final prefsUid = prefs.getCurrentUserId();
    if (prefsUid == null || prefsUid.trim().isEmpty || prefsUid.trim() != authUid) {
      await prefs.setCurrentUserId(authUid);
    }

    final lastPulledAtMs = prefs.getInt('cloud_last_pulled_at_ms') ?? 0;
    debugPrint('SyncService → Cloud pull start. uid=$authUid lastPulledAtMs=$lastPulledAtMs');

    QuerySnapshot<Map<String, dynamic>> leaguesSnap;
    try {
      leaguesSnap = await _firestore.collection('leagues').where('memberIds', arrayContains: authUid).get();
    } catch (e) {
      debugPrint('SyncService → Cloud pull FAILED at leagues query (non-fatal): $e');
      return;
    }

    final leagueIds = leaguesSnap.docs.map((d) => d.id).toList();

    await _upsertLeaguesLocal(
      prefs,
      leaguesSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return League.fromRemoteMap(data);
      }).toList(),
    );

    for (final leagueId in leagueIds) {
      try {
        await _pullTeams(prefs, leagueId);
        await _pullMatches(prefs, leagueId);
        await _pullKnockout(prefs, leagueId);
        await _pullMemberships(prefs, leagueId);
        await _pullAnnouncements(prefs, leagueId);
        await _pullSpaceCurrent(prefs, leagueId);
      } catch (e) {
        debugPrint('SyncService → Cloud pull partial failure leagueId=$leagueId (non-fatal): $e');
      }
    }

    await prefs.setInt('cloud_last_pulled_at_ms', DateTime.now().millisecondsSinceEpoch);
    debugPrint('SyncService → Cloud pull done. leagues=${leagueIds.length}');
  }

  Future<void> _upsertLeaguesLocal(PreferencesService prefs, List<League> leaguesToUpsert) async {
    final raw = prefs.getStringList(LocalLeaguesRepository.kLeaguesKey);
    final leagues = <League>[];

    for (final s in raw) {
      try {
        leagues.add(League.fromJsonString(s));
      } catch (_) {
        // skip malformed
      }
    }

    for (final l in leaguesToUpsert) {
      final idx = leagues.indexWhere((x) => x.id == l.id);
      if (idx >= 0) {
        leagues[idx] = l;
      } else {
        leagues.add(l);
      }
    }

    await prefs.setStringList(
      LocalLeaguesRepository.kLeaguesKey,
      leagues.map((l) => l.toJsonString()).toList(),
    );
  }

  Future<void> _pullTeams(PreferencesService prefs, String leagueId) async {
    final snap = await _firestore.collection('leagues').doc(leagueId).collection('teams').get();
    final teams = snap.docs.map((d) => Team.fromRemoteMap(d.data())).toList();

    final allRaw = prefs.getStringList(LocalLeaguesRepository.kTeamsKey);
    final all = allRaw.map((e) => Team.fromRemoteMap((jsonDecode(e) as Map).cast<String, dynamic>())).toList();

    all.removeWhere((t) => t.leagueId == leagueId);
    all.addAll(teams);

    await prefs.setStringList(
      LocalLeaguesRepository.kTeamsKey,
      all.map((t) => jsonEncode(t.toRemoteMap())).toList(),
    );
  }

  Future<void> _pullMatches(PreferencesService prefs, String leagueId) async {
    final snap = await _firestore.collection('leagues').doc(leagueId).collection('matches').get();
    final matches = snap.docs.map((d) => FixtureMatch.fromJson(d.data())).toList();

    final allRaw = prefs.getStringList(LocalLeaguesRepository.kMatchesKey);
    final all = allRaw.map((e) => FixtureMatch.fromJson((jsonDecode(e) as Map).cast<String, dynamic>())).toList();

    all.removeWhere((m) => m.leagueId == leagueId);
    all.addAll(matches);

    await prefs.setStringList(
      LocalLeaguesRepository.kMatchesKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  Future<void> _pullKnockout(PreferencesService prefs, String leagueId) async {
    final snap = await _firestore.collection('leagues').doc(leagueId).collection('knockout').get();
    final matches = snap.docs.map((d) => KnockoutMatch.fromJson(d.data())).toList();

    final allRaw = prefs.getStringList(LocalLeaguesRepository.kKnockoutMatchesKey);
    final all = allRaw.map((e) => KnockoutMatch.fromJson((jsonDecode(e) as Map).cast<String, dynamic>())).toList();

    all.removeWhere((m) => m.leagueId == leagueId);
    all.addAll(matches);

    await prefs.setStringList(
      LocalLeaguesRepository.kKnockoutMatchesKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  Future<void> _pullMemberships(PreferencesService prefs, String leagueId) async {
    final snap = await _firestore.collection('leagues').doc(leagueId).collection('memberships').get();
    final memberships = snap.docs.map((d) => Membership.fromRemoteMap(d.data())).toList();

    final allRaw = prefs.getStringList(LocalLeaguesRepository.kMembershipsKey);
    final all = allRaw.map((e) => Membership.fromRemoteMap((jsonDecode(e) as Map).cast<String, dynamic>())).toList();

    all.removeWhere((m) => m.leagueId == leagueId);
    all.addAll(memberships);

    await prefs.setStringList(
      LocalLeaguesRepository.kMembershipsKey,
      all.map((m) => jsonEncode(m.toRemoteMap())).toList(),
    );
  }

  Future<void> _pullAnnouncements(PreferencesService prefs, String leagueId) async {
    final snap = await _firestore.collection('leagues').doc(leagueId).collection('announcements').get();
    final anns = snap.docs.map((d) => LeagueAnnouncement.fromMap(d.data())).toList();

    final key = 'league_announcements_$leagueId';
    await prefs.setString(key, jsonEncode(anns.map((a) => a.toMap()).toList()));
  }

  Future<void> _pullSpaceCurrent(PreferencesService prefs, String leagueId) async {
    final doc = await _firestore.collection('leagues').doc(leagueId).collection('space').doc('current').get();
    if (!doc.exists) return;

    final space = LeagueSpace.fromJson(doc.data()!);
    await prefs.setString('league_space_$leagueId', jsonEncode(space.toJson()));
  }
}
