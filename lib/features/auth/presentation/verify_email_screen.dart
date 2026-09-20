//VerifyEmailScreen
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
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
    final now = DateTime.now();
    if (_lastResendAt != null) {
      final diff = now.difference(_lastResendAt!);
      if (diff.inSeconds < 20) {
        _showSnack(context.l10n.tr('verify_email_resend_wait'));
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await _auth.sendEmailVerification();
      _lastResendAt = DateTime.now();
      _showSnack(context.l10n.tr('verify_email_sent_message'));
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
        _showSnack(context.l10n.tr('verify_email_verified_welcome'));
      } else {
        _showSnack(
          context.l10n.tr('verify_email_applied_message'),
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
        _showSnack(context.l10n.tr('verify_email_signed_out'));
        return;
      }
      if (!u.emailVerified) {
        _showSnack(
          context.l10n.tr('verify_email_not_verified_yet'),
        );
        return;
      }

      _showSnack(context.l10n.tr('verify_email_verified_continuing'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _submitting = true);
    try {
      await _auth.signOut();
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';

    return GlassScaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('verify_email_appbar_title')),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _signOut,
            child: Text(context.l10n.tr('verify_email_sign_out_button')),
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
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 44,
                      color: AppTheme.limeAccentDark,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.tr('verify_email_heading'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      email.isEmpty
                          ? context.l10n.tr('verify_email_sent_generic')
                          : "${context.l10n.tr('verify_email_sent_to_prefix')}$email",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.tr('verify_email_options_instructions'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _codeOrLink,
                      label: context.l10n.tr('verify_email_code_label'),
                      hint: context.l10n.tr('verify_email_code_hint'),
                      enabled: !_submitting,
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        tooltip: context.l10n.tr('common_paste'),
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
                            child: Text(context.l10n.tr('verify_email_resend_button')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.limeAccent,
                              foregroundColor: AppTheme.darkText,
                            ),
                            onPressed: _submitting ? null : _verifyByCode,
                            child: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.darkText,
                                    ),
                                  )
                                : Text(context.l10n.tr('verify_email_verify_button')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _submitting ? null : _verifiedContinue,
                        child: Text(context.l10n.tr('verify_email_continue_button')),
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
