import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/standings/standings.dart';
import '../models/league_format.dart';
import 'standings_providers.dart';
import 'widgets/standings_table.dart';

class LeagueStandingsScreen extends ConsumerStatefulWidget {
  final String id;

  const LeagueStandingsScreen({
    super.key,
    required this.id,
  });

  @override
  ConsumerState<LeagueStandingsScreen> createState() => _LeagueStandingsScreenState();
}

class _LeagueStandingsScreenState extends ConsumerState<LeagueStandingsScreen> {
  bool _refreshing = false;

  // Best-effort team images map (teamId -> url). Empty => placeholder.
  Map<String, String> _teamImageUrls = {};

  // Prevent repeated user lookups on rebuilds.
  final Set<String> _requestedUserImageIds = <String>{};

  @override
  void initState() {
    super.initState();

    // Online-only: no sync engine. Just refresh providers once after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _refresh();
    });

    // Best-effort prefetch for fast avatar strip.
    unawaited(_loadTeamImagesBestEffort());
  }

  String _displayGroupName(String groupId) {
    final l10n = context.l10n;
    switch (groupId) {
      case 'Group A':
        return l10n.tr('add_teams_group_a');
      case 'Group B':
        return l10n.tr('add_teams_group_b');
      case 'Group C':
        return l10n.tr('add_teams_group_c');
      case 'Group D':
        return l10n.tr('add_teams_group_d');
      case 'Group E':
        return l10n.tr('add_teams_group_e');
      case 'Group F':
        return l10n.tr('add_teams_group_f');
      case 'Group G':
        return l10n.tr('add_teams_group_g');
      case 'Group H':
        return l10n.tr('add_teams_group_h');
      default:
        return groupId;
    }
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  String _bestEffortUrlFromMap(Map<String, dynamic> data) {
    const keys = <String>[
      'teamImageUrl',
      'imageUrl',
      'logoUrl',
      'photoUrl',
      'profileImageUrl',
      'avatarUrl',
    ];
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String _bestUserImageUrlFromUserDoc(Map<String, dynamic> data) {
    final teamImageUrl = (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final profileImageUrl = (data['profileImageUrl'] as String?)?.trim() ?? '';
    if (profileImageUrl.isNotEmpty) return profileImageUrl;

    final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
    if (photoUrl.isNotEmpty) return photoUrl;

    return '';
  }

  Future<Map<String, String>> _fetchUserImagesByIds(List<String> ids) async {
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty && _looksLikeFirebaseUid(e)).toList(growable: false);
    if (clean.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    // whereIn limit 10
    const chunkSize = 10;
    for (var i = 0; i < clean.length; i += chunkSize) {
      final chunk = clean.sublist(i, (i + chunkSize > clean.length) ? clean.length : i + chunkSize);

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      for (final d in snap.docs) {
        final url = _bestUserImageUrlFromUserDoc(d.data());
        if (url.trim().isNotEmpty) out[d.id] = url.trim();
      }
    }

    return out;
  }

  /// Loads image URLs from:
  /// 1) leagues/{leagueId}/teams (if any teamImageUrl exists)
  /// 2) users/{uid} for UID-based teams (PRIMARY source of truth, overrides)
  Future<void> _loadTeamImagesBestEffort() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.id)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));

      final out = <String, String>{};
      final teamIds = <String>[];

      for (final d in snap.docs) {
        final data = d.data();
        final id = (data['id'] is String && (data['id'] as String).trim().isNotEmpty) ? (data['id'] as String).trim() : d.id;
        teamIds.add(id);

        final url = _bestEffortUrlFromMap(data);
        if (id.trim().isNotEmpty && url.isNotEmpty) out[id] = url;
      }

      // Override with user profile images for UID-based teams
      final userImages = await _fetchUserImagesByIds(teamIds);
      for (final e in userImages.entries) {
        out[e.key] = e.value;
      }

      if (!mounted) return;
      if (out.isEmpty) return;

      setState(() => _teamImageUrls = {..._teamImageUrls, ...out});
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _ensureUserImagesForTeamIds(List<String> ids) async {
    final missing = <String>[];
    for (final id in ids) {
      final clean = id.trim();
      if (!_looksLikeFirebaseUid(clean)) continue;
      if (_requestedUserImageIds.contains(clean)) continue;
      if ((_teamImageUrls[clean] ?? '').trim().isNotEmpty) {
        _requestedUserImageIds.add(clean);
        continue;
      }
      missing.add(clean);
      _requestedUserImageIds.add(clean);
    }

    if (missing.isEmpty) return;

    try {
      final userImages = await _fetchUserImagesByIds(missing);
      if (!mounted) return;
      if (userImages.isEmpty) return;

      setState(() => _teamImageUrls = {..._teamImageUrls, ...userImages});
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    // Online-only: invalidate providers so they refetch live Firebase data.
    ref.invalidate(leagueProvider(widget.id));
    ref.invalidate(leagueStandingsProvider(widget.id));
    ref.invalidate(leagueGroupedStandingsProvider(widget.id));

    // Best-effort refresh of team avatars too.
    unawaited(_loadTeamImagesBestEffort());

    if (mounted) setState(() => _refreshing = false);
  }

  Widget _errorText(BuildContext context, String prefixKey, Object error) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final message = UserFriendlyError.toMessage(error);

    return Center(
      child: Text(
        '${l10n.tr(prefixKey)}\n$message',
        style: TextStyle(
          color: cs.onSurface.withOpacity(0.72),
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _rowTeamId(StandingsRow row) {
    try {
      final dyn = row as dynamic;
      final v = (dyn.teamId as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final dyn = row as dynamic;
      final v = (dyn.id as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return '';
  }

  String _rowTeamName(StandingsRow row) {
    try {
      final dyn = row as dynamic;
      final v = (dyn.teamName as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final dyn = row as dynamic;
      final v = (dyn.name as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return '';
  }

  Widget _avatarStrip(List<StandingsRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    final take = rows.length > 12 ? rows.take(12).toList() : rows.toList();
    final ids = <String>[];
    final names = <String>[];

    for (final r in take) {
      ids.add(_rowTeamId(r));
      names.add(_rowTeamName(r));
    }

    if (ids.every((e) => e.trim().isEmpty)) return const SizedBox.shrink();

    // Ensure user images are fetched for these ids (post-frame to avoid setState in build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _ensureUserImagesForTeamIds(ids);
    });

    return Container(
      height: 28,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ids.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i].trim();
          final name = names[i].trim();
          final url = (id.isEmpty ? '' : (_teamImageUrls[id] ?? '')).trim();

          return Tooltip(
            message: name.isEmpty ? id : name,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.04),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.onSurface.withOpacity(0.10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TeamThumb(url: url),
                  const SizedBox(width: 6),
                  Text(
                    (name.isNotEmpty ? name : id).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.70),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final leagueAsync = ref.watch(leagueProvider(widget.id));

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('standings_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('admin_knockout_reload_tooltip'),
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: cs.primary,
          backgroundColor: cs.surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(l10n.tr('standings_section_title')),
                      const SizedBox(height: 12),
                      Expanded(
                        child: leagueAsync.when(
                          loading: () => Center(
                            child: CircularProgressIndicator(color: cs.primary),
                          ),
                          error: (error, _) => _errorText(
                            context,
                            'standings_failed_load_league_prefix',
                            error,
                          ),
                          data: (league) {
                            switch (league.format) {
                              case LeagueFormat.uclGroup:
                                final groupedAsync = ref.watch(leagueGroupedStandingsProvider(widget.id));
                                return groupedAsync.when(
                                  loading: () => Center(
                                    child: CircularProgressIndicator(color: cs.primary),
                                  ),
                                  error: (error, _) => _errorText(
                                    context,
                                    'standings_failed_load_group_standings_prefix',
                                    error,
                                  ),
                                  data: (groupMap) {
                                    if (groupMap.isEmpty) {
                                      return Center(
                                        child: Text(
                                          l10n.tr('standings_no_group_results_yet'),
                                          style: TextStyle(
                                            color: cs.onSurface.withOpacity(0.55),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }

                                    final groupKeys = groupMap.keys.toList()..sort();

                                    final invalidGroupCount = !(groupKeys.length == 4 || groupKeys.length == 8);
                                    final invalidGroupSizes = groupKeys.any((g) => (groupMap[g]?.length ?? 0) != 4);

                                    return ListView.builder(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      itemCount: groupKeys.length + ((invalidGroupCount || invalidGroupSizes) ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if ((invalidGroupCount || invalidGroupSizes) && index == 0) {
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: Text(
                                              '${l10n.tr('standings_ucl_group_structure_warning_prefix')}${groupKeys.length}${l10n.tr('standings_ucl_group_structure_warning_suffix')}',
                                              style: const TextStyle(
                                                color: Color(0xFFF59E0B),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        }

                                        final adjIndex = (invalidGroupCount || invalidGroupSizes) ? index - 1 : index;

                                        final groupId = groupKeys[adjIndex];
                                        final rows = groupMap[groupId] ?? const <StandingsRow>[];

                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom: adjIndex == groupKeys.length - 1 ? 0 : 16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                child: Text(
                                                  _displayGroupName(groupId),
                                                  style: TextStyle(
                                                    color: cs.primary,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _avatarStrip(rows),
                                              StandingsTable(rows: rows),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );

                              case LeagueFormat.uclSwiss:
                                final standingsAsync = ref.watch(leagueStandingsProvider(widget.id));
                                return standingsAsync.when(
                                  loading: () => Center(
                                    child: CircularProgressIndicator(color: cs.primary),
                                  ),
                                  error: (error, _) => _errorText(
                                    context,
                                    'standings_failed_load_standings_prefix',
                                    error,
                                  ),
                                  data: (rows) {
                                    return FutureBuilder<int>(
                                      future: _getSwissCurrentRound(ref, widget.id),
                                      builder: (context, snapshot) {
                                        final current = snapshot.data ?? 0;
                                        final total = league.settings.swissRounds;

                                        final label = current == 0
                                            ? '${l10n.tr('standings_swiss_phase_no_rounds_yet_prefix')}$total${l10n.tr('standings_swiss_phase_no_rounds_yet_suffix')}'
                                            : '${l10n.tr('standings_swiss_phase_round_prefix')}$current${l10n.tr('standings_swiss_phase_round_mid')}$total';

                                        final autoColor = const Color(0xFF22C55E).withOpacity(0.12);
                                        final playoffColor = cs.primary.withOpacity(0.10);
                                        final eliminatedColor = cs.error.withOpacity(0.08);

                                        final n = rows.length;
                                        final allowed = (n == 18 || n == 36);

                                        final int autoCut = (n == 36) ? 8 : (n == 18 ? 4 : 0);
                                        final int playoffCut = (n == 36) ? 24 : (n == 18 ? 12 : 0);

                                        if (rows.isEmpty) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                label,
                                                style: TextStyle(
                                                  color: cs.onSurface.withOpacity(0.55),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Expanded(
                                                child: Center(
                                                  child: Text(
                                                    l10n.tr('standings_no_results_yet'),
                                                    style: TextStyle(
                                                      color: cs.onSurface.withOpacity(0.55),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              label,
                                              style: TextStyle(
                                                color: cs.onSurface.withOpacity(0.55),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (!allowed) ...[
                                              Text(
                                                '${l10n.tr('standings_swiss_team_count_warning_prefix')}$n.',
                                                style: const TextStyle(
                                                  color: Color(0xFFF59E0B),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 8),
                                            ] else ...[
                                              _swissLegendDynamic(
                                                context: context,
                                                teamCount: n,
                                                autoColor: autoColor,
                                                playoffColor: playoffColor,
                                                eliminatedColor: eliminatedColor,
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                            _avatarStrip(rows),
                                            Expanded(
                                              child: StandingsTable(
                                                rows: rows,
                                                allowSorting: false,
                                                rowColorBuilder: (ctx, index, row, totalRows) {
                                                  if (!allowed) return Colors.transparent;
                                                  final rank = index + 1;
                                                  if (rank <= autoCut) return autoColor;
                                                  if (rank <= playoffCut) return playoffColor;
                                                  return eliminatedColor;
                                                },
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                );

                              case LeagueFormat.classic:
                              default:
                                final standingsAsync = ref.watch(leagueStandingsProvider(widget.id));
                                return standingsAsync.when(
                                  loading: () => Center(
                                    child: CircularProgressIndicator(color: cs.primary),
                                  ),
                                  error: (error, _) => _errorText(
                                    context,
                                    'standings_failed_load_standings_prefix',
                                    error,
                                  ),
                                  data: (rows) {
                                    if (rows.isEmpty) {
                                      return Center(
                                        child: Text(
                                          l10n.tr('standings_no_results_yet'),
                                          style: TextStyle(
                                            color: cs.onSurface.withOpacity(0.55),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _avatarStrip(rows),
                                        Expanded(child: StandingsTable(rows: rows)),
                                      ],
                                    );
                                  },
                                );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<int> _getSwissCurrentRound(WidgetRef ref, String leagueId) async {
  try {
    final repo = ref.read(localLeaguesRepositoryProvider);
    final allMatches = await repo.getMatches(leagueId);
    if (allMatches.isEmpty) return 0;
    return allMatches.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
  } catch (_) {
    // Best-effort: standings still render even if round label can't be computed.
    return 0;
  }
}

Widget _swissLegendDynamic({
  required BuildContext context,
  required int teamCount,
  required Color autoColor,
  required Color playoffColor,
  required Color eliminatedColor,
}) {
  final l10n = context.l10n;
  final cs = Theme.of(context).colorScheme;

  Widget dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: cs.onSurface.withOpacity(0.18), width: 0.5),
        ),
      );

  final labelStyle = TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w600);

  if (teamCount == 36) {
    return Row(
      children: [
        dot(autoColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_top8_r16'), style: labelStyle),
        const SizedBox(width: 12),
        dot(playoffColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_9_24_playoff'), style: labelStyle),
        const SizedBox(width: 12),
        dot(eliminatedColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_25_36_eliminated'), style: labelStyle),
      ],
    );
  }

  return Row(
    children: [
      dot(autoColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_top4_quarter_finals'), style: labelStyle),
      const SizedBox(width: 12),
      dot(playoffColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_5_12_playoff'), style: labelStyle),
      const SizedBox(width: 12),
      dot(eliminatedColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_13_18_eliminated'), style: labelStyle),
    ],
  );
}

class _TeamThumb extends StatelessWidget {
  const _TeamThumb({
    required this.url,
  });

  final String url;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(String url, {int width = 64, int height = 64}) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary = u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;

    final marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = 'f_auto,q_auto,w_$width,h_$height,c_fill,g_auto';

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly = first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final d = has ? _cloudinaryOptimizedUrl(raw, width: 64, height: 64) : '';

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        border: Border.all(color: cs.onSurface.withOpacity(0.14)),
      ),
      child: ClipOval(
        child: has
            ? Image.network(
                d,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: 64,
                cacheHeight: 64,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.emoji_events_outlined, size: 12, color: cs.onSurface.withOpacity(0.55)),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(Icons.emoji_events_outlined, size: 12, color: cs.onSurface.withOpacity(0.55));
                },
              )
            : Icon(Icons.emoji_events_outlined, size: 12, color: cs.onSurface.withOpacity(0.55)),
      ),
    );
  }
}
