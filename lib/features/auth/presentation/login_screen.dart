import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';

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
        title: const Text('Exit app?'),
        content: const Text('Are you sure you want to close the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _afterAuth(UserCredential cred) async {
    final user = cred.user;
    if (user == null) return;

    final prefs = ref.read(prefsServiceProvider);
    await prefs.setCurrentUserId(user.uid);

    if (!mounted) return;

    // Using go() here is intentional: user should not be able to go back to login
    // after signing in.
    context.go('/');
  }

  Future<void> _signInGoogle() async {
    setState(() => _submitting = true);
    try {
      final cred = await _authService.signInWithGoogle();
      await _afterAuth(cred);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInEmail() async {
    final l10n = context.l10n;

    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorEmailPasswordRequired)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final cred = await _authService.signInWithEmailPassword(email: email, password: pass);
      await _afterAuth(cred);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _registerEmail() async {
    final l10n = context.l10n;

    final email = _email.text.trim();
    final pass = _password.text;
    final confirm = _confirm.text;

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorEmailPasswordRequired)),
      );
      return;
    }
    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorPasswordsDoNotMatch)),
      );
      return;
    }
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorPasswordMinLength)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final cred = await _authService.registerWithEmailPassword(email: email, password: pass);
      await _afterAuth(cred);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = Theme.of(context).textTheme;

    return WillPopScope(
      onWillPop: _confirmExitApp,
      child: GlassScaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Glass(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sports_esports,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.authLoginBrand,
                        style: t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister ? l10n.authLoginSubtitleRegister : l10n.authLoginSubtitleSignIn,
                        style: t.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _signInGoogle,
                          icon: const Icon(Icons.login),
                          label: Text(l10n.authLoginContinueWithGoogle),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white.withOpacity(0.15))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              l10n.authLoginOr,
                              style: TextStyle(color: Colors.white.withOpacity(0.65)),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white.withOpacity(0.15))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.authLoginEmailLabel,
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.authLoginPasswordLabel,
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      if (_isRegister) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _confirm,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: l10n.authLoginConfirmPasswordLabel,
                            labelStyle: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : (_isRegister ? _registerEmail : _signInEmail),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_isRegister ? l10n.authLoginCreateAccount : l10n.authLoginSignIn),
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
                          _isRegister ? l10n.authLoginToggleToSignIn : l10n.authLoginToggleToRegister,
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
