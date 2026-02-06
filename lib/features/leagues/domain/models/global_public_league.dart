import 'dart:math' as math;

import '../../models/league.dart';

/// View-model for the Global discovery list.
/// Keeps League model untouched while adding global-only computed fields.
class GlobalPublicLeague {
  final League league;

  /// Optional denormalized count stored on the league doc.
  /// Recommended for scale (millions of users).
  final int? registeredCount;

  /// Optional stored boolean on the league doc.
  /// If true, it indicates the league has reached participant capacity.
  ///
  /// NOTE: With your updated product requirement, we DO NOT hide full leagues.
  /// We keep it for UI and join enforcement.
  final bool isFullStored;

  /// Optional finished flag; if true, global list will hide it (finished leagues).
  final bool isFinishedStored;

  const GlobalPublicLeague({
    required this.league,
    required this.registeredCount,
    required this.isFullStored,
    required this.isFinishedStored,
  });

  bool get isPublic => !league.isPrivate;

  bool get isFinished => isFinishedStored;

  /// Participant-fullness:
  /// - if isFullStored is true => full
  /// - else if registeredCount is available and >= maxTeams => full
  bool get isFullComputed {
    if (isFullStored) return true;
    final c = registeredCount;
    if (c == null) return false;
    return c >= league.maxTeams;
  }

  int? get spotsLeft {
    final c = registeredCount;
    if (c == null) return null;
    return math.max(0, league.maxTeams - c);
  }
}
