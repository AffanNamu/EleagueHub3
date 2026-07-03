// lib/features/master_leagues/domain/competition_template.dart
//
// MODIFIED: Added optional `worldCupFormat` field for World Cup templates.
// Fully backward-compatible — old Firestore documents without this field
// will deserialize with worldCupFormat = null (safe default).

import '../../leagues/models/enums.dart';
import '../../leagues/models/league_format.dart';
import '../../leagues/models/league_settings.dart';

class CompetitionTemplate {
  final String id;
  final String masterLeagueId;
  final String name;
  final String description;
  final LeagueFormat format;
  final LeaguePrivacy privacy;
  final int maxTeams;
  final bool homeAwayEnabled;
  final bool containsRewards;
  final int createdAtMs;
  final int updatedAtMs;
  final String createdBy;

  /// World Cup sub-format (FIFA 2022 or FIFA 2026).
  /// Null for all non-World Cup templates.
  /// Backward-compatible: old docs without this field deserialize as null.
  final WorldCupFormat? worldCupFormat;

  const CompetitionTemplate({
    required this.id,
    required this.masterLeagueId,
    required this.name,
    required this.description,
    required this.format,
    required this.privacy,
    required this.maxTeams,
    required this.homeAwayEnabled,
    required this.containsRewards,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.createdBy,
    this.worldCupFormat,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'templateId': id.trim(),
      'masterLeagueId': masterLeagueId.trim(),
      'name': name.trim(),
      'description': description.trim(),
      'format': format.index,
      'privacy': privacy.name,
      'maxTeams': maxTeams,
      'homeAwayEnabled': homeAwayEnabled,
      'containsRewards': containsRewards,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'createdBy': createdBy.trim(),
      // Only write worldCupFormat when format is worldCup and sub-format is set.
      // For all other formats this key is omitted from Firestore entirely.
      if (format == LeagueFormat.worldCup && worldCupFormat != null)
        'worldCupFormat': worldCupFormat!.firestoreKey,
    };
  }

  factory CompetitionTemplate.fromMap(Map<String, dynamic> map) {
    final formatIndex = ((map['format'] as num?) ?? 0).toInt();
    final privacyRaw = (map['privacy'] as String? ?? 'private').trim();
    final parsedFormat = LeagueFormatX.fromInt(formatIndex);

    // Safe deserialization of worldCupFormat.
    // Returns null for all non-World Cup templates and for any template
    // created before this field was introduced (backward-compatible).
    final wcFormatRaw = map['worldCupFormat'] as String?;
    final parsedWcFormat =
        parsedFormat == LeagueFormat.worldCup && wcFormatRaw != null
            ? WorldCupFormatX.fromString(wcFormatRaw)
            : null;

    return CompetitionTemplate(
      id: (map['templateId'] as String? ?? map['id'] as String? ?? '').trim(),
      masterLeagueId: (map['masterLeagueId'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      format: parsedFormat,
      privacy: privacyRaw == 'public' ? LeaguePrivacy.public : LeaguePrivacy.private,
      maxTeams: ((map['maxTeams'] as num?) ?? 20).toInt(),
      homeAwayEnabled: map['homeAwayEnabled'] == true,
      containsRewards: map['containsRewards'] == true,
      createdAtMs: ((map['createdAtMs'] as num?) ?? 0).toInt(),
      updatedAtMs: ((map['updatedAtMs'] as num?) ?? 0).toInt(),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
      worldCupFormat: parsedWcFormat,
    );
  }

  CompetitionTemplate copyWith({
    String? id,
    String? masterLeagueId,
    String? name,
    String? description,
    LeagueFormat? format,
    LeaguePrivacy? privacy,
    int? maxTeams,
    bool? homeAwayEnabled,
    bool? containsRewards,
    int? createdAtMs,
    int? updatedAtMs,
    String? createdBy,
    WorldCupFormat? worldCupFormat,
    bool clearWorldCupFormat = false,
  }) {
    return CompetitionTemplate(
      id: id ?? this.id,
      masterLeagueId: masterLeagueId ?? this.masterLeagueId,
      name: name ?? this.name,
      description: description ?? this.description,
      format: format ?? this.format,
      privacy: privacy ?? this.privacy,
      maxTeams: maxTeams ?? this.maxTeams,
      homeAwayEnabled: homeAwayEnabled ?? this.homeAwayEnabled,
      containsRewards: containsRewards ?? this.containsRewards,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      createdBy: createdBy ?? this.createdBy,
      worldCupFormat: clearWorldCupFormat
          ? null
          : (worldCupFormat ?? this.worldCupFormat),
    );
  }
}