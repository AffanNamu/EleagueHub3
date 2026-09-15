//AccountSuspendedScreen
import 'package:flutter/material.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';

/// Shown in place of the main app whenever AuthRouterRefresh.isSuspended
/// is true (a live listener on app/accountStatus/users/{uid} — see
/// app_router.dart). Reads the reason directly off that same listener
/// rather than fetching separately, so it always matches what triggered
/// the redirect. If an admin lifts the suspension, the same listener
/// flips isSuspended back to false and the router redirects away from
/// here automatically — no polling needed.
class AccountSuspendedScreen extends StatefulWidget {
  const AccountSuspendedScreen({super.key});

  @override
  State<AccountSuspendedScreen> createState() =>
      _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  final _auth = AuthService();
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await _auth.signOut();
    } catch (_) {
      // Best-effort: if sign-out fails, the user stays on this screen
      // and can retry.
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final reason = authRouterRefresh.suspensionReason;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Account Suspended'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              padding: EdgeInsets.zero,
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block,
                      size: 44,
                      color: AppTheme.limeAccentDark,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your account has been suspended',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reason.isEmpty
                          ? 'Contact support if you believe this is a mistake.'
                          : reason,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: _signingOut ? null : _signOut,
                        child: _signingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.darkText,
                                ),
                              )
                            : const Text('Sign out'),
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
