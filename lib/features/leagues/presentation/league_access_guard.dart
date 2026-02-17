import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../logic/league_charges_payment_service.dart';
import '../logic/league_charges_store.dart';

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

  Future<bool> _hasMembershipServer(String leagueId, String uid) async {
    // Fast path: deterministic doc id == uid (your ParticipantsService uses this).
    final direct = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .collection('memberships')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    if (direct.exists) return true;

    // Backward-compatible fallback: any membership doc where userId == uid.
    final qs = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .collection('memberships')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    return qs.docs.isNotEmpty;
  }

  Future<bool> _hasPaidChargesServer(String leagueId, String uid) async {
    final store = LeagueChargesStore.online();
    return store.hasPaidCharges(userId: uid, leagueId: leagueId);
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

      final doc = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

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

      // Access is allowed if:
      // - organizer/owner
      // - in leagues/{leagueId}.memberIds
      // - OR a membership doc exists (canonical participant storage in your app)
      // - OR user has a leagueCharges receipt (pay-to-access)
      var allowed = memberIds.contains(uid) || organizerUid == uid || ownerUid == uid;

      if (!allowed) {
        allowed = await _hasMembershipServer(widget.leagueId, uid);
      }

      if (!allowed) {
        allowed = await _hasPaidChargesServer(widget.leagueId, uid);
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
    // Keep underscores, remove spaces/dashes and non A-Z/0-9/_.
    return raw
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll(RegExp(r'[^A-Z0-9_]'), '');
  }

  Future<void> _ensureMemberAccessWrite(String uid) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final leagueRef = _firestore.collection('leagues').doc(widget.leagueId);
    final membershipRef = leagueRef.collection('memberships').doc(uid);

    await _firestore.runTransaction((tx) async {
      tx.set(
        membershipRef,
        <String, dynamic>{
          'id': uid,
          'leagueId': widget.leagueId,
          'userId': uid,
          'teamId': null,
          'role': 0, // member
          'updatedAtMs': now,
          'version': 1,
        },
        SetOptions(merge: true),
      );

      // Keep memberIds array in sync (older UI + rules read this in multiple places).
      tx.update(leagueRef, <String, dynamic>{
        'memberIds': FieldValue.arrayUnion([uid]),
        'updatedAtMs': now,
      });
    }).timeout(const Duration(seconds: 25));
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

      final leagueRef = _firestore.collection('leagues').doc(widget.leagueId);
      final couponRef = leagueRef.collection('couponCodes').doc(code);
      final redemptionRef = leagueRef.collection('couponRedemptions').doc(uid);
      final membershipRef = leagueRef.collection('memberships').doc(uid);

      await _firestore.runTransaction((tx) async {
        final leagueSnap = await tx.get(leagueRef);
        if (!leagueSnap.exists) {
          throw StateError('League not found.');
        }

        final couponSnap = await tx.get(couponRef);
        if (!couponSnap.exists) {
          throw StateError('Invalid coupon code.');
        }

        final couponData = (couponSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final usedBy = (couponData['usedBy'] as String? ?? '').trim();
        if (usedBy.isNotEmpty) {
          throw StateError('This coupon has already been used.');
        }

        // Mark coupon as used (RULES require exactly these keys)
        tx.update(couponRef, <String, dynamic>{
          'usedBy': uid,
          'usedAtMs': now,
          'updatedAtMs': now,
        });

        // Record redemption (rules require userId == auth uid)
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

        // Ensure membership exists (role 0 = member)
        tx.set(
          membershipRef,
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

        // Keep memberIds array in sync
        tx.update(leagueRef, <String, dynamic>{
          'memberIds': FieldValue.arrayUnion([uid]),
          'updatedAtMs': now,
        });
      }).timeout(const Duration(seconds: 25));

      _couponCtrl.clear();
      _toast('Coupon redeemed. Access unlocked.');
      await _checkAccess();
    } catch (e) {
      _toast(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')), error: true);
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

      // If user already has a receipt, don't charge again—just ensure membership exists.
      final alreadyPaid = await _hasPaidChargesServer(widget.leagueId, uid);
      if (alreadyPaid) {
        await _ensureMemberAccessWrite(uid);
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

      try {
        await LeagueChargesStore.online().storeReceipt(receipt);
      } catch (e) {
        // Receipt storage failing should not block access (payment already succeeded).
        _toast('Payment succeeded, but receipt sync failed. Access will still unlock.', error: false);
      }

      // Unlock: ensure membership + memberIds.
      await _ensureMemberAccessWrite(uid);

      _toast('Payment successful. Access unlocked.');
      await _checkAccess();
    } catch (e) {
      _toast(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')), error: true);
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
                // Lock icon
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

                // Unlock section (Pay or Coupon)
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

                      // Pay button
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

                // Navigation buttons
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => context.pop(),
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.onSurface.withOpacity(0.15)),
                              color: cs.onSurface.withOpacity(0.05),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: cs.onSurface.withOpacity(0.70)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Back',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(0.70),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _actionBusy ? null : _checkAccess,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  cs.primary,
                                  cs.primary.withOpacity(0.75),
                                ],
                              ),
                              border: Border.all(color: cs.primary.withOpacity(0.40)),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Retry',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
