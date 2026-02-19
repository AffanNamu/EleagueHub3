import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // New Visual Props
    this.imageUrl,
    this.isLocked = false,
    this.onPay,
    this.isOwner = false,
    this.isViewer = false,
    this.isFull = false,
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

  // Visual props to integrate badges/thumb into the card surface
  final String? imageUrl;
  final bool isLocked;
  final VoidCallback? onPay;
  final bool isOwner;
  final bool isViewer;
  final bool isFull;

  @override
  State<LeagueFlipCard> createState() => _LeagueFlipCardState();
}

class _LeagueFlipCardState extends State<LeagueFlipCard>
    with SingleTickerProviderStateMixin {
  static const double _outerRadius = 28;

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
      duration: const Duration(milliseconds: 560),
      vsync: this,
    );
    _anim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
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

  String _readString(
    dynamic obj,
    List<String> keys, {
    String fallback = '',
  }) {
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
    final id = (map['id'] ?? map['leagueId'] ?? map['docId'] ?? '')
        .toString()
        .trim();
    if (id.isNotEmpty) return id;

    try {
      final v = (league as dynamic).id;
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    } catch (_) {}

    return '';
  }

  String _title() {
    final legacy = (widget.leagueName ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    return _readString(
      widget.league,
      const ['name', 'leagueName', 'title'],
      fallback: 'League',
    );
  }

  String _code() {
    final legacy = (widget.leagueCode ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    return _readString(
      widget.league,
      const ['code', 'joinCode'],
      fallback: '',
    );
  }

  String _distribution() {
    final legacy = (widget.distribution ?? '').trim();
    if (legacy.isNotEmpty) return legacy;

    final fmt = _readString(
      widget.league,
      const ['formatName', 'format', 'leagueFormat'],
      fallback: '',
    );
    final season = _readString(widget.league, const ['season'], fallback: '');
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

  Future<void> _copyInviteCode(BuildContext context) async {
    final code = _code().trim();
    if (code.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite code copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leagueId = _deriveLeagueId();

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.hasBoundedHeight && constraints.maxHeight > 0)
            ? constraints.maxHeight
            : 220.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onTap?.call();
            _toggleFlip();
          },
          onLongPress: widget.onLongPress,
          onDoubleTap: widget.onDoubleTap,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.985, end: 1.0),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, s, child) => Transform.scale(scale: s, child: child),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final t = _anim.value; // 0..1
                final angle = t * math.pi;

                // Different flip feel (more "2050"): vertical flip (X axis) + slight diagonal twist (Y).
                final diagonalTwist = 0.16 * math.sin(angle);

                // Lift + premium shadow while flipping.
                final lift = math.sin(t * math.pi);
                final translateY = -3.0 * lift;
                final scale = 1.0 + (0.018 * lift);

                // Which face should be painted (keeps QR build cheap: only built when needed).
                final isBackVisible = t >= 0.5;
                final face = isBackVisible
                    ? _backFace(context, t)
                    : _frontFace(context, leagueId, t);

                final shadowOpacity = 0.10 + (0.20 * lift);

                return Transform.translate(
                  offset: Offset(0, translateY),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_outerRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowOpacity),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0019)
                          ..rotateX(angle)
                          ..rotateY(diagonalTwist),
                        child: Transform(
                          alignment: Alignment.center,
                          // Prevent mirrored content on the back side.
                          transform: isBackVisible
                              ? (Matrix4.identity()..rotateX(math.pi))
                              : Matrix4.identity(),
                          child: Glass(
                            borderRadius: _outerRadius,
                            padding: EdgeInsets.zero,
                            blur: 18,
                            opacity: 0.055,
                            borderColor: Colors.white.withValues(alpha: 0.10),
                            child: SizedBox(height: height, child: face),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _frontFace(BuildContext context, String leagueId, double t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = _title();
    final distribution = _distribution();
    final subtitle = _subtitle();

    final bool wantsRewardsUi =
        (widget.showRewardsBadge || widget.showRewardsPreview) &&
            leagueId.trim().isNotEmpty;

    final Future<String?>? topRewardFuture =
        wantsRewardsUi ? _topRewardNameFuture(leagueId) : null;

    // Holographic sheen moves slightly only while flipping.
    final sheenPos = -1.35 + (2.70 * t);
    final sheenStrength = (math.sin(t * math.pi)).clamp(0.0, 1.0);

    return Stack(
      children: [
        // Base futuristic glass surface.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_outerRadius - 3),
              gradient: LinearGradient(
                colors: [
                  cs.onSurface.withValues(alpha: 0.045),
                  cs.onSurface.withValues(alpha: 0.030),
                  cs.onSurface.withValues(alpha: 0.020),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
            ),
          ),
        ),

        // Soft neon glows (premium, subtle).
        Positioned(
          left: -40,
          top: -40,
          child: _GlowBlob(color: cs.primary, opacity: 0.18, size: 160),
        ),
        Positioned(
          right: -50,
          bottom: -60,
          child: _GlowBlob(color: cs.secondary, opacity: 0.14, size: 190),
        ),

        // Nano grid overlay (static, very subtle).
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_outerRadius - 3),
              child: CustomPaint(
                painter: _NanoGridPainter(
                  color: cs.onSurface.withValues(alpha: 0.10),
                ),
              ),
            ),
          ),
        ),

        // Holographic sheen (animated by flip progress).
        if (sheenStrength > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_outerRadius - 3),
                child: Opacity(
                  opacity: 0.10 + 0.22 * sheenStrength,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(sheenPos, -1),
                        end: Alignment(sheenPos + 1.1, 1),
                        colors: const [
                          Colors.transparent,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: const [0.35, 0.50, 0.65],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icon tile (more premium than flat).
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.98),
                          cs.secondary.withValues(alpha: 0.92),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.emoji_events_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (widget.showRewardsBadge && topRewardFuture != null)
                    FutureBuilder<String?>(
                      future: topRewardFuture,
                      builder: (context, snap) {
                        final name = (snap.data ?? '').trim();
                        if (name.isEmpty) return const SizedBox.shrink();
                        return _MiniPill(
                          icon: Icons.card_giftcard_rounded,
                          label: 'Rewards',
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD54F), Color(0xFFFF8A65)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          textColor: Colors.black.withValues(alpha: 0.86),
                        );
                      },
                    ),
                ],
              ),

              const SizedBox(height: 12),

              if (distribution.isNotEmpty)
                Text(
                  distribution,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),

              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.80),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],

              if (widget.showRewardsPreview && topRewardFuture != null) ...[
                const SizedBox(height: 12),
                FutureBuilder<String?>(
                  future: topRewardFuture,
                  builder: (context, snap) {
                    final name = (snap.data ?? '').trim();

                    if (name.isEmpty) {
                      if (snap.connectionState != ConnectionState.waiting) {
                        return const SizedBox.shrink();
                      }
                      return _SoftStatusPill(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Checking rewards...',
                      );
                    }

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      child: Container(
                        key: ValueKey<String>('topReward:$name'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              cs.primary.withValues(alpha: 0.15),
                              cs.secondary.withValues(alpha: 0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.24),
                          ),
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
                                style: theme.textTheme.labelLarge?.copyWith(
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

              // Clean bottom CTA (no code on front anymore).
              Row(
                children: [
                  Expanded(
                    child: _ActionChip(
                      icon: Icons.qr_code_2_rounded,
                      label: 'Tap for QR & invite code',
                      fg: cs.primary,
                      bg: cs.primary.withValues(alpha: 0.14),
                      border: cs.primary.withValues(alpha: 0.32),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ActionChip(
                    icon: Icons.touch_app_rounded,
                    label: 'Flip',
                    fg: cs.onSurface.withValues(alpha: 0.75),
                    bg: cs.onSurface.withValues(alpha: 0.06),
                    border: cs.onSurface.withValues(alpha: 0.12),
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _backFace(BuildContext context, double t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final code = _code().trim();

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

    // Back side has a slightly stronger contrast for readability.
    final sheenPos = -1.20 + (2.40 * t);
    final sheenStrength = (math.sin(t * math.pi)).clamp(0.0, 1.0);

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_outerRadius - 3),
              gradient: LinearGradient(
                colors: [
                  cs.onSurface.withValues(alpha: 0.050),
                  cs.onSurface.withValues(alpha: 0.028),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
            ),
          ),
        ),

        Positioned(
          left: -50,
          bottom: -60,
          child: _GlowBlob(color: cs.primary, opacity: 0.12, size: 210),
        ),
        Positioned(
          right: -60,
          top: -70,
          child: _GlowBlob(color: cs.secondary, opacity: 0.10, size: 220),
        ),

        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_outerRadius - 3),
              child: CustomPaint(
                painter: _NanoGridPainter(
                  color: cs.onSurface.withValues(alpha: 0.09),
                ),
              ),
            ),
          ),
        ),

        if (sheenStrength > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_outerRadius - 3),
                child: Opacity(
                  opacity: 0.08 + 0.18 * sheenStrength,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(sheenPos, -1),
                        end: Alignment(sheenPos + 1.1, 1),
                        colors: const [
                          Colors.transparent,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: const [0.36, 0.50, 0.64],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            children: [
              // QR side
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    Text(
                      'Scan to Join',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 22,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: qr,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tap anywhere to flip back',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.68),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // Invite code + actions side
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVITE CODE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: cs.onSurface.withValues(alpha: 0.06),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        code.isEmpty ? '— — — — —' : code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: code.isEmpty
                              ? cs.onSurface.withValues(alpha: 0.35)
                              : cs.onSurface.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Copy button (doesn't move; no bottom-right collisions with PAY overlay).
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: code.isEmpty ? null : () => _copyInviteCode(context),
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          height: 44,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: code.isEmpty
                                  ? [
                                      cs.onSurface.withValues(alpha: 0.08),
                                      cs.onSurface.withValues(alpha: 0.06),
                                    ]
                                  : [
                                      cs.primary.withValues(alpha: 0.90),
                                      cs.secondary.withValues(alpha: 0.82),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 18,
                                  color: code.isEmpty
                                      ? cs.onSurface.withValues(alpha: 0.45)
                                      : Colors.white,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'COPY',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color: code.isEmpty
                                        ? cs.onSurface.withValues(alpha: 0.45)
                                        : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      code.isEmpty
                          ? 'No invite code available for this league.'
                          : 'Share this code with friends or let them scan the QR.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.68),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),

                    const Spacer(),

                    // Subtle hint (keeps back clean).
                    _SoftStatusPill(
                      icon: Icons.rocket_launch_rounded,
                      label: 'Fast join (QR) • Easy share (code)',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.color,
    required this.opacity,
    required this.size,
  });

  final Color color;
  final double opacity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;
  final Color border;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftStatusPill extends StatelessWidget {
  const _SoftStatusPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.onSurface.withValues(alpha: 0.05),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Gradient gradient;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Very subtle futuristic micro-grid.
/// Kept lightweight (fixed number of strokes), and does not repaint.
class _NanoGridPainter extends CustomPainter {
  _NanoGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Sparse diagonal lines
    final step = math.max(22.0, size.shortestSide / 8);
    for (double x = -size.height; x < size.width + size.height; x += step) {
      final p1 = Offset(x, 0);
      final p2 = Offset(x + size.height, size.height);
      canvas.drawLine(p1, p2, paint..color = color.withValues(alpha: 0.07));
    }

    // Tiny dots constellation
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final dx = math.max(28.0, size.width / 7);
    final dy = math.max(28.0, size.height / 6);
    for (double y = dy * 0.75; y < size.height; y += dy) {
      for (double x = dx * 0.75; x < size.width; x += dx) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NanoGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _LeagueCardThumb extends StatelessWidget {
  const _LeagueCardThumb({this.imageUrl});
  final String? imageUrl;

  Uint8List? _tryDecode(String s) {
    if (!s.startsWith('data:image')) return null;
    try {
      return base64Decode(s.split(',').last);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = (imageUrl ?? '').trim();
    if (s.isEmpty) {
      return const Center(
        child: Icon(Icons.emoji_events_outlined, color: Colors.white),
      );
    }

    final bytes = _tryDecode(s);
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);

    return Image.network(
      s,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image, color: Colors.white)),
    );
  }
}
