import '../../leagues/models/enums.dart';
import '../../leagues/models/league_format.dart';

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
    };
  }

  factory CompetitionTemplate.fromMap(Map<String, dynamic> map) {
    final formatIndex = ((map['format'] as num?) ?? 0).toInt();
    final privacyRaw = (map['privacy'] as String? ?? 'private').trim();

    return CompetitionTemplate(
      id: (map['templateId'] as String? ?? map['id'] as String? ?? '').trim(),
      masterLeagueId: (map['masterLeagueId'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      format: LeagueFormatX.fromInt(formatIndex),
      privacy: privacyRaw == 'public' ? LeaguePrivacy.public : LeaguePrivacy.private,
      maxTeams: ((map['maxTeams'] as num?) ?? 20).toInt(),
      homeAwayEnabled: map['homeAwayEnabled'] == true,
      containsRewards: map['containsRewards'] == true,
      createdAtMs: ((map['createdAtMs'] as num?) ?? 0).toInt(),
      updatedAtMs: ((map['updatedAtMs'] as num?) ?? 0).toInt(),
      createdBy: (map['createdBy'] as String? ?? '').trim(),
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
    );
  }
}
