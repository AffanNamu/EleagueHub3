import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eleaguehub3/core/errors/user_friendly_error.dart';
import 'package:eleaguehub3/core/locale/app_localizations.dart';
import 'package:eleaguehub3/features/leagues/logic/league_creation_payment_service.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/league.dart';
import 'package:eleaguehub3/features/leagues/models/league_announcement.dart';
import 'package:eleaguehub3/features/leagues/models/league_format.dart';
import 'package:eleaguehub3/features/leagues/models/league_settings.dart';
import 'package:eleaguehub3/features/leagues/models/membership.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';

enum _LeagueViewTab { leagues, master }

class LeaguesListScreen extends ConsumerStatefulWidget {
  const LeaguesListScreen({super.key});

  @override
  ConsumerState<LeaguesListScreen> createState() => _LeaguesListScreenState();
}

class _LeaguesListScreenState extends ConsumerState<LeaguesListScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color _premiumAmber = Color(0xFFF59E0B);
  static const int _freeLeagueListLimit = 3;

  late final LocalLeaguesRepository _repo;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TextEditingController _searchController;

  List<League> _leagues = [];
  Map<String, int> _participantCounts = {};
  Map<String, LeagueAnnouncement?> _latestAnnouncements = {};
  Map<String, bool> _viewerIsParticipantByLeagueId = {};

  String _effectiveUserId = '';
  bool _isLoading = true;
  bool _loadingAnnouncements = false;
  bool _isPremiumUser = false;

  String? _removingLeagueId;
  String _searchQuery = '';
  _LeagueViewTab _selectedTab = _LeagueViewTab.leagues;

  @override
  bool get wantKeepAlive => true;

  String _authUidOrEmpty() => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  bool _isOwnerForViewer(League league, String viewerUid) {
    final v = viewerUid.trim();
    if (v.isEmpty) return false;

    final orgUid = league.organizerUid.trim();
    if (orgUid.isNotEmpty) return orgUid == v;

    final legacy = league.organizerUserId.trim();
    return legacy.isNotEmpty && legacy == v && _looksLikeFirebaseUid(legacy);
  }

  bool get _freeLimitReached =>
      !_isPremiumUser && _leagues.length >= _freeLeagueListLimit;

  String _freeLimitMessage([String action = 'add more leagues']) {
    return 'Free users can only have $_freeLeagueListLimit leagues total on the leagues screen. Upgrade to Premium to $action.';
  }

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchChanged);
    _loadLeagues(showSpinner: true);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text;
    if (next == _searchQuery) return;
    if (!mounted) return;
    setState(() => _searchQuery = next);
  }

  Future<bool> _detectPremiumUser(String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return false;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
      final claims = token?.claims ?? const <String, dynamic>{};

      final isPremium = claims['isPremium'] == true || claims['premium'] == true;
      if (isPremium) return true;

      final premiumExpiresAtMs = claims['premiumExpiresAtMs'];
      if (premiumExpiresAtMs is int &&
          premiumExpiresAtMs > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
      if (premiumExpiresAtMs is num &&
          premiumExpiresAtMs.toInt() > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {}

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      final data = userDoc.data() ?? const <String, dynamic>{};
      if (data['isPremium'] == true) return true;

      final expires = data['premiumExpiresAtMs'];
      if (expires is int && expires > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
      if (expires is num &&
          expires.toInt() > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openPremiumUpgradeFlow() async {
    if (_isPremiumUser) {
      _snack('Premium is already active on your account.');
      return;
    }

    final result = await context.push<LeagueCreationPaymentResult?>(
      '/leagues/create/payment',
      extra: <String, dynamic>{
        'premiumUpgrade': true,
        'leagueName': 'Organizer Premium',
      },
    );

    if (!mounted) return;

    if (result != null && result.success) {
      _snack('Premium upgrade payment completed. Refreshing access...');
      await _refreshLeagues();
      return;
    }

    if (result == null) {
      _snack('Premium upgrade cancelled.');
      return;
    }

    _snack(result.errorMessage ?? 'Premium upgrade failed.');
  }

  Future<void> _loadLeagues({required bool showSpinner}) async {
    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final effectiveUserId = _authUidOrEmpty();
      if (effectiveUserId.isEmpty) {
        throw FirebaseAuthException(code: 'unauthenticated');
      }

      final premium = await _detectPremiumUser(effectiveUserId);

      final leagues = await _repo.listLeagues().timeout(const Duration(seconds: 20));
      final memberships = await _repo.listMemberships().timeout(const Duration(seconds: 25));

      final Map<String, int> counts = {};
      final Map<String, bool> viewerIsParticipant = {};

      await Future.wait(
        leagues.map((league) async {
          final registered = await _countParticipantsRemote(league.id);
          counts[league.id] = registered;

          final isParticipant = memberships.any(
            (m) =>
                m.leagueId == league.id &&
                m.userId == effectiveUserId &&
                (m.role == LeagueRole.member || m.role == LeagueRole.organizer),
          );
          viewerIsParticipant[league.id] = isParticipant;
        }),
      );

      if (!mounted) return;

      setState(() {
        _leagues = leagues;
        _participantCounts = counts;
        _viewerIsParticipantByLeagueId = viewerIsParticipant;
        _effectiveUserId = effectiveUserId;
        _isPremiumUser = premium;
        _isLoading = false;
      });

      unawaited(_loadLatestAnnouncements(leagues));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  Future<void> _loadLatestAnnouncements(List<League> leagues) async {
    if (_loadingAnnouncements) return;
    _loadingAnnouncements = true;

    try {
      final Map<String, LeagueAnnouncement?> latestAnns = {};

      await Future.wait(leagues.map((league) async {
        try {
          final snap = await _firestore
              .collection('leagues')
              .doc(league.id)
              .collection('announcements')
              .orderBy('createdAtMs', descending: true)
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 6));

          if (snap.docs.isEmpty) return;
          latestAnns[league.id] =
              LeagueAnnouncement.fromMap(snap.docs.first.data());
        } catch (_) {}
      }));

      if (!mounted) return;
      setState(() => _latestAnnouncements = latestAnns);
    } finally {
      _loadingAnnouncements = false;
    }
  }

  Future<void> _refreshLeagues() async {
    await _loadLeagues(showSpinner: true);
  }

  DocumentReference<Map<String, dynamic>> _leagueRef(String leagueId) =>
      _firestore.collection('leagues').doc(leagueId);

  CollectionReference<Map<String, dynamic>> _membershipsCol(String leagueId) =>
      _leagueRef(leagueId).collection('memberships');

  Future<int> _countParticipantsRemote(String leagueId) async {
    final snap = await _membershipsCol(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    var count = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final uid = (data['userId'] as String?)?.trim() ?? '';
      final roleIdx = (data['role'] as num?)?.toInt();
      final isParticipantRole =
          roleIdx == LeagueRole.organizer.index || roleIdx == LeagueRole.member.index;

      if (uid.isNotEmpty && isParticipantRole) {
        count++;
      }
    }
    return count;
  }

  Future<void> _showLeagueLongPressMenu(
    BuildContext context,
    League league,
  ) async {
    final authUid = _authUidOrEmpty();
    final isOwner = _isOwnerForViewer(league, authUid);

    if (isOwner) {
      _snack('League owners should manage their league from the owner/admin area.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final cs = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        league.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        league.isInsideMasterLeague
                            ? 'This competition belongs to a master league workspace. You can still remove it from your personal list.'
                            : 'You can remove this league from your list if you no longer need it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.68),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            await _leaveLeague(league);
                          },
                          icon: const Icon(Icons.exit_to_app_rounded),
                          label: const Text(
                            'Remove from My List',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      if (league.isInsideMasterLeague &&
                          league.masterLeagueId.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.of(sheetCtx).pop();
                              context.push('/master-leagues/${league.masterLeagueId}');
                            },
                            icon: const Icon(Icons.hub_rounded),
                            label: const Text(
                              'Open Workspace',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _leaveLeague(League league) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.exit_to_app_rounded, color: cs.primary, size: 34),
                    const SizedBox(height: 10),
                    Text(
                      'Remove league from your list?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You will leave "${league.name}" and it will no longer appear on your leagues screen.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.70),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text(
                              'Remove',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    if (mounted) {
      setState(() => _removingLeagueId = league.id);
    }

    try {
      await _repo.leaveLeague(league.id);
      if (!mounted) return;
      _snack('League removed from your list.');
      await _refreshLeagues();
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) {
        setState(() => _removingLeagueId = null);
      }
    }
  }

  Future<void> _handleCreateLeagueTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await context.push('/leagues/create');
    if (mounted) {
      await _refreshLeagues();
    }
  }

  Future<void> _handleJoinQrTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await context.push('/leagues/join-scanner');
    if (mounted) {
      await _refreshLeagues();
    }
  }

  Future<void> _handleJoinByIdTap(BuildContext context) async {
    if (_freeLimitReached) {
      await _openPremiumUpgradeFlow();
      return;
    }

    await _showJoinByIdSheet(context);
    if (mounted) {
      await _refreshLeagues();
    }
  }

  List<League> _filteredLeagues() {
    final q = _searchQuery.trim().toLowerCase();

    final base = _selectedTab == _LeagueViewTab.leagues
        ? _leagues.where((l) => !l.isInsideMasterLeague).toList()
        : _leagues.where((l) => l.isInsideMasterLeague).toList();

    if (q.isEmpty) return base;

    return base.where((league) {
      final latestAnn = _latestAnnouncements[league.id];
      final haystack = <String>[
        league.name,
        league.region,
        league.season,
        league.description,
        league.code,
        league.masterLeagueId,
        latestAnn?.title ?? '',
        latestAnn?.message ?? '',
      ].join(' ').toLowerCase();

      return haystack.contains(q);
    }).toList();
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

    if (league.viewerCapacity > 0) {
      pieces.add('${league.viewerCapacity} Viewers');
    }

    final desc = league.description.trim();
    if (desc.isNotEmpty) {
      pieces.add(desc);
    }

    if (latestAnn != null && latestAnn.title.trim().isNotEmpty) {
      pieces.add(latestAnn.title.trim());
    }

    return pieces.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isTablet = screenWidth >= 600;
    final fabBottomOffset =
        kBottomNavigationBarHeight + media.padding.bottom + 16;

    final filtered = _filteredLeagues();
    final normalCount = _leagues.where((l) => !l.isInsideMasterLeague).length;
    final masterCount = _leagues.where((l) => l.isInsideMasterLeague).length;

    return GlassScaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: l10n.tr('common_refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshLeagues,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: fabBottomOffset),
        child: FloatingActionButton(
          onPressed: () => _showOptions(context),
          backgroundColor: _freeLimitReached ? _premiumAmber : cs.primary,
          foregroundColor: _freeLimitReached ? Colors.black : cs.onPrimary,
          child: Icon(
            _freeLimitReached
                ? Icons.workspace_premium_rounded
                : Icons.add_rounded,
          ),
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 900 : 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primary.withOpacity(0.30),
                                    cs.primary.withOpacity(0.08),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.emoji_events_rounded,
                                color: cs.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.tr('leagues_my_leagues_title'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: -0.3,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isLoading
                                        ? 'Loading...'
                                        : '${_leagues.length} league${_leagues.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      color: onSurface.withOpacity(0.55),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!_isLoading) ...[
                          const SizedBox(height: 10),
                          Text(
                            _isPremiumUser
                                ? 'Premium active: you can have more than $_freeLeagueListLimit league cards.'
                                : (_freeLimitReached
                                    ? 'Free limit reached: you already have $_freeLeagueListLimit league cards. Upgrade to Premium to add more.'
                                    : 'Free plan: you can have up to $_freeLeagueListLimit league cards total.'),
                            style: TextStyle(
                              color: _isPremiumUser
                                  ? cs.primary
                                  : (_freeLimitReached
                                      ? _premiumAmber
                                      : onSurface.withOpacity(0.62)),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                          if (!_isPremiumUser) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _openPremiumUpgradeFlow,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _freeLimitReached
                                      ? _premiumAmber
                                      : cs.primary,
                                  foregroundColor: _freeLimitReached
                                      ? Colors.black
                                      : cs.onPrimary,
                                ),
                                icon: const Icon(Icons.payments_outlined),
                                label: Text(
                                  _freeLimitReached
                                      ? 'Pay Now'
                                      : 'Upgrade to Premium',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Glass(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText:
                                  'Search leagues, codes, announcements...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchController.clear();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _TopLeagueSwitcher(
                    selectedTab: _selectedTab,
                    normalCount: normalCount,
                    masterCount: masterCount,
                    onChanged: (tab) {
                      if (_selectedTab == tab) return;
                      setState(() => _selectedTab = tab);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: cs.primary,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Loading leagues...',
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.55),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? _buildEmptyState(context)
                            : _buildLeagueGrid(context, filtered, isTablet),
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

class _TopLeagueSwitcher extends StatelessWidget {
  const _TopLeagueSwitcher({
    required this.selectedTab,
    required this.normalCount,
    required this.masterCount,
    required this.onChanged,
  });

  final _LeagueViewTab selectedTab;
  final int normalCount;
  final int masterCount;
  final ValueChanged<_LeagueViewTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    Widget chip({
      required _LeagueViewTab tab,
      required String label,
      required int count,
      required IconData icon,
    }) {
      final selected = selectedTab == tab;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(tab),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? cs.primary
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? cs.onPrimary : onSurface.withOpacity(0.70),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    count > 0 ? '$label ($count)' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? cs.onPrimary : onSurface.withOpacity(0.78),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Glass(
      borderRadius: 999,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          chip(
            tab: _LeagueViewTab.leagues,
            label: 'Leagues',
            count: normalCount,
            icon: Icons.emoji_events_outlined,
          ),
          const SizedBox(width: 6),
          chip(
            tab: _LeagueViewTab.master,
            label: 'Master',
            count: masterCount,
            icon: Icons.hub_rounded,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconBg.withOpacity(0.15),
              ),
              child: Icon(icon, color: iconBg, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: onSurface.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: onSurface.withOpacity(0.25),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final color = selected ? cs.primary : onSurface.withOpacity(0.60);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? cs.primary.withOpacity(0.12)
              : onSurface.withOpacity(0.04),
          border: Border.all(
            color: selected
                ? cs.primary.withOpacity(0.30)
                : onSurface.withOpacity(0.10),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
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
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

bool auth_routerRefreshNeedsOnboardingFix(Object _) => false;
