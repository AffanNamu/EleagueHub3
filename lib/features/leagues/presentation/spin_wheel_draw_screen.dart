// lib/features/leagues/presentation/spin_wheel_draw_screen.dart
//
// Spin Wheel / Random Draw — optional alternative input method for the
// existing Classic League fixture generation flow.
//
// ARCHITECTURE NOTE (read before touching this file):
// This screen does NOT create, persist, or touch any FixtureMatch,
// any Firestore document, or any repository. It only randomizes the
// ORDER of the Team list it is given and hands that order back to the
// caller via Navigator.pop(context, orderedTeams). AddTeamsScreen then
// feeds that order into the exact same
// FixtureGenerator.generateClassicLeagueFixtures(...) and
// LocalLeaguesRepository.replaceMatches(...) calls used by the existing
// "Automatic" button. That means:
//   - no new fixture data model
//   - no new Firestore collection/path
//   - no Security Rules changes required
//   - existing organizer-only write permission on matches still applies,
//     enforced exactly as it is today, on the exact same write call.
//
// If the organizer backs out or leaves before tapping "Confirm & Generate",
// this screen pops with `null` and nothing is generated or saved.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../models/team.dart';

class SpinWheelDrawScreen extends StatefulWidget {
  final List<Team> teams;

  const SpinWheelDrawScreen({super.key, required this.teams});

  @override
  State<SpinWheelDrawScreen> createState() => _SpinWheelDrawScreenState();
}

