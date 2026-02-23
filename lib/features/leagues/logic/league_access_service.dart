import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';
import 'league_charges_store.dart';

enum LeagueAccessGrant {
  owner,
  purchased,
  coupon,
  freeClassicParticipant,
  none,
}

final class LeagueAccessDecision {
  final bool allowed;
  final LeagueAccessGrant grant;
  final String leagueId;
  final String leagueName;

  /// True when league format is classic (participants can view for free).
  final bool isClassicLeague;

  final bool verifiedOnline;
  final String? denyMessage;
  final int evaluatedAtMs;

  const LeagueAccessDecision({
    required this.allowed,
    required this.grant,
    required this.leagueId,
    required this.leagueName,
    required this.isClassicLeague,
    required this.verifiedOnline,
    required this.evaluatedAtMs,
    this.denyMessage,
  });

  bool get isFresh {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMs = now - evaluatedAtMs;
    final ttlMs = allowed ? 10 * 60 * 1000 : 25 * 1000;
    return ageMs >= 0 && ageMs <= ttlMs;
  }
}

enum _MembershipStatus { none, deterministic, legacy }

final class _LeagueMeta {
  final String leagueId;
  final String name;
  final String ownerUid;
  final String organizerUid;
  final bool isClassicLeague;
  final Set<String> memberIds;

  const _LeagueMeta({
    required this.leagueId,
    required this.name,
    required this.ownerUid,
    required this.organizerUid,
    required this.isClassicLeague,
    required this.memberIds,
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

  static final LeagueAccessService instance = LeagueAccessService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  final Map<String, _LeagueMeta> _metaCache = <String, _LeagueMeta>{};
  final Map<String, LeagueAccessDecision> _decisionCache = <String, LeagueAccessDecision>{};
  final Map<String, Future<LeagueAccessDecision>> _inFlight = <String, Future<LeagueAccessDecision>>{};

  String _uidOrEmpty() => _auth.currentUser?.uid.trim() ?? '';
  String _key(String uid, String leagueId) => '$uid::$leagueId';

  DocumentReference<Map<String, dynamic>> _leagueRef(String leagueId) => _firestore.collection('leagues').doc(leagueId);

  LeagueAccessDecision? peekCachedDecision({required String leagueId}) {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return null;

    final d = _decisionCache[_key(uid, leagueId)];
    if (d == null || !d.isFresh) return null;

    // Only trust cached allows if they were online-verified, except owner cached allows (safe UX fast-path).
    if (d.allowed && !d.verifiedOnline && d.grant != LeagueAccessGrant.owner) return null;

    return d;
  }

  Future<_LeagueMeta?> tryLeagueMetaFromFirestoreCache(String leagueId) async {
    try {
      final snap = await _leagueRef(leagueId)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 250));
      if (!snap.exists) return null;

      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final meta = _parseMeta(leagueId: leagueId, data: data);
      _metaCache[leagueId] = meta;
      return meta;
    } catch (_) {
      return null;
    }
  }

  Future<_LeagueMeta> _fetchMetaServer(String leagueId) async {
    final snap = await _leagueRef(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) throw StateError('League not found.');

    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final meta = _parseMeta(leagueId: leagueId, data: data);
    _metaCache[leagueId] = meta;
    return meta;
  }

  _LeagueMeta _parseMeta({required String leagueId, required Map<String, dynamic> data}) {
    final rawName = (data['name'] as String?)?.trim();
    final name = (rawName != null && rawName.isNotEmpty) ? rawName : 'this league';

    final ownerUid = (data['ownerUid'] ?? '').toString().trim();
    final organizerUid = (data['organizerUid'] ?? '').toString().trim();

    final memberIdsRaw = data['memberIds'];
    final memberIds = (memberIdsRaw is List)
        ? memberIdsRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet()
        : <String>{};

    final isClassicLeague = _isClassicLeague(data);

    return _LeagueMeta(
      leagueId: leagueId,
      name: name,
      ownerUid: ownerUid,
      organizerUid: organizerUid,
      isClassicLeague: isClassicLeague,
      memberIds: memberIds,
    );
  }

  bool _isClassicLeague(Map<String, dynamic> data) {
    // Most projects store LeagueFormat as enum index (int) under "format".
    final v = data['format'] ?? data['leagueFormat'] ?? data['formatIndex'] ?? data['type'];

    // Optional explicit flags if you ever add them.
    final flag = data['isClassic'] ?? data['classic'];
    if (flag is bool) return flag;

    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'classic' || s.contains('classic');
    }

    if (v is int) {
      // Conservative: LeagueFormat.classic is typically index 0.
      return v == 0;
    }

    if (v is num) {
      return v.toInt() == 0;
    }

