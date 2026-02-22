import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
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
    final notifier = ref.read(leagueAccessControllerProvider(widget.leagueId).notifier);
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
    final cs = theme.colorScheme;

    // If already allowed, exit immediately.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Redeem Coupon'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              borderRadius: 26,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.confirmation_number_outlined, color: cs.primary, size: 34),
                  const SizedBox(height: 12),
                  Text(
                    'Enter Coupon Code',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Apply a valid coupon to unlock league access.',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    enabled: !st.busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'ESLXXXX…',
                      prefixIcon: const Icon(Icons.verified_outlined),
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
                    onSubmitted: (_) => _apply(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: st.busy ? null : _apply,
                      child: st.busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Apply Coupon', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  if ((st.errorMessage ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.error.withOpacity(0.25)),
                      ),
                      child: Text(
                        st.errorMessage!.trim(),
                        style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
