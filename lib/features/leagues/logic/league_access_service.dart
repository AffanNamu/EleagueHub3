import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';
import 'league_charges_store.dart';

enum LeagueAccessGrant {
  owner,
  purchased,
  coupon,
  none,
}

final class LeagueAccessDecision {
  final bool allowed;
  final LeagueAccessGrant grant;
  final String leagueId;
  final String leagueName;
  final String? denyMessage;
  final bool verifiedOnline;
  final int evaluatedAtMs;

  const LeagueAccessDecision({
    required this.allowed,
    required this.grant,
    required this.leagueId,
    required this.leagueName,
    required this.verifiedOnline,
    required this.evaluatedAtMs,
    this.denyMessage,
  });

  bool get isFresh {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMs = now - evaluatedAtMs;
    // Allowed can be cached longer for UX. Denied is short.
    final ttlMs = allowed ? 10 * 60 * 1000 : 30 * 1000;
    return ageMs >= 0 && ageMs <= ttlMs;
  }
}

final class LeagueMeta {
  final String leagueId;
  final String name;
  final String ownerUid;
  final String organizerUid;

  const LeagueMeta({
    required this.leagueId,
    required this.name,
    required this.ownerUid,
    required this.organizerUid,
  });

  bool isOwner(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return false;
    return ownerUid.trim() == u || organizerUid.trim() == u;
  }
}

final class LeagueAccessService {
  LeagueAccessService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static final LeagueAccessService instance = LeagueAccessService();

  final Map<String, LeagueMeta> _metaCache = <String, LeagueMeta>{};
  final Map<String, LeagueAccessDecision> _decisionCache = <String, LeagueAccessDecision>{};
  final Map<String, Future<LeagueAccessDecision>> _inFlight = <String, Future<LeagueAccessDecision>>{};

  String _uidOrEmpty() => _auth.currentUser?.uid.trim() ?? '';
  String _key(String uid, String leagueId) => '$uid::$leagueId';

  DocumentReference<Map<String, dynamic>> _leagueRef(String leagueId) => _firestore.collection('leagues').doc(leagueId);

  LeagueAccessDecision? peekCachedDecision({required String leagueId}) {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return null;
    final d = _decisionCache[_key(uid, leagueId)];
    if (d == null) return null;
    if (!d.isFresh) return null;
    // Only trust cached ALLOW if it was verified online at time of evaluation.
    if (d.allowed && !d.verifiedOnline) return null;
    return d;
  }

  void invalidate({required String leagueId}) {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return;
    _decisionCache.remove(_key(uid, leagueId));
  }

