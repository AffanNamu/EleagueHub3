import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../logic/league_charges_payment_service.dart';
import '../logic/league_charges_store.dart';

enum _MembershipStatus { none, deterministic, legacy }

class LeagueAccessGuard extends ConsumerStatefulWidget {
  final String leagueId;
  final Widget child;

  const LeagueAccessGuard({
    super.key,
    required this.leagueId,
    required this.child,
  });

  @override
  ConsumerState<LeagueAccessGuard> createState() => _LeagueAccessGuardState();
}

class _LeagueAccessGuardState extends ConsumerState<LeagueAccessGuard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  bool _allowed = false;
  String? _errorMessage;

  // UI actions
  final TextEditingController _couponCtrl = TextEditingController();
  bool _actionBusy = false;

  // Cached league info (for nicer UX + payment descriptions)
  String _leagueName = 'this league';

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _checkAccess();
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? cs.error : null,
        content: Text(msg),
      ),
    );
  }

  void _toastErr(Object e) => _toast(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')), error: true);

  DocumentReference<Map<String, dynamic>> _leagueRef() => _firestore.collection('leagues').doc(widget.leagueId);

  Future<_MembershipStatus> _membershipStatusServer(String uid) async {
    // Deterministic doc (preferred)
    final direct = await _leagueRef()
        .collection('memberships')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (direct.exists) return _MembershipStatus.deterministic;

    // Legacy fallback: any doc where userId == uid
    final qs = await _leagueRef()
        .collection('memberships')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    return qs.docs.isNotEmpty ? _MembershipStatus.legacy : _MembershipStatus.none;
  }

  Future<void> _upsertDeterministicMembershipOnly(String uid) async {
    // IMPORTANT: This is the fix for your league chat permission issue.
    // Chat rules allow access when memberships/{uid} exists.
    // Older data might have random membership doc ids → guard may pass but chat rules fail.
    final now = DateTime.now().millisecondsSinceEpoch;

    await _leagueRef()
        .collection('memberships')
        .doc(uid)
        .set(
          <String, dynamic>{
            'id': uid,
            'leagueId': widget.leagueId,
            'userId': uid,
            'teamId': null,
            'role': 0,
            'updatedAtMs': now,
            'version': 1,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<bool> _hasPaidChargesServer(String uid) async {
    final store = LeagueChargesStore.online();
    return store.hasPaidCharges(userId: uid, leagueId: widget.leagueId);
  }

  Future<void> _checkAccess() async {
    setState(() {
      _loading = true;
      _allowed = false;
      _errorMessage = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final doc = await _leagueRef().get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 15));
      if (!doc.exists) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _loading = false;
          _errorMessage = 'We couldn’t find this league.';
        });
        return;
      }

      final data = doc.data() ?? <String, dynamic>{};
      _leagueName = (data['name'] as String?)?.trim().isNotEmpty == true ? (data['name'] as String).trim() : 'this league';

      final memberIdsRaw = data['memberIds'];
      final memberIds = (memberIdsRaw is List)
          ? memberIdsRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet()
          : <String>{};

      final organizerUid = (data['organizerUid'] ?? '').toString().trim();
      final ownerUid = (data['ownerUid'] ?? '').toString().trim();

      // Allowed if owner or listed memberIds
      var allowed = memberIds.contains(uid) || organizerUid == uid || ownerUid == uid;

      // Otherwise, check membership collection (including legacy)
      if (!allowed) {
        final st = await _membershipStatusServer(uid);
        if (st != _MembershipStatus.none) {
          allowed = true;

          // FIX: if legacy membership exists, create deterministic memberships/{uid}
          // so chat rules and other rule checks work reliably.
          if (st == _MembershipStatus.legacy) {
            await _upsertDeterministicMembershipOnly(uid);
          }
        }
      }

      // Otherwise, allow if user has paid receipt; also ensure memberships/{uid} exists for chat rules.
      if (!allowed) {
        final paid = await _hasPaidChargesServer(uid);
        if (paid) {
          allowed = true;
          await _upsertDeterministicMembershipOnly(uid);
        }
      }

      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _loading = false;
        _errorMessage = allowed ? null : 'You don’t have access to $_leagueName yet.';
      });
    } catch (e) {
      if (!mounted) return;

      var msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      if (msg == 'You don\'t have permission to do that right now.') {
        msg = 'You don’t have access to $_leagueName yet.';
      }

      setState(() {
        _errorMessage = msg;
        _loading = false;
        _allowed = false;
      });
    }
  }

  String _normalizeCoupon(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll(RegExp(r'[^A-Z0-9_]'), '');
  }

  Future<void> _redeemCouponAndUnlock() async {
    if (_actionBusy) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }

    final code = _normalizeCoupon(_couponCtrl.text);
    if (code.isEmpty || code.length < 6) {
      _toast('Enter a valid coupon code.', error: true);
      return;
    }

    setState(() => _actionBusy = true);

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;

      final couponRef = _leagueRef().collection('couponCodes').doc(code);
      final redemptionRef = _leagueRef().collection('couponRedemptions').doc(uid);

      await _firestore.runTransaction((tx) async {
        final leagueSnap = await tx.get(_leagueRef());
        if (!leagueSnap.exists) throw StateError('League not found.');

        final couponSnap = await tx.get(couponRef);
        if (!couponSnap.exists) throw StateError('Invalid coupon code.');

        final couponData = (couponSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final usedBy = (couponData['usedBy'] as String? ?? '').trim();
        if (usedBy.isNotEmpty) throw StateError('This coupon has already been used.');

        tx.update(couponRef, <String, dynamic>{
          'usedBy': uid,
          'usedAtMs': now,
          'updatedAtMs': now,
        });

        tx.set(
          redemptionRef,
          <String, dynamic>{
            'userId': uid,
            'couponCode': code,
            'usedAtMs': now,
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );

        // Deterministic membership for rules
        tx.set(
          _leagueRef().collection('memberships').doc(uid),
          <String, dynamic>{
            'id': uid,
            'leagueId': widget.leagueId,
            'userId': uid,
            'teamId': null,
            'role': 0,
            'updatedAtMs': now,
            'version': 1,
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 25));

      _couponCtrl.clear();
      _toast('Coupon redeemed. Access unlocked.');
      await _checkAccess();
    } catch (e) {
      _toastErr(e);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _payAndUnlock() async {
    if (_actionBusy) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }

    setState(() => _actionBusy = true);

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      // Avoid double charging
      final alreadyPaid = await _hasPaidChargesServer(uid);
      if (alreadyPaid) {
        await _upsertDeterministicMembershipOnly(uid);
        _toast('Access unlocked.');
        await _checkAccess();
        return;
      }

      final pay = ref.read(leagueChargesPaymentServiceProvider);

      final result = await pay.payLeagueCharges(
        context: context,
        userId: uid,
        leagueId: widget.leagueId,
        leagueName: _leagueName,
      );

      if (!mounted) return;

      if (!result.success) {
        _toast(result.errorMessage ?? 'Payment cancelled or not successful.', error: true);
        return;
      }

      // Store receipt under: users/{uid}/leagueCharges/{leagueId}
      final receipt = LeagueChargesReceipt(
        leagueId: widget.leagueId,
        userId: uid,
        receiptId: result.receiptId ?? 'FLW-UNKNOWN',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await LeagueChargesStore.online().storeReceipt(receipt);

      // Ensure deterministic membership for rules (especially chatroom).
      await _upsertDeterministicMembershipOnly(uid);

      _toast('Payment successful. Access unlocked.');
      await _checkAccess();
    } catch (e) {
      _toastErr(e);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return widget.child;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Checking access...',
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.60),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final message = (_errorMessage ?? 'You don’t have access yet.').trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 26,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withOpacity(0.25),
                        cs.primary.withOpacity(0.08),
                      ],
                    ),
                  ),
                  child: Icon(Icons.lock_outline_rounded, color: cs.primary, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  'Access Restricted',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.3,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unlock access',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _actionBusy ? null : _payAndUnlock,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                            _actionBusy ? 'Processing…' : 'Pay to unlock',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Or use a coupon',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withOpacity(0.70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _couponCtrl,
                        enabled: !_actionBusy,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.confirmation_number_outlined),
                          hintText: 'Enter coupon code',
                          filled: true,
                          fillColor: cs.onSurface.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: cs.onSurface.withOpacity(0.12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: cs.onSurface.withOpacity(0.12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: cs.primary.withOpacity(0.55)),
                          ),
                        ),
                        onSubmitted: (_) => _redeemCouponAndUnlock(),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _actionBusy ? null : _redeemCouponAndUnlock,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text(
                            'Redeem coupon',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                        label: const Text('Back', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _actionBusy ? null : _checkAccess,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                Text(
                  'Tip: If you were just approved/added, tap Retry.',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.45),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
