// lib/features/profile/models/formation_detector.dart
import 'squad.dart';

/// Infers a "4-3-3"-style formation label purely from where the starting
/// XI currently sit on the pitch (normalized y coordinates), so dragging
/// players around the pitch automatically updates the displayed formation
/// without the user ever picking a preset.
///
/// Approach: the goalkeeper is excluded, the remaining outfield players are
/// sorted by depth (y), and gaps between consecutive players are used to
/// split them into "lines" (defense / mid / attack, or four lines for
/// shapes like 4-2-3-1). Only clear gaps count as a line break, so players
/// clustered close together don't produce a meaningless formation string.
class FormationDetector {
  const FormationDetector._();

  /// Minimum vertical gap (normalized 0..1) between two players before we
  /// consider them to be in different lines.
  static const double _minLineGap = 0.10;

  static String detect(List<SquadPlayerSlot> startingXI, {required String fallback}) {
    if (startingXI.isEmpty) return fallback;

    SquadPlayerSlot? gk;
    for (final p in startingXI) {
      if (p.position.trim().toUpperCase() == 'GK') {
        gk = p;
        break;
      }
    }
    gk ??= startingXI.reduce((a, b) => a.y <= b.y ? a : b);

    final outfield = startingXI.where((p) => p.playerId != gk!.playerId).toList()
      ..sort((a, b) => a.y.compareTo(b.y));

    if (outfield.length < 3) return fallback;

    final ys = outfield.map((p) => p.y).toList(growable: false);
    final gaps = <double>[];
    for (int i = 0; i < ys.length - 1; i++) {
      gaps.add(ys[i + 1] - ys[i]);
    }
    if (gaps.isEmpty) return fallback;

    final meanGap = gaps.reduce((a, b) => a + b) / gaps.length;
    final threshold = (meanGap * 1.3) > _minLineGap ? meanGap * 1.3 : _minLineGap;

    // Gap indices where the vertical separation is large enough to count
    // as a new line, capped at 3 splits (=> max 4 lines).
    final candidateSplits = <int>[];
    for (int i = 0; i < gaps.length; i++) {
      if (gaps[i] > threshold) candidateSplits.add(i);
    }

    List<int> splits = candidateSplits;
    if (splits.length > 3) {
      final byGapDesc = [...splits]..sort((a, b) => gaps[b].compareTo(gaps[a]));
      splits = byGapDesc.take(3).toList()..sort();
    }

    if (splits.isEmpty) {
      // Players are clumped with no clear line separation — keep whatever
      // formation was already set rather than emit a meaningless label.
      return fallback;
    }

    final lineCounts = <int>[];
    int start = 0;
    for (final splitIndex in splits) {
      lineCounts.add(splitIndex - start + 1);
      start = splitIndex + 1;
    }
    lineCounts.add(outfield.length - start);

    if (lineCounts.any((c) => c <= 0)) return fallback;

    return lineCounts.join('-');
  }
}
