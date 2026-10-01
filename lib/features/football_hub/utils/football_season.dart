// lib/features/football_hub/utils/football_season.dart

/// Best-effort guess at the "current" European football season year, for
/// screens that don't already have a real season value passed to them
/// (e.g. jumping straight into a team/player profile without having
/// fetched the competition's own season first). European club seasons
/// typically start in the summer, so before ~July the "current" season
/// is still the one that started the previous calendar year.
int currentFootballSeasonGuess() {
  final now = DateTime.now();
  return now.month >= 7 ? now.year : now.year - 1;
}
