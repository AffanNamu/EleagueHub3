import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../auth/data/user_profile_repository.dart';
import '../../data/leagues_repository_local.dart';
import '../../models/league.dart';
import '../../models/league_format.dart';
import '../../models/membership.dart';

class RosterCsvExporter {
  /// Builds a roster CSV (importable later in Add Teams) and shares it via the platform share sheet.
  ///
  /// Output columns:
  /// - userIdOrShareId  (we export Firebase uid to ensure offline re-import works)
  /// - teamName         (from local Team.name; for orphan members tries to fetch profile name best-effort)
  /// - group            (only meaningful for UCL Group)
  static Future<void> shareRosterCsv({
    required LocalLeaguesRepository repo,
    required League league,
  }) async {
    final xfile = await _buildRosterCsvXFile(repo: repo, league: league);
    await Share.shareXFiles(
      [xfile],
      text: 'Roster CSV (importable) • ${league.name}',
    );
  }

  static Future<XFile> _buildRosterCsvXFile({
    required LocalLeaguesRepository repo,
    required League league,
  }) async {
    final teams = await repo.getTeams(league.id);
    final memberships = await repo.listMemberships();

    // Orphan participants (joined but not assigned to a team yet).
    final orphanUserIds = memberships
        .where((m) =>
            m.leagueId == league.id &&
            m.role == LeagueRole.member &&
            (m.teamId == null || m.teamId!.trim().isEmpty))
        .map((m) => m.userId)
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    // Avoid duplicates: if a user is already a team, don't list them as orphan.
    for (final t in teams) {
      orphanUserIds.remove(t.id);
    }

    // Best-effort: fetch profile team names for orphans (so CSV can still import nicely offline).
    final profiles = UserProfileRepository();
    final Map<String, String> orphanNameByUid = {};
    for (final uid in orphanUserIds) {
      try {
        final p = await profiles.fetchByUserId(uid);
        final name = p?.teamName.trim() ?? '';
        if (name.isNotEmpty) orphanNameByUid[uid] = name;
      } catch (_) {
        // Offline/permission/transient: ignore; teamName will be empty in CSV.
      }
    }

    final isGroupLeague = league.format == LeagueFormat.uclGroup;

    final buffer = StringBuffer();
    buffer.writeln('userIdOrShareId,teamName,group');

    // Teams first (these are the "official" roster rows).
    for (final t in teams) {
      final group = isGroupLeague ? (t.groupId ?? '') : '';
      buffer.writeln(_csvRow([t.id, t.name, group]));
    }

    // Then orphan members (useful so organizer can re-import everyone).
    for (final uid in orphanUserIds) {
      final name = orphanNameByUid[uid] ?? '';
      buffer.writeln(_csvRow([uid, name, '']));
    }

    final csv = buffer.toString();

    final dir = await getTemporaryDirectory();
    final safeLeagueName = league.name
        .trim()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final shortId = league.id.length >= 8 ? league.id.substring(0, 8) : league.id;
    final fileName = 'roster_${safeLeagueName}_$shortId.csv';

    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);
    await file.writeAsString(csv, flush: true);

    return XFile(file.path, name: fileName, mimeType: 'text/csv');
  }

  static String _csvRow(List<String> fields) => fields.map(_csvEscape).join(',');

  static String _csvEscape(String v) {
    final s = v;
    final mustQuote = s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    if (!mustQuote) return s;
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }
}
