import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';
import '../data/auth_validators.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.initialCode,
  });

  final String? initialCode;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _auth = AuthService();
  final _codeOrLink = TextEditingController();

  bool _submitting = false;
  Timer? _poll;
  DateTime? _lastResendAt;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode?.trim();
    if (initial != null && initial.isNotEmpty) {
      _codeOrLink.text = initial;
    }

    // Poll a little so if user taps the email link and comes back,
    // the UI can auto-unlock without requiring app restart.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      await authRouterRefresh.refreshAuthUser();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _codeOrLink.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _codeOrLink.text = text;
    setState(() {});
  }

  Future<void> _resend() async {
    // Basic client-side cooldown to reduce "too-many-requests".
    final now = DateTime.now();
    if (_lastResendAt != null) {
      final diff = now.difference(_lastResendAt!);
      if (diff.inSeconds < 20) {
        _showSnack('Please wait a moment before resending.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await _auth.sendEmailVerification();
      _lastResendAt = DateTime.now();
      _showSnack('Verification email sent. Check your inbox (and spam).');
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _verifyByCode() async {
    final input = _codeOrLink.text;
    final err = AuthValidators.validateActionCodeOrLink(input);
    if (err != null) {
      _showSnack(err);
      return;
    }

    final code = AuthValidators.extractOobCode(input);

    setState(() => _submitting = true);
    try {
      await _auth.applyEmailVerificationCode(code: code);
      await authRouterRefresh.refreshAuthUser();

      if (!mounted) return;

      final u = FirebaseAuth.instance.currentUser;
      if (u != null && u.emailVerified) {
        _showSnack('Email verified. Welcome!');
        // Router redirect will move user onward.
      } else {
        _showSnack(
          'Verification applied. If you still see this screen, tap “I verified, continue”.',
        );
      }
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _verifiedContinue() async {
    setState(() => _submitting = true);
    try {
      await authRouterRefresh.refreshAuthUser();
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        _showSnack('You are signed out.');
        return;
      }
      if (!u.emailVerified) {
        _showSnack(
          'Not verified yet. Please open the email and follow the verification link, then try again.',
        );
        return;
      }

      _showSnack('Verified. Continuing…');
      // Router redirect will proceed to onboarding / home.
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _submitting = true);
    try {
      await _auth.signOut();
      // Router redirect sends to /login
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Verify your email'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 44,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Confirm your email to continue',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      email.isEmpty
                          ? 'We sent a verification email using Firebase Authentication.'
                          : 'We sent a verification email to:\n$email',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Option A: Tap the link in the email.\nOption B: Copy the link (or code) and paste it below.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _codeOrLink,
                      label: 'Verification code or link',
                      hint: 'Paste here (contains oobCode=...)',
                      enabled: !_submitting,
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Paste',
                        onPressed: _submitting ? null : _paste,
                        icon: const Icon(Icons.content_paste),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verifyByCode(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _submitting ? null : _resend,
                            child: const Text('Resend email'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitting ? null : _verifyByCode,
                            child: _submitting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onPrimary,
                                    ),
                                  )
                                : const Text('Verify'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _submitting ? null : _verifiedContinue,
                        child: const Text('I verified, continue'),
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
