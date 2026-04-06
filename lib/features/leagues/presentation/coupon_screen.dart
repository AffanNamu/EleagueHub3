import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/league_access_controller.dart';

class CouponScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const CouponScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<CouponScreen> createState() => _CouponScreenState();
}

class _CouponScreenState extends ConsumerState<CouponScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final notifier =
        ref.read(leagueAccessControllerProvider(widget.leagueId).notifier);
    await notifier.redeemCouponCode(context, _ctrl.text);

    final st = ref.read(leagueAccessControllerProvider(widget.leagueId));
    if (st.decision?.allowed == true && mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/leagues/${widget.leagueId}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(leagueAccessControllerProvider(widget.leagueId));
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    if (st.decision?.allowed == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/leagues/${widget.leagueId}');
        }
      });
      return const SizedBox.shrink();
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Redeem Coupon'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Glass(
                borderRadius: 26,
                padding: const EdgeInsets.all(22),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      color: AppTheme.limeAccentDark,
                      size: 34,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter Coupon Code',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Apply a valid coupon to unlock league access.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      enabled: !st.busy,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'ESLXXXX…',
                        prefixIcon: Icon(Icons.verified_outlined),
                      ),
                      onSubmitted: (_) => _apply(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: st.busy ? null : _apply,
                        child: st.busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.darkText,
                                ),
                              )
                            : const Text(
                                'Apply Coupon',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                    if ((st.errorMessage ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withOpacity(0.25),
                          ),
                        ),
                        child: Text(
                          st.errorMessage!.trim(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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
