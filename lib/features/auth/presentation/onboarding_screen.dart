import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';
import '../data/user_profile_repository.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _teamName = TextEditingController();
  final _q1 = TextEditingController();
  final _q2 = TextEditingController();
  final _q3 = TextEditingController();

  bool _submitting = false;

  final UserProfileRepository _profiles = UserProfileRepository();
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _teamName.dispose();
    _q1.dispose();
    _q2.dispose();
    _q3.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final team = _teamName.text.trim();
    if (team.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorTeamNameRequired)),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final onboardingAnswers = <String, dynamic>{
        'favoriteGame': _q1.text.trim(),
        'experienceLevel': _q2.text.trim(),
        'region': _q3.text.trim(),
      }..removeWhere((_, v) => (v is String) && v.trim().isEmpty);

      final provider = AuthService.detectAuthProvider(user);

      await _profiles.createProfileIfMissing(
        userId: user.uid,
        teamName: team,
        authProvider: provider,
        onboardingAnswers: onboardingAnswers,
      );

      await authRouterRefresh.refreshProfileStatus();

      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorFailedOnboardingPrefix}: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = theme.textTheme;

    final fieldStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    );

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.onboardingTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.onboardingHeader,
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.onboardingDescription,
                      style: t.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _teamName,
                      style: fieldStyle,
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        labelText: l10n.onboardingTeamNameLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _q1,
                      style: fieldStyle,
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        labelText: l10n.onboardingFavoriteGameLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q2,
                      style: fieldStyle,
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        labelText: l10n.onboardingExperienceLevelLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q3,
                      style: fieldStyle,
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        labelText: l10n.onboardingRegionLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : Text(l10n.onboardingContinue),
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
