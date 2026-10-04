// lib/features/team_claim/presentation/claim_team_screen.dart
//
// The screen a real-world team's captain/owner lands on after opening a
// claim link/QR (Sections 12, 16, 37-39 of the claim spec). Renders
// identically whether the link arrived via native deep link or direct web
// navigation to /claim/:token (see _publicShareRoutePrefixes in
// app_router.dart -- this route is intentionally reachable signed-out).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/team_claim_repository.dart';

enum _ClaimScreenState { loading, error, ready, confirming, success }

class ClaimTeamScreen extends StatefulWidget {
  const ClaimTeamScreen({super.key, required this.token});

  final String token;

  @override
  State<ClaimTeamScreen> createState() => _ClaimTeamScreenState();
}

class _ClaimTeamScreenState extends State<ClaimTeamScreen> {
  final _repo = TeamClaimRepository();

  _ClaimScreenState _state = _ClaimScreenState.loading;
  TeamClaimPreview? _preview;
  TeamClaimResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _ClaimScreenState.loading;
      _error = null;
    });

    try {
      final preview = await _repo.preview(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _state = _ClaimScreenState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
        _state = _ClaimScreenState.error;
      });
    }
  }

  String get _returnToPath => '/claim/${widget.token}';

  void _goToAuth(String basePath) {
    context.go('$basePath?returnTo=${Uri.encodeComponent(_returnToPath)}');
  }

  Future<void> _confirm() async {
    setState(() => _state = _ClaimScreenState.confirming);
    unawaited(AppAnalyticsService.instance.logEvent(eventName: 'claim_started'));
    try {
      final result = await _repo.confirm(widget.token);
      if (!mounted) return;
      setState(() {
        _result = result;
        _state = _ClaimScreenState.success;
      });
      unawaited(
        AppAnalyticsService.instance.logEvent(
          eventName: 'team_claimed',
          extra: {'leagueId': result.leagueId, 'teamId': result.teamId},
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
        _state = _ClaimScreenState.ready;
      });
      unawaited(AppAnalyticsService.instance.logEvent(eventName: 'claim_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('team_claim_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _buildContent(l10n, brightness),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n, Brightness brightness) {
    switch (_state) {
      case _ClaimScreenState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator()),
        );

      case _ClaimScreenState.error:
        return _ErrorCard(message: _error ?? '', onRetry: _load, brightness: brightness);

      case _ClaimScreenState.success:
        return _SuccessCard(result: _result!, brightness: brightness);

      case _ClaimScreenState.ready:
      case _ClaimScreenState.confirming:
        return _PreviewCard(
          preview: _preview!,
          brightness: brightness,
          busy: _state == _ClaimScreenState.confirming,
          error: _error,
          onConfirm: _confirm,
          onSignIn: () => _goToAuth('/login'),
          onCreateAccount: () => _goToAuth('/login'),
        );
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.brightness,
    required this.busy,
    required this.error,
    required this.onConfirm,
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final TeamClaimPreview preview;
  final Brightness brightness;
  final bool busy;
  final String? error;
  final VoidCallback onConfirm;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final signedIn = FirebaseAuth.instance.currentUser != null;

    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🏆', style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            l10n.tr('team_claim_header'),
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.searchBackground(brightness),
              border: Border.all(color: AppTheme.cardBorder(brightness)),
              image: preview.teamLogoUrl.isNotEmpty
                  ? DecorationImage(image: NetworkImage(preview.teamLogoUrl), fit: BoxFit.cover)
                  : null,
            ),
            child: preview.teamLogoUrl.isEmpty
                ? Icon(Icons.shield_outlined, size: 36, color: AppTheme.secondaryText(brightness))
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            preview.teamName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tr('team_claim_intro_text'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 13, height: 1.4),
          ),
          if (preview.leagueName.isNotEmpty || preview.organizerName.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.searchBackground(brightness),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder(brightness)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview.leagueName.isNotEmpty) ...[
                    _InfoRow(label: l10n.tr('team_claim_competition_label'), value: preview.leagueName),
                    const SizedBox(height: 8),
                  ],
                  if (preview.organizerName.isNotEmpty)
                    _InfoRow(label: l10n.tr('team_claim_organizer_label'), value: preview.organizerName),
                ],
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          if (signedIn)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkText),
                      )
                    : Text(l10n.tr('team_claim_confirm_button'), style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSignIn,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(l10n.tr('team_claim_sign_in_button'), style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onCreateAccount,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryText(brightness),
                  side: BorderSide(color: AppTheme.cardBorder(brightness)),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(l10n.tr('team_claim_create_account_button')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: AppTheme.primaryText(brightness), fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry, required this.brightness});
  final String message;
  final VoidCallback onRetry;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: onRetry, child: Text(l10n.tr('common_retry'))),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.result, required this.brightness});
  final TeamClaimResult result;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            l10n.tr('team_claim_success_title'),
            style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            '${result.teamName} ${l10n.tr('team_claim_success_body')}',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go('/leagues/${result.leagueId}'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(l10n.tr('team_claim_view_competition_button'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryText(brightness),
                side: BorderSide(color: AppTheme.cardBorder(brightness)),
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(l10n.tr('team_claim_done_button')),
            ),
          ),
        ],
      ),
    );
  }
}
