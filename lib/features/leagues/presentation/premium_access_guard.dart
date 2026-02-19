import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/remote_pricing_service.dart';
import '../../../core/widgets/glass.dart';
import '../logic/premium_payment_service.dart';

/// Wrap any screen that requires an active premium subscription.
///
/// Logic:
///   - Super admin (hardcoded UID) always passes through.
///   - If RemotePricingPlan.premiumEnabled == false → passes through (kill-switch).
///   - If user has isPremium == true AND premiumExpiresAtMs > now → shows child.
///   - Otherwise → shows paywall UI with a Buy button.
///
/// The guard uses a real-time Firestore stream so the UI updates
/// immediately after a successful purchase without needing a rebuild.
class PremiumAccessGuard extends ConsumerStatefulWidget {
  const PremiumAccessGuard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<PremiumAccessGuard> createState() =>
      _PremiumAccessGuardState();
}

class _PremiumAccessGuardState extends ConsumerState<PremiumAccessGuard> {
  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  // null = still loading
  bool? _isPremium;
  int _premiumExpiresAtMs = 0;

  RemotePricingPlan? _plan;
  bool _planLoading = true;

  bool _buying = false;
  String? _buyError;

  @override
  void initState() {
    super.initState();
    _startStreams();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startStreams() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Super admin bypasses immediately.
    if (uid.trim() == _superAdminUid) {
      if (mounted) setState(() => _isPremium = true);
      return;
    }

    if (uid.trim().isEmpty) {
      if (mounted) context.go('/login');
      return;
    }

    // Load plan for price display (non-blocking, show loading state).
    RemotePricingService.instance
        .getPlanForLocale(Localizations.maybeLocaleOf(context))
        .then((plan) {
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _planLoading = false;

        // If admin disabled premium feature globally, pass everyone through.
        if (!plan.premiumEnabled) {
          _isPremium = true;
        }
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _planLoading = false);
    });

    // Stream user doc for isPremium + premiumExpiresAtMs.
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: false)
        .listen(
      (snap) {
        if (!mounted) return;
        if (!snap.exists) {
          setState(() {
            _isPremium = false;
            _premiumExpiresAtMs = 0;
          });
          return;
        }
        final data = snap.data() ?? <String, dynamic>{};
        final rawPremium = data['isPremium'];
        final rawExpiry = data['premiumExpiresAtMs'];

        final isPremium = rawPremium == true;
        final expiresAtMs = (rawExpiry is int)
            ? rawExpiry
            : (rawExpiry is num)
                ? rawExpiry.toInt()
                : 0;

        final now = DateTime.now().millisecondsSinceEpoch;
        final isActive = isPremium && expiresAtMs > now;

        setState(() {
          _isPremium = isActive;
          _premiumExpiresAtMs = expiresAtMs;
          _buyError = null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isPremium = false);
      },
    );
  }

  Future<void> _buy() async {
    if (_buying) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) {
      context.go('/login');
      return;
    }

    setState(() {
      _buying = true;
      _buyError = null;
    });

    try {
      final result = await ref
          .read(premiumPaymentServiceProvider)
          .purchasePremium(context: context, userId: uid);

      if (!mounted) return;

      if (result.success) {
        // The Firestore stream will fire automatically and flip _isPremium.
        // No manual setState needed here.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Premium activated! Expires in ${result.premiumDurationDays} days.',
            ),
          ),
        );
      } else {
        setState(() {
          _buyError = result.errorMessage ?? 'Payment failed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buyError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    // Still loading user doc.
    if (_isPremium == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: cs.primary),
              const SizedBox(height: 14),
              Text(
                'Checking premium status…',
                style: TextStyle(
                  color: onSurface.withOpacity(0.60),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // User is premium (or feature disabled / super-admin).
    if (_isPremium == true) {
      return widget.child;
    }

    // ── Paywall ──────────────────────────────────────────────────────────────
    final bool hasExpired = _premiumExpiresAtMs > 0 &&
        _premiumExpiresAtMs <= DateTime.now().millisecondsSinceEpoch;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Glass(
                borderRadius: 28,
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFFFD54F).withOpacity(0.30),
                              const Color(0xFFFF8A65).withOpacity(0.15),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 36,
                          color: Color(0xFFFFD54F),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      hasExpired
                          ? 'Your Premium Has Expired'
                          : 'Premium Required',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.4,
                        color: onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      hasExpired
                          ? 'Renew your premium subscription to continue accessing this feature.'
                          : 'This feature is available to premium subscribers only.',
                      style: TextStyle(
                        color: onSurface.withOpacity(0.65),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 22),

                    // Price display
                    _planLoading
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                          )
                        : _plan != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: cs.primary.withOpacity(0.08),
                                  border: Border.all(
                                    color: cs.primary.withOpacity(0.22),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _formatPrice(_plan!),
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: cs.primary,
                                        letterSpacing: -0.5,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'for ${_plan!.premiumDurationDays} days',
                                      style: TextStyle(
                                        color: cs.primary.withOpacity(0.70),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),

                    const SizedBox(height: 20),

                    // What's included
                    _FeatureBullet(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Custom quick messages (up to 15)',
                      onSurface: onSurface,
                      primary: cs.primary,
                    ),
                    const SizedBox(height: 8),
                    _FeatureBullet(
                      icon: Icons.star_rounded,
                      label: 'Priority access to premium leagues',
                      onSurface: onSurface,
                      primary: cs.primary,
                    ),
                    const SizedBox(height: 8),
                    _FeatureBullet(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Premium badge on your profile',
                      onSurface: onSurface,
                      primary: cs.primary,
                    ),

                    const SizedBox(height: 24),

                    // Error
                    if (_buyError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.error.withOpacity(0.30),
                          ),
                        ),
                        child: Text(
                          _buyError!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Buy button
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _buying ? null : _buy,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _buying
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: cs.onPrimary,
                                ),
                              )
                            : Text(
                                hasExpired
                                    ? 'Renew Premium'
                                    : 'Get Premium',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Back button
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: onSurface.withOpacity(0.70),
                          side: BorderSide(
                            color: onSurface.withOpacity(0.18),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Go back',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatPrice(RemotePricingPlan plan) {
    final fee = plan.premiumFee;
    final c = plan.currency;
    if (c == 'NGN') {
      return '₦${fee.toStringAsFixed(0)}';
    }
    return '\$${fee.toStringAsFixed(2)}';
  }
}

// ─────────────────────────────────────────────
// Feature bullet point
// ─────────────────────────────────────────────
class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({
    required this.icon,
    required this.label,
    required this.onSurface,
    required this.primary,
  });

  final IconData icon;
  final String label;
  final Color onSurface;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withOpacity(0.12),
          ),
          child: Icon(icon, color: primary, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: onSurface.withOpacity(0.80),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