    return false;
  }

  Future<_MembershipStatus> _membershipStatusServer({
    required String leagueId,
    required String uid,
  }) async {
    final direct = await _leagueRef(leagueId)
        .collection('memberships')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (direct.exists) return _MembershipStatus.deterministic;

    final qs = await _leagueRef(leagueId)
        .collection('memberships')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    return qs.docs.isNotEmpty ? _MembershipStatus.legacy : _MembershipStatus.none;
  }

  Future<void> ensureDeterministicMembershipBestEffort({
    required String leagueId,
    required String uid,
  }) async {
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
              'teamId': null, // viewer-safe
              'role': 1,
              'updatedAtMs': now,
              'version': 1,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // best-effort
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

    // SECURITY: pending is NOT access.
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    final paidAtMs = (data['paidAtMs'] is num) ? (data['paidAtMs'] as num).toInt() : 0;

    if (status == 'paid') return true;
    if (status.isEmpty && paidAtMs > 0) return true; // legacy tolerance

    return false;
  }

  /// Owner fast-path (uses Firestore local cache if available) to avoid owners seeing any loader.
  Future<LeagueAccessDecision?> tryOwnerAllowFast({
    required String leagueId,
  }) async {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return null;

    final meta = _metaCache[leagueId] ?? await tryLeagueMetaFromFirestoreCache(leagueId);
    if (meta == null) return null;

    if (!meta.isOwner(uid)) return null;

    final d = LeagueAccessDecision(
      allowed: true,
      grant: LeagueAccessGrant.owner,
      leagueId: leagueId,
      leagueName: meta.name,
      isClassicLeague: meta.isClassicLeague,
      verifiedOnline: false,
      evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _decisionCache[_key(uid, leagueId)] = d;
    return d;
  }

  /// ACCESS ORDER (UPDATED PER YOUR REQUIREMENT):
  /// 1) Owner -> allow
  /// 2) Purchased -> allow (even if classic)
  /// 3) Coupon paid -> allow (even if classic)
  /// 4) Classic participant -> allow for free
  /// 5) Otherwise -> deny (classic viewers can still pay/coupon via UI)
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
        leagueName: _metaCache[leagueId]?.name ?? 'this league',
        isClassicLeague: _metaCache[leagueId]?.isClassicLeague ?? false,
        verifiedOnline: false,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
        denyMessage: 'Please sign in to continue.',
      );
    }

    final cached = peekCachedDecision(leagueId: leagueId);
    if (!force && cached != null) return cached;

    final k = _key(uid, leagueId);
    final inflight = _inFlight[k];
    if (inflight != null) return inflight;

    final fut = _checkAccessInternal(uid: uid, leagueId: leagueId);
    _inFlight[k] = fut;

    try {
      return await fut;
    } finally {
      _inFlight.remove(k);
    }
  }

  Future<LeagueAccessDecision> _checkAccessInternal({
    required String uid,
    required String leagueId,
  }) async {
    await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
    final meta = await _fetchMetaServer(leagueId);

    // STEP 1: OWNER
    if (meta.isOwner(uid)) {
      unawaited(ensureDeterministicMembershipBestEffort(leagueId: leagueId, uid: uid));

      final d = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.owner,
        leagueId: leagueId,
        leagueName: meta.name,
        isClassicLeague: meta.isClassicLeague,
        verifiedOnline: true,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _decisionCache[_key(uid, leagueId)] = d;
      return d;
    }

    // STEP 2: PURCHASED (works for classic viewers too)
    final paid = await _hasPaidReceiptServer(uid: uid, leagueId: leagueId);
    if (paid) {
      await ensureDeterministicMembershipBestEffort(leagueId: leagueId, uid: uid);

      final d = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.purchased,
        leagueId: leagueId,
        leagueName: meta.name,
        isClassicLeague: meta.isClassicLeague,
        verifiedOnline: true,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _decisionCache[_key(uid, leagueId)] = d;
      return d;
    }

    // STEP 3: COUPON (PAID) (works for classic viewers too)
    final couponPaid = await _hasPaidCouponServer(uid: uid, leagueId: leagueId);
    if (couponPaid) {
      await ensureDeterministicMembershipBestEffort(leagueId: leagueId, uid: uid);

      final d = LeagueAccessDecision(
        allowed: true,
        grant: LeagueAccessGrant.coupon,
        leagueId: leagueId,
        leagueName: meta.name,
        isClassicLeague: meta.isClassicLeague,
        verifiedOnline: true,
        evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _decisionCache[_key(uid, leagueId)] = d;
      return d;
    }

    // STEP 4: CLASSIC PARTICIPANT FREE
    if (meta.isClassicLeague) {
      var isParticipant = meta.memberIds.contains(uid);

      if (!isParticipant) {
        final st = await _membershipStatusServer(leagueId: leagueId, uid: uid);
        isParticipant = st != _MembershipStatus.none;

        if (st == _MembershipStatus.legacy) {
          await ensureDeterministicMembershipBestEffort(leagueId: leagueId, uid: uid);
        }
      }

      if (isParticipant) {
        final d = LeagueAccessDecision(
          allowed: true,
          grant: LeagueAccessGrant.freeClassicParticipant,
          leagueId: leagueId,
          leagueName: meta.name,
          isClassicLeague: true,
          verifiedOnline: true,
          evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _decisionCache[_key(uid, leagueId)] = d;
        return d;
      }
    }

    // STEP 5: DENY (classic viewers can still pay/coupon in UI)
    final deny = meta.isClassicLeague
        ? 'This is a classic league. Participants enter free. Viewers can pay the entry fee or redeem a coupon to unlock ${meta.name}.'
        : 'Pay the entry fee or redeem a coupon to unlock ${meta.name}.';

    final d = LeagueAccessDecision(
      allowed: false,
      grant: LeagueAccessGrant.none,
      leagueId: leagueId,
      leagueName: meta.name,
      isClassicLeague: meta.isClassicLeague,
      verifiedOnline: true,
      evaluatedAtMs: DateTime.now().millisecondsSinceEpoch,
      denyMessage: deny,
    );
    _decisionCache[_key(uid, leagueId)] = d;
    return d;
  }
}
