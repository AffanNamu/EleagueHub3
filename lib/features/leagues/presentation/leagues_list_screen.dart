import '../utils/current_user.dart';
import "package:eleaguehub3/core/app/sync_debug_screen.dart";
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/league.dart';
import 'package:eleaguehub3/features/leagues/models/league_settings.dart';
import 'package:eleaguehub3/features/leagues/models/membership.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/league_format.dart';
import '../models/league_announcement.dart';
import '../data/leagues_repository_local.dart';
import '../data/league_announcements_local.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/glass_search_bar.dart';
import '../../../widgets/league_flip_card.dart';
import '../../../core/services/sync_service.dart';

class LeaguesListScreen extends ConsumerStatefulWidget {
  const LeaguesListScreen({super.key});

  @override
  ConsumerState<LeaguesListScreen> createState() => _LeaguesListScreenState();
}

class _LeaguesListScreenState extends ConsumerState<LeaguesListScreen> {
  late LocalLeaguesRepository _localRepo;
  late LeagueAnnouncementsFirebase _annRepo;

  List<League> _leagues = [];

  Map<String, int> _participantCounts = {};
  Map<String, LeagueAnnouncement?> _latestAnnouncements = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _localRepo = LocalLeaguesRepository(prefs);
    _annRepo = LeagueAnnouncementsFirebase(prefs);
    _refreshLeagues();
  }

  Future<void> _refreshLeagues() async {
    setState(() {
      _isLoading = true;
    });

    // Try pulling latest from cloud to local first (if online)
    await SyncService.instance.syncAll();

    final leagues = await _localRepo.listLeagues();

    // NOTE: Your current file references memberships/teams methods that are not shown here.
    // If those methods exist in your LocalLeaguesRepository in your real codebase,
    // keep them. If not, remove the membership/team counting section.
    //
    // For now we keep your original logic but it requires:
    // - _localRepo.listMemberships()
    // - _localRepo.getTeams(league.id)

    final memberships = await _localRepo.listMemberships();

    final Map<String, int> counts = {};
    final Map<String, LeagueAnnouncement?> latestAnns = {};

    await Future.wait(
      leagues.map((league) async {
        final teams = await _localRepo.getTeams(league.id);

        final orphanMembersCount = memberships
            .where((m) =>
                m.leagueId == league.id &&
                m.role == LeagueRole.member &&
                m.teamId == null)
            .length;

        counts[league.id] = teams.length + orphanMembersCount;

        final anns = await _annRepo.listForLeague(league.id);
        if (anns.isNotEmpty) {
          anns.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
          latestAnns[league.id] = anns.first;
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      _leagues = leagues;
      _participantCounts = counts;
      _latestAnnouncements = latestAnns;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;

    final double fabBottomOffset =
        kBottomNavigationBarHeight + media.padding.bottom + 16;

    return GlassScaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('My Leagues'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncDebugScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLeagues,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: fabBottomOffset),
        child: FloatingActionButton(
          onPressed: () => _showOptions(context),
          backgroundColor: Colors.cyanAccent,
          foregroundColor: Colors.black,
          child: const Icon(Icons.add),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isTablet ? 900 : 600,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                const GlassSearchBar(),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.cyanAccent,
                            ),
                          )
                        : _leagues.isEmpty
                            ? _buildEmptyState(context)
                            : _buildLeagueList(context, _leagues, isTablet),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeagueList(
    BuildContext context,
    List<League> leagues,
    bool isTablet,
  ) {
    final prefs = ref.read(prefsServiceProvider);
    final String currentUserId = prefs.getCurrentUserId() ?? 'admin_user';

    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 + media.padding.bottom + kBottomNavigationBarHeight;

    final mainAxisExtent = isTablet ? 230.0 : 210.0;

    return GridView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 2 : 1,
        mainAxisSpacing: 20,
        crossAxisSpacing: 16,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: leagues.length,
      itemBuilder: (context, index) {
        final league = leagues[index];
        final bool isOwner = league.organizerUserId == currentUserId;

        final registered = _participantCounts[league.id] ?? 0;
        final latestAnn = _latestAnnouncements[league.id];
        final baseSubtitle = '$registered / ${league.maxTeams} teams';
        final subtitle = latestAnn != null ? '$baseSubtitle • ${latestAnn.title}' : baseSubtitle;

        return Stack(
          children: [
            LeagueFlipCard(
              leagueName: league.name,
              leagueCode: league.code.isNotEmpty ? league.code : league.id.substring(0, 8),
              distribution: "${league.format.displayName} • ${league.season}",
              subtitle: subtitle,
              onDoubleTap: () => context.push('/leagues/${league.id}'),
              qrWidget: QrImageView(
                data: league.qrPayload,
                version: QrVersions.auto,
                gapless: true,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            if (isOwner)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.5),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        size: 12,
                        color: Colors.cyanAccent,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'OWNER',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 + media.padding.bottom + kBottomNavigationBarHeight;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
        child: Glass(
          borderRadius: 32,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.emoji_events_outlined,
                    size: 64,
                    color: Colors.cyanAccent.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'No Leagues Found',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Create a new tournament or join one using a code to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _showOptions(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Get Started'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    minimumSize: const Size(200, 50),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final media = MediaQuery.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          minimum: EdgeInsets.only(
            bottom: media.padding.bottom + kBottomNavigationBarHeight,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Glass(
                borderRadius: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'League Options',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white10),
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.cyanAccent,
                          child: Icon(Icons.add, color: Colors.black),
                        ),
                        title: const Text(
                          'Create New League',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Start a fresh tournament',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () async {
                          context.pop();
                          await context.push('/leagues/create');
                          _refreshLeagues();
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Colors.white,
                          ),
                        ),
                        title: const Text(
                          'Join via QR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Scan a QR code',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () async {
                          context.pop();
                          await context.push('/leagues/join-scanner');
                          if (mounted) _refreshLeagues();
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          child: const Icon(
                            Icons.key,
                            color: Colors.white,
                          ),
                        ),
                        title: const Text(
                          'Join by ID',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Enter Join ID code',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () async {
                          context.pop();
                          await _showJoinByIdDialog(context);
                          if (mounted) _refreshLeagues();
                        },
                      ),
                      const SizedBox(height: 16),
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

  Future<void> _showJoinByIdDialog(BuildContext context) async {
    final controller = TextEditingController();
    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);
    final userId = await CurrentUser.getOrCreateUserId();

    try {
      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1D37),
            title: const Text(
              'Join by ID',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter Join ID',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final code = controller.text.trim().toUpperCase();
                  if (code.isEmpty) return;

                  await repo.joinLeagueLocallyByCode(
                    joinCode: code,
                    userId: userId,
                    placeholderBuilder: (generatedLeagueId) {
                      final now = DateTime.now().millisecondsSinceEpoch;
                      return League(
                        id: generatedLeagueId,
                        name: 'Joined League',
                        format: LeagueFormat.classic,
                        privacy: LeaguePrivacy.private,
                        region: 'Global',
                        maxTeams: 20,
                        season: '2026',
                        organizerUserId: '',
                        code: code,
                        qrPayloadOverride: '',
                        settings: LeagueSettings.defaultsFor(LeagueFormat.classic)
                            .copyWith(lastPulledAtMs: now),
                        updatedAtMs: now,
                        version: 1,
                      );
                    },
                  );

                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('Join'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}
