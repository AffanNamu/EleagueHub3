// lib/features/football_hub/models/football_match_event.dart

/// A single timeline event from API-Football's /fixtures/events endpoint
/// (goal, card, substitution, VAR).
class FootballMatchEvent {
  final int minute;
  final int? extraMinute;
  final String type; // "Goal", "Card", "subst", "Var"
  final String detail; // e.g. "Normal Goal", "Yellow Card", "Red Card"
  final String teamName;
  final String teamLogoUrl;
  final String playerName;
  final String? assistName;
  final String comments;

  const FootballMatchEvent({
    required this.minute,
    required this.extraMinute,
    required this.type,
    required this.detail,
    required this.teamName,
    required this.teamLogoUrl,
    required this.playerName,
    required this.assistName,
    required this.comments,
  });

  bool get isGoal => type.toLowerCase() == 'goal';
  bool get isCard => type.toLowerCase() == 'card';
  bool get isSubstitution => type.toLowerCase() == 'subst';
  bool get isRedCard => isCard && detail.toLowerCase().contains('red');

  factory FootballMatchEvent.fromJson(Map<String, dynamic> json) {
    final time = (json['time'] as Map?)?.cast<String, dynamic>() ?? const {};
    final team = (json['team'] as Map?)?.cast<String, dynamic>() ?? const {};
    final player = (json['player'] as Map?)?.cast<String, dynamic>() ?? const {};
    final assist = (json['assist'] as Map?)?.cast<String, dynamic>() ?? const {};

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    int? toIntOrNull(dynamic v) =>
        v == null ? null : (v is int ? v : (v is num ? v.toInt() : int.tryParse('$v')));
    String toStr(dynamic v) => (v ?? '').toString();

    return FootballMatchEvent(
      minute: toInt(time['elapsed']),
      extraMinute: toIntOrNull(time['extra']),
      type: toStr(json['type']),
      detail: toStr(json['detail']),
      teamName: toStr(team['name']),
      teamLogoUrl: toStr(team['logo']),
      playerName: toStr(player['name']),
      assistName: toStr(assist['name']).isNotEmpty ? toStr(assist['name']) : null,
      comments: toStr(json['comments']),
    );
  }
}
