#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys
import re

TARGET = Path("lib/features/leagues/presentation/fixtures_screen.dart")

# We replace the entire _shareFixturesMessage(...) function, regardless of current comment text.
PATTERN = re.compile(
    r"""
    String\s+_shareFixturesMessage\s*\(\s*List<FixtureMatch>\s+matches\s*\)\s*\{
    .*?
    \n\s*\}\n
    """,
    re.DOTALL | re.VERBOSE,
)

REPLACEMENT = r"""
  /// Share message format (standard):
  /// One fixture per line, showing:
  /// - Round number
  /// - Group label (if present)
  /// - Score (if present) else "vs"
  ///
  /// Examples:
  ///   R2 • Group A: Barcelona 2 - 1 Madrid
  ///   R1: Barcelona vs Madrid
  String _shareFixturesMessage(List<FixtureMatch> matches) {
    final l10n = context.l10n;

    final sorted = [...matches];
    sorted.sort((a, b) {
      final r = a.roundNumber.compareTo(b.roundNumber);
      if (r != 0) return r;
      final si = a.sortIndex.compareTo(b.sortIndex);
      if (si != 0) return si;
      return a.id.compareTo(b.id);
    });

    final lines = <String>[];
    for (final m in sorted) {
      final homeName = (_teamNames[m.homeTeamId] ?? l10n.tr('fixtures_tbd')).trim();
      final awayName = (_teamNames[m.awayTeamId] ?? l10n.tr('fixtures_tbd')).trim();

      final groupRaw = (m.groupId ?? '').trim();
      final groupPart = groupRaw.isEmpty ? '' : ' • ${_groupDisplayName(l10n, groupRaw)}';

      final hasScore = m.homeScore != null && m.awayScore != null;
      final scoreOrVs = hasScore ? '${m.homeScore} - ${m.awayScore}' : 'vs';

      // Standard single-line format per fixture
      lines.add('R${m.roundNumber}$groupPart: $homeName $scoreOrVs $awayName'.trim());
    }

    return lines.join('\n');
  }

"""

def main() -> int:
  if not TARGET.exists():
    print(f"[ERROR] Target file not found: {TARGET}", file=sys.stderr)
    return 2

  s = TARGET.read_text(encoding="utf-8")

  m = PATTERN.search(s)
  if not m:
    print("[ERROR] Could not find _shareFixturesMessage(List<FixtureMatch> matches) function.", file=sys.stderr)
    print("Open fixtures_screen.dart and search for '_shareFixturesMessage'.", file=sys.stderr)
    return 3

  s2 = s[:m.start()] + REPLACEMENT + s[m.end():]
  TARGET.write_text(s2, encoding="utf-8")
  print("[OK] Updated fixture share message format (round + group + score).")
  return 0

if __name__ == "__main__":
  raise SystemExit(main())
