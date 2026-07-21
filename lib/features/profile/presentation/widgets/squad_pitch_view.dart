import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../models/formation_presets.dart';
import '../../models/squad.dart';
import 'pitch_player_marker.dart';

/// Renders a tactical pitch for [squad], laying starting-XI players onto
/// the formation template slots and listing bench players separately.
///
/// Desktop (width >= 900): large pitch on the left, info panel (manager,
/// captain/vice, formation, bench) on the right.
/// Mobile/tablet: pitch on top, bench + info stacked below, scrollable.
class SquadPitchView extends StatelessWidget {
  const SquadPitchView({
    super.key,
    required this.squad,
    this.onSlotTap,
    this.isEditable = false,
    this.onAddBenchPlayer,
    this.onEditBenchPlayer,
    this.onSetCaptain,
    this.onSetViceCaptain,
  });

  final Squad squad;
  final void Function(int slotIndex)? onSlotTap;
  final bool isEditable;
  final VoidCallback? onAddBenchPlayer;
  final void Function(SquadPlayerSlot)? onEditBenchPlayer;
  final void Function(String playerId)? onSetCaptain;
  final void Function(String playerId)? onSetViceCaptain;

  static const double _desktopBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        final infoPanel = _InfoPanel(
          squad: squad,
          isEditable: isEditable,
          onAddBenchPlayer: onAddBenchPlayer,
          onEditBenchPlayer: onEditBenchPlayer,
          onSetCaptain: onSetCaptain,
          onSetViceCaptain: onSetViceCaptain,
        );

        if (isDesktop) {
          return _DesktopLayout(
            squad: squad,
            onSlotTap: isEditable ? onSlotTap : null,
            infoPanel: infoPanel,
          );
        }
        return _MobileLayout(
          squad: squad,
          onSlotTap: isEditable ? onSlotTap : null,
          infoPanel: infoPanel,
        );
      },
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.squad,
    required this.infoPanel,
    this.onSlotTap,
  });
  
  final Squad squad;
  final Widget infoPanel;
  final void Function(int)? onSlotTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _Pitch(
                squad: squad,
                onSlotTap: onSlotTap,
                markerSize: 56,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 2,
            child: infoPanel,
          ),
        ],
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.squad,
    required this.infoPanel,
    this.onSlotTap,
  });

  final Squad squad;
  final Widget infoPanel;
  final void Function(int)? onSlotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 0.62,
          child: _Pitch(
            squad: squad,
            onSlotTap: onSlotTap,
            markerSize: 40,
            dense: true,
          ),
        ),
        const SizedBox(height: 16),
        infoPanel,
      ],
    );
  }
}

/// The green pitch surface with markings + player markers laid out
/// according to the squad's formation.
class _Pitch extends StatelessWidget {
  const _Pitch({
    required this.squad,
    required this.markerSize,
    this.onSlotTap,
    this.dense = false,
  });

