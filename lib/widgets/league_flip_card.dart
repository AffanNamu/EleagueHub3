import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/locale/app_localizations.dart';
import '../core/theme/app_theme.dart';

/// Glass flip card (clean, not upside-down, smooth flip)
/// - Uses a proper 3D flip with perspective
/// - Ensures the "back" face is readable (not mirrored)
/// - Tap: flip
/// - Double tap: callback
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

  bool get _isFront => _controller.value < 0.5;

  Future<void> _copyCode() async {
    final l10n = context.l10n;

    await Clipboard.setData(ClipboardData(text: widget.leagueCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('league_flip_card_invite_code_copied'))),
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
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value; // 0..1
          final angle = t * pi;

          // perspective makes it "beautiful"
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateY(angle);

          // Show front until 90deg, then show back.
          // Back is pre-rotated by pi so it is readable.
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
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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

    // The hint "Double tap to view details" was getting clipped on smaller heights
    // when distribution/subtitle are long. Pin the hint area to the bottom so it
    // always remains visible inside the fixed-height glass container.
    return _glass(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 62),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events_outlined, color: Colors.amber, size: 40),
                  ),
                  const SizedBox(height: 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.leagueName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.distribution,
                    style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(color: Colors.white.withOpacity(0.58), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app, size: 16, color: Colors.cyanAccent.withOpacity(0.8)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.tr('league_flip_card_tap_to_join_scan_qr').toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.onDoubleTap != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.tr('league_flip_card_double_tap_to_view_details'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBack() {
    final l10n = context.l10n;

    return _glass(
      child: Row(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: Center(
                  child: widget.qrWidget ?? const Icon(Icons.qr_code_2_rounded, size: 100, color: Colors.black),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr('league_flip_card_invite_code_label').toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.leagueCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l10n.tr('common_copy').toUpperCase()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
