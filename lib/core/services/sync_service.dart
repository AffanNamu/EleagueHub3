import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  bool _boolFromAny(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return fallback;
  }

  int _intFromAny(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static const String _couponAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Random _couponRnd = Random.secure();

  String _randomCouponToken(int length) {
    return List.generate(length, (_) => _couponAlphabet[_couponRnd.nextInt(_couponAlphabet.length)]).join();
  }

  String _generateCouponCode() {
    // Readable + shareable + docId-safe.
    // Collision is extremely unlikely due to Random.secure + 12-char token.
    return 'EH${_randomCouponToken(12)}';
  }

  Future<void> _maybeAutoGenerateInitialCoupons({
    required DocumentReference<Map<String, dynamic>> leagueRef,
    required Map<String, dynamic> leaguePayload,
  }) async {
    final couponsEnabled = _boolFromAny(leaguePayload['couponsEnabled'], fallback: false);
    if (!couponsEnabled) return;

    final discountPercent = _intFromAny(leaguePayload['couponDiscountPercent'], fallback: 0).clamp(0, 100);
    if (discountPercent <= 0) return;

    // Don’t generate coupons for finished leagues.
    final finishedFromPayload = _boolFromAny(leaguePayload['isFinished'], fallback: false);
    if (finishedFromPayload) return;

    final organizerUserId = (leaguePayload['organizerUserId'] as String?)?.trim() ?? '';
    if (organizerUserId.isEmpty) return;

    // Idempotency: if any coupon exists, do nothing.
    // This avoids duplicates if sync retries.
    final existing = await leagueRef.collection('coupons').limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final maxTeams = _intFromAny(leaguePayload['maxTeams'], fallback: 0);
    // Initial batch: enough for expected participants, but organizer can generate unlimited later.
    // Cap to stay well within Firestore batch write limits.
    final initialCount = (maxTeams > 0 ? maxTeams : 20).clamp(1, 200);

    final now = DateTime.now().millisecondsSinceEpoch;

    final batch = _firestore.batch();

    // Mark on league doc that we attempted initial generation (best-effort traceability).
    batch.set(
      leagueRef,
      <String, dynamic>{
        'couponsEnabled': true,
        'couponDiscountPercent': discountPercent,
        'couponsAutoGeneratedAtMs': now,
        'couponsAutoGeneratedCount': initialCount,
        'updatedAtMs': now,
      },
      SetOptions(merge: true),
    );

    for (int i = 0; i < initialCount; i++) {
      final code = _generateCouponCode();
      final couponRef = leagueRef.collection('coupons').doc(code);

      batch.set(
        couponRef,
        <String, dynamic>{
          'leagueId': leagueRef.id,
          'code': code,
          'organizerUserId': organizerUserId,
          'discountPercent': discountPercent,
          'usedBy': '',
          'usedAtMs': 0,
          'createdAtMs': now,
          'updatedAtMs': now,
          'version': 1,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> _uploadLeague(SyncQueueItem item) async {
    final ref = _firestore.collection('leagues').doc(item.entityId);

    if (item.action == 'delete') {
      await ref.delete();
      return;
    }

    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for league');

    final data = Map<String, dynamic>.from(payload);
    data['id'] = item.entityId;

    final ownerId = (data['organizerUserId'] as String?) ?? '';
    data['ownerId'] = ownerId;

    final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
    data['isPrivate'] = isPrivate;

    final existing = (data['memberIds'] as List?)?.cast<dynamic>() ?? const [];
    data['memberIds'] = <String>{
      ...existing.map((e) => e.toString()),
      if (ownerId.isNotEmpty) ownerId,
    }.toList();

    await ref.set(data, SetOptions(merge: true));

    // Automatic coupon generation:
    // - only when organizer selected coupons at creation (couponsEnabled=true)
    // - only after successful payment (enforced by app: couponsEnabled stored only after payment success)
    // - tied to league creation sync (this upload)
    //
    // Best-effort: coupon generation should never block the league upload.
    try {
      await _maybeAutoGenerateInitialCoupons(
        leagueRef: ref,
        leaguePayload: data,
      );
    } catch (e, st) {
      debugPrint('SyncService → Coupon auto-generation failed for leagueId=${ref.id} (non-fatal): $e');
      debugPrint('$st');
    }
  }

  Future<void> _uploadLeagueJoin(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for league_join');

    final code = (payload['code'] as String?)?.trim().toUpperCase();
    final userId = (payload['userId'] as String?)?.trim();
    if (code == null || userId == null) throw StateError('Invalid league_join payload');

    final snap = await _firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();
    if (snap.docs.isEmpty) throw StateError('League not found for Join ID: $code');

    final leagueId = snap.docs.first.id;
    await _firestore.collection('leagues').doc(leagueId).set(
      {
        'memberIds': FieldValue.arrayUnion([userId]),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _uploadMembership(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for membership');

    final leagueId = payload['leagueId'] as String?;
    if (leagueId == null || leagueId.isEmpty) throw StateError('membership payload missing leagueId');

    final doc = _firestore.collection('leagues').doc(leagueId).collection('memberships').doc(item.entityId);
    await doc.set(payload, SetOptions(merge: true));
  }

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

  Future<void> _uploadKnockoutReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for knockout_replace');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || matches == null) throw StateError('knockout_replace payload invalid');

    final col = _firestore.collection('leagues').doc(leagueId).collection('knockout');
    await _batchUpsertList(col: col, items: matches);
  }

  Future<void> _uploadAnnouncement(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for announcement');

    final leagueId = payload['leagueId'] as String?;
    final annId = payload['id'] as String?;
    if (leagueId == null || annId == null) throw StateError('announcement payload invalid');

    final doc = _firestore.collection('leagues').doc(leagueId).collection('announcements').doc(annId);
    await doc.set(payload, SetOptions(merge: true));
  }

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
    final prefs = await PreferencesService.create();
    final uid = prefs.getCurrentUserId();
    if (uid == null || uid.isEmpty) {
      debugPrint('SyncService → Cloud pull skipped (no uid)');
      return;
    }

    final lastPulledAtMs = prefs.getInt('cloud_last_pulled_at_ms') ?? 0;
    debugPrint('SyncService → Cloud pull start. uid=$uid lastPulledAtMs=$lastPulledAtMs');

    QuerySnapshot<Map<String, dynamic>> leaguesSnap;
    try {
      leaguesSnap = await _firestore.collection('leagues').where('memberIds', arrayContains: uid).get();
    } catch (e) {
      debugPrint('SyncService → Cloud pull FAILED at leagues query (non-fatal): $e');
      return;
    }

    final leagueIds = leaguesSnap.docs.map((d) => d.id).toList();

    // Upsert leagues into local list
    await _upsertLeaguesLocal(prefs, leaguesSnap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return League.fromRemoteMap(data);
    }).toList());

    // Pull subcollections per league (best-effort per league)
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
    final leagues = raw.map((e) => League.fromJsonString(e)).toList();

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
