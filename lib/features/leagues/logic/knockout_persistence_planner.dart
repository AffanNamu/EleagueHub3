// lib/features/leagues/logic/knockout_persistence_planner.dart
//
// PHASE C: pure decision logic for LocalLeaguesRepository.saveKnockoutMatches,
// kept free of Firestore so it's unit-testable in isolation. Previously,
// saveKnockoutMatches deleted every existing knockout document before
// writing the full passed-in list back -- harmless by accident only
// because callers always reused the same ids, but it meant every score
// submission (which round-trips the WHOLE bracket, finished matches
// included, through this same method) briefly deleted already-finished
// matches before recreating them. That both violated "never destroy
// history" on its own (a mid-operation failure could leave them gone)
// and, after firestore.rules' knockoutMatchWriteRespectsHistory started
// blocking deletes of finished matches, would have broken the
// advancement flow outright.
//
// The fix: never delete a document that's still part of the bracket
// (upsert it instead, via merge, exactly like saveMatches already does
// for round-robin matches) -- only prune documents that genuinely have
// no counterpart in the new list, and even then, never one that's
// already finished.

import '../models/knockout_match.dart';

class KnockoutPersistencePlanner {
  const KnockoutPersistencePlanner._();

  /// Document ids present in [existing] but absent from [matches] --
  /// these have no place in the bracket being saved and may be deleted,
  /// unless they're already finished (matches firestore.rules'
  /// knockoutMatchWriteRespectsHistory, which refuses that delete
  /// server-side too -- this check just avoids attempting a write that
  /// would be rejected).
  static List<String> idsToPrune({
    required List<KnockoutMatch> existing,
    required List<KnockoutMatch> matches,
  }) {
    final keepIds = matches
        .map((m) => m.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    return existing
        .where((m) => !keepIds.contains(m.id.trim()))
        .where((m) => !m.isFinished)
        .map((m) => m.id)
        .toList(growable: false);
  }
}
