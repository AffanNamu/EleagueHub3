import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';

/// Result of resolving a roster row to an internal Firebase uid + team name.
class ResolvedRosterProfile {
  final String userId; // internal Firebase uid
  final String teamName;

  const ResolvedRosterProfile({
    required this.userId,
    required this.teamName,
  });
}

/// Validation status per CSV row.
enum RosterRowStatus {
  pending,

  /// Verified by looking up the user profile (uid/shareId -> uid) online.
  ok,

  /// Accepted from CSV (not verified).
  ///
  /// This is used when:
  /// - userId looks like a Firebase uid (not eS...), AND
  /// - CSV contains teamName, AND
  /// - we couldn't verify (offline / profile missing / error).
  okCsv,

  notFound,

  /// Could not verify due to network / permissions / transient errors.
  offline,
}

/// One CSV row for roster import.
///
/// `input` can be either:
/// - Firebase uid
/// - short ShareId (eSxxxxxx)
///
/// `group` is optional and only used for UCL Group leagues.
class RosterCsvRow {
  final String input;
  final String? teamNameFromCsv;
  final String? group;

  final ResolvedRosterProfile? resolved;
  final RosterRowStatus status;

  const RosterCsvRow({
    required this.input,
    required this.teamNameFromCsv,
    required this.group,
    required this.resolved,
    required this.status,
  });

  RosterCsvRow copyWith({
    String? input,
    String? teamNameFromCsv,
    String? group,
    ResolvedRosterProfile? resolved,
    RosterRowStatus? status,
  }) {
    return RosterCsvRow(
      input: input ?? this.input,
      teamNameFromCsv: teamNameFromCsv ?? this.teamNameFromCsv,
      group: group ?? this.group,
      resolved: resolved ?? this.resolved,
      status: status ?? this.status,
    );
  }
}

typedef ResolveRosterProfile = Future<ResolvedRosterProfile?> Function(String userIdOrShareId);

bool _looksLikeShareId(String input) => input.trim().startsWith('eS');

/// Opens a "Pick CSV -> Preview -> Validate -> Add valid to preview" flow.
///
/// This is designed to be called from AddTeamsScreen.
///
/// Key behavior:
/// - Validation is resilient: one failed lookup does NOT fail the whole sheet.
/// - Rows failing due to network/permission errors are marked as OFFLINE (not crashing).
/// - If CSV contains teamName and the ID is a uid (not eS...), we can accept it as OK (CSV)
///   even when offline.
Future<void> showRosterCsvImportFlow({
  required BuildContext context,
  required bool isGroupLeague,
  required List<String> allowedGroups,
  required ResolveRosterProfile resolveProfile,
  required Future<void> Function(
    ResolvedRosterProfile resolved, {
    String? groupOverride,
  })
      onAddResolved,
  required int currentTeamCount,
  required int maxTeams,
}) async {
  try {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read file. Please pick a different CSV.')),
      );
      return;
    }

    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = latin1.decode(bytes);
    }

    final rows = _parseRosterCsv(
      csvText: text,
      isGroupLeague: isGroupLeague,
      allowedGroups: allowedGroups,
    );

    if (rows.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rows found in CSV.')),
      );
      return;
    }

    if (!context.mounted) return;

    await _showImportPreviewSheet(
      context: context,
      sourceLabel: file.name,
      isGroupLeague: isGroupLeague,
      rows: rows,
      resolveProfile: resolveProfile,
      onAddResolved: onAddResolved,
      currentTeamCount: currentTeamCount,
      maxTeams: maxTeams,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV import failed: $e')),
    );
  }
}

