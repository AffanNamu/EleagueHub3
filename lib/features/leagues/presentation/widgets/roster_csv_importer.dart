//leagues/presentation/widgets/roster csv importer
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';

class ResolvedRosterProfile {
  final String userId;
  final String teamName;

  const ResolvedRosterProfile({
    required this.userId,
    required this.teamName,
  });
}

enum RosterRowStatus {
  pending,
  ok,
  okCsv,
  notFound,
  offline,
}

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

typedef ResolveRosterProfile = Future<ResolvedRosterProfile?> Function(
  String userIdOrShareId,
);

bool _looksLikeShareId(String input) => input.trim().startsWith('eS');

bool _looksLikeFirebaseUid(String input) {
  final t = input.trim();
  if (t.isEmpty) return false;
  if (_looksLikeShareId(t)) return false;
  return t.length > 20;
}

String _displayInput(String raw) {
  final t = raw.trim();
  if (_looksLikeFirebaseUid(t)) return 'Firebase UID (hidden)';
  return t;
}

Future<void> showRosterCsvImportFlow({
  required BuildContext context,
  required bool isGroupLeague,
  required List<String> allowedGroups,
  required ResolveRosterProfile resolveProfile,
  required Future<void> Function(
    ResolvedRosterProfile resolved, {
    String? groupOverride,
  }) onAddResolved,
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
        const SnackBar(
          content: Text('Could not read file. Please pick a different CSV.'),
        ),
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
  }) onAddResolved,
  required int currentTeamCount,
  required int maxTeams,
}) async {
  bool validating = false;
  String? error;
  List<RosterCsvRow> stateRows = rows;

  Future<RosterCsvRow> validateOne(RosterCsvRow r) async {
    final input = r.input.trim();
    final csvName = r.teamNameFromCsv?.trim();
    final canFallbackToCsv =
        !_looksLikeShareId(input) && (csvName != null && csvName.isNotEmpty);

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
      stateRows = stateRows
          .map(
            (r) => r.copyWith(
              status: RosterRowStatus.pending,
              resolved: null,
            ),
          )
          .toList();
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
        .where(
          (r) =>
              (r.status == RosterRowStatus.ok ||
                  r.status == RosterRowStatus.okCsv) &&
              r.resolved != null,
        )
        .toList();

    if (valid.isEmpty) return;

    for (final r in valid) {
      await onAddResolved(r.resolved!, groupOverride: r.group);
    }

    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
      final theme = Theme.of(ctx);
      final brightness = theme.brightness;

      const success = Color(0xFF22C55E);
      final info = AppTheme.limeAccentDark;
      const warning = Color(0xFFF59E0B);

      final subtleText = AppTheme.secondaryText(brightness);
      final borderColor = AppTheme.cardBorder(brightness);
      final chipBg = AppTheme.searchBackground(brightness);

      return SafeArea(
        child: Padding(
          padding:
              EdgeInsets.only(bottom: bottomInset).add(const EdgeInsets.all(12)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Glass(
                borderRadius: 28,
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    final okCount = stateRows
                        .where((r) => r.status == RosterRowStatus.ok)
                        .length;
                    final okCsvCount = stateRows
                        .where((r) => r.status == RosterRowStatus.okCsv)
                        .length;
                    final notFoundCount = stateRows
                        .where((r) => r.status == RosterRowStatus.notFound)
                        .length;
                    final offlineCount = stateRows
                        .where((r) => r.status == RosterRowStatus.offline)
                        .length;
                    final totalValid = okCount + okCsvCount;

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: borderColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.iconCircleBackground(brightness),
                                ),
                                child: Icon(
                                  Icons.upload_file_rounded,
                                  color: AppTheme.limeAccentDark,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Import Roster',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        letterSpacing: -0.3,
                                        color: AppTheme.primaryText(brightness),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      sourceLabel,
                                      style: TextStyle(
                                        color: subtleText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Text(
                                  '$currentTeamCount / $maxTeams',
                                  style: TextStyle(
                                    color: subtleText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _StatusChip(
                                  icon: Icons.list_alt_rounded,
                                  label: '${stateRows.length} Rows',
                                  color: subtleText,
                                  bg: chipBg,
                                ),
                                const SizedBox(width: 8),
                                _StatusChip(
                                  icon: Icons.verified_rounded,
                                  label: '$okCount OK',
                                  color: success,
                                  bg: success.withOpacity(0.10),
                                ),
                                const SizedBox(width: 8),
                                _StatusChip(
                                  icon: Icons.cloud_off_rounded,
                                  label: '$okCsvCount CSV',
                                  color: info,
                                  bg: info.withOpacity(0.10),
                                ),
                                const SizedBox(width: 8),
                                if (notFoundCount > 0) ...[
                                  _StatusChip(
                                    icon: Icons.close_rounded,
                                    label: '$notFoundCount Missing',
                                    color: Theme.of(context).colorScheme.error,
                                    bg: Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withOpacity(0.10),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (offlineCount > 0)
                                  _StatusChip(
                                    icon: Icons.wifi_off_rounded,
                                    label: '$offlineCount Offline',
                                    color: warning,
                                    bg: warning.withOpacity(0.12),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _GlassActionButton(
                                  icon: validating
                                      ? null
                                      : Icons.verified_rounded,
                                  isLoading: validating,
                                  label: 'Validate',
                                  color: AppTheme.limeAccentDark,
                                  onPressed: validating
                                      ? null
                                      : () => validateNow(setModalState),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _GlassActionButton(
                                  icon: Icons.close_rounded,
                                  label: 'Close',
                                  color: subtleText,
                                  outlined: true,
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ),
                            ],
                          ),
                          if (offlineCount > 0) ...[
                            const SizedBox(height: 12),
                            Glass(
                              borderRadius: 16,
                              padding: const EdgeInsets.all(12),
                              fill: AppTheme.searchBackground(brightness),
                              borderColor: AppTheme.searchOutline(brightness),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: warning.withOpacity(0.12),
                                    ),
                                    child: Icon(
                                      Icons.wifi_off_rounded,
                                      color: warning,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Some rows could not be verified. Reconnect and tap Validate again.',
                                      style: TextStyle(
                                        color: subtleText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              itemCount: stateRows.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final r = stateRows[index];
                                return _RosterRowCard(
                                  row: r,
                                  isGroupLeague: isGroupLeague,
                                );
                              },
                            ),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 10),
                            Glass(
                              borderRadius: 14,
                              padding: const EdgeInsets.all(12),
                              fill: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withOpacity(0.08),
                              borderColor: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withOpacity(0.20),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      error!,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.error,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: (validating || totalValid == 0)
                                    ? null
                                    : () => addValidAndClose(ctx),
                                borderRadius: BorderRadius.circular(16),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: (validating || totalValid == 0)
                                        ? AppTheme.tabInactiveBackground(
                                            brightness,
                                          )
                                        : AppTheme.limeAccent,
                                    border: Border.all(
                                      color: (validating || totalValid == 0)
                                          ? borderColor
                                          : AppTheme.limeAccentDark,
                                    ),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.playlist_add_check_rounded,
                                          size: 20,
                                          color: (validating || totalValid == 0)
                                              ? AppTheme.secondaryText(
                                                  brightness,
                                                )
                                              : AppTheme.darkText,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Add valid ($totalValid) to preview',
                                          style: TextStyle(
                                            color:
                                                (validating || totalValid == 0)
                                                    ? AppTheme.secondaryText(
                                                        brightness,
                                                      )
                                                    : AppTheme.darkText,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
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

class _RosterRowCard extends StatelessWidget {
  const _RosterRowCard({
    required this.row,
    required this.isGroupLeague,
  });

  final RosterCsvRow row;
  final bool isGroupLeague;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    const success = Color(0xFF22C55E);
    final info = AppTheme.limeAccentDark;
    const warning = Color(0xFFF59E0B);

    final isOk = row.status == RosterRowStatus.ok && row.resolved != null;
    final isOkCsv = row.status == RosterRowStatus.okCsv && row.resolved != null;
    final isPending = row.status == RosterRowStatus.pending;
    final isOffline = row.status == RosterRowStatus.offline;

    final rawInput = row.input.trim();
    final displayInput = _displayInput(rawInput);
    final isHiddenUid = displayInput != rawInput;

    final IconData icon;
    final Color iconColor;
    final Color bgColor;

    String title;
    String subtitle;

    if (isOk) {
      icon = Icons.verified_rounded;
      iconColor = success;
      bgColor = success.withOpacity(0.12);

      title = row.resolved!.teamName;
      subtitle =
          isHiddenUid ? 'Verified • UID hidden' : 'Verified • $displayInput';
    } else if (isOkCsv) {
      icon = Icons.cloud_off_rounded;
      iconColor = info;
      bgColor = info.withOpacity(0.10);

      title = row.resolved!.teamName;
      subtitle = isHiddenUid ? 'CSV OK • UID hidden' : 'CSV OK • $displayInput';
    } else if (isPending) {
      icon = Icons.hourglass_empty_rounded;
      iconColor = AppTheme.secondaryText(brightness);
      bgColor = AppTheme.searchBackground(brightness);

      title = displayInput;
      subtitle = 'Pending validation';
    } else if (isOffline) {
      icon = Icons.wifi_off_rounded;
      iconColor = warning;
      bgColor = warning.withOpacity(0.12);

      title = displayInput;
      subtitle = 'Offline (cannot verify)';
    } else {
      icon = Icons.close_rounded;
      iconColor = Theme.of(context).colorScheme.error;
      bgColor = Theme.of(context).colorScheme.error.withOpacity(0.10);

      title = displayInput;
      subtitle = 'No profile found';
    }

    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isGroupLeague)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.searchBackground(brightness),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.searchOutline(brightness),
                ),
              ),
              child: Text(
                (row.group == null || row.group!.isEmpty) ? '—' : row.group!,
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
    this.isLoading = false,
    this.onPressed,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final bool outlined;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: outlined
                ? Colors.transparent
                : AppTheme.searchBackground(brightness),
            border: Border.all(
              color: outlined
                  ? color.withOpacity(0.30)
                  : AppTheme.searchOutline(brightness),
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<RosterCsvRow> _parseRosterCsv({
  required String csvText,
  required bool isGroupLeague,
  required List<String> allowedGroups,
}) {
  final lines = const LineSplitter().convert(csvText);
  final cleaned =
      lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (cleaned.isEmpty) return [];

  final first = _splitCsvLine(cleaned.first).map((e) => e.trim()).toList();
  bool hasHeader = false;

  int idIdx = 0;
  int? groupIdx;
  int? teamNameIdx;

  if (first.isNotEmpty) {
    final lowered =
        first.map((e) => e.toLowerCase().replaceAll(' ', '')).toList();

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
    final groupCandidates = <String>{'group', 'groupid', 'group_id'};
    final teamNameCandidates = <String>{'teamname', 'team_name'};

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
