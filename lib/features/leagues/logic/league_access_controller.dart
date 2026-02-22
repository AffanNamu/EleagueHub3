import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_friendly_error.dart';
import 'coupon_codes_service.dart';
import 'league_access_service.dart';
import 'league_charges_payment_service.dart';
import 'league_charges_store.dart';

@immutable
final class LeagueAccessUiState {
  final bool checking;
  final bool busy;
  final LeagueAccessDecision? decision;
  final String? errorMessage;

  const LeagueAccessUiState({
    required this.checking,
    required this.busy,
    required this.decision,
    required this.errorMessage,
  });

  factory LeagueAccessUiState.initial({LeagueAccessDecision? cached}) => LeagueAccessUiState(
        checking: cached == null,
        busy: false,
        decision: cached,
        errorMessage: null,
      );

  LeagueAccessUiState copyWith({
    bool? checking,
    bool? busy,
    LeagueAccessDecision? decision,
    String? errorMessage,
  }) {
    return LeagueAccessUiState(
      checking: checking ?? this.checking,
      busy: busy ?? this.busy,
      decision: decision ?? this.decision,
      errorMessage: errorMessage,
    );
  }
}

final leagueAccessServiceProvider = Provider<LeagueAccessService>((ref) {
  return LeagueAccessService.instance;
});

final leagueAccessControllerProvider =
    StateNotifierProviderFamily.autoDispose<LeagueAccessController, LeagueAccessUiState, String>((ref, leagueId) {
  return LeagueAccessController(ref: ref, leagueId: leagueId);
});

class LeagueAccessController extends StateNotifier<LeagueAccessUiState> {
  LeagueAccessController({
    required Ref ref,
    required this.leagueId,
  })  : _ref = ref,
        super(LeagueAccessUiState.initial(cached: LeagueAccessService.instance.peekCachedDecision(leagueId: leagueId))) {
    unawaited(_init());
  }

  final Ref _ref;
  final String leagueId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _receiptSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _couponSub;

  String _uid() => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  Future<void> _init() async {
    // Owner fast-path from Firestore local cache (prevents owners seeing any loader in most cases).
    await _tryOwnerCacheFastPath();

    // Start reactive listeners (best-effort).
    _startReactiveWatches();

    // Server-verified check (security).
    await check(force: false, silentIfAlreadyAllowed: true);
  }

  Future<void> _tryOwnerCacheFastPath() async {
    try {
      final d = await _ref.read(leagueAccessServiceProvider).tryOwnerDecisionFromCache(leagueId: leagueId);
      if (d != null && d.allowed) {
        state = state.copyWith(checking: false, decision: d, errorMessage: null);
      }
    } catch (_) {
      // ignore
    }
  }

  void _startReactiveWatches() {
    final uid = _uid();
    if (uid.isEmpty) return;

    final fs = FirebaseFirestore.instance;

    _receiptSub?.cancel();
    _receiptSub = fs.collection('users').doc(uid).collection('leagueCharges').doc(leagueId).snapshots().listen(
      (_) => unawaited(check(force: true, silentIfAlreadyAllowed: true)),
      onError: (_) {},
    );

    _couponSub?.cancel();
    _couponSub = fs.collection('leagues').doc(leagueId).collection('couponRedemptions').doc(uid).snapshots().listen(
      (_) => unawaited(check(force: true, silentIfAlreadyAllowed: true)),
      onError: (_) {},
    );

    _ref.onDispose(() {
      _receiptSub?.cancel();
      _couponSub?.cancel();
    });
  }

  Future<LeagueAccessDecision?> check({
    bool force = false,
    bool silentIfAlreadyAllowed = false,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) {
      state = state.copyWith(checking: false, errorMessage: 'Please sign in to continue.');
      return state.decision;
    }

    final currentAllowed = state.decision?.allowed == true;
    final shouldShowChecking = !(silentIfAlreadyAllowed && currentAllowed);

    if (shouldShowChecking) {
      state = state.copyWith(checking: true, errorMessage: null);
    }

    try {
      final d = await _ref.read(leagueAccessServiceProvider).checkAccess(leagueId: leagueId, force: force);
      state = state.copyWith(checking: false, decision: d, errorMessage: null);

      // If allowed, ensure deterministic membership best-effort (for chat rules).
      if (d.allowed) {
        unawaited(_ref.read(leagueAccessServiceProvider).ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId));
      }

      return d;
    } catch (e) {
      final msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      state = state.copyWith(checking: false, errorMessage: msg);
      return state.decision;
    }
  }

  Future<void> payToUnlock(BuildContext context) async {
    if (state.busy) return;

    final uid = _uid();
    if (uid.isEmpty) {
      state = state.copyWith(errorMessage: 'Please sign in to continue.');
      return;
    }

    state = state.copyWith(busy: true, errorMessage: null);
    try {
      // If already paid, refresh decision.
      final alreadyPaid = await LeagueChargesStore.online().hasPaidCharges(userId: uid, leagueId: leagueId);
      if (alreadyPaid) {
        await _ref.read(leagueAccessServiceProvider).ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId);
        await check(force: true, silentIfAlreadyAllowed: true);
        return;
      }

      final leagueName = state.decision?.leagueName ?? _ref.read(leagueAccessServiceProvider).peekMeta(leagueId)?.name ?? 'this league';

      final pay = _ref.read(leagueChargesPaymentServiceProvider);
      final result = await pay.payLeagueCharges(
        context: context,
        userId: uid,
        leagueId: leagueId,
        leagueName: leagueName,
      );

      if (!result.success) {
        state = state.copyWith(errorMessage: result.errorMessage ?? 'Payment cancelled or not successful.');
        return;
      }

      final receipt = LeagueChargesReceipt(
        leagueId: leagueId,
        userId: uid,
        receiptId: result.receiptId ?? 'FLW-UNKNOWN',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await LeagueChargesStore.online().storeReceipt(receipt);

      await _ref.read(leagueAccessServiceProvider).ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId);
      await check(force: true, silentIfAlreadyAllowed: true);
    } catch (e) {
      final msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      state = state.copyWith(errorMessage: msg);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> redeemCouponCode(BuildContext context, String rawCode) async {
    if (state.busy) return;

    final uid = _uid();
    if (uid.isEmpty) {
      state = state.copyWith(errorMessage: 'Please sign in to continue.');
      return;
    }

    final code = rawCode.trim().toUpperCase();
    if (code.length < 6) {
      state = state.copyWith(errorMessage: 'Enter a valid coupon code.');
      return;
    }

    state = state.copyWith(busy: true, errorMessage: null);
    try {
      final leagueName = state.decision?.leagueName ?? _ref.read(leagueAccessServiceProvider).peekMeta(leagueId)?.name ?? 'this league';

      final res = await CouponCodesService().redeemWithCode(
        context: context,
        leagueId: leagueId,
        leagueName: leagueName,
        userId: uid,
        code: code,
      );

      if (!res.success) {
        state = state.copyWith(errorMessage: res.errorMessage ?? 'Coupon redemption failed.');
        return;
      }

      await _ref.read(leagueAccessServiceProvider).ensureDeterministicMembershipBestEffort(uid: uid, leagueId: leagueId);
      await check(force: true, silentIfAlreadyAllowed: true);
    } catch (e) {
      final msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      state = state.copyWith(errorMessage: msg);
    } finally {
      state = state.copyWith(busy: false);
    }
  }
}