Future<void> _showImportPreviewSheet({
  required BuildContext context,
  required String sourceLabel,
  required bool isGroupLeague,
  required List<RosterCsvRow> rows,
  required ResolveRosterProfile resolveProfile,
  required Future<void> Function(
    ResolvedRosterProfile resolved, {
    String? groupOverride,
  })
      onAddResolved,
  required int currentTeamCount,
  required int maxTeams,
}) async {
  bool validating = false;
  String? error;
  List<RosterCsvRow> stateRows = rows;

  Future<RosterCsvRow> validateOne(RosterCsvRow r) async {
    final input = r.input.trim();
    final csvName = r.teamNameFromCsv?.trim();

    // If it's a shareId (eS...), we must verify online because we can't map to uid offline.
    final canFallbackToCsv = !_looksLikeShareId(input) && (csvName != null && csvName.isNotEmpty);

    try {
      final resolved = await resolveProfile(input);
      if (resolved != null) {
        return r.copyWith(resolved: resolved, status: RosterRowStatus.ok);
      }

      if (canFallbackToCsv) {
        return r.copyWith(
          resolved: ResolvedRosterProfile(userId: input, teamName: csvName),
          status: RosterRowStatus.okCsv,
        );
      }

      return r.copyWith(resolved: null, status: RosterRowStatus.notFound);
    } catch (_) {
      if (canFallbackToCsv) {
        return r.copyWith(
          resolved: ResolvedRosterProfile(userId: input, teamName: csvName),
          status: RosterRowStatus.okCsv,
        );
      }
      return r.copyWith(resolved: null, status: RosterRowStatus.offline);
    }
  }

  Future<void> validateNow(StateSetter setModalState) async {
    if (stateRows.isEmpty) return;

    setModalState(() {
      validating = true;
      error = null;
      stateRows = stateRows.map((r) => r.copyWith(status: RosterRowStatus.pending, resolved: null)).toList();
    });

    try {
      final updated = await Future.wait(stateRows.map(validateOne).toList());

      if (!context.mounted) return;
      setModalState(() {
        stateRows = updated;
        validating = false;
        error = null;
      });
    } catch (e) {
      if (!context.mounted) return;
      setModalState(() {
        validating = false;
        error = 'Validation failed: $e';
      });
    }
  }

  Future<void> addValidAndClose(BuildContext ctx) async {
    final valid = stateRows
        .where((r) =>
            (r.status == RosterRowStatus.ok || r.status == RosterRowStatus.okCsv) && r.resolved != null)
        .toList();

    if (valid.isEmpty) return;

    for (final r in valid) {
      await onAddResolved(
        r.resolved!,
        groupOverride: r.group,
      );
    }

    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset).add(const EdgeInsets.all(12)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Glass(
                borderRadius: 28,
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    final okCount = stateRows.where((r) => r.status == RosterRowStatus.ok).length;
                    final okCsvCount = stateRows.where((r) => r.status == RosterRowStatus.okCsv).length;
                    final notFoundCount = stateRows.where((r) => r.status == RosterRowStatus.notFound).length;
                    final offlineCount = stateRows.where((r) => r.status == RosterRowStatus.offline).length;

                    return Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Import roster from CSV',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'File: $sourceLabel',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _MiniChip(label: 'Rows: ${stateRows.length}', color: Colors.white24),
                              const SizedBox(width: 8),
                              _MiniChip(label: 'OK: $okCount', color: Colors.cyanAccent.withOpacity(0.22)),
                              const SizedBox(width: 8),
                              _MiniChip(label: 'CSV OK: $okCsvCount', color: Colors.blueAccent.withOpacity(0.18)),
                              const SizedBox(width: 8),
                              _MiniChip(label: 'Not found: $notFoundCount', color: Colors.redAccent.withOpacity(0.18)),
                              const SizedBox(width: 8),
                              _MiniChip(label: 'Offline: $offlineCount', color: Colors.orangeAccent.withOpacity(0.18)),
                              const Spacer(),
                              Text(
                                '$currentTeamCount / $maxTeams',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: validating ? null : () => validateNow(setModalState),
                                  icon: validating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.verified),
                                  label: const Text('Validate'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Close'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(color: Colors.white24),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (offlineCount > 0) ...[
                            const SizedBox(height: 10),
                            Glass(
                              borderRadius: 18,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Some rows could not be verified (offline or blocked). Reconnect and tap Validate again.',
                                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11, height: 1.25),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: stateRows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final r = stateRows[index];

                                final isOk = r.status == RosterRowStatus.ok && r.resolved != null;
                                final isOkCsv = r.status == RosterRowStatus.okCsv && r.resolved != null;
                                final isPending = r.status == RosterRowStatus.pending;
                                final isOffline = r.status == RosterRowStatus.offline;

                                final icon = isOk
                                    ? Icons.verified
                                    : isOkCsv
                                        ? Icons.cloud_off
                                        : isPending
                                            ? Icons.hourglass_empty
                                            : isOffline
                                                ? Icons.wifi_off
                                                : Icons.close;

                                final iconColor = isOk
                                    ? Colors.cyanAccent
                                    : isOkCsv
                                        ? Colors.blueAccent
                                        : isOffline
                                            ? Colors.orangeAccent
                                            : Colors.white54;

                                final subtitle = isOk
                                    ? r.resolved!.teamName
                                    : isOkCsv
                                        ? 'CSV OK: ${r.resolved!.teamName}'
                                        : (isOffline
                                            ? 'Offline (cannot verify)'
                                            : 'No profile found');

                                return Glass(
                                  borderRadius: 16,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: isOk
                                              ? Colors.cyanAccent.withOpacity(0.18)
                                              : isOkCsv
                                                  ? Colors.blueAccent.withOpacity(0.16)
                                                  : isOffline
                                                      ? Colors.orangeAccent.withOpacity(0.16)
                                                      : Colors.white.withOpacity(0.08),
                                          child: Icon(icon, size: 16, color: iconColor),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r.input,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                subtitle,
                                                style: TextStyle(
                                                  color: (isOk || isOkCsv) ? Colors.white70 : Colors.white38,
                                                  fontSize: 11,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isGroupLeague)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8),
                                            child: Text(
                                              (r.group == null || r.group!.isEmpty) ? '—' : r.group!,
                                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              error!,
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: validating ? null : () => addValidAndClose(ctx),
                              icon: const Icon(Icons.playlist_add_check),
                              label: Text('Add valid${stateRows.isEmpty ? '' : ' (${okCount + okCsvCount})'} to preview'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

List<RosterCsvRow> _parseRosterCsv({
  required String csvText,
  required bool isGroupLeague,
  required List<String> allowedGroups,
}) {
  final lines = const LineSplitter().convert(csvText);
  final cleaned = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (cleaned.isEmpty) return [];

  final first = _splitCsvLine(cleaned.first).map((e) => e.trim()).toList();
  bool hasHeader = false;

  int idIdx = 0;
  int? groupIdx;
  int? teamNameIdx;

  if (first.isNotEmpty) {
    final lowered = first.map((e) => e.toLowerCase().replaceAll(' ', '')).toList();

    final idCandidates = <String>{
      'userid',
      'user_id',
      'useridorshareid',
      'useridor_shareid',
      'user_id_or_share_id',
      'useridorshare',
      'shareid',
      'share_id',
    };

    final groupCandidates = <String>{
      'group',
      'groupid',
      'group_id',
    };

    final teamNameCandidates = <String>{
      'teamname',
      'team_name',
    };

    final foundId = lowered.indexWhere((c) => idCandidates.contains(c));
    if (foundId >= 0) {
      hasHeader = true;
      idIdx = foundId;
    }

    final foundGroup = lowered.indexWhere((c) => groupCandidates.contains(c));
    if (foundGroup >= 0) {
      hasHeader = true;
      groupIdx = foundGroup;
    }

    final foundTeam = lowered.indexWhere((c) => teamNameCandidates.contains(c));
    if (foundTeam >= 0) {
      hasHeader = true;
      teamNameIdx = foundTeam;
    }
  }

  final dataLines = hasHeader ? cleaned.skip(1).toList() : cleaned;

  final out = <RosterCsvRow>[];
  for (final line in dataLines) {
    final cols = _splitCsvLine(line);
    if (cols.isEmpty) continue;

    final id = (idIdx < cols.length) ? cols[idIdx].trim() : '';
    if (id.isEmpty) continue;

    String? group;
    if (isGroupLeague && groupIdx != null && groupIdx < cols.length) {
      group = _normalizeGroup(cols[groupIdx], allowedGroups);
    }

    String? teamNameFromCsv;
    if (teamNameIdx != null && teamNameIdx < cols.length) {
      final t = cols[teamNameIdx].trim();
      if (t.isNotEmpty) teamNameFromCsv = t;
    }

    out.add(
      RosterCsvRow(
        input: id,
        teamNameFromCsv: teamNameFromCsv,
        group: group,
        resolved: null,
        status: RosterRowStatus.pending,
      ),
    );
  }

  return out;
}

String? _normalizeGroup(String raw, List<String> allowedGroups) {
  final t = raw.trim();
  if (t.isEmpty) return null;

  if (allowedGroups.contains(t)) return t;

  final upper = t.toUpperCase();
  if (upper.length == 1 && RegExp(r'^[A-H]$').hasMatch(upper)) {
    final candidate = 'Group $upper';
    if (allowedGroups.contains(candidate)) return candidate;
  }

  final compact = upper.replaceAll(' ', '');
  if (compact.startsWith('GROUP') && compact.length == 6) {
    final letter = compact.substring(5, 6);
    final candidate = 'Group $letter';
    if (allowedGroups.contains(candidate)) return candidate;
  }

  return null;
}

List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  bool inQuotes = false;

  for (int i = 0; i < line.length; i++) {
    final ch = line[i];

    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }

    if (ch == ',' && !inQuotes) {
      out.add(buf.toString());
      buf.clear();
      continue;
    }

    buf.write(ch);
  }

  out.add(buf.toString());
  return out;
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
