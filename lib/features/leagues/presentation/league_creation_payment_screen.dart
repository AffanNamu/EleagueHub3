import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/league_creation_payment_service.dart';
import '../utils/current_user.dart';

class LeagueCreationPaymentScreen extends ConsumerStatefulWidget {
  const LeagueCreationPaymentScreen({
    super.key,
    required this.leagueName,
  });

  final String leagueName;

  @override
  ConsumerState<LeagueCreationPaymentScreen> createState() => _LeagueCreationPaymentScreenState();
}

class _LeagueCreationPaymentScreenState extends ConsumerState<LeagueCreationPaymentScreen> {
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final provider = ref.watch(leagueCreationPaymentServiceProvider);

    final locale = Localizations.maybeLocaleOf(context);
    final pricing = FlutterwaveConfig.pricingForLocale(locale);

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_creation_payment_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
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
                    Icons.payments_outlined,
                    color: Colors.cyanAccent.withOpacity(0.95),
                    size: 46,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr('league_creation_payment_required_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${l10n.tr('league_creation_payment_amount_prefix')} ${pricing.createLeagueAmount} ${pricing.currency}\n\n'
                    '${l10n.tr('league_creation_payment_explanation_prefix')} ${widget.leagueName}\n'
                    '${l10n.tr('league_creation_payment_provider_prefix')} ${provider.providerName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _processing ? null : () => context.pop<LeagueCreationPaymentResult?>(null),
                          child: Text(l10n.tr('common_cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _processing
                              ? null
                              : () async {
                                  setState(() => _processing = true);
                                  try {
                                    final userId = await CurrentUser.getOrCreateUserId();

                                    final result = await provider.collectLeagueCreationFee(
                                      context: context,
                                      userId: userId,
                                      leagueName: widget.leagueName,
                                    );

                                    if (!mounted) return;

                                    if (result.success) {
                                      context.pop<LeagueCreationPaymentResult>(result);
                                      return;
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed')),
                                        backgroundColor: theme.colorScheme.error,
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('${l10n.tr('league_creation_payment_failed_prefix')} $e'),
                                        backgroundColor: theme.colorScheme.error,
                                      ),
                                    );
                                  } finally {
                                    if (mounted) setState(() => _processing = false);
                                  }
                                },
                          child: _processing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(l10n.tr('league_creation_payment_pay_continue')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
