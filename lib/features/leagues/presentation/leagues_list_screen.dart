import 'package:eleaguehub3/core/services/sync_trigger.dart';
import '../utils/current_user.dart';
import "package:eleaguehub3/core/app/sync_debug_screen.dart";
import 'package:eleaguehub3/features/leagues/logic/league_charges_payment_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_store.dart';
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

  /// per league paid charges for the CURRENT viewer (used only for UI lock badges/buttons)
  Map<String, bool> _viewerChargesPaid = {};

  /// Whether the CURRENT viewer has a participant membership in this league.
  /// If false (and not owner), they are considered a VIEWER-only for UI badge purposes.
  Map<String, bool> _viewerIsParticipantByLeagueId = {};

  /// resolved viewer id (so owner/lock UI is accurate even if prefs.current_user_id is empty)
  String _effectiveUserId = '';

  bool _isLoading = true;

  String? _payingLeagueId;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _localRepo = LocalLeaguesRepository(prefs);
    _annRepo = LeagueAnnouncementsFirebase(prefs);

    // ignore: discarded_futures
    SyncTrigger.trySync().then((_) => _refreshLeagues());
    _refreshLeagues();
  }

  Future<void> _refreshLeagues() async {
    setState(() {
      _isLoading = true;
    });

    await SyncService.instance.syncAll();

    final leagues = await _localRepo.listLeagues();

    final prefs = ref.read(prefsServiceProvider);

    String effectiveUserId = prefs.getCurrentUserId() ?? '';
    if (effectiveUserId.trim().isEmpty) {
      effectiveUserId = await CurrentUser.getOrCreateUserId();
    }

    final chargesStore = LeagueChargesStore(prefs);

    final memberships = await _localRepo.listMemberships();

    final Map<String, int> counts = {};
    final Map<String, LeagueAnnouncement?> latestAnns = {};
    final Map<String, bool> viewerPaid = {};
    final Map<String, bool> viewerIsParticipant = {};

    await Future.wait(
      leagues.map((league) async {
        final teams = await _localRepo.getTeams(league.id);

        final orphanMembersCount = memberships
            .where((m) => m.leagueId == league.id && m.role == LeagueRole.member && m.teamId == null)
            .length;

        counts[league.id] = teams.length + orphanMembersCount;

        // Viewer participation badge detection (local membership presence)
        viewerIsParticipant[league.id] = memberships.any(
          (m) =>
              m.leagueId == league.id &&
              m.userId == effectiveUserId &&
              (m.role == LeagueRole.member || m.role == LeagueRole.organizer),
        );

        final anns = await _annRepo.listForLeague(league.id);
        if (anns.isNotEmpty) {
          anns.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
          latestAnns[league.id] = anns.first;
        }

        final requiresCharges = league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;

        if (!requiresCharges) {
          viewerPaid[league.id] = true; // classic is always “unlocked”
        } else {
          viewerPaid[league.id] = chargesStore.hasPaidCharges(
            userId: effectiveUserId,
            leagueId: league.id,
          );
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      _leagues = leagues;
      _participantCounts = counts;
      _latestAnnouncements = latestAnns;
      _viewerChargesPaid = viewerPaid;
      _viewerIsParticipantByLeagueId = viewerIsParticipant;
      _effectiveUserId = effectiveUserId;
      _isLoading = false;
    });
  }

  Future<void> _payChargesForLeague(BuildContext context, League league) async {
    if (_payingLeagueId == league.id) return;

    final prefs = ref.read(prefsServiceProvider);
    String userId = _effectiveUserId;
    if (userId.trim().isEmpty) {
      userId = prefs.getCurrentUserId() ?? '';
    }
    if (userId.trim().isEmpty) {
      userId = await CurrentUser.getOrCreateUserId();
    }

    final requiresCharges = league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;
    if (!requiresCharges) return;

    if (league.organizerUserId == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are the league creator. Access is already unlocked.')),
      );
      return;
    }

    final store = LeagueChargesStore(prefs);
    final alreadyPaid = store.hasPaidCharges(userId: userId, leagueId: league.id);
    if (alreadyPaid) {
      setState(() {
        _viewerChargesPaid[league.id] = true;
      });
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1D37),
          title: const Text(
            'Unlock this league',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Pay charges to unlock Fixtures and Standings for:\n\n${league.name}',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Pay'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _payingLeagueId = league.id);

    try {
      final paymentService = ref.read(leagueChargesPaymentServiceProvider);

      final result = await paymentService.payLeagueCharges(
        context: context,
        userId: userId,
        leagueId: league.id,
        leagueName: league.name,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() => _payingLeagueId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? 'Payment failed')),
        );
        return;
      }

      final receipt = LeagueChargesReceipt(
        leagueId: league.id,
        userId: userId,
        receiptId: result.receiptId ?? '',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await store.storeReceipt(receipt);

      if (!mounted) return;

      setState(() {
        _payingLeagueId = null;
        _viewerChargesPaid[league.id] = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlocked successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _payingLeagueId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;

    final double fabBottomOffset = kBottomNavigationBarHeight + media.padding.bottom + 16;

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
    final String currentUserId = prefs.getCurrentUserId() ?? '';
    final String viewerId = _effectiveUserId.isNotEmpty ? _effectiveUserId : currentUserId;

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

        final bool isOwner = league.organizerUserId == viewerId || league.organizerUserId == currentUserId;

        final bool viewerIsParticipant = _viewerIsParticipantByLeagueId[league.id] ?? false;
        final bool viewerIsViewerOnly = !isOwner && !viewerIsParticipant;

        final requiresCharges = league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;
        final paid = _viewerChargesPaid[league.id] ?? false;
        final showLockedBadge = requiresCharges && !isOwner && !paid;

        final registered = _participantCounts[league.id] ?? 0;
        final isFull = registered >= league.maxTeams;

        final latestAnn = _latestAnnouncements[league.id];
        final baseSubtitle = '$registered / ${league.maxTeams} teams';
        final subtitle = latestAnn != null ? '$baseSubtitle • ${latestAnn.title}' : baseSubtitle;

        final payingThis = _payingLeagueId == league.id;

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

            // OWNER badge
            if (isOwner)
              Positioned(
                top: 12,
                right: 12,
                child: _CardBadge(
                  label: 'OWNER',
                  icon: Icons.admin_panel_settings,
                  color: Colors.cyanAccent,
                  bg: Colors.cyanAccent.withOpacity(0.20),
                  border: Colors.cyanAccent.withOpacity(0.50),
                ),
              ),

            // VIEWER badge (not a participant)
            if (viewerIsViewerOnly)
              Positioned(
                top: 12,
                right: 12,
                child: _CardBadge(
                  label: 'VIEWER',
                  icon: Icons.visibility,
                  color: Colors.white70,
                  bg: Colors.white.withOpacity(0.10),
                  border: Colors.white.withOpacity(0.22),
                ),
              ),

            // LEFT badges stack (FULL / LOCKED)
            Positioned(
              top: 12,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFull)
                    _CardBadge(
                      label: 'FULL',
                      icon: Icons.block,
                      color: Colors.redAccent,
                      bg: Colors.redAccent.withOpacity(0.16),
                      border: Colors.redAccent.withOpacity(0.45),
                    ),
                  if (isFull && showLockedBadge) const SizedBox(height: 6),
                  if (showLockedBadge)
                    _CardBadge(
                      label: 'LOCKED',
                      icon: Icons.lock_outline,
                      color: Colors.orangeAccent,
                      bg: Colors.orangeAccent.withOpacity(0.16),
                      border: Colors.orangeAccent.withOpacity(0.45),
                    ),
                ],
              ),
            ),

            // PAY button if locked
            if (showLockedBadge)
              Positioned(
                bottom: 14,
                right: 14,
                child: SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: payingThis ? null : () => _payChargesForLeague(context, league),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orangeAccent.withOpacity(0.92),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: payingThis
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text(
                            'PAY',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                          ),
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
                          await _showJoinByIdSheet(context);
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

  Future<void> _showJoinByIdSheet(BuildContext context) async {
    final controller = TextEditingController();
    LeagueJoinMode mode = LeagueJoinMode.participant;
    String? error;
    bool joining = false;

    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);
    final userId = await CurrentUser.getOrCreateUserId();

    Future<void> doJoin(StateSetter setModalState) async {
      final code = controller.text.trim().toUpperCase();
      if (code.isEmpty) {
        setModalState(() => error = 'Join ID is required');
        return;
      }

      setModalState(() {
        joining = true;
        error = null;
      });

      try {
        final league = await repo.joinLeagueLocallyByCode(
          joinCode: code,
          userId: userId,
          mode: mode,
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
              settings: LeagueSettings.defaultsFor(LeagueFormat.classic).copyWith(lastPulledAtMs: now),
              updatedAtMs: now,
              version: 1,
            );
          },
        );

        // Determine effective mode (participant may be blocked if league is full).
        final membership = await repo.getMembership(leagueId: league.id, userId: userId);
        final effectiveMode = (membership != null) ? LeagueJoinMode.participant : LeagueJoinMode.viewer;

        if (!context.mounted) return;
        Navigator.of(context).pop();

        if (!context.mounted) return;

        if (mode == LeagueJoinMode.participant && effectiveMode == LeagueJoinMode.viewer) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('League is full. You joined as Viewer only.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (mode == LeagueJoinMode.viewer) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Joined as Viewer only.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Joined as Participant.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        setModalState(() {
          joining = false;
          error = '$e';
        });
      }
    }

    try {
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
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Glass(
                    borderRadius: 28,
                    child: StatefulBuilder(
                      builder: (ctx, setModalState) {
                        return Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Join League',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Enter Join ID, then choose how you want to join.',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  hintText: 'e.g. ABC123',
                                  hintStyle: const TextStyle(color: Colors.white38),
                                  prefixIcon: const Icon(Icons.key, color: Colors.white70),
                                  errorText: error,
                                ),
                                onChanged: (_) {
                                  if (error != null) setModalState(() => error = null);
                                },
                              ),
                              const SizedBox(height: 12),
                              Glass(
                                borderRadius: 20,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Join as',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ChoiceChip(
                                              label: const Text('Participant'),
                                              selected: mode == LeagueJoinMode.participant,
                                              onSelected: joining
                                                  ? null
                                                  : (v) {
                                                      if (!v) return;
                                                      setModalState(() => mode = LeagueJoinMode.participant);
                                                    },
                                              selectedColor: Colors.cyanAccent.withOpacity(0.25),
                                              backgroundColor: Colors.white10,
                                              labelStyle: TextStyle(
                                                color: mode == LeagueJoinMode.participant ? Colors.cyanAccent : Colors.white70,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ChoiceChip(
                                              label: const Text('Viewer only'),
                                              selected: mode == LeagueJoinMode.viewer,
                                              onSelected: joining
                                                  ? null
                                                  : (v) {
                                                      if (!v) return;
                                                      setModalState(() => mode = LeagueJoinMode.viewer);
                                                    },
                                              selectedColor: Colors.white.withOpacity(0.12),
                                              backgroundColor: Colors.white10,
                                              labelStyle: TextStyle(
                                                color: mode == LeagueJoinMode.viewer ? Colors.white : Colors.white70,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        mode == LeagueJoinMode.viewer
                                            ? 'Viewer-only: you can browse the league but you won’t be counted as a participant.'
                                            : 'Participant: you will be counted as a participant in this league (if there is space).',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.25),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: joining ? null : () => Navigator.of(ctx).pop(),
                                      child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: joining ? null : () => doJoin(setModalState),
                                      icon: joining
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.login),
                                      label: Text(joining ? 'Joining…' : 'Join'),
                                    ),
                                  ),
                                ],
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
    } finally {
      controller.dispose();
    }
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