class _SpinWheelDrawScreenState extends State<SpinWheelDrawScreen>
    with SingleTickerProviderStateMixin {
  final Random _random = Random();

  late List<Team> _pool;
  final List<Team> _drawnOrder = [];

  late final AnimationController _controller;
  Animation<double> _spinAnimation = const AlwaysStoppedAnimation<double>(0);

  double _wheelAngle = 0; // Settled angle (radians) between spins.
  bool _isSpinning = false;

  @override
  void initState() {
    super.initState();
    // Fair initial ordering for the wheel layout itself — the actual
    // per-spin selection below is what determines the real draw result.
    _pool = List<Team>.from(widget.teams)..shuffle(_random);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _drawComplete => _pool.isEmpty;

  int get _currentMatchNumber => (_drawnOrder.length ~/ 2) + 1;

  Team? get _slotA {
    final pairStart = (_drawnOrder.length ~/ 2) * 2;
    return pairStart < _drawnOrder.length ? _drawnOrder[pairStart] : null;
  }

  Team? get _slotB {
    final pairStart = (_drawnOrder.length ~/ 2) * 2;
    return (pairStart + 1) < _drawnOrder.length
        ? _drawnOrder[pairStart + 1]
        : null;
  }

  // ── The actual random draw ──────────────────────────────────────────────

  Future<void> _spin() async {
    if (_isSpinning || _pool.isEmpty) return;

    // The real, genuinely random selection happens FIRST. The wheel
    // animation below only visualizes this already-decided outcome —
    // it can never land on, or report, a different participant.
    final selectedIndex = _random.nextInt(_pool.length);
    final selected = _pool[selectedIndex];

    final segmentCount = _pool.length;
    final segmentAngle = (2 * pi) / segmentCount;
    final targetSegmentMid = selectedIndex * segmentAngle + segmentAngle / 2;

    // Spin a few full rotations, then settle exactly on the selected
    // segment under the fixed top pointer.
    final extraSpins = 4 + _random.nextInt(3); // 4–6 full rotations
    final targetAngle =
        _wheelAngle + (extraSpins * 2 * pi) + (2 * pi - targetSegmentMid);

    _spinAnimation = Tween<double>(begin: _wheelAngle, end: targetAngle)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    setState(() => _isSpinning = true);

    _controller.value = 0;
    await _controller.forward();

    if (!mounted) return;
    setState(() {
      _wheelAngle = targetAngle % (2 * pi);
      _pool.removeAt(selectedIndex);
      _drawnOrder.add(selected);
      _isSpinning = false;
    });
  }

  Future<void> _restartDraw() async {
    if (_drawnOrder.isEmpty) return;

    final confirmed = await _confirmDialog(
      title: 'Restart this draw?',
      message: 'All current temporary pairings will be discarded.',
      confirmLabel: 'Restart',
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _pool = List<Team>.from(widget.teams)..shuffle(_random);
      _drawnOrder.clear();
      _wheelAngle = 0;
      _controller.value = 0;
    });
  }

  void _confirmAndGenerate() {
    if (!_drawComplete) return;
    Navigator.of(context).pop<List<Team>>(List<Team>.from(_drawnOrder));
  }

  Future<bool> _handleBack() async {
    if (_drawnOrder.isEmpty) return true;

    final leave = await _confirmDialog(
      title: 'Leave draw?',
      message: 'Your current draw has not been confirmed. '
          'Leaving will discard the temporary pairings.',
      confirmLabel: 'Leave',
    );
    return leave == true;
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    final brightness = Theme.of(context).brightness;
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Glass(
          borderRadius: 26,
          padding: const EdgeInsets.all(18),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Stay'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return WillPopScope(
      onWillPop: _handleBack,
      child: GlassScaffold(
        appBar: AppBar(
          title: const Text('🎡 Spin Wheel Draw'),
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _handleBack() && mounted) {
                Navigator.of(context).pop<List<Team>>(null);
              }
            },
          ),
        ),
        body: SafeArea(
          child:
              _drawComplete ? _buildReview(brightness) : _buildDraw(brightness),
        ),
      ),
    );
  }

  Widget _buildDraw(Brightness brightness) {
    final remaining = _pool.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Match $_currentMatchNumber',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Glass(
            borderRadius: 20,
            padding: const EdgeInsets.all(14),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Row(
              children: [
                Expanded(child: _slotTile(_slotA?.name, brightness)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(child: _slotTile(_slotB?.name, brightness)),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final angle = _isSpinning ? _spinAnimation.value : _wheelAngle;
                return _buildWheel(angle, brightness);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            remaining == 0
                ? 'All participants drawn'
                : '$remaining participant${remaining == 1 ? '' : 's'} remaining',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              if (_drawnOrder.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSpinning ? null : _restartDraw,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Restart'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: (_isSpinning || _pool.isEmpty) ? null : _spin,
                  icon: const Icon(Icons.casino),
                  label: Text(_isSpinning ? 'Spinning…' : 'SPIN'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slotTile(String? name, Brightness brightness) {
    return Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color:
            name != null ? AppTheme.limeAccent.withOpacity(0.16) : Colors.transparent,
        border: Border.all(
          color: name != null
              ? AppTheme.limeAccentDark
              : AppTheme.cardBorder(brightness),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        name ?? 'Waiting…',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: name != null
              ? AppTheme.primaryText(brightness)
              : AppTheme.secondaryText(brightness),
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildWheel(double angle, Brightness brightness) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final wheelSize = (shortestSide * 0.72).clamp(220.0, 340.0).toDouble();

    return SizedBox(
      width: wheelSize,
      height: wheelSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: angle,
            child: CustomPaint(
              size: Size(wheelSize, wheelSize),
              painter: _WheelPainter(
                labels: _pool.map((t) => t.name).toList(growable: false),
              ),
            ),
          ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.limeAccent,
              border: Border.all(color: AppTheme.darkText, width: 2),
            ),
          ),
          const Positioned(
            top: -6,
            child: Icon(
              Icons.arrow_drop_down,
              size: 44,
              color: AppTheme.limeAccentDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(Brightness brightness) {
    final pairs = <List<Team>>[];
    for (var i = 0; i + 1 < _drawnOrder.length; i += 2) {
      pairs.add([_drawnOrder[i], _drawnOrder[i + 1]]);
    }
    final leftover = _drawnOrder.length.isOdd ? _drawnOrder.last : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '🎡 Draw Complete',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: pairs.length + (leftover != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < pairs.length) {
                final pair = pairs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(14),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Row(
                      children: [
                        Text(
                          'Match ${index + 1}',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            pair[0].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: AppTheme.primaryText(brightness),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'vs',
                            style:
                                TextStyle(color: AppTheme.secondaryText(brightness)),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            pair[1].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.primaryText(brightness),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Odd participant count — the round-robin schedule rotates
              // every team through a bye round automatically. This is
              // informational only; it does not block generation.
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(14),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.secondaryText(brightness), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${leftover!.name} — odd participant count. '
                          'The league schedule rotates each team through a '
                          'bye round automatically.',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'All participants have been assigned.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _restartDraw,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Restart Draw'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.limeAccent,
                        foregroundColor: AppTheme.darkText,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _confirmAndGenerate,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Confirm & Generate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<String> labels;

  _WheelPainter({required this.labels});

  static const List<Color> _segmentColors = [
    Color(0xFF1F2937),
    Color(0xFF111827),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = (2 * pi) / labels.length;

    final fontSize = labels.length <= 6
        ? 13.0
        : labels.length <= 12
            ? 11.0
            : labels.length <= 20
                ? 9.0
                : 7.5;

    for (int i = 0; i < labels.length; i++) {
      final startAngle = i * segmentAngle - (pi / 2) - (segmentAngle / 2);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        Paint()
          ..color = _segmentColors[i % _segmentColors.length]
          ..style = PaintingStyle.fill,
      );

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        Paint()
          ..color = AppTheme.limeAccent.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      final midAngle = startAngle + segmentAngle / 2;
      canvas.save();
      canvas.translate(
        center.dx + cos(midAngle) * radius * 0.62,
        center.dy + sin(midAngle) * radius * 0.62,
      );
      canvas.rotate(midAngle + pi / 2);

      final maxLabelWidth = (radius * 0.62).clamp(28.0, 120.0).toDouble();
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxLabelWidth);

      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }

    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = AppTheme.limeAccentDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return oldDelegate.labels != labels;
  }
}
