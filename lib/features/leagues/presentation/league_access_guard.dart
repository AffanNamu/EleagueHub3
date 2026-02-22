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

  @override
  void initState() {
    super.initState();

    // Delay loader to prevent flicker (and owners seeing any "checking" UI).
    _loaderDelay = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      setState(() => _showLoader = true);
    });

    // Trigger check in background; controller will use cache and fast owner path.
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

    if (decision?.allowed == true) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
                        color: cs.onSurface.withOpacity(0.70),
                        fontWeight: FontWeight.w800,
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
    final message = (st.errorMessage?.trim().isNotEmpty == true)
        ? st.errorMessage!.trim()
        : (decision?.denyMessage?.trim().isNotEmpty == true)
            ? decision!.denyMessage!.trim()
            : 'You don’t have access to $leagueName yet.';

    final gate = Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                    'Access Restricted',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.3),
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
                          'Unlock access',
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
                          label: Text(st.busy ? 'Processing…' : 'Pay league entry fee', style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: st.busy
                              ? null
                              : () {
                                  context.push('/leagues/${widget.leagueId}/coupon');
                                },
                          icon: const Icon(Icons.confirmation_number_outlined),
                          label: const Text('Use coupon code', style: TextStyle(fontWeight: FontWeight.w900)),
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
                  const SizedBox(height: 10),
                  Text(
                    'If you just paid or redeemed a coupon, tap Retry.',
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
      ),
    );

    final showLoader = st.checking && _showLoader;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: showLoader ? loader : gate,
    );
  }
}
