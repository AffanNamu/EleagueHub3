import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';
import '../data/auth_validators.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    this.emailHint,
    this.initialCode,
  });

  final String? emailHint;
  final String? initialCode;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _auth = AuthService();

  final _codeOrLink = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode?.trim();
    if (initial != null && initial.isNotEmpty) {
      _codeOrLink.text = initial;
    }
  }

  @override
  void dispose() {
    _codeOrLink.dispose();
    _newPassword.dispose();
    _confirm.dispose();
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

  Future<void> _reset() async {
    final codeInput = _codeOrLink.text;
    final codeErr = AuthValidators.validateActionCodeOrLink(codeInput);
    if (codeErr != null) {
      _showSnack(codeErr);
      return;
    }

    final newPass = _newPassword.text;
    final confirm = _confirm.text;

    final passErr = AuthValidators.validatePassword(newPass);
    if (passErr != null) {
      _showSnack(passErr);
      return;
    }
    if (newPass != confirm) {
      _showSnack('Passwords do not match.');
      return;
    }

    final code = AuthValidators.extractOobCode(codeInput);

    setState(() => _submitting = true);
    try {
      // Optional: verify code first (better errors + shows account email if needed).
      await _auth.verifyPasswordResetCode(code: code);

      await _auth.confirmPasswordReset(code: code, newPassword: newPass);

      if (!mounted) return;
      _showSnack('Password updated. You can sign in now.');
      context.go('/login');
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

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Set new password'),
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
                    Icon(
                      Icons.password,
                      size: 44,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Enter the code/link from your email',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.emailHint == null
                          ? 'Paste the password reset link (or code) you received from Firebase.'
                          : 'We sent a reset email to ${widget.emailHint}. Paste the reset link (or code) here.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _codeOrLink,
                      label: 'Reset code or link',
                      hint: 'Paste here (contains oobCode=...)',
                      enabled: !_submitting,
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Paste',
                        onPressed: _submitting ? null : _paste,
                        icon: const Icon(Icons.content_paste),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _newPassword,
                      label: 'New password',
                      enabled: !_submitting,
                      obscureText: _obscureNew,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip:
                            _obscureNew ? 'Show password' : 'Hide password',
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _obscureNew = !_obscureNew),
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _confirm,
                      label: 'Confirm new password',
                      enabled: !_submitting,
                      obscureText: _obscureConfirm,
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        tooltip:
                            _obscureConfirm ? 'Show password' : 'Hide password',
                        onPressed: _submitting
                            ? null
                            : () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _reset(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _reset,
                        child: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Text('Update password'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          _submitting ? null : () => context.go('/forgot-password'),
                      child: const Text('Resend reset email'),
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
