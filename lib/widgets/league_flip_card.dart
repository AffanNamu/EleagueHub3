import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/locale/app_localizations.dart';
import '../core/theme/app_theme.dart';

class LeagueFlipCard extends StatefulWidget {
  final String leagueName;
  final String leagueCode;
  final String distribution;

  final Widget? qrWidget;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTap;
  final String? subtitle;
  const LeagueFlipCard({
    super.key,
    required this.leagueName,
    required this.leagueCode,
    required this.distribution,
    this.qrWidget,
    this.onDoubleTap,
    this.onTap,
    this.subtitle,
  });

  @override
  State<LeagueFlipCard> createState() => _LeagueFlipCardState();
}

class _LeagueFlipCardState extends State<LeagueFlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyCode() async {
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: widget.leagueCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.tr('league_flip_card_invite_code_copied')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggle() {
    if (_controller.isAnimating) return;
    if (_controller.value < 0.5) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedBuilder(
        listenable: _anim,
        builder: (context, _) {
          final t = _anim.value;
          final angle = t * pi;

          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateY(angle);

          final child = angle <= (pi / 2)
              ? _buildFront()
              : Transform(
                  transform: Matrix4.rotationY(pi),
                  alignment: Alignment.center,
                  child: _buildBack(),
                );

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: child,
          );
        },
      ),
    );
  }

  Widget _glass({required Widget child}) {
    final brightness = Theme.of(context).brightness;
    final fill = AppTheme.glassFill(brightness);
    final stroke = AppTheme.glassStroke(brightness);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: stroke),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFront() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _glass(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          children: [
            // ── Top content (takes available space) ──
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Trophy icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withOpacity(0.25),
                          Colors.amber.withOpacity(0.15),
                        ],
                      ),
                      border: Border.all(color: Colors.amber.withOpacity(0.30)),
                    ),
                    child: const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(height: 10),

                  // League name
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.leagueName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Distribution
                  Text(
                    widget.distribution,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),

                  // Subtitle (if provided)
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.40),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // ── Bottom hints (fixed, never overlaps) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded, size: 13, color: cs.primary.withOpacity(0.8)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.tr('league_flip_card_tap_to_join_scan_qr').toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.primary.withOpacity(0.85),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.onDoubleTap != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('league_flip_card_double_tap_to_view_details'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.40),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _glass(
      child: Row(
        children: [
          // QR code
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.94),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Center(
                  child: widget.qrWidget ??
                      const Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.black87),
                ),
              ),
            ),
          ),

          // Code + copy
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr('league_flip_card_invite_code_label').toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.leagueCode,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Copy button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _copyCode,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: cs.primary.withOpacity(0.14),
                          border: Border.all(color: cs.primary.withOpacity(0.30)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              l10n.tr('common_copy').toUpperCase(),
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  Animation<dynamic> get animation => listenable as Animation<dynamic>;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
