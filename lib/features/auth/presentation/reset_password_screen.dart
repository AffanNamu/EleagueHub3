//ResetPasswordScreen
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
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
      _showSnack(context.l10n.errorPasswordsDoNotMatch);
      return;
    }

    final code = AuthValidators.extractOobCode(codeInput);

    setState(() => _submitting = true);
    try {
      await _auth.verifyPasswordResetCode(code: code);
      await _auth.confirmPasswordReset(code: code, newPassword: newPass);

      if (!mounted) return;
      _showSnack(context.l10n.tr('reset_password_success'));
      context.go('/login');
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('reset_password_app_bar_title')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                      Icons.password,
                      size: 44,
                      color: AppTheme.limeAccentDark,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.tr('reset_password_title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.emailHint == null
                          ? l10n.tr('reset_password_subtitle_no_email')
                          : '${l10n.tr('reset_password_subtitle_with_email_prefix')}${widget.emailHint}${l10n.tr('reset_password_subtitle_with_email_suffix')}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _codeOrLink,
                      label: l10n.tr('reset_password_code_label'),
                      hint: l10n.tr('reset_password_code_hint'),
                      enabled: !_submitting,
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        tooltip: l10n.tr('reset_password_paste_tooltip'),
                        onPressed: _submitting ? null : _paste,
                        icon: const Icon(Icons.content_paste),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _newPassword,
                      label: l10n.tr('reset_password_new_password_label'),
                      enabled: !_submitting,
                      obscureText: _obscureNew,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscureNew
                            ? l10n.tr('reset_password_show_password')
                            : l10n.tr('reset_password_hide_password'),
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
                      label: l10n.tr('reset_password_confirm_password_label'),
                      enabled: !_submitting,
                      obscureText: _obscureConfirm,
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirm
                            ? l10n.tr('reset_password_show_password')
                            : l10n.tr('reset_password_hide_password'),
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
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _reset(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: _submitting ? null : _reset,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.darkText,
                                ),
                              )
                            : Text(l10n.tr('reset_password_update_button')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          _submitting ? null : () => context.go('/forgot-password'),
                      child: Text(l10n.tr('reset_password_resend_button')),
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
