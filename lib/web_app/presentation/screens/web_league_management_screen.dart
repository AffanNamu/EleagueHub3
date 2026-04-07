import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';

/// Web desktop league management panel.
/// Shows all leagues where the paired user is organizer or member.
/// Tapping a league opens the detail panel inline.
class WebLeagueManagementScreen extends StatefulWidget {
  final String pairedUserUid;
  const WebLeagueManagementScreen({
    super.key,
    required this.pairedUserUid,
  });

  @override
  State<WebLeagueManagementScreen> createState() =>
      _WebLeagueManagementScreenState();
}

class _WebLeagueManagementScreenState
    extends State<WebLeagueManagementScreen> {
  String? _selectedLeagueId;
  String _selectedLeagueName = '';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Firestore queries ─────────────────────────────────────────────────────
  // The rules allow list for signed-in users.
  // We fetch leagues where user is organizer OR in memberIds.
  Stream<List<Map<String, dynamic>>> _leaguesStream() {
    final uid = widget.pairedUserUid.trim();
    if (uid.isEmpty) return const Stream.empty();

    final fs = FirebaseFirestore.instance;

    // Two queries merged: organizer + member
    final q1 = fs
        .collection('leagues')
        .where('organizerUid', isEqualTo: uid)
        .snapshots();

    final q2 = fs
        .collection('leagues')
        .where('memberIds', arrayContains: uid)
        .snapshots();

    // Merge both streams
    return _mergeLeagueStreams(q1, q2);
  }

  Stream<List<Map<String, dynamic>>> _mergeLeagueStreams(
    Stream<QuerySnapshot<Map<String, dynamic>>> a,
    Stream<QuerySnapshot<Map<String, dynamic>>> b,
  ) async* {
    List<Map<String, dynamic>> fromA = [];
    List<Map<String, dynamic>> fromB = [];

    await for (final _ in Stream.periodic(Duration.zero).take(1)) {
      break;
    }

    // Use a combined approach with async*
    final combined = <String, Map<String, dynamic>>{};

    // We use a simpler single-stream approach to avoid complex merging
    yield* FirebaseFirestore.instance
        .collection('leagues')
        .snapshots()
        .map((snap) {
      final uid = widget.pairedUserUid.trim();
      final results = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final orgUid    = (d['organizerUid']   ?? '').toString().trim();
        final orgUserId = (d['organizerUserId'] ?? '').toString().trim();
        final ownerUid  = (d['ownerUid']        ?? '').toString().trim();
        final ownerId   = (d['ownerId']          ?? '').toString().trim();
        final members   = (d['memberIds'] is List)
            ? List<String>.from((d['memberIds'] as List).map((e) => e.toString()))
            : <String>[];
        final isOrganizer = orgUid == uid ||
            orgUserId == uid ||
            ownerUid == uid ||
            ownerId == uid;
        final isMember = members.contains(uid);
        if (isOrganizer || isMember) {
          results.add({'id': doc.id, ...d});
        }
      }
      return results;
    });
  }

  bool _isOrganizer(Map<String, dynamic> d) {
    final uid = widget.pairedUserUid.trim();
    return (d['organizerUid']   ?? '').toString().trim() == uid ||
        (d['organizerUserId'] ?? '').toString().trim() == uid ||
        (d['ownerUid']        ?? '').toString().trim() == uid ||
        (d['ownerId']         ?? '').toString().trim() == uid;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final width      = MediaQuery.of(context).size.width;
    final showDetail = _selectedLeagueId != null && width >= 900;

    return Row(
      children: [
        // ── League list ──────────────────────────────────────────────────
        SizedBox(
          width: showDetail ? 360 : double.infinity,
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  fill: AppTheme.searchBackground(brightness),
                  borderColor: AppTheme.searchOutline(brightness),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 18,
                          color: AppTheme.secondaryText(brightness)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              setState(() => _searchQuery = v),
                          decoration: const InputDecoration(
                            hintText: 'Search leagues...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // League list
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _leaguesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    final all = snapshot.data ?? [];
                    final q   = _searchQuery.trim().toLowerCase();
                    final filtered = q.isEmpty
                        ? all
                        : all.where((d) {
                            final name   = (d['name'] ?? '').toString().toLowerCase();
                            final region = (d['region'] ?? '').toString().toLowerCase();
                            final code   = (d['code'] ?? '').toString().toLowerCase();
                            return name.contains(q) ||
                                region.contains(q) ||
                                code.contains(q);
                          }).toList();

                    if (filtered.isEmpty) {
                      return _buildEmpty(brightness);
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          16, 0, 16, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final d          = filtered[i];
                        final id         = d['id'].toString();
                        final name       = (d['name'] ?? 'League').toString();
                        final region     = (d['region'] ?? '').toString();
                        final season     = (d['season'] ?? '').toString();
                        final format     = (d['format'] ?? '').toString();
                        final isOwner    = _isOrganizer(d);
                        final isSelected = _selectedLeagueId == id;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LeagueTile(
                            name: name,
                            region: region,
                            season: season,
                            format: format,
                            isOrganizer: isOwner,
                            isSelected: isSelected,
                            brightness: brightness,
                            onTap: () => setState(() {
                              _selectedLeagueId   = id;
                              _selectedLeagueName = name;
                            }),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // ── Detail panel ─────────────────────────────────────────────────
        if (showDetail) ...[
          VerticalDivider(
            width: 1,
            color: AppTheme.cardBorder(brightness),
          ),
          Expanded(
            child: WebLeagueDetailPanel(
              leagueId: _selectedLeagueId!,
              leagueName: _selectedLeagueName,
              pairedUserUid: widget.pairedUserUid,
              onClose: () =>
                  setState(() => _selectedLeagueId = null),
            ),
          ),
        ],

        // ── Mobile: full-screen detail ───────────────────────────────────
        if (_selectedLeagueId != null && width < 900)
          Expanded(
            child: WebLeagueDetailPanel(
              leagueId: _selectedLeagueId!,
              leagueName: _selectedLeagueName,
              pairedUserUid: widget.pairedUserUid,
              onClose: () =>
                  setState(() => _selectedLeagueId = null),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(Brightness brightness) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 56,
                color: AppTheme.secondaryText(brightness)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'No leagues found'
                  : 'No results for "$_searchQuery"',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Leagues you organize or join will appear here.'
                  : 'Try a different search term.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── League tile ───────────────────────────────────────────────────────────────

class _LeagueTile extends StatelessWidget {
  final String name;
  final String region;
  final String season;
  final String format;
  final bool isOrganizer;
  final bool isSelected;
  final Brightness brightness;
  final VoidCallback onTap;

  const _LeagueTile({
    required this.name,
    required this.region,
    required this.season,
    required this.format,
    required this.isOrganizer,
    required this.isSelected,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected
                ? AppTheme.limeAccentDark.withOpacity(0.10)
                : AppTheme.cardColor(brightness),
            border: Border.all(
              color: isSelected
                  ? AppTheme.limeAccentDark
                  : AppTheme.cardBorder(brightness),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.iconCircleBackground(brightness),
                ),
                child: Icon(
                  isOrganizer
                      ? Icons.admin_panel_settings_rounded
                      : Icons.emoji_events_rounded,
                  color: isOrganizer
                      ? AppTheme.limeAccentDark
                      : AppTheme.secondaryText(brightness),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        )),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (region.isNotEmpty)
                          _Chip(label: region, brightness: brightness),
                        if (season.isNotEmpty)
                          _Chip(label: season, brightness: brightness),
                        if (format.isNotEmpty)
                          _Chip(label: format, brightness: brightness),
                        if (isOrganizer)
                          _Chip(
                            label: 'Organizer',
                            brightness: brightness,
                            accent: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.secondaryText(brightness)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Brightness brightness;
  final bool accent;
  const _Chip({
    required this.label,
    required this.brightness,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? AppTheme.limeAccentDark.withOpacity(0.12)
            : AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
            color: accent
                ? AppTheme.limeAccentDark
                : AppTheme.secondaryText(brightness),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}

// ── League detail panel ───────────────────────────────────────────────────────

class WebLeagueDetailPanel extends StatefulWidget {
  final String leagueId;
  final String leagueName;
  final String pairedUserUid;
  final VoidCallback onClose;

  const WebLeagueDetailPanel({
    super.key,
    required this.leagueId,
    required this.leagueName,
    required this.pairedUserUid,
    required this.onClose,
  });

  @override
  State<WebLeagueDetailPanel> createState() =>
      _WebLeagueDetailPanelState();
}

class _WebLeagueDetailPanelState extends State<WebLeagueDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WebLeagueDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.leagueId != widget.leagueId) {
      _tabs.animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Column(
      children: [
        // Header
        Glass(
          borderRadius: 0,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          fill: AppTheme.cardColor(brightness),
          border: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back to list',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.leagueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabs,
                labelColor: AppTheme.limeAccentDark,
                unselectedLabelColor:
                    AppTheme.secondaryText(brightness),
                indicatorColor: AppTheme.limeAccentDark,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Teams'),
                  Tab(text: 'Fixtures'),
                  Tab(text: 'Standings'),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _LeagueOverviewTab(
                leagueId: widget.leagueId,
                pairedUserUid: widget.pairedUserUid,
                brightness: brightness,
              ),
              _LeagueTeamsTab(
                leagueId: widget.leagueId,
                brightness: brightness,
              ),
              _LeagueFixturesTab(
                leagueId: widget.leagueId,
                pairedUserUid: widget.pairedUserUid,
                brightness: brightness,
              ),
              _LeagueStandingsTab(
                leagueId: widget.leagueId,
                brightness: brightness,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Overview tab ──────────────────────────────────────────────────────────────

class _LeagueOverviewTab extends StatelessWidget {
  final String leagueId;
  final String pairedUserUid;
  final Brightness brightness;
  const _LeagueOverviewTab({
    required this.leagueId,
    required this.pairedUserUid,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('leagues')
          .doc(leagueId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d      = snap.data!.data() ?? {};
        final name   = (d['name']   ?? '').toString();
        final region = (d['region'] ?? '').toString();
        final season = (d['season'] ?? '').toString();
        final format = (d['format'] ?? '').toString();
        final maxT   = ((d['maxTeams'] as num?) ?? 0).toInt();
        final desc   = (d['description'] ?? '').toString();
        final code   = (d['code'] ?? '').toString();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _InfoCard(brightness: brightness, children: [
              _InfoRow('Name', name, brightness),
              _InfoRow('Region', region, brightness),
              _InfoRow('Season', season, brightness),
              _InfoRow('Format', format, brightness),
              _InfoRow('Max Teams', '$maxT', brightness),
              if (code.isNotEmpty) _InfoRow('Code', code, brightness),
              if (desc.isNotEmpty)
                _InfoRow('Description', desc, brightness),
            ]),
            const SizedBox(height: 16),
            _AnnouncementsSection(
                leagueId: leagueId,
                pairedUserUid: pairedUserUid,
                brightness: brightness),
          ],
        );
      },
    );
  }
}

// ── Teams tab ─────────────────────────────────────────────────────────────────

class _LeagueTeamsTab extends StatelessWidget {
  final String leagueId;
  final Brightness brightness;
  const _LeagueTeamsTab({
    required this.leagueId,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.group_outlined,
            message: 'No teams yet',
            brightness: brightness,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d    = docs[i].data();
            final name = (d['name'] ?? d['teamName'] ?? 'Team')
                .toString();
            final members = ((d['memberCount'] as num?) ?? 0).toInt();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                borderRadius: 14,
                padding: const EdgeInsets.all(14),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.iconCircleBackground(brightness),
                      ),
                      child: Icon(Icons.shield_rounded,
                          color: AppTheme.limeAccentDark, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          style: TextStyle(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w800,
                          )),
                    ),
                    if (members > 0)
                      Text('$members members',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontSize: 12,
                          )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Fixtures tab ──────────────────────────────────────────────────────────────

class _LeagueFixturesTab extends StatefulWidget {
  final String leagueId;
  final String pairedUserUid;
  final Brightness brightness;
  const _LeagueFixturesTab({
    required this.leagueId,
    required this.pairedUserUid,
    required this.brightness,
  });

  @override
  State<_LeagueFixturesTab> createState() =>
      _LeagueFixturesTabState();
}

class _LeagueFixturesTabState extends State<_LeagueFixturesTab> {
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in ['all', 'pending', 'FINISHED'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s == 'all'
                          ? 'All'
                          : s == 'FINISHED'
                              ? 'Finished'
                              : 'Pending'),
                      selected: _statusFilter == s,
                      selectedColor: AppTheme.limeAccent,
                      onSelected: (_) =>
                          setState(() => _statusFilter = s),
                    ),
                  ),
              ],
            ),
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('leagues')
                .doc(widget.leagueId)
                .collection('matches')
                .orderBy('matchday')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator());
              }

              final all = snap.data!.docs;
              final filtered = _statusFilter == 'all'
                  ? all
                  : all.where((doc) {
                      final d = doc.data();
                      final status =
                          (d['status'] ?? d['matchStatus'] ?? '')
                              .toString();
                      final played = d['isPlayed'] == true;
                      if (_statusFilter == 'FINISHED') {
                        return status == 'FINISHED' || played;
                      }
                      return status != 'FINISHED' && !played;
                    }).toList();

              if (filtered.isEmpty) {
                return _EmptyState(
                  icon: Icons.sports_rounded,
                  message: 'No matches found',
                  brightness: widget.brightness,
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final d       = filtered[i].data();
                  final matchId = filtered[i].id;
                  final home    = (d['homeTeamName'] ??
                          d['homeName'] ??
                          'Home')
                      .toString();
                  final away    = (d['awayTeamName'] ??
                          d['awayName'] ??
                          'Away')
                      .toString();
                  final hScore  =
                      (d['homeScore'] as num?)?.toInt();
                  final aScore  =
                      (d['awayScore'] as num?)?.toInt();
                  final played  = d['isPlayed'] == true ||
                      (d['status'] ?? '') == 'FINISHED';
                  final matchday =
                      (d['matchday'] as num?)?.toInt() ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MatchCard(
                      matchId: matchId,
                      leagueId: widget.leagueId,
                      home: home,
                      away: away,
                      homeScore: hScore,
                      awayScore: aScore,
                      played: played,
                      matchday: matchday,
                      pairedUserUid: widget.pairedUserUid,
                      brightness: widget.brightness,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MatchCard extends StatefulWidget {
  final String matchId;
  final String leagueId;
  final String home;
  final String away;
  final int? homeScore;
  final int? awayScore;
  final bool played;
  final int matchday;
  final String pairedUserUid;
  final Brightness brightness;

  const _MatchCard({
    required this.matchId,
    required this.leagueId,
    required this.home,
    required this.away,
    required this.homeScore,
    required this.awayScore,
    required this.played,
    required this.matchday,
    required this.pairedUserUid,
    required this.brightness,
  });

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _editing = false;
  final _homeCtrl = TextEditingController();
  final _awayCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _homeCtrl.dispose();
    _awayCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveScore() async {
    final h = int.tryParse(_homeCtrl.text.trim());
    final a = int.tryParse(_awayCtrl.text.trim());
    if (h == null || a == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('matches')
          .doc(widget.matchId)
          .update({
        'homeScore': h,
        'awayScore': a,
        'isPlayed': true,
        'status': 'FINISHED',
        'matchStatus': 'FINISHED',
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving score: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;

    return Glass(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      fill: AppTheme.cardColor(b),
      borderColor: AppTheme.cardBorder(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Matchday label
          Text(
            'Matchday ${widget.matchday}',
            style: TextStyle(
              color: AppTheme.secondaryText(b),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),

          // Score row
          Row(
            children: [
              Expanded(
                child: Text(widget.home,
                    style: TextStyle(
                      color: AppTheme.primaryText(b),
                      fontWeight: FontWeight.w800,
                    )),
              ),
              if (widget.played && !_editing)
                Text(
                  '${widget.homeScore ?? 0} - ${widget.awayScore ?? 0}',
                  style: TextStyle(
                    color: AppTheme.primaryText(b),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                )
              else if (_editing)
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _homeCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(
                                  vertical: 6),
                        ),
                      ),
                    ),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6),
                      child: Text('-',
                          style: TextStyle(
                              fontWeight: FontWeight.w900)),
                    ),
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _awayCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(
                                  vertical: 6),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text('vs',
                    style: TextStyle(
                      color: AppTheme.secondaryText(b),
                      fontWeight: FontWeight.w700,
                    )),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.away,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: AppTheme.primaryText(b),
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_editing)
                TextButton.icon(
                  onPressed: () {
                    _homeCtrl.text =
                        '${widget.homeScore ?? 0}';
                    _awayCtrl.text =
                        '${widget.awayScore ?? 0}';
                    setState(() => _editing = true);
                  },
                  icon: const Icon(Icons.edit_rounded,
                      size: 14),
                  label: Text(
                    widget.played
                        ? 'Edit Score'
                        : 'Enter Score',
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              else ...[
                TextButton(
                  onPressed: _saving
                      ? null
                      : () =>
                          setState(() => _editing = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  onPressed: _saving ? null : _saveScore,
                  icon: _saving
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.darkText),
                        )
                      : const Icon(Icons.save_rounded,
                          size: 14),
                  label: const Text('Save',
                      style:
                          TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Standings tab ─────────────────────────────────────────────────────────────

class _LeagueStandingsTab extends StatelessWidget {
  final String leagueId;
  final Brightness brightness;
  const _LeagueStandingsTab({
    required this.leagueId,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .orderBy('points', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.leaderboard_rounded,
            message: 'No standings yet',
            brightness: brightness,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d      = docs[i].data();
            final name   = (d['name'] ?? d['teamName'] ?? 'Team')
                .toString();
            final pts    = ((d['points'] as num?) ?? 0).toInt();
            final played = ((d['played'] as num?) ?? 0).toInt();
            final won    = ((d['won'] as num?) ?? 0).toInt();
            final drawn  = ((d['drawn'] as num?) ?? 0).toInt();
            final lost   = ((d['lost'] as num?) ?? 0).toInt();
            final gd     = ((d['goalDifference'] as num?) ?? 0)
                .toInt();

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Glass(
                borderRadius: 12,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                fill: i == 0
                    ? AppTheme.limeAccentDark.withOpacity(0.10)
                    : AppTheme.cardColor(brightness),
                borderColor: i == 0
                    ? AppTheme.limeAccentDark
                    : AppTheme.cardBorder(brightness),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: i == 0
                              ? AppTheme.limeAccentDark
                              : AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(name,
                          style: TextStyle(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w800,
                          )),
                    ),
                    _StandingCell('P', '$played', brightness),
                    _StandingCell('W', '$won', brightness),
                    _StandingCell('D', '$drawn', brightness),
                    _StandingCell('L', '$lost', brightness),
                    _StandingCell('GD',
                        gd >= 0 ? '+$gd' : '$gd', brightness),
                    _StandingCell('Pts', '$pts', brightness,
                        bold: true),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StandingCell extends StatelessWidget {
  final String label;
  final String value;
  final Brightness brightness;
  final bool bold;
  const _StandingCell(this.label, this.value, this.brightness,
      {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              )),
          Text(value,
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontSize: 12,
                fontWeight:
                    bold ? FontWeight.w900 : FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

// ── Announcements section ─────────────────────────────────────────────────────

class _AnnouncementsSection extends StatefulWidget {
  final String leagueId;
  final String pairedUserUid;
  final Brightness brightness;
  const _AnnouncementsSection({
    required this.leagueId,
    required this.pairedUserUid,
    required this.brightness,
  });

  @override
  State<_AnnouncementsSection> createState() =>
      _AnnouncementsSectionState();
}

class _AnnouncementsSectionState
    extends State<_AnnouncementsSection> {
  final _titleCtrl   = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _posting      = false;
  bool _showForm     = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title   = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) return;

    setState(() => _posting = true);
    try {
      final now  = DateTime.now().millisecondsSinceEpoch;
      final docId = 'ann_${now}_${widget.pairedUserUid.substring(0, 6)}';
      await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('announcements')
          .doc(docId)
          .set({
        'id': docId,
        'leagueId': widget.leagueId,
        'title': title,
        'message': message,
        'createdAtMs': now,
        'authorId': widget.pairedUserUid,
        'authorName': 'Organizer',
        'scope': 'league',
      });
      _titleCtrl.clear();
      _messageCtrl.clear();
      if (mounted) setState(() => _showForm = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Announcements',
                style: TextStyle(
                  color: AppTheme.primaryText(b),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                )),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showForm = !_showForm),
              icon: Icon(
                  _showForm ? Icons.close_rounded : Icons.add_rounded,
                  size: 16),
              label:
                  Text(_showForm ? 'Cancel' : 'New'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_showForm) ...[
          Glass(
            borderRadius: 14,
            padding: const EdgeInsets.all(14),
            fill: AppTheme.cardColor(b),
            borderColor: AppTheme.cardBorder(b),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed: _posting ? null : _post,
                    icon: _posting
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.darkText),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 16),
                    label: const Text('Post Announcement',
                        style: TextStyle(
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('leagues')
              .doc(widget.leagueId)
              .collection('announcements')
              .orderBy('createdAtMs', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return Text('No announcements yet.',
                  style: TextStyle(
                      color: AppTheme.secondaryText(b)));
            }
            return Column(
              children: docs.map((doc) {
                final d       = doc.data();
                final title   = (d['title'] ?? '').toString();
                final message =
                    (d['message'] ?? '').toString();
                final ms      =
                    ((d['createdAtMs'] as num?) ?? 0).toInt();
                final dt      = ms > 0
                    ? DateTime.fromMillisecondsSinceEpoch(ms)
                    : null;
                final date    = dt != null
                    ? '${dt.day}/${dt.month}/${dt.year}'
                    : '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Glass(
                    borderRadius: 12,
                    padding: const EdgeInsets.all(12),
                    fill: AppTheme.cardColor(b),
                    borderColor: AppTheme.cardBorder(b),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title,
                                  style: TextStyle(
                                    color:
                                        AppTheme.primaryText(b),
                                    fontWeight: FontWeight.w800,
                                  )),
                            ),
                            Text(date,
                                style: TextStyle(
                                  color:
                                      AppTheme.secondaryText(b),
                                  fontSize: 11,
                                )),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(message,
                            style: TextStyle(
                              color: AppTheme.secondaryText(b),
                              height: 1.4,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final Brightness brightness;
  final List<Widget> children;
  const _InfoCard({required this.brightness, required this.children});

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Brightness brightness;
  const _InfoRow(this.label, this.value, this.brightness);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Brightness brightness;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 48,
              color: AppTheme.secondaryText(brightness)),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}