  Future<LeagueMeta> _fetchLeagueMeta({
    required String leagueId,
    required Source source,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final snap = await _leagueRef(leagueId)
        .get(GetOptions(source: source))
        .timeout(timeout);

    if (!snap.exists) {
      throw StateError('League not found.');
    }

    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final rawName = (data['name'] as String?)?.trim();
    final name = (rawName != null && rawName.isNotEmpty) ? rawName : 'this league';

    final meta = LeagueMeta(
      leagueId: leagueId,
      name: name,
      ownerUid: (data['ownerUid'] ?? '').toString().trim(),
      organizerUid: (data['organizerUid'] ?? '').toString().trim(),
    );

    _metaCache[leagueId] = meta;
    return meta;
  }

  LeagueMeta? peekMeta(String leagueId) => _metaCache[leagueId];

  Future<LeagueAccessDecision?> tryOwnerDecisionFromCache({required String leagueId}) async {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return null;

    try {
      final meta = await _fetchLeagueMeta(
        leagueId: leagueId,
        source: Source.cache,
        timeout: const Duration(milliseconds: 250),
      );

      if (!meta.isOwner(uid)) return null;

      final decision = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.owner,
        leagueId: leagueId,
        leagueName: meta.name,
        denyMessage: null,
        verifiedOnline: false, // cache path
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      // Store as "not verified online", but still usable for immediate owner UX.
      // Controller/UI will still do online check in background.
      _decisionCache[_key(uid, leagueId)] = decision;
      return decision;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasPaidReceiptServer({required String uid, required String leagueId}) {
    return LeagueChargesStore.online().hasPaidCharges(userId: uid, leagueId: leagueId);
  }

  Future<bool> _hasPaidCouponServer({required String uid, required String leagueId}) async {
    final snap = await _leagueRef(leagueId)
        .collection('couponRedemptions')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    if (!snap.exists) return false;
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    // SECURITY: do NOT treat "pending" as access.
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    final paidAtMs = (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;

    if (status == 'paid') return true;
    if (paidAtMs > 0 && status.isEmpty) return true; // legacy fallback (if any)
    return false;
  }

  Future<void> ensureDeterministicMembershipBestEffort({
    required String uid,
    required String leagueId,
  }) async {
    // Best-effort only. Do not throw; do not block access.
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _leagueRef(leagueId)
          .collection('memberships')
          .doc(uid)
          .set(
            <String, dynamic>{
              'id': uid,
              'leagueId': leagueId,
              'userId': uid,
              'teamId': null,
              'role': 0,
              'updatedAtMs': now,
              'version': 1,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // ignore
    }
  }

  Future<LeagueAccessDecision> checkAccess({
    required String leagueId,
    bool force = false,
  }) async {
    final uid = _uidOrEmpty();

    if (uid.isEmpty) {
      return LeagueAccessDecision(
        allowed: false,
        grant: LeagueAccessGrant.none,
        leagueId: leagueId,
        leagueName: peekMeta(leagueId)?.name ?? 'this league',
        denyMessage: 'Please sign in to continue.',
        verifiedOnline: false,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    final cached = peekCachedDecision(leagueId: leagueId);
    if (!force && cached != null) return cached;

    final inflightKey = _key(uid, leagueId);
    final existing = _inFlight[inflightKey];
    if (existing != null) return existing;

    final fut = _checkAccessInternal(uid: uid, leagueId: leagueId, force: force);
    _inFlight[inflightKey] = fut;

    try {
      return await fut;
    } finally {
      _inFlight.remove(inflightKey);
    }
  }

  Future<LeagueAccessDecision> _checkAccessInternal({
    required String uid,
    required String leagueId,
    required bool force,
  }) async {
    await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

    final meta = await _fetchLeagueMeta(leagueId: leagueId, source: Source.server);

    // STEP 1: OWNER
    if (meta.isOwner(uid)) {
      // Best-effort membership for chat/rules
      unawaited(ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId));

      final d = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.owner,
        leagueId: leagueId,
        leagueName: meta.name,
        denyMessage: null,
        verifiedOnline: true,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      _decisionCache[_key(uid, leagueId)] = d;
      return d;
    }

    // STEP 2: PURCHASED
    final paid = await _hasPaidReceiptServer(uid: uid, leagueId: leagueId);
    if (paid) {
      await ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId);

      final d = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.purchased,
        leagueId: leagueId,
        leagueName: meta.name,
        denyMessage: null,
        verifiedOnline: true,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      _decisionCache[_key(uid, leagueId)] = d;
      return d;
    }

    // STEP 3: USED COUPON (PAID status only)
    final coupon = await _hasPaidCouponServer(uid: uid, leagueId: leagueId);
    if (coupon) {
      await ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId);

      final d = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.coupon,
        leagueId: leagueId,
        leagueName: meta.name,
        denyMessage: null,
        verifiedOnline: true,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      _decisionCache[_key(uid, leagueId)] = d;
      return d;
    }

    // STEP 4: BLOCK
    final d = LeagueAccessDecision(
      allowed: false,
      grant: LeagueAccessGrant.none,
      leagueId: leagueId,
      leagueName: meta.name,
      denyMessage: 'You don’t have access to ${meta.name} yet.',
      verifiedOnline: true,
      evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _decisionCache[_key(uid, leagueId)] = d;
    return d;
  }
}
