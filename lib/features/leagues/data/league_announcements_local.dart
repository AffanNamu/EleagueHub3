import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../models/league_announcement.dart';

/// Local cache for announcements (per league) stored in SharedPreferences.
/// Also enqueues changes for Firestore sync.
class LeagueAnnouncementsFirebase {
  final PreferencesService _prefs;
  final SyncQueueService _queue = SyncQueueService.instance;
  final Uuid _uuid = const Uuid();

  LeagueAnnouncementsFirebase(this._prefs);

  String _key(String leagueId) => 'league_announcements_$leagueId';

  Future<List<LeagueAnnouncement>> listForLeague(String leagueId) async {
    final raw = _prefs.getString(_key(leagueId));
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final List decoded = jsonDecode(raw);
      return decoded
          .map((e) => LeagueAnnouncement.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addAnnouncement(LeagueAnnouncement ann) async {
    final list = await listForLeague(ann.leagueId);
    list.add(ann);

    final encoded = jsonEncode(list.map((a) => a.toMap()).toList());
    await _prefs.setString(_key(ann.leagueId), encoded);

    // Enqueue for cloud
    final now = DateTime.now().millisecondsSinceEpoch;
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'announcement',
      entityId: ann.id,
      action: 'create',
      lastModified: now,
      payload: ann.toMap(),
    );
  }
}