  final Squad squad;
  final double markerSize;
  final void Function(int)? onSlotTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final slots = FormationPresets.slotsFor(squad.formation);
    final starting = squad.startingXI;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Pitch background: vertical stripes + markings.
          CustomPaint(painter: _PitchPainter()),

          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              return Stack(
                children: List.generate(slots.length, (i) {
                  final slot = slots[i];
                  final player = i < starting.length ? starting[i] : null;

                  final isCaptain = player != null &&
                      player.playerId == squad.captainPlayerId &&
                      squad.captainPlayerId.isNotEmpty;
                  final isVice = player != null &&
                      player.playerId == squad.viceCaptainPlayerId &&
                      squad.viceCaptainPlayerId.isNotEmpty;

                  // y=0 is defensive (near bottom of screen, own goal),
                  // y=1 is attacking (top). Flip so GK sits at the bottom.
                  final left = (slot.x * w) - (markerSize / 2);
                  final top = ((1 - slot.y) * h) - (markerSize / 2);

                  return Positioned(
                    left: left.clamp(0, w - markerSize),
                    top: top.clamp(0, h - markerSize),
                    width: dense ? markerSize + 30 : markerSize + 24,
                    child: PitchPlayerMarker(
                      slotLabel: slot.label,
                      player: player,
                      isCaptain: isCaptain,
                      isViceCaptain: isVice,
                      size: markerSize,
                      dense: dense,
                      onTap: onSlotTap == null ? null : () => onSlotTap!(i),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFF1E7A34);
    canvas.drawRect(Offset.zero & size, base);

    // Alternating stripes.
    final stripe = Paint()..color = const Color(0xFF22873A);
    const stripeCount = 8;
    final stripeHeight = size.height / stripeCount;
    for (int i = 0; i < stripeCount; i++) {
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(0, stripeHeight * i, size.width, stripeHeight),
          stripe,
        );
      }
    }

    final line = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Outer boundary
    canvas.drawRect(
      Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
      line,
    );

    // Halfway line
    canvas.drawLine(
      Offset(8, size.height / 2),
      Offset(size.width - 8, size.height / 2),
      line,
    );

    // Center circle
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.14,
      line,
    );

    // Own-goal box (bottom, where GK sits)
    final boxW = size.width * 0.5;
    canvas.drawRect(
      Rect.fromLTWH(
        (size.width - boxW) / 2,
        size.height - 8 - size.height * 0.14,
        boxW,
        size.height * 0.14,
      ),
      line,
    );

    // Attacking box (top)
    canvas.drawRect(
      Rect.fromLTWH(
        (size.width - boxW) / 2,
        8,
        boxW,
        size.height * 0.14,
      ),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Manager, captain/vice, formation, team strength, and bench list.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.squad,
    this.isEditable = false,
    this.onAddBenchPlayer,
    this.onEditBenchPlayer,
    this.onSetCaptain,
    this.onSetViceCaptain,
  });

  final Squad squad;
  final bool isEditable;
  final VoidCallback? onAddBenchPlayer;
  final void Function(SquadPlayerSlot)? onEditBenchPlayer;
  final void Function(String playerId)? onSetCaptain;
  final void Function(String playerId)? onSetViceCaptain;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bench = squad.bench;

    final captain = squad.players
        .where((p) => p.playerId == squad.captainPlayerId)
        .cast<SquadPlayerSlot?>()
        .firstWhere((_) => true, orElse: () => null);
    final vice = squad.players
        .where((p) => p.playerId == squad.viceCaptainPlayerId)
        .cast<SquadPlayerSlot?>()
        .firstWhere((_) => true, orElse: () => null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(context, 'Formation', squad.formation),
              _row(context, 'Manager', squad.managerName.isEmpty ? '—' : squad.managerName),
              _row(context, 'Team Strength', '${squad.teamStrength}'),
              _row(context, 'Captain', captain?.name ?? '—'),
              _row(context, 'Vice Captain', vice?.name ?? '—'),
              if (isEditable)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tap a player below to set captain / vice captain.',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Bench (${bench.length})',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (isEditable)
              TextButton.icon(
                onPressed: onAddBenchPlayer,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add sub'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (bench.isEmpty)
          Text(
            'No substitutes added yet.',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          )
        else
          Glass(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(vertical: 4),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Column(
              children: bench.map((p) {
                final isCap = p.playerId == squad.captainPlayerId;
                final isVice = p.playerId == squad.viceCaptainPlayerId;

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.iconCircleBackground(brightness),
                    child: Text(
                      p.shirtNumber > 0 ? '${p.shirtNumber}' : '-',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                  ),
                  title: Text(
                    p.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  trailing: isCap
                      ? const Icon(Icons.stars_rounded, size: 16, color: Color(0xFFFFB300))
                      : isVice
                          ? const Icon(Icons.star_border_rounded, size: 16, color: Color(0xFF94A3B8))
                          : Text(
                              p.position,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: AppTheme.secondaryText(brightness),
                              ),
                            ),
                  onTap: isEditable ? () => onEditBenchPlayer?.call(p) : null,
                  onLongPress: isEditable
                      ? () => _showCaptaincyMenu(context, p.playerId)
                      : null,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  void _showCaptaincyMenu(BuildContext context, String playerId) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.stars_rounded),
              title: const Text('Make Captain'),
              onTap: () {
                Navigator.of(ctx).pop();
                onSetCaptain?.call(playerId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_border_rounded),
              title: const Text('Make Vice Captain'),
              onTap: () {
                Navigator.of(ctx).pop();
                onSetViceCaptain?.call(playerId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
