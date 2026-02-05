import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
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

  InputDecoration _fieldDecoration({
    required bool isLight,
    required String label,
  }) {
    final base = isLight ? AppTheme.navyBg : Colors.white;
    final borderColor = isLight ? AppTheme.navyBg.withOpacity(0.18) : Colors.white.withOpacity(0.18);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: base.withOpacity(0.75)),
      filled: true,
      fillColor: isLight ? Colors.black.withOpacity(0.04) : Colors.white.withOpacity(0.04),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.85), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = theme.textTheme;

    final isLight = theme.brightness == Brightness.light;

    final titleColor = isLight ? AppTheme.navyBg : Colors.white;
    final bodyColor = isLight ? AppTheme.navyBg.withOpacity(0.72) : Colors.white70;
    final fieldTextColor = isLight ? AppTheme.navyBg : Colors.white;

    final cardFill = isLight ? Colors.white.withOpacity(0.82) : null;
    final cardStroke = isLight ? AppTheme.navyBg.withOpacity(0.12) : null;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.onboardingTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              fill: cardFill,
              stroke: cardStroke,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.onboardingHeader,
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.onboardingDescription,
                      style: t.bodySmall?.copyWith(
                        color: bodyColor,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _teamName,
                      style: TextStyle(color: fieldTextColor, fontWeight: FontWeight.w600),
                      cursorColor: theme.colorScheme.primary,
                      decoration: _fieldDecoration(
                        isLight: isLight,
                        label: l10n.onboardingTeamNameLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _q1,
                      style: TextStyle(color: fieldTextColor, fontWeight: FontWeight.w600),
                      cursorColor: theme.colorScheme.primary,
                      decoration: _fieldDecoration(
                        isLight: isLight,
                        label: l10n.onboardingFavoriteGameLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q2,
                      style: TextStyle(color: fieldTextColor, fontWeight: FontWeight.w600),
                      cursorColor: theme.colorScheme.primary,
                      decoration: _fieldDecoration(
                        isLight: isLight,
                        label: l10n.onboardingExperienceLevelLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q3,
                      style: TextStyle(color: fieldTextColor, fontWeight: FontWeight.w600),
                      cursorColor: theme.colorScheme.primary,
                      decoration: _fieldDecoration(
                        isLight: isLight,
                        label: l10n.onboardingRegionLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
