import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../data/leagues_repository_local.dart';
import '../logic/league_charges_payment_service.dart';
import '../logic/league_charges_store.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../utils/current_user.dart';

class LeagueAccessGuard extends ConsumerStatefulWidget {
  const LeagueAccessGuard({
    super.key,
    required this.leagueId,
    required this.child,
  });

  final String leagueId;
  final Widget child;

  @override
  ConsumerState<LeagueAccessGuard> createState() => _LeagueAccessGuardState();
}

class _LeagueAccessGuardState extends ConsumerState<LeagueAccessGuard> {
  static const Duration _couponReservationTtl = Duration(minutes: 15);

  bool _loading = true;
  bool _processingPayment = false;

  League? _league;
  String _userId = '';
  bool _hasPaid = false;
  LeagueChargesReceipt? _receipt;

  final TextEditingController _couponController = TextEditingController();
  bool _applyingCoupon = false;
  String? _couponError;
  String _appliedCouponCode = '';
  int _appliedCouponDiscountPercent = 0;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _load();
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    final league = await repo.getLeagueById(widget.leagueId);

    String userId = prefs.getCurrentUserId() ?? '';
    if (userId.trim().isEmpty) {
      userId = await CurrentUser.getOrCreateUserId();
    }

    final store = LeagueChargesStore(prefs);

    final hasPaid = store.hasPaidCharges(userId: userId, leagueId: widget.leagueId);
    final receipt = store.getReceipt(userId: userId, leagueId: widget.leagueId);

