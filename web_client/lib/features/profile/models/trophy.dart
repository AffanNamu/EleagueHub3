import 'package:cloud_firestore/cloud_firestore.dart';

class Trophy {
  const Trophy({
    required this.id,
    required this.leagueId,
    required this.leagueName,
    required this.position, // 1 = winner, 2 = runner-up, etc.
    required this.season,
    required this.createdAtMs,
  });

  final String id;
  final String leagueId;
  final String leagueName;
  final int position;
  final String season;
  final int createdAtMs;

  factory Trophy.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Trophy(
      id: doc.id,
      leagueId: (map['leagueId'] as String? ?? '').trim(),
      leagueName: (map['leagueName'] as String? ?? '').trim(),
      position: _asInt(map['position']),
      season: (map['season'] as String? ?? '').trim(),
      createdAtMs: _asInt(map['createdAtMs']),
    );
  }

  Map<String, dynamic> toMap() => {
        'leagueId': leagueId,
        'leagueName': leagueName,
        'position': position,
        'season': season,
        'createdAtMs': createdAtMs,
      };

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
