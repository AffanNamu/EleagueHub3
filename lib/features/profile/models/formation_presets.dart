// lib/features/profile/models/formation_presets.dart
/// Normalized (0.0–1.0) pitch positions for each supported formation.
/// x=0 is left touchline, x=1 is right touchline.
/// y=0 is defensive third (near own goal), y=1 is attacking third.
///
/// Each entry is a template slot: {position label, x, y}. When a squad
/// has no player assigned to a slot yet, the slot renders empty so the
/// pitch shape is always recognizable even for a half-built squad.
class FormationSlot {
  const FormationSlot({required this.label, required this.x, required this.y});
  final String label;
  final double x;
  final double y;
}

class FormationPresets {
  const FormationPresets._();

  static const Map<String, List<FormationSlot>> all = {
    '4-3-3': [
      FormationSlot(label: 'GK', x: 0.50, y: 0.06),
      FormationSlot(label: 'LB', x: 0.14, y: 0.24),
      FormationSlot(label: 'CB', x: 0.36, y: 0.20),
      FormationSlot(label: 'CB', x: 0.64, y: 0.20),
      FormationSlot(label: 'RB', x: 0.86, y: 0.24),
      FormationSlot(label: 'CM', x: 0.30, y: 0.46),
      FormationSlot(label: 'CM', x: 0.50, y: 0.42),
      FormationSlot(label: 'CM', x: 0.70, y: 0.46),
      FormationSlot(label: 'LW', x: 0.16, y: 0.78),
      FormationSlot(label: 'ST', x: 0.50, y: 0.86),
      FormationSlot(label: 'RW', x: 0.84, y: 0.78),
    ],
    '4-2-3-1': [
      FormationSlot(label: 'GK', x: 0.50, y: 0.06),
      FormationSlot(label: 'LB', x: 0.14, y: 0.24),
      FormationSlot(label: 'CB', x: 0.36, y: 0.20),
      FormationSlot(label: 'CB', x: 0.64, y: 0.20),
      FormationSlot(label: 'RB', x: 0.86, y: 0.24),
      FormationSlot(label: 'CDM', x: 0.36, y: 0.42),
      FormationSlot(label: 'CDM', x: 0.64, y: 0.42),
      FormationSlot(label: 'LAM', x: 0.18, y: 0.66),
      FormationSlot(label: 'CAM', x: 0.50, y: 0.62),
      FormationSlot(label: 'RAM', x: 0.82, y: 0.66),
      FormationSlot(label: 'ST', x: 0.50, y: 0.88),
    ],
    '4-4-2': [
      FormationSlot(label: 'GK', x: 0.50, y: 0.06),
      FormationSlot(label: 'LB', x: 0.14, y: 0.24),
      FormationSlot(label: 'CB', x: 0.36, y: 0.20),
      FormationSlot(label: 'CB', x: 0.64, y: 0.20),
      FormationSlot(label: 'RB', x: 0.86, y: 0.24),
      FormationSlot(label: 'LM', x: 0.14, y: 0.50),
      FormationSlot(label: 'CM', x: 0.38, y: 0.48),
      FormationSlot(label: 'CM', x: 0.62, y: 0.48),
      FormationSlot(label: 'RM', x: 0.86, y: 0.50),
      FormationSlot(label: 'ST', x: 0.38, y: 0.84),
      FormationSlot(label: 'ST', x: 0.62, y: 0.84),
    ],
    '3-5-2': [
      FormationSlot(label: 'GK', x: 0.50, y: 0.06),
      FormationSlot(label: 'CB', x: 0.26, y: 0.20),
      FormationSlot(label: 'CB', x: 0.50, y: 0.16),
      FormationSlot(label: 'CB', x: 0.74, y: 0.20),
      FormationSlot(label: 'LWB', x: 0.08, y: 0.46),
      FormationSlot(label: 'CM', x: 0.34, y: 0.44),
      FormationSlot(label: 'CM', x: 0.50, y: 0.40),
      FormationSlot(label: 'CM', x: 0.66, y: 0.44),
      FormationSlot(label: 'RWB', x: 0.92, y: 0.46),
      FormationSlot(label: 'ST', x: 0.38, y: 0.84),
      FormationSlot(label: 'ST', x: 0.62, y: 0.84),
    ],
  };

  static const List<String> supported = ['4-3-3', '4-2-3-1', '4-4-2', '3-5-2'];

  static List<FormationSlot> slotsFor(String formation) {
    return all[formation.trim()] ?? all['4-3-3']!;
  }
}
