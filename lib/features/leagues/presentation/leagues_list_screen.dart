import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:eleaguehub3/core/locale/app_localizations.dart';
import '../utils/current_user.dart';
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

class _LeaguesListScreenState extends ConsumerState<LeaguesListScreen> with AutomaticKeepAliveClientMixin {
  static const Color _premiumAmber = Color(0xFFF59E0B);

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
  bool _loadingAnnouncements = false;

  String? _payingLeagueId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _localRepo = LocalLeaguesRepository(prefs);
    _annRepo = LeagueAnnouncementsFirebase(prefs);

    // Initial load must be FAST and never hang on network.
    // We load local data only; remote sync happens only when user manually refreshes.
    // ignore: discarded_futures
    _loadLeagues(syncFirst: false, showSpinner: true);
  }

  Future<void> _loadLeagues({
    required bool syncFirst,
    required bool showSpinner,
  }) async {
    if (showSpinner) {
      if (!mounted) return;
      setState(() => _isLoading = true);
    }

    try {
      if (syncFirst) {
        // Never let a sync keep the UI stuck forever.
        try {
          await SyncService.instance.syncAll().timeout(const Duration(seconds: 20));
        } catch (e) {
          // ignore: avoid_print
          print('LeaguesListScreen: syncAll failed (non-fatal): $e');
        }
      }

      final leagues = await _localRepo.listLeagues();
      final prefs = ref.read(prefsServiceProvider);

      String effectiveUserId = prefs.getCurrentUserId() ?? '';
      if (effectiveUserId.trim().isEmpty) {
        effectiveUserId = await CurrentUser.getOrCreateUserId();
      }

      final chargesStore = LeagueChargesStore(prefs);
      final memberships = await _localRepo.listMemberships();

      final Map<String, int> counts = {};
      final Map<String, bool> viewerPaid = {};
      final Map<String, bool> viewerIsParticipant = {};

      // Local calculations only (fast).
      await Future.wait(
        leagues.map((league) async {
          final teams = await _localRepo.getTeams(league.id);

          final orphanMembersCount = memberships
              .where((m) => m.leagueId == league.id && m.role == LeagueRole.member && m.teamId == null)
              .length;

          counts[league.id] = teams.length + orphanMembersCount;

          viewerIsParticipant[league.id] = memberships.any(
            (m) =>
                m.leagueId == league.id &&
                m.userId == effectiveUserId &&
                (m.role == LeagueRole.member || m.role == LeagueRole.organizer),
          );

          final requiresCharges = league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;

          if (!requiresCharges) {
            viewerPaid[league.id] = true;
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
        _viewerChargesPaid = viewerPaid;
        _viewerIsParticipantByLeagueId = viewerIsParticipant;
        _effectiveUserId = effectiveUserId;
        _isLoading = false;
      });

      // Announcements may come from Firebase; do not block the "loaded" UI.
      // Load them best-effort in the background.
      unawaited(_loadLatestAnnouncements(leagues));
    } catch (e) {
      // If anything fails, never keep a perpetual spinner.
      if (!mounted) return;
      setState(() => _isLoading = false);
      // ignore: avoid_print
      print('LeaguesListScreen: load failed (non-fatal): $e');
    }
  }

  Future<void> _loadLatestAnnouncements(List<League> leagues) async {
    if (_loadingAnnouncements) return;
    _loadingAnnouncements = true;

    try {
      final Map<String, LeagueAnnouncement?> latestAnns = {};

      // Best-effort per-league fetch with timeouts so it can't hang.
      await Future.wait(leagues.map((league) async {
        try {
          final anns = await _annRepo.listForLeague(league.id).timeout(const Duration(seconds: 5));
          if (anns.isNotEmpty) {
            anns.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
            latestAnns[league.id] = anns.first;
          }
        } catch (_) {
          // Ignore per-league announcement failures (offline, timeout, etc.)
        }
      }));

      if (!mounted) return;
      setState(() {
        _latestAnnouncements = latestAnns;
      });
    } finally {
      _loadingAnnouncements = false;
    }
  }

  Future<void> _refreshLeagues() async {
    // Manual refresh: do a sync, then reload local data.
    await _loadLeagues(syncFirst: true, showSpinner: true);
  }

  Future<void> _payChargesForLeague(BuildContext context, League league) async {
    final l10n = context.l10n;

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
        SnackBar(
          content: Text(l10n.tr('leagues_creator_unlocked')),
          behavior: SnackBarBehavior.floating,
        ),
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
        final dialogTheme = Theme.of(ctx);
        final dialogCs = dialogTheme.colorScheme;

        return AlertDialog(
          backgroundColor: dialogCs.surface,
          title: Text(
            l10n.tr('leagues_unlock_dialog_title'),
            style: TextStyle(color: dialogCs.onSurface, fontWeight: FontWeight.w900),
          ),
          content: Text(
            '${l10n.tr('leagues_unlock_dialog_content_prefix')}\n\n${league.name}',
            style: TextStyle(color: dialogCs.onSurface.withOpacity(0.72), height: 1.35, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.tr('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.tr('common_pay')),
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
          SnackBar(
            content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed')),
            behavior: SnackBarBehavior.floating,
          ),
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
        SnackBar(
          content: Text(l10n.tr('leagues_unlocked_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _payingLeagueId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('leagues_payment_failed')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;

    final double fabBottomOffset = kBottomNavigationBarHeight + media.padding.bottom + 16;

    return GlassScaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(l10n.tr('leagues_my_leagues_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: l10n.tr('common_refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLeagues,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: fabBottomOffset),
        child: FloatingActionButton(
          onPressed: () => _showOptions(context),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
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
                        ? Center(
                            child: CircularProgressIndicator(
                              color: cs.primary,
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

  String _buildCardSubtitle({
    required BuildContext context,
    required League league,
    required int registered,
    required LeagueAnnouncement? latestAnn,
  }) {
    final l10n = context.l10n;

    final pieces = <String>[
      '$registered / ${league.maxTeams} ${l10n.tr('leagues_teams_word')}',
    ];

    // Viewer capacity (optional paid add-on)
    if (league.viewerCapacity > 0) {
      pieces.add('${league.viewerCapacity} Viewers');
    }

    // Description (optional)
    final desc = league.description.trim();
    if (desc.isNotEmpty) {
      pieces.add(desc);
    }

    if (latestAnn != null && latestAnn.title.trim().isNotEmpty) {
      pieces.add(latestAnn.title.trim());
    }

    return pieces.join(' • ');
  }

  Widget _buildLeagueList(
    BuildContext context,
    List<League> leagues,
    bool isTablet,
  ) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final prefs = ref.read(prefsServiceProvider);
    final String currentUserId = prefs.getCurrentUserId() ?? '';
    final String viewerId = _effectiveUserId.isNotEmpty ? _effectiveUserId : currentUserId;

    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 + media.padding.bottom + kBottomNavigationBarHeight;

    final mainAxisExtent = isTablet ? 230.0 : 210.0;

    return GridView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsetsDirectional.fromSTEB(16, 12, 16, bottomPadding),
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

        final subtitle = _buildCardSubtitle(
          context: context,
          league: league,
          registered: registered,
          latestAnn: latestAnn,
        );

        final payingThis = _payingLeagueId == league.id;

        return Stack(
          children: [
            LeagueFlipCard(
              leagueName: league.name,
              leagueCode: league.code.isNotEmpty ? league.code : league.id.substring(0, 8),
              distribution: "${l10n.tr(league.format.l10nKey)} • ${league.season}",
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

            // League image (optional) — list shows league image only.
            PositionedDirectional(
              bottom: 14,
              start: 14,
              child: _LeagueImageThumb(
                imageUrl: league.leagueImageUrl,
              ),
            ),

            if (isOwner)
              PositionedDirectional(
                top: 12,
                end: 12,
                child: _CardBadge(
                  label: l10n.tr('leagues_badge_owner'),
                  icon: Icons.admin_panel_settings,
                  color: cs.primary,
                  bg: cs.primary.withOpacity(0.18),
                  border: cs.primary.withOpacity(0.45),
                ),
              ),
            if (viewerIsViewerOnly)
              PositionedDirectional(
                top: 12,
                end: 12,
                child: _CardBadge(
                  label: l10n.tr('leagues_badge_viewer'),
                  icon: Icons.visibility,
                  color: cs.onSurface.withOpacity(0.72),
                  bg: cs.onSurface.withOpacity(0.08),
                  border: cs.onSurface.withOpacity(0.18),
                ),
              ),
            PositionedDirectional(
              top: 12,
              start: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFull)
                    _CardBadge(
                      label: l10n.tr('leagues_badge_full'),
                      icon: Icons.block,
                      color: cs.error,
                      bg: cs.error.withOpacity(0.14),
                      border: cs.error.withOpacity(0.40),
                    ),
                  if (isFull && showLockedBadge) const SizedBox(height: 6),
                  if (showLockedBadge)
                    _CardBadge(
                      label: l10n.tr('leagues_badge_locked'),
                      icon: Icons.lock_outline,
                      color: _premiumAmber,
                      bg: _premiumAmber.withOpacity(0.14),
                      border: _premiumAmber.withOpacity(0.40),
                    ),
                ],
              ),
            ),
            if (showLockedBadge)
              PositionedDirectional(
                bottom: 14,
                end: 14,
                child: SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: payingThis ? null : () => _payChargesForLeague(context, league),
                    style: FilledButton.styleFrom(
                      backgroundColor: _premiumAmber.withOpacity(0.92),
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
                        : Text(
                            l10n.tr('leagues_pay_button'),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final media = MediaQuery.of(context);
    final bottomPadding = 16.0 + media.padding.bottom + kBottomNavigationBarHeight;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, bottomPadding),
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
                    color: cs.onSurface.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                  ),
                  child: Icon(
                    Icons.emoji_events_outlined,
                    size: 64,
                    color: cs.primary.withOpacity(0.92),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.tr('leagues_empty_title'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    fontSize: 22,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('leagues_empty_subtitle'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _showOptions(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.tr('leagues_empty_cta')),
                  style: FilledButton.styleFrom(
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          l10n.tr('leagues_options_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Divider(color: cs.onSurface.withOpacity(0.12)),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primary,
                          child: Icon(Icons.add, color: cs.onPrimary),
                        ),
                        title: Text(
                          l10n.tr('leagues_options_create_title'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          l10n.tr('leagues_options_create_subtitle'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                          backgroundColor: cs.onSurface.withOpacity(0.08),
                          child: Icon(
                            Icons.qr_code_scanner,
                            color: cs.onSurface,
                          ),
                        ),
                        title: Text(
                          l10n.tr('leagues_options_join_qr_title'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          l10n.tr('leagues_options_join_qr_subtitle'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                          backgroundColor: cs.onSurface.withOpacity(0.08),
                          child: Icon(
                            Icons.key,
                            color: cs.onSurface,
                          ),
                        ),
                        title: Text(
                          l10n.tr('leagues_options_join_id_title'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          l10n.tr('leagues_options_join_id_subtitle'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
    final l10n = context.l10n;

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
        setModalState(() => error = l10n.tr('leagues_join_id_required'));
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
              name: l10n.tr('leagues_joined_league_placeholder_name'),
              format: LeagueFormat.classic,
              privacy: LeaguePrivacy.private,
              region: l10n.tr('common_region_global'),
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

        final Membership? membership = await repo.getMembership(leagueId: league.id, userId: userId);
        final effectiveMode = (membership != null) ? LeagueJoinMode.participant : LeagueJoinMode.viewer;

        if (!context.mounted) return;
        Navigator.of(context).pop();

        if (!context.mounted) return;

        String message;

        final bool adminAlreadyAdded = membership != null && (membership.teamId?.trim().isNotEmpty == true);

        if (adminAlreadyAdded) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr('leagues_join_snackbar_viewer_but_already_added')
              : l10n.tr('leagues_join_snackbar_already_added');
        } else if (membership != null) {
          message = (mode == LeagueJoinMode.viewer)
              ? l10n.tr('leagues_join_snackbar_viewer_but_already_registered')
              : l10n.tr('leagues_join_snackbar_already_registered');
        } else if (mode == LeagueJoinMode.participant && effectiveMode == LeagueJoinMode.viewer) {
          message = l10n.tr('leagues_join_snackbar_league_full_joined_viewer');
        } else if (mode == LeagueJoinMode.viewer) {
          message = l10n.tr('leagues_join_snackbar_joined_viewer');
        } else {
          message = l10n.tr('leagues_join_snackbar_joined_participant');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
          final theme = Theme.of(ctx);
          final cs = theme.colorScheme;
          final onSurface = cs.onSurface;

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
                              Text(
                                l10n.tr('leagues_join_sheet_title'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.tr('leagues_join_sheet_subtitle'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: onSurface.withOpacity(0.70),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                textCapitalization: TextCapitalization.characters,
                                style: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
                                decoration: InputDecoration(
                                  hintText: l10n.tr('leagues_join_hint'),
                                  prefixIcon: const Icon(Icons.key),
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
                                      Text(
                                        l10n.tr('leagues_join_as_title'),
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: onSurface,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ChoiceChip(
                                              label: Text(l10n.tr('leagues_join_participant')),
                                              selected: mode == LeagueJoinMode.participant,
                                              onSelected: joining
                                                  ? null
                                                  : (v) {
                                                      if (!v) return;
                                                      setModalState(() => mode = LeagueJoinMode.participant);
                                                    },
                                              selectedColor: cs.primary.withOpacity(0.18),
                                              backgroundColor: onSurface.withOpacity(0.06),
                                              labelStyle: TextStyle(
                                                color: mode == LeagueJoinMode.participant ? cs.primary : onSurface.withOpacity(0.72),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ChoiceChip(
                                              label: Text(l10n.tr('leagues_join_viewer_only')),
                                              selected: mode == LeagueJoinMode.viewer,
                                              onSelected: joining
                                                  ? null
                                                  : (v) {
                                                      if (!v) return;
                                                      setModalState(() => mode = LeagueJoinMode.viewer);
                                                    },
                                              selectedColor: onSurface.withOpacity(0.10),
                                              backgroundColor: onSurface.withOpacity(0.06),
                                              labelStyle: TextStyle(
                                                color: mode == LeagueJoinMode.viewer ? onSurface : onSurface.withOpacity(0.72),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        mode == LeagueJoinMode.viewer
                                            ? l10n.tr('leagues_join_as_viewer_description')
                                            : l10n.tr('leagues_join_as_participant_description'),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: onSurface.withOpacity(0.70),
                                          fontSize: 11,
                                          height: 1.25,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                      child: Text(l10n.tr('common_cancel')),
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
                                      label: Text(joining ? l10n.tr('common_joining') : l10n.tr('common_join')),
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

class _LeagueImageThumb extends StatelessWidget {
  const _LeagueImageThumb({
    required this.imageUrl,
  });

  final String imageUrl;

  Uint8List? _tryDecodeDataUri(String raw) {
    final s = raw.trim();
    if (!s.startsWith('data:image')) return null;
    final idx = s.indexOf('base64,');
    if (idx < 0) return null;
    final b64 = s.substring(idx + 'base64,'.length);
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final url = imageUrl.trim();
    final bytes = url.isEmpty ? null : _tryDecodeDataUri(url);

    final Widget content;

    if (bytes != null) {
      content = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (url.isNotEmpty) {
      content = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Icon(Icons.emoji_events_outlined, color: cs.onSurface.withOpacity(0.65));
        },
        loadingBuilder: (context, child, event) {
          if (event == null) return child;
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary.withOpacity(0.85),
              ),
            ),
          );
        },
      );
    } else {
      content = Icon(Icons.emoji_events_outlined, color: cs.onSurface.withOpacity(0.65));
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        border: Border.all(color: cs.onSurface.withOpacity(0.14)),
      ),
      child: ClipOval(child: Center(child: content)),
    );
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
