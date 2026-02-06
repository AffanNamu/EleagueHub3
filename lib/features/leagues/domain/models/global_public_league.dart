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
  /// If true, the league must not appear in global discovery.
  final bool isFullStored;

  const GlobalPublicLeague({
    required this.league,
    required this.registeredCount,
    required this.isFullStored,
  });

  bool get isPublic => !league.isPrivate;

  /// Global visibility rule:
  /// - if isFullStored is true => hide
  /// - else if registeredCount is available and >= maxTeams => hide
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
