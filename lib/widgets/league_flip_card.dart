import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/color_compat.dart';
import '../core/widgets/glass.dart';
import '../features/leagues/data/services/reward_firestore_service.dart';

class LeagueFlipCard extends StatefulWidget {
  const LeagueFlipCard({
    super.key,
    this.league,
    this.leagueId,
    this.showRewardsBadge = true,
    this.showRewardsPreview = true,
    this.leagueName,
    this.leagueCode,
    this.distribution,
    this.subtitle,
    this.qrWidget,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
  });

  final dynamic league;
  final String? leagueId;
  final bool showRewardsBadge;
  final bool showRewardsPreview;
  final String? leagueName;
  final String? leagueCode;
  final String? distribution;
  final String? subtitle;
  final Widget? qrWidget;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  @override
  State<LeagueFlipCard> createState() => _LeagueFlipCardState();
}

class _LeagueFlipCardState extends State<LeagueFlipCard>
    with SingleTickerProviderStateMixin {
  final RewardFirestoreService _rewardsService = RewardFirestoreService();

  late final AnimationController _controller;
  late final Animation<double> _anim;

  bool _showBack = false;

  final Map<String, Future<String?>> _topRewardFutureCache =
      <String, Future<String?>>{};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 420), vsync: this);
    _anim = CurvedAnimation(
        parent: _controller, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Map<String, dynamic> _extractMap(dynamic obj) {
    if (obj == null) return const <String, dynamic>{};
    if (obj is Map<String, dynamic>) return obj;
    if (obj is Map) return obj.map((k, v) => MapEntry(k.toString(), v));
    try {
      final m = (obj as dynamic).toJson();
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return m.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    return const <String, dynamic>{};
  }

  String _readString(dynamic obj, List<String> keys,
      {String fallback = ''}) {
    final map = _extractMap(obj);
    for (final k in keys) {
      final v = map[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return fallback;
  }

  String _deriveLeagueId() {
    final explicit = (widget.leagueId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;

    final league = widget.league;
    final map = _extractMap(league);
    final id =
        (map['id'] ?? map['leagueId'] ?? map['docId'] ?? '')
            .toString()
            .trim();
    if (id.isNotEmpty) return id;

    try {
      final v = (league as dynamic).id;
      if (v != null && v.toString().trim().isNotEmpty)
        return v.toString().trim();
    } catch (_) {}

    return '';
  }

  String _title() {
    final legacy = (widget.leagueName ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    return _readString(widget.league, const ['name', 'leagueName', 'title'],
        fallback: 'League');
  }

  String _code() {
    final legacy = (widget.leagueCode ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    return _readString(widget.league, const ['code', 'joinCode'],
        fallback: '');
  }

  String _distribution() {
    final legacy = (widget.distribution ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    final fmt = _readString(
        widget.league, const ['formatName', 'format', 'leagueFormat'],
        fallback: '');
    final season =
        _readString(widget.league, const ['season'], fallback: '');
    return [fmt, season].where((e) => e.trim().isNotEmpty).join(' • ');
  }

  String _subtitle() {
    final legacy = (widget.subtitle ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    return _readString(widget.league, const ['subtitle', 'region'],
        fallback: '');
  }

  String _qrPayload() {
    final map = _extractMap(widget.league);
    final override = (map['qrPayloadOverride'] ?? '').toString().trim();
    if (override.isNotEmpty) return override;
    final qr = (map['qrPayload'] ?? '').toString().trim();
    if (qr.isNotEmpty) return qr;
    return _code();
  }

  void _toggleFlip() {
    setState(() => _showBack = !_showBack);
    if (_showBack) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  Future<String?> _topRewardNameFuture(String leagueId) {
    return _topRewardFutureCache.putIfAbsent(
      leagueId,
      () => _rewardsService.fetchTopRewardName(leagueId: leagueId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leagueId = _deriveLeagueId();

    return GestureDetector(
      onTap: () {
        widget.onTap?.call();
        _toggleFlip();
      },
      onLongPress: widget.onLongPress,
      onDoubleTap: widget.onDoubleTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.98, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, s, child) =>
            Transform.scale(scale: s, child: child),
        child: Glass(
          borderRadius: 26,
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 240,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final t = _anim.value;
                final angle = t * math.pi;
                final isBackVisible = t >= 0.5;

                final face = isBackVisible
                    ? _backFace(context)
                    : _frontFace(context, leagueId);

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0016)
                    ..rotateY(angle),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: isBackVisible
                        ? (Matrix4.identity()..rotateY(math.pi))
                        : Matrix4.identity(),
                    child: face,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _frontFace(BuildContext context, String leagueId) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = _title();
    final code = _code();
    final distribution = _distribution();
    final subtitle = _subtitle();

    final bool wantsRewardsUi =
        (widget.showRewardsBadge || widget.showRewardsPreview) &&
            leagueId.trim().isNotEmpty;
    final Future<String?>? topRewardFuture =
        wantsRewardsUi ? _topRewardNameFuture(leagueId) : null;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.14),
                  cs.secondary.withValues(alpha: 0.10),
                  cs.onSurface.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color: cs.onSurface.withValues(alpha: 0.10)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.95),
                          cs.secondary.withValues(alpha: 0.95),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.emoji_events_outlined,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (distribution.isNotEmpty)
                Text(
                  distribution,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
              if (widget.showRewardsPreview &&
                  topRewardFuture != null) ...[
                const SizedBox(height: 10),
                FutureBuilder<String?>(
                  future: topRewardFuture,
                  builder: (context, snap) {
                    final name = (snap.data ?? '').trim();
                    if (name.isEmpty) {
                      if (snap.connectionState !=
                          ConnectionState.waiting)
                        return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: cs.onSurface.withValues(alpha: 0.05),
                          border: Border.all(
                              color: cs.onSurface
                                  .withValues(alpha: 0.10)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.card_giftcard_outlined,
                                size: 16,
                                color: cs.onSurface
                                    .withValues(alpha: 0.45)),
                            const SizedBox(width: 8),
                            Text(
                              'Checking rewards...',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(
                                color: cs.onSurface
                                    .withValues(alpha: 0.55),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      child: Container(
                        key: ValueKey<String>('topReward:$name'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: cs.primary.withValues(alpha: 0.12),
                          border: Border.all(
                              color: cs.primary
                                  .withValues(alpha: 0.28)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.card_giftcard_outlined,
                                size: 16, color: cs.primary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Top reward: $name',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  if (code.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: cs.onSurface.withValues(alpha: 0.06),
                        border: Border.all(
                            color: cs.onSurface
                                .withValues(alpha: 0.12)),
                      ),
                      child: Text(
                        'CODE: $code',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: cs.primary.withValues(alpha: 0.14),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      'TAP TO FLIP',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.showRewardsBadge && topRewardFuture != null)
          Positioned(
            right: 14,
            top: 14,
            child: FutureBuilder<String?>(
              future: topRewardFuture,
              builder: (context, snap) {
                final name = (snap.data ?? '').trim();
                if (name.isEmpty) return const SizedBox.shrink();

                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD54F), Color(0xFFFF8A65)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Text(
                      '🏆 Rewards Available',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.black.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _backFace(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final qr = widget.qrWidget ??
        QrImageView(
          data: _qrPayload(),
          version: QrVersions.auto,
          gapless: true,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: cs.onSurface.withValues(alpha: 0.03),
        border:
            Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              'Scan to Join',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: qr,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to flip back',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.70),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
