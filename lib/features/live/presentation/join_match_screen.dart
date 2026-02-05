import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

class JoinMatchScreen extends ConsumerStatefulWidget {
  const JoinMatchScreen({super.key});

  @override
  ConsumerState<JoinMatchScreen> createState() => _JoinMatchScreenState();
}

class _JoinMatchScreenState extends ConsumerState<JoinMatchScreen> {
  final _matchIdCtrl = TextEditingController();
  final _homeCtrl = TextEditingController();
  final _awayCtrl = TextEditingController();

  String? _errorKey;

  @override
  void dispose() {
    _matchIdCtrl.dispose();
    _homeCtrl.dispose();
    _awayCtrl.dispose();
    super.dispose();
  }

  void _pushLiveView({
    required bool isHost,
    required String side, // 'home' | 'away' | 'unknown'
  }) {
    final matchId = _matchIdCtrl.text.trim();
    final homeName = _homeCtrl.text.trim();
    final awayName = _awayCtrl.text.trim();

    if (matchId.isEmpty) {
      setState(() => _errorKey = 'join_match_error_match_id_required');
      return;
    }

    setState(() => _errorKey = null);

    context.push(
      '/live/view/$matchId',
      extra: <String, dynamic>{
        'isHost': isHost,
        if (homeName.isNotEmpty) 'homeName': homeName,
        if (awayName.isNotEmpty) 'awayName': awayName,
        'side': side.trim().isEmpty ? 'unknown' : side.trim(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final media = MediaQuery.of(context);
    final isWide = media.size.width > 600;

    // IMPORTANT for small devices:
    // When keyboard is open, we add bottom padding so fields/buttons can be scrolled into view.
    final bottomInset = media.viewInsets.bottom;
    final bottomPadding = 16.0 + bottomInset;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('join_match_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 720 : 520),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 14),
                _buildFormCard(context),
                const SizedBox(height: 14),
                _buildActionsCard(isWide: isWide),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withOpacity(0.18),
              border: Border.all(color: cs.primary.withOpacity(0.24)),
            ),
            child: Icon(Icons.public, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('join_match_header_title'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.tr('join_match_header_subtitle'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isCompact = MediaQuery.of(context).size.width < 520;
    final errorText = _errorKey == null ? null : l10n.tr(_errorKey!);

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _matchIdCtrl,
            textInputAction: TextInputAction.next,
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              labelText: l10n.tr('join_match_match_id_label'),
              hintText: l10n.tr('join_match_match_id_hint'),
              prefixIcon: const Icon(Icons.tag),
              errorText: errorText,
            ),
            onChanged: (_) {
              if (_errorKey != null) setState(() => _errorKey = null);
            },
          ),
          const SizedBox(height: 10),
          if (isCompact) ...[
            TextField(
              controller: _homeCtrl,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: l10n.tr('join_match_home_name_optional'),
                prefixIcon: const Icon(Icons.home),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _awayCtrl,
              textInputAction: TextInputAction.done,
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: l10n.tr('join_match_away_name_optional'),
                prefixIcon: const Icon(Icons.flight_takeoff),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _homeCtrl,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: l10n.tr('join_match_home_name_optional'),
                      prefixIcon: const Icon(Icons.home),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _awayCtrl,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: l10n.tr('join_match_away_name_optional'),
                      prefixIcon: const Icon(Icons.flight_takeoff),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            l10n.tr('join_match_tip'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.45),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard({required bool isWide}) {
    final l10n = context.l10n;

    final matchId = _matchIdCtrl.text.trim();
    final disabled = matchId.isEmpty;

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: disabled ? null : () => _pushLiveView(isHost: false, side: 'unknown'),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.tr('join_match_join_as_viewer')),
            ),
          ),
          const SizedBox(height: 10),
          if (isWide) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: disabled ? null : () => _pushLiveView(isHost: true, side: 'home'),
                    icon: const Icon(Icons.sports_esports),
                    label: Text(l10n.tr('join_match_host_as_home')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: disabled ? null : () => _pushLiveView(isHost: true, side: 'away'),
                    icon: const Icon(Icons.sports_esports),
                    label: Text(l10n.tr('join_match_host_as_away')),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Small phones: stack buttons so they never get cramped/truncated.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: disabled ? null : () => _pushLiveView(isHost: true, side: 'home'),
                icon: const Icon(Icons.sports_esports),
                label: Text(l10n.tr('join_match_host_as_home')),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: disabled ? null : () => _pushLiveView(isHost: true, side: 'away'),
                icon: const Icon(Icons.sports_esports),
                label: Text(l10n.tr('join_match_host_as_away')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
