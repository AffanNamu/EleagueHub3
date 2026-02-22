import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
import '../logic/league_access_controller.dart';

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
  Timer? _loaderDelay;
  bool _showLoader = false;

  final TextEditingController _couponCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Delay loader to avoid flicker + prevent owners seeing any intermediate screen in most flows.
    _loaderDelay = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _showLoader = true);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(leagueAccessControllerProvider(widget.leagueId).notifier).check(
            force: false,
            silentIfAlreadyAllowed: true,
          ));
    });
  }

  @override
  void dispose() {
    _loaderDelay?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(leagueAccessControllerProvider(widget.leagueId));
    final decision = st.decision;

    if (decision?.allowed == true) return widget.child;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final showLoader = st.checking && _showLoader;

    final loader = Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              borderRadius: 26,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Verifying access…',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final leagueName = decision?.leagueName ?? 'this league';
    final isClassic = decision?.isClassicLeague == true;

    final err = (st.errorMessage ?? '').trim();
    final deny = (decision?.denyMessage ?? '').trim();
    final message = err.isNotEmpty ? err : (deny.isNotEmpty ? deny : 'You don’t have access yet.');

    final gate = Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Glass(
              borderRadius: 26,
              padding: const EdgeInsets.all(22),
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
                  const SizedBox(height: 14),
                  Text(
                    'Access Required',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.68),
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),

                  if (isClassic) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.primary.withOpacity(0.18)),
                      ),
                      child: Text(
                        'Classic league: participants enter free. Viewers can still unlock access by paying or using a coupon.',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.70),
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Unlock $leagueName',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: st.busy
                              ? null
                              : () async {
                                  await ref.read(leagueAccessControllerProvider(widget.leagueId).notifier).payToUnlock(context);
                                  final after = ref.read(leagueAccessControllerProvider(widget.leagueId));
                                  if (after.decision?.allowed == true) {
                                    _toast('Access unlocked.');
                                  }
                                },
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                            st.busy ? 'Processing…' : 'Pay league entry fee',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Or redeem a coupon',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface.withOpacity(0.70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _couponCtrl,
                          enabled: !st.busy,
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
                              borderSide: BorderSide(color: cs.primary.withOpacity(0.60)),
                            ),
                          ),
                          onSubmitted: (_) async {
                            await ref.read(leagueAccessControllerProvider(widget.leagueId).notifier).redeemCouponCode(context, _couponCtrl.text);
                            final after = ref.read(leagueAccessControllerProvider(widget.leagueId));
                            if (after.decision?.allowed == true) {
                              _couponCtrl.clear();
                              _toast('Coupon redeemed. Access unlocked.');
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: st.busy
                              ? null
                              : () async {
                                  await ref.read(leagueAccessControllerProvider(widget.leagueId).notifier).redeemCouponCode(context, _couponCtrl.text);
                                  final after = ref.read(leagueAccessControllerProvider(widget.leagueId));
                                  if (after.decision?.allowed == true) {
                                    _couponCtrl.clear();
                                    _toast('Coupon redeemed. Access unlocked.');
                                  }
                                },
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Apply coupon', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: st.busy
                              ? null
                              : () {
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/');
                                  }
                                },
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                          label: const Text('Back', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: st.busy
                              ? null
                              : () async {
                                  await ref.read(leagueAccessControllerProvider(widget.leagueId).notifier).check(force: true);
                                },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w900)),
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: showLoader ? loader : gate,
    );
  }
}
