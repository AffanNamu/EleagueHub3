import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';

class MasterLeagueEntryTile extends StatelessWidget {
  const MasterLeagueEntryTile({
    super.key,
    required this.isSignedIn,
    required this.unlocked,
    required this.loading,
    required this.priceText,
    required this.onOpen,
    required this.onUnlock,
    required this.onSignIn,
  });

  final bool isSignedIn;
  final bool unlocked;
  final bool loading;
  final String priceText;

  final VoidCallback onOpen;
  final VoidCallback onUnlock;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    const title = 'Master League';

    String subtitle;
    if (!isSignedIn) {
      subtitle = 'Sign in to create and manage Master Leagues.';
    } else if (loading) {
      subtitle = 'Checking your access...';
    } else if (unlocked) {
      subtitle = 'Open your Master Leagues, view created and joined leagues.';
    } else {
      subtitle = priceText.isEmpty
          ? 'Open Master Leagues and proceed to payment during creation.'
          : 'Open Master Leagues • current plan price: $priceText';
    }

    final badgeColor = !isSignedIn
        ? onSurface.withOpacity(0.45)
        : (unlocked ? const Color(0xFF22C55E) : const Color(0xFFF59E0B));

    final badgeLabel =
        !isSignedIn ? 'SIGN IN' : (unlocked ? 'READY' : 'PAY AS YOU CREATE');

    final actionLabel = !isSignedIn ? 'Sign in' : 'Open';

    VoidCallback action;
    if (!isSignedIn) {
      action = onSignIn;
    } else {
      action = onOpen;
    }

    return Glass(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.18),
              cs.onSurface.withOpacity(0.03),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.onSurface.withOpacity(0.06),
                border: Border.all(color: cs.onSurface.withOpacity(0.10)),
              ),
              child: Icon(Icons.hub_rounded, color: cs.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: badgeColor.withOpacity(0.14),
                          border: Border.all(
                            color: badgeColor.withOpacity(0.32),
                          ),
                        ),
                        child: Text(
                          badgeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: loading ? null : action,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
