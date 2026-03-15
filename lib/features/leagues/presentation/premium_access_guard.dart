import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../logic/premium_payment_service.dart';

/// Riverpod provider that streams the current user's premium status
/// directly from Firestore. This is the single source of truth.
final premiumStatusStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream<bool>.value(false);

  return UserProfileRepository().watchIsPremium(uid);
});

/// A guard widget that wraps premium-only content.
///
/// If the user has an active premium subscription (verified from Firestore),
/// [child] is displayed. Otherwise, a paywall screen is shown with a
/// "Purchase Premium" button.
///
/// Security model:
/// - Premium status is READ from Firestore (set by server via Worker).
/// - The purchase flow goes through Flutterwave → Worker verifies → Worker
///   writes to Firestore. Client cannot write isPremium directly when
///   Firestore rules are locked down and worker is configured.
class PremiumAccessGuard extends ConsumerWidget {
  const PremiumAccessGuard({
    super.key,
    required this.child,
    this.title = 'Premium Feature',
    this.description =
        'This feature requires a premium subscription. Unlock it to get full access.',
  });

  final Widget child;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumAsync = ref.watch(premiumStatusStreamProvider);

    return premiumAsync.when(
      loading: () => _buildLoading(context),
      error: (e, _) => _buildError(context, ref, e),
      data: (isPremium) {
        if (isPremium) return child;
        return _PremiumPaywall(
          title: title,
          description: description,
        );
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Checking subscription status…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    final cs = Theme.of(context).colorScheme;
    return GlassScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Glass(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: cs.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Unable to verify subscription',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    // ignore: unused_result
                    ref.invalidate(premiumStatusStreamProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumPaywall extends ConsumerStatefulWidget {
  const _PremiumPaywall({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  ConsumerState<_PremiumPaywall> createState() => _PremiumPaywallState();
}

class _PremiumPaywallState extends ConsumerState<_PremiumPaywall> {
  bool _processing = false;
  String? _errorMessage;

  Future<void> _handlePurchase() async {
    if (_processing) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      setState(() => _errorMessage = 'Please sign in to continue.');
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(premiumPaymentServiceProvider);
      final result = await service.purchasePremium(
        context: context,
        userId: uid,
      );

      if (!mounted) return;

      if (result.success) {
        // Invalidate the stream so the guard re-evaluates
        ref.invalidate(premiumStatusStreamProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Premium activated! Enjoy ${result.premiumDurationDays} days of access.',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        setState(() {
          _errorMessage =
              result.errorMessage ?? 'Payment cancelled or not successful.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Glass(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Premium icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withOpacity(0.2),
                            cs.tertiary.withOpacity(0.15),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        Icons.workspace_premium,
                        color: cs.primary,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      widget.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      widget.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Security note
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: cs.primary.withOpacity(0.8),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Secure payment verified by server',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error message
                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.error.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 18, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Purchase button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _processing ? null : _handlePurchase,
                        icon: _processing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Icon(Icons.diamond_outlined),
                        label: Text(
                          _processing
                              ? 'Processing…'
                              : 'Purchase Premium',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Restore / refresh button
                    TextButton.icon(
                      onPressed: _processing
                          ? null
                          : () {
                              ref.invalidate(premiumStatusStreamProvider);
                            },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text(
                        'Already purchased? Refresh status',
                        style: TextStyle(fontWeight: FontWeight.w700),
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
}
