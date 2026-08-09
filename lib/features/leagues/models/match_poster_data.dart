// lib/features/leagues/models/match_poster_data.dart
//
// Data model for the Match Poster / Match Card generator.
//
// This file intentionally has NO Flutter dependency (pure Dart) so it can
// be unit tested and reused by both the poster widget (UI) and the export
// service without dragging in `dart:ui`.
//
// IMPORTANT — data honesty:
// FixtureMatch (lib/features/leagues/models/fixture_match.dart) does not
// currently store a scheduled date/time, venue, or platform field. Rather
// than fabricate one, [dateTimeLabel] / [venueLabel] are nullable and are
// only populated if the organizer explicitly types something into the
// preview screen before exporting (see MatchPosterPreviewScreen). If left
// blank, the poster simply omits that row — it never shows a fake date.

import 'fixture_match.dart';
import 'team.dart';

/// Supported export formats. Sizes chosen to match common social platform
/// recommendations (portrait feed post, square post, vertical story/status).
enum MatchPosterFormat { portrait, square, story }

extension MatchPosterFormatX on MatchPosterFormat {
  int get exportWidth {
    switch (this) {
      case MatchPosterFormat.portrait:
        return 1080;
      case MatchPosterFormat.square:
        return 1080;
      case MatchPosterFormat.story:
        return 1080;
    }
  }

  int get exportHeight {
    switch (this) {
      case MatchPosterFormat.portrait:
        return 1350;
      case MatchPosterFormat.square:
        return 1080;
      case MatchPosterFormat.story:
        return 1920;
    }
  }

  double get aspectRatio => exportWidth / exportHeight;

  String get label {
    switch (this) {
      case MatchPosterFormat.portrait:
        return 'Portrait';
      case MatchPosterFormat.square:
        return 'Square';
      case MatchPosterFormat.story:
        return 'Story';
    }
  }
}

class MatchPosterTeamData {
  const MatchPosterTeamData({
    required this.name,
    required this.imageUrl,
  });

  final String name;
  final String imageUrl;

  bool get hasImage => imageUrl.trim().isNotEmpty;
}

class MatchPosterData {
  const MatchPosterData({
    required this.competitionName,
    required this.home,
    required this.away,
    this.competitionLogoUrl = '',
    this.season,
    this.footballCategory,
    this.roundLabel,
    this.dateTimeLabel,
    this.venueLabel,
  });

  final String competitionName;
  final String competitionLogoUrl;
  final String? season;
  final String? footballCategory;

  final MatchPosterTeamData home;
  final MatchPosterTeamData away;

  /// e.g. "Round 3" or "Group A • Round 3". Built from FixtureMatch's real
  /// roundNumber/groupId fields — never invented.
  final String? roundLabel;

  /// Organizer-entered, optional. Null/empty means "not shown".
  final String? dateTimeLabel;

  /// Organizer-entered, optional. Null/empty means "not shown".
  final String? venueLabel;

  bool get hasCompetitionLogo => competitionLogoUrl.trim().isNotEmpty;

  List<String> get remoteImageUrls => [
        if (home.hasImage) home.imageUrl,
        if (away.hasImage) away.imageUrl,
        if (hasCompetitionLogo) competitionLogoUrl,
      ];

  MatchPosterData copyWith({
    String? dateTimeLabel,
    String? venueLabel,
  }) {
    return MatchPosterData(
      competitionName: competitionName,
      competitionLogoUrl: competitionLogoUrl,
      season: season,
      footballCategory: footballCategory,
      home: home,
      away: away,
      roundLabel: roundLabel,
      dateTimeLabel: dateTimeLabel ?? this.dateTimeLabel,
      venueLabel: venueLabel ?? this.venueLabel,
    );
  }
}

/// Builds [MatchPosterData] from real application data only:
/// - Team names/images come from the already-loaded Team objects
///   (match_detail_screen.dart already resolves these).
/// - Competition name/logo/season/footballCategory are read directly from
///   the existing `leagues/{leagueId}` Firestore document (same fields
///   League.fromRemoteMap already knows about) — no new collection, no
///   new document, no schema change.
class MatchPosterDataBuilder {
  const MatchPosterDataBuilder._();

  static Future<MatchPosterData> fromMatch({
    required String leagueId,
    required FixtureMatch match,
    required Map<String, Team> teamsById,
    required Future<Map<String, dynamic>?> Function(String leagueId)
        fetchLeagueFields,
    String? manualDateTimeLabel,
    String? manualVenueLabel,
  }) async {
    String competitionName = 'League';
    String competitionLogoUrl = '';
    String? season;
    String? footballCategory;

    try {
      final data = await fetchLeagueFields(leagueId);
      if (data != null) {
        final name = (data['name'] as String? ?? '').trim();
        if (name.isNotEmpty) competitionName = name;

        competitionLogoUrl = (data['leagueImageUrl'] as String? ?? '').trim();

        final seasonRaw = (data['season'] as String? ?? '').trim();
        if (seasonRaw.isNotEmpty) season = seasonRaw;

        final categoryRaw = (data['footballCategory'] as String? ?? '').trim();
        if (categoryRaw.isNotEmpty) footballCategory = categoryRaw;
      }
    } catch (_) {
      // Network hiccup or missing doc — fall back to sane defaults rather
      // than failing poster generation entirely (Section 19: never crash).
    }

    final homeTeam = teamsById[match.homeTeamId];
    final awayTeam = teamsById[match.awayTeamId];

    String? roundLabel;
    if (match.roundNumber > 0) {
      roundLabel = 'Round ${match.roundNumber}';
    }
    final groupId = (match.groupId ?? '').trim();
    if (groupId.isNotEmpty) {
      roundLabel = roundLabel == null ? 'Group $groupId' : 'Group $groupId • $roundLabel';
    }

    final homeName = (homeTeam?.name.trim().isNotEmpty ?? false)
        ? homeTeam!.name.trim()
        : 'TBD';
    final awayName = (awayTeam?.name.trim().isNotEmpty ?? false)
        ? awayTeam!.name.trim()
        : 'TBD';

    return MatchPosterData(
      competitionName: competitionName,
      competitionLogoUrl: competitionLogoUrl,
      season: season,
      footballCategory: footballCategory,
      home: MatchPosterTeamData(
        name: homeName,
        imageUrl: (homeTeam?.teamImageUrl ?? '').trim(),
      ),
      away: MatchPosterTeamData(
        name: awayName,
        imageUrl: (awayTeam?.teamImageUrl ?? '').trim(),
      ),
      roundLabel: roundLabel,
      dateTimeLabel: (manualDateTimeLabel ?? '').trim().isEmpty
          ? null
          : manualDateTimeLabel!.trim(),
      venueLabel: (manualVenueLabel ?? '').trim().isEmpty
          ? null
          : manualVenueLabel!.trim(),
    );
  }
}
