import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/master_league_entitlement_service.dart';
import '../logic/master_league_payment_service.dart';
import '../logic/master_league_pricing_service.dart';
import '../logic/master_leagues_providers.dart';

class CreateMasterLeagueScreen extends ConsumerStatefulWidget {
  const CreateMasterLeagueScreen({super.key});

  @override
  ConsumerState<CreateMasterLeagueScreen> createState() => _CreateMasterLeagueScreenState();
}

class _CreateMasterLeagueScreenState extends ConsumerState<CreateMasterLeagueScreen> {
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
      return await svc.getMasterLeaguePriceForLocale(Localizations.maybeLocaleOf(context));
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensureSubscriptionActive() async {
    final entitlementSvc = ref.read(masterLeagueEntitlementServiceProvider);

    final unlocked = await entitlementSvc.isUnlocked();
    if (unlocked) return true;

    final price = await _loadPrice();

    if (!mounted) return false;

    final String priceLine = (price != null) ? 'Price: ${price.display}' : 'Price: unavailable';
    const String durationLine = 'Access duration: 3 months (renew required)';

    final shouldPurchase = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        return AlertDialog(
          title: const Text('Master League (Premium)'),
          content: Text(
            'Master League is a premium feature. It allows you to create multiple competitions inside one league system.\n\n$durationLine\n$priceLine',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Purchase / Renew'),
            ),
          ],
          icon: Icon(Icons.hub_rounded, color: cs.primary),
        );
      },
    );

    if (shouldPurchase != true) return false;

    // Charge using Flutterwave and only unlock AFTER success.
    final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
    final userId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    final result = await paymentSvc.purchaseMasterLeagueAccess(
      context: context,
      userId: userId,
    );

    if (!mounted) return false;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(result.errorMessage ?? 'Payment failed. Please try again.'),
        ),
      );
      return false;
    }

    try {
      await entitlementSvc.grantOrExtendAfterPayment(payment: result);
      return true;
    } on MasterLeagueEntitlementException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.message)),
      );
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
      return false;
    }
  }

  Future<void> _create() async {
    if (_saving) return;

    final ok = await _ensureSubscriptionActive();
    if (!ok) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Please enter a name.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final created = await repo.create(name: name);

      if (!mounted) return;
      context.go('/master-leagues/${created.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
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
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
              children: [
                Glass(
                  borderRadius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withOpacity(0.12),
                              border: Border.all(color: cs.primary.withOpacity(0.25)),
                            ),
                            child: Icon(Icons.hub_rounded, color: cs.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Premium Master League',
                              style: theme.textTheme.titleMedium?.copyWith(
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
                        'Master League is a 3-month premium subscription. Renew to continue creating competitions.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _create(),
                        decoration: const InputDecoration(
                          labelText: 'Master League Name',
                          prefixIcon: Icon(Icons.edit_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _saving ? null : _create,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_circle_outline_rounded),
                        label: Text(
                          _saving ? 'Creating...' : 'Create Master League',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tip: Create Classic, Swiss (Series), and UCL Group competitions inside your Master League.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.60),
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