    if (!mounted) return;
    setState(() {
      _league = league;
      _userId = userId;
      _hasPaid = hasPaid;
      _receipt = receipt;
      _loading = false;
    });
  }

  bool _isClassicFree(League league) => league.format == LeagueFormat.classic;

  bool _isOrganizerAlwaysAllowed(League league) => league.organizerUserId == _userId;

  bool _requiresCharges(League league) => league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;

  double _parseAmount(String raw) => double.tryParse(raw.trim()) ?? 0;

  String _money(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  double _discountedAmount({
    required double base,
    required int discountPercent,
  }) {
    final pct = discountPercent.clamp(0, 100);
    if (pct >= 100) return 0;
    final out = base * ((100 - pct) / 100.0);
    return double.parse(out.toStringAsFixed(2));
  }

  DocumentReference<Map<String, dynamic>> _couponRef(League league, String code) {
    return FirebaseFirestore.instance.collection('leagues').doc(league.id).collection('coupons').doc(code);
  }

  Future<void> _releaseCouponReservation({
    required League league,
    required String code,
  }) async {
    final docRef = _couponRef(league, code);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;

      final data = (snap.data() ?? <String, dynamic>{});
      final usedBy = (data['usedBy'] as String?)?.trim() ?? '';
      if (usedBy.isNotEmpty) return;

      final reservedBy = (data['reservedBy'] as String?)?.trim() ?? '';
      if (reservedBy != _userId) return;

      tx.set(
        docRef,
        <String, dynamic>{
          'reservedBy': '',
          'reservedAt': null,
          'reservedUntil': null,
          'updatedAtMs': nowMs,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _finalizeCouponUse({
    required League league,
    required String code,
  }) async {
    final docRef = _couponRef(league, code);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) throw StateError('invalid');

      final data = (snap.data() ?? <String, dynamic>{});

      final usedBy = (data['usedBy'] as String?)?.trim() ?? '';
      if (usedBy.isNotEmpty) throw StateError('used');

      final reservedBy = (data['reservedBy'] as String?)?.trim() ?? '';
      if (reservedBy != _userId) throw StateError('notReserved');

      final reservedUntil = data['reservedUntil'];
      if (reservedUntil is Timestamp) {
        final nowTs = Timestamp.now();
        if (reservedUntil.compareTo(nowTs) <= 0) throw StateError('expired');
      } else {
        throw StateError('notReserved');
      }

      tx.set(
        docRef,
        <String, dynamic>{
          'usedBy': _userId,
          'usedAtMs': nowMs,
          'reservedBy': '',
          'reservedAt': null,
          'reservedUntil': null,
          'updatedAtMs': nowMs,
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }

    final league = _league;
    if (league == null) {
      return Center(
        child: Glass(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.tr('leagues_error_not_found_local_storage'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isClassicFree(league)) return widget.child;

    if (_isOrganizerAlwaysAllowed(league)) return widget.child;

    if (!_requiresCharges(league)) return widget.child;

    if (_hasPaid) return widget.child;

    final pricing = FlutterwaveConfig.pricingForLocale(Localizations.maybeLocaleOf(context));
    final baseAmount = _parseAmount(pricing.viewLeagueAmount);

    final hasCoupon = _appliedCouponCode.trim().isNotEmpty && _appliedCouponDiscountPercent > 0;
    final isFreeCoupon = hasCoupon && _appliedCouponDiscountPercent >= 100;

    final discounted = hasCoupon ? _discountedAmount(base: baseAmount, discountPercent: _appliedCouponDiscountPercent) : baseAmount;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  color: cs.primary.withOpacity(0.95),
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('league_access_charges_required_title'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  hasCoupon
                      ? ('${l10n.tr('league_access_amount_prefix')} ${pricing.viewLeagueAmount} ${pricing.currency}\n'
                          'Coupon: $_appliedCouponCode (${_appliedCouponDiscountPercent}%)\n'
                          'Pay: ${_money(discounted)} ${pricing.currency}\n\n'
                          '${l10n.tr('league_access_charges_explanation')}\n\n'
                          '${l10n.tr('league_access_league_prefix')} ${league.name}')
                      : ('${l10n.tr('league_access_amount_prefix')} ${pricing.viewLeagueAmount} ${pricing.currency}\n\n'
                          '${l10n.tr('league_access_charges_explanation')}\n\n'
                          '${l10n.tr('league_access_league_prefix')} ${league.name}'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.72),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_receipt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${l10n.tr('league_access_receipt_prefix')} ${_receipt!.receiptId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.80),
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),

                // Coupon input (optional)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Have a coupon?',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _couponController,
                              enabled: !_applyingCoupon && !_processingPayment && !hasCoupon,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Coupon code',
                                prefixIcon: const Icon(Icons.confirmation_number_outlined),
                                helperText: hasCoupon ? 'Coupon reserved.' : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (!hasCoupon)
                            FilledButton(
                              onPressed: (_applyingCoupon || _processingPayment) ? null : () => _applyCoupon(league),
                              child: _applyingCoupon
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Apply'),
                            )
                          else
                            OutlinedButton(
                              onPressed: (_processingPayment || _applyingCoupon)
                                  ? null
                                  : () async {
                                      final code = _appliedCouponCode.trim().toUpperCase();
                                      try {
                                        await _releaseCouponReservation(league: league, code: code);
                                      } catch (_) {
                                        // non-fatal
                                      }
                                      if (!mounted) return;
                                      setState(() {
                                        _appliedCouponCode = '';
                                        _appliedCouponDiscountPercent = 0;
                                        _couponError = null;
                                      });
                                    },
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      if (_couponError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _couponError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Coupons are applied only on this payment step. Reservation expires after ${_couponReservationTtl.inMinutes} minutes if not completed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.60),
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _processingPayment || isFreeCoupon ? null : () => _pay(context, league, discounted),
                        child: _processingPayment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                hasCoupon
                                    ? 'Pay ${_money(discounted)} ${pricing.currency}'
                                    : l10n.tr('league_access_pay_charges'),
                              ),
                      ),
                    ),
                  ],
                ),
                if (isFreeCoupon) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: (_processingPayment || _applyingCoupon) ? null : () => _completeFreeAccessWithCoupon(league),
                    icon: const Icon(Icons.verified),
                    label: const Text('Continue (Free)'),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  l10n.tr('league_access_note_classic_free'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.55),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyCoupon(League league) async {
    final theme = Theme.of(context);

    final raw = _couponController.text.trim().toUpperCase();
    if (raw.isEmpty) {
      setState(() => _couponError = 'Paste a coupon code.');
      return;
    }

    setState(() {
      _applyingCoupon = true;
      _couponError = null;
    });

    try {
      final docRef = _couponRef(league, raw);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final reservedAt = Timestamp.now();
      final reservedUntil = Timestamp.fromDate(DateTime.now().add(_couponReservationTtl));

      final int discountPercent = await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          throw StateError('invalid');
        }

        final data = (snap.data() ?? <String, dynamic>{});

        final usedBy = (data['usedBy'] as String?)?.trim() ?? '';
        if (usedBy.isNotEmpty) {
          throw StateError('used');
        }

        final storedLeagueId = (data['leagueId'] as String?)?.trim() ?? '';
        if (storedLeagueId.isNotEmpty && storedLeagueId != league.id) {
          throw StateError('wrongLeague');
        }

        final pct = (data['discountPercent'] as num?)?.toInt() ?? 0;
        if (pct <= 0 || pct > 100) {
          throw StateError('invalid');
        }

        final reservedBy = (data['reservedBy'] as String?)?.trim() ?? '';
        final reservedUntilExisting = data['reservedUntil'];

        if (reservedBy.isNotEmpty && reservedBy != _userId) {
          if (reservedUntilExisting is Timestamp) {
            if (reservedUntilExisting.compareTo(Timestamp.now()) > 0) {
              throw StateError('reserved');
            }
          } else {
            throw StateError('reserved');
          }
        }

        // Reserve to prevent concurrent use.
        tx.set(
          docRef,
          <String, dynamic>{
            'reservedBy': _userId,
            'reservedAt': reservedAt,
            'reservedUntil': reservedUntil,
            'updatedAtMs': nowMs,
          },
          SetOptions(merge: true),
        );

        return pct;
      });

      if (!mounted) return;

      setState(() {
        _appliedCouponCode = raw;
        _appliedCouponDiscountPercent = discountPercent;
        _couponError = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(discountPercent >= 100 ? 'Coupon reserved: free access.' : 'Coupon reserved: $discountPercent% discount.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.colorScheme.primary,
        ),
      );
    } on FirebaseException catch (e) {
      final msg = (e.code == 'permission-denied')
          ? 'Coupon cannot be reserved (expired or not allowed).'
          : 'Failed to apply coupon: ${e.message ?? e.code}';
      if (!mounted) return;
      setState(() => _couponError = msg);
    } on StateError catch (e) {
      String msg = 'Invalid coupon.';
      if (e.message == 'used') msg = 'Coupon already used.';
      if (e.message == 'reserved') msg = 'Coupon is currently reserved by someone else. Try again later.';
      if (e.message == 'wrongLeague') msg = 'Coupon does not match this league.';
      if (!mounted) return;
      setState(() => _couponError = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _couponError = 'Failed to apply coupon: $e');
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  Future<void> _completeFreeAccessWithCoupon(League league) async {
    final l10n = context.l10n;
    final code = _appliedCouponCode.trim().toUpperCase();
    if (code.isEmpty || _appliedCouponDiscountPercent < 100) return;

    setState(() => _processingPayment = true);

    try {
      // Finalize coupon first (prevents reuse).
      await _finalizeCouponUse(league: league, code: code);

      final prefs = ref.read(prefsServiceProvider);
      final store = LeagueChargesStore(prefs);

      final now = DateTime.now().millisecondsSinceEpoch;

      final receipt = LeagueChargesReceipt(
        leagueId: league.id,
        userId: _userId,
        receiptId: 'CPN-$code',
        provider: 'coupon',
        paidAtMs: now,
      );

      await store.storeReceipt(receipt);

      if (!mounted) return;
      setState(() {
        _processingPayment = false;
        _hasPaid = true;
        _receipt = receipt;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_access_charges_paid_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete free access: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pay(BuildContext context, League league, double discountedAmount) async {
    final l10n = context.l10n;

    setState(() => _processingPayment = true);

    final hasCoupon = _appliedCouponCode.trim().isNotEmpty && _appliedCouponDiscountPercent > 0;
    final code = hasCoupon ? _appliedCouponCode.trim().toUpperCase() : '';

    try {
      final prefs = ref.read(prefsServiceProvider);
      final payment = ref.read(leagueChargesPaymentServiceProvider);
      final store = LeagueChargesStore(prefs);

      final amountOverride = hasCoupon ? _money(discountedAmount) : null;

      final result = await payment.payLeagueCharges(
        context: context,
        userId: _userId,
        leagueId: league.id,
        leagueName: league.name,
        amountOverride: amountOverride,
        couponCode: hasCoupon ? code : null,
        couponDiscountPercent: hasCoupon ? _appliedCouponDiscountPercent : null,
      );

      if (!mounted) return;

      if (!result.success) {
        if (hasCoupon) {
          try {
            await _releaseCouponReservation(league: league, code: code);
          } catch (_) {
            // non-fatal
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _processingPayment = false);
        return;
      }

      // Try to finalize coupon after payment success.
      if (hasCoupon) {
        bool finalized = false;
        Object? lastError;

        for (int i = 0; i < 3; i++) {
          try {
            await _finalizeCouponUse(league: league, code: code);
            finalized = true;
            break;
          } catch (e) {
            lastError = e;
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }

        if (!finalized) {
          // Best-effort: don't block paid user, but warn.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment succeeded, but coupon finalization failed: $lastError'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      final receipt = LeagueChargesReceipt(
        leagueId: league.id,
        userId: _userId,
        receiptId: result.receiptId ?? '',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await store.storeReceipt(receipt);

      if (!mounted) return;
      setState(() {
        _processingPayment = false;
        _hasPaid = true;
        _receipt = receipt;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_access_charges_paid_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      if (hasCoupon && code.isNotEmpty) {
        try {
          await _releaseCouponReservation(league: league, code: code);
        } catch (_) {
          // non-fatal
        }
      }

      setState(() => _processingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_access_payment_failed_prefix')} $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
