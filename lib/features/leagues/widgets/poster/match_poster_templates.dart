// lib/features/leagues/widgets/poster/match_poster_templates.dart
//
// The template registry. Five genuinely distinct templates (per Section 2
// of the brief: "I would rather have 5 excellent templates than 20 poor
// ones"), in the order shown to the organizer. Classic is first/default --
// it's the recognizable eSportlyic house style.

import 'match_poster_template.dart';
import 'templates/battle_arena_template.dart';
import 'templates/championship_template.dart';
import 'templates/classic_template.dart';
import 'templates/dark_pro_template.dart';
import 'templates/neon_clash_template.dart';

const List<MatchPosterTemplate> matchPosterTemplates = <MatchPosterTemplate>[
  ClassicTemplate(),
  BattleArenaTemplate(),
  NeonClashTemplate(),
  ChampionshipTemplate(),
  DarkProTemplate(),
];

MatchPosterTemplate matchPosterTemplateById(String id) {
  return matchPosterTemplates.firstWhere(
    (t) => t.id == id,
    orElse: () => matchPosterTemplates.first,
  );
}
