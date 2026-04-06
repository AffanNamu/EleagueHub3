import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';
import '../data/auth_validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _authService = AuthService();

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _isRegister = false;
  bool _submitting = false;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<bool> _confirmExitApp() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(Theme.of(ctx).brightness),
        surfaceTintColor: Colors.transparent,
        title: const Text('Exit app?'),
        content: const Text('Are you sure you want to close the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _afterAuth() async {
    final user = _authService.currentUser;
    if (user == null) return;

    final prefs = ref.read(prefsServiceProvider);
    await prefs.setCurrentUserId(user.uid);

    if (!mounted) return;
    context.go('/');
  }

  Future<void> _signInGoogle() async {
    setState(() => _submitting = true);
    try {
      await _authService.signInWithGoogle();
      await _afterAuth();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInEmail() async {
    final l10n = context.l10n;

    final email = _email.text.trim();
    final pass = _password.text;

    final emailErr = AuthValidators.validateEmail(email);
    if (emailErr != null) {
      _showError(emailErr);
      return;
    }
    if (pass.isEmpty) {
      _showError(l10n.errorEmailPasswordRequired);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _authService.signInWithEmailPassword(email: email, password: pass);
      await _afterAuth();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _registerEmail() async {
    final l10n = context.l10n;

    final email = _email.text.trim();
    final pass = _password.text;
    final confirm = _confirm.text;

    final emailErr = AuthValidators.validateEmail(email);
    if (emailErr != null) {
      _showError(emailErr);
      return;
    }

    final passErr = AuthValidators.validatePassword(pass);
    if (passErr != null) {
      _showError(passErr);
      return;
    }

    if (pass != confirm) {
      _showError(l10n.errorPasswordsDoNotMatch);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _authService.registerWithEmailPassword(email: email, password: pass);
      await _afterAuth();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final dividerColor = AppTheme.cardBorder(brightness);
    final orTextColor = AppTheme.secondaryText(brightness);

    return WillPopScope(
      onWillPop: _confirmExitApp,
      child: GlassScaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                        Icons.sports_esports,
                        size: 56,
                        color: AppTheme.limeAccentDark,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.authLoginBrand,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? l10n.authLoginSubtitleRegister
                            : l10n.authLoginSubtitleSignIn,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.limeAccent,
                            foregroundColor: AppTheme.darkText,
                          ),
                          onPressed: _submitting ? null : _signInGoogle,
                          icon: const Icon(Icons.login),
                          label: Text(l10n.authLoginContinueWithGoogle),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Divider(color: dividerColor)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              l10n.authLoginOr,
                              style: TextStyle(color: orTextColor),
                            ),
                          ),
                          Expanded(child: Divider(color: dividerColor)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        label: l10n.authLoginEmailLabel,
                        hint: 'name@example.com',
                        enabled: !_submitting,
                        prefixIcon: const Icon(Icons.email_outlined),
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 10),
                      AppTextField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        label: l10n.authLoginPasswordLabel,
                        enabled: !_submitting,
                        prefixIcon: const Icon(Icons.lock_outline),
                        textInputAction:
                            _isRegister ? TextInputAction.next : TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        suffixIcon: IconButton(
                          tooltip:
                              _obscurePassword ? 'Show password' : 'Hide password',
                          onPressed: _submitting
                              ? null
                              : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        onSubmitted: (_) => _isRegister ? null : _signInEmail(),
                      ),
                      if (_isRegister) ...[
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _confirm,
                          obscureText: _obscureConfirm,
                          label: l10n.authLoginConfirmPasswordLabel,
                          enabled: !_submitting,
                          prefixIcon: const Icon(Icons.lock_reset),
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          suffixIcon: IconButton(
                            tooltip:
                                _obscureConfirm ? 'Show password' : 'Hide password',
                            onPressed: _submitting
                                ? null
                                : () => setState(
                                      () => _obscureConfirm = !_obscureConfirm,
                                    ),
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          onSubmitted: (_) => _registerEmail(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (!_isRegister)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _submitting
                                ? null
                                : () => context.go('/forgot-password'),
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(color: AppTheme.limeAccentDark),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.limeAccent,
                            foregroundColor: AppTheme.darkText,
                          ),
                          onPressed: _submitting
                              ? null
                              : (_isRegister ? _registerEmail : _signInEmail),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.darkText,
                                  ),
                                )
                              : Text(
                                  _isRegister
                                      ? l10n.authLoginCreateAccount
                                      : l10n.authLoginSignIn,
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => setState(() {
                                  _isRegister = !_isRegister;
                                }),
                        child: Text(
                          _isRegister
                              ? l10n.authLoginToggleToSignIn
                              : l10n.authLoginToggleToRegister,
                          style: TextStyle(color: AppTheme.limeAccentDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
