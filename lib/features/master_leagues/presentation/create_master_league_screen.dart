import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/country/country_resolver_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/master_league_entitlement_service.dart';
import '../logic/master_league_payment_service.dart';
import '../logic/master_league_pricing_service.dart';
import '../logic/master_leagues_providers.dart';

class CreateMasterLeagueScreen extends ConsumerStatefulWidget {
  const CreateMasterLeagueScreen({super.key});

  @override
  ConsumerState<CreateMasterLeagueScreen> createState() =>
      _CreateMasterLeagueScreenState();
}

class _CreateMasterLeagueScreenState
    extends ConsumerState<CreateMasterLeagueScreen> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<MasterLeaguePrice?> _loadPrice() async {
    try {
      final svc = MasterLeaguePricingService();
      return await svc.getMasterLeaguePriceForLocale(
        Localizations.maybeLocaleOf(context),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _showPurchaseDialog({
    required MasterLeaguePrice? price,
    required bool preferNgn,
  }) async {
    if (!mounted) return false;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String priceLine =
        (price != null) ? 'Price: ${price.display}' : 'Price: unavailable';
    const String durationLine = 'Access duration: 3 months (renew required)';

    final actualCurrency = (price?.currency ?? '').trim().toUpperCase();
    final String? warning =
        (preferNgn && actualCurrency.isNotEmpty && actualCurrency != 'NGN')
            ? 'NGN price is not configured in Firestore. Falling back to $actualCurrency.'
            : null;

    final shouldPurchase = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Glass(
            borderRadius: 28,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withOpacity(0.12),
                        border: Border.all(
                          color: cs.primary.withOpacity(0.25),
                        ),
                      ),
                      child:
                          Icon(Icons.hub_rounded, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Master League (Premium)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Master League is a premium feature. It allows you to create '
                  'multiple competitions inside one league system.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.72),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$durationLine\n$priceLine',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.86),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (warning != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.error.withOpacity(0.30),
                      ),
                    ),
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(false),
                        child: const Text('Cancel',
                            style: TextStyle(
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(true),
                        child: const Text('Purchase / Renew',
                            style: TextStyle(
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return shouldPurchase == true;
  }

  Future<bool> _ensureSubscriptionActive() async {
    // Use the provider from master_leagues_providers.dart
    final entitlementSvc =
        ref.read(masterLeagueEntitlementServiceProvider);

    // Check if already unlocked
    bool unlocked = false;
    try {
      unlocked = await entitlementSvc.isUnlocked();
      debugPrint('[CreateML] isUnlocked=$unlocked');
    } catch (e) {
      debugPrint('[CreateML] isUnlocked check failed: $e');
    }

    if (unlocked) return true;

    // Not unlocked — show purchase dialog
    final price = await _loadPrice();
    final cc =
        await CountryResolverService.instance.resolveCountryCode(
      locale: Localizations.maybeLocaleOf(context),
    );
    final preferNgn = cc.trim().toUpperCase() == 'NG';

    final shouldPurchase = await _showPurchaseDialog(
      price: price,
      preferNgn: preferNgn,
    );
    if (!shouldPurchase) return false;
    if (!mounted) return false;

    final paymentSvc =
        ref.read(masterLeaguePaymentServiceProvider);
    final userId =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    final result = await paymentSvc.purchaseMasterLeagueAccess(
      context: context,
      userId: userId,
    );

    if (!mounted) return false;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            result.errorMessage ??
                'Payment failed. Please try again.',
          ),
        ),
      );
      return false;
    }

    debugPrint(
      '[CreateML] Payment success: receiptId=${result.receiptId} '
      'paidAtMs=${result.paidAtMs} provider=${result.provider}',
    );

    // Write entitlement
    try {
      await entitlementSvc.grantOrExtendAfterPayment(
          payment: result);
      debugPrint('[CreateML] Entitlement granted successfully');
    } on MasterLeagueEntitlementException catch (e) {
      debugPrint(
          '[CreateML] Entitlement write failed: ${e.message}');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.message),
        ),
      );
      return false;
    } catch (e) {
      debugPrint(
          '[CreateML] Entitlement write failed (unexpected): $e');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('$e'),
        ),
      );
      return false;
    }

    // Wait for Firestore to propagate the entitlement write.
    // The master_leagues create rule reads entitlement via get(),
    // so we need the write to be visible before creating the doc.
    debugPrint(
        '[CreateML] Waiting for entitlement propagation...');
    await Future<void>.delayed(const Duration(seconds: 2));

    // Verify entitlement is now readable from server
    try {
      final nowUnlocked = await entitlementSvc.isUnlocked();
      debugPrint(
          '[CreateML] Post-payment isUnlocked=$nowUnlocked');
      if (!nowUnlocked) {
        // Try once more with a longer delay
        debugPrint(
            '[CreateML] Not yet visible, waiting 3 more seconds...');
        await Future<void>.delayed(
            const Duration(seconds: 3));
        final retryUnlocked =
            await entitlementSvc.isUnlocked();
        debugPrint(
            '[CreateML] Retry isUnlocked=$retryUnlocked');
        if (!retryUnlocked) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Your payment was successful but the subscription is still '
                'processing. Please wait a moment and try again.',
              ),
            ),
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint('[CreateML] Post-payment verify failed: $e');
      // Proceed anyway — the write may have succeeded
    }

    return true;
  }

  Future<void> _create() async {
    if (_saving) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Please enter a name.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // Ensure subscription is active (purchase if needed)
      final ok = await _ensureSubscriptionActive();
      if (!ok) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      if (!mounted) return;

      final repo = ref.read(masterLeaguesRepositoryProvider);

      debugPrint('[CreateML] Creating master league: "$name"');
      final created = await repo.create(name: name);
      debugPrint('[CreateML] Created: id=${created.id}');

      if (!mounted) return;
      context.go('/master-leagues/${created.id}');
    } catch (e) {
      debugPrint('[CreateML] Create failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('$e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Create Master League'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  16, 12, 16, 24),
              children: [
                Glass(
                  borderRadius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary
                                  .withOpacity(0.12),
                              border: Border.all(
                                color: cs.primary
                                    .withOpacity(0.25),
                              ),
                            ),
                            child: Icon(
                              Icons.hub_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Premium Master League',
                              style: theme
                                  .textTheme.titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Master League is a 3-month premium subscription. '
                        'Renew to continue creating competitions.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(
                          color: cs.onSurface
                              .withOpacity(0.70),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _nameCtrl,
                        textInputAction:
                            TextInputAction.done,
                        onSubmitted: (_) => _create(),
                        decoration: const InputDecoration(
                          labelText: 'Master League Name',
                          prefixIcon:
                              Icon(Icons.edit_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed:
                            _saving ? null : _create,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons
                                .add_circle_outline_rounded),
                        label: Text(
                          _saving
                              ? 'Creating...'
                              : 'Create Master League',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tip: Create Classic, Swiss (Series), and UCL Group '
                        'competitions inside your Master League.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                          color: cs.onSurface
                              .withOpacity(0.60),
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
