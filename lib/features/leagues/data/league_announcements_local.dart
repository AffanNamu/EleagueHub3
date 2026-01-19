import 'dart:convert';

import '../../../core/persistence/prefs_service.dart';
import '../models/league_announcement.dart';

class LeagueAnnouncementsLocal {
  final PreferencesService _prefs;

  LeagueAnnouncementsLocal(this._prefs);

  String _key(String leagueId) => 'league_announcements_$leagueId';

  Future<List<LeagueAnnouncement>> listForLeague(String leagueId) async {
    final raw = _prefs.getString(_key(leagueId));
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final List decoded = jsonDecode(raw);
      return decoded
          .map((e) => LeagueAnnouncement.fromMap(
                (e as Map).cast<String, dynamic>(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addAnnouncement(LeagueAnnouncement ann) async {
    final list = await listForLeague(ann.leagueId);
    list.add(ann);
    final encoded =
        jsonEncode(list.map((a) => a.toMap()).toList());
    await _prefs.setString(_key(ann.leagueId), encoded);
  }
}
