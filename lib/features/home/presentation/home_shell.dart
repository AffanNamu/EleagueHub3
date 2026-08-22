import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/routing/home_shell_tab_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../discovery/presentation/discovery_hub_screen.dart';
import '../../leagues/presentation/leagues_list_screen.dart';
import '../../marketplace/presentation/marketplace_list_screen.dart';
import '../../master_leagues/data/organizer_feed_firebase.dart';
import '../../master_leagues/domain/organizer_feed_event.dart';
import '../../profile/presentation/profile_screen.dart';

String _trOr(AppLocalizations l10n, String key, String fallback) {
  final v = l10n.tr(key);
  return v == key ? fallback : v;
}

// ---------------------------------------------------------------------------
// HomeShell
// ---------------------------------------------------------------------------

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  late final List<Widget> _tabs;
  late final List<bool> _built;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _index = homeShellTabIndexNotifier.value.clamp(0, 4);

    _tabs = const [
      _HomeTab(),
      LeaguesListScreen(showAppBar: false),
      DiscoveryHubScreen(),
      MarketplaceListScreen(),
      ProfileScreen(),
    ];

    _built = List<bool>.filled(_tabs.length, false);
    _built[_index] = true;

    homeShellTabIndexNotifier.addListener(_handleExternalTabChange);
  }

  @override
  void dispose() {
    homeShellTabIndexNotifier.removeListener(_handleExternalTabChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleExternalTabChange() {
    final next =
        homeShellTabIndexNotifier.value.clamp(0, _tabs.length - 1);
    if (!mounted || next == _index) return;
    setState(() {
      _index = next;
      _built[next] = true;
    });
  }

  void _selectTab(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _built[i] = true;
    });
    homeShellTabIndexNotifier.value = i;
  }

  void _onDestinationSelected(int i) => _selectTab(i);

  Future<bool> _handleSystemBack() async {
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
      return false;
    }
    if (_index > 0) {
      _selectTab(_index - 1);
      return false;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.28),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final brightness = theme.brightness;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Glass(
            borderRadius: 28,
            padding: const EdgeInsets.all(20),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.iconCircleBackground(brightness),
                    border:
                        Border.all(color: AppTheme.cardBorder(brightness)),
                  ),
                  child: Icon(
                    Icons.exit_to_app_rounded,
                    color: AppTheme.limeAccentDark,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Exit app?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to close the app?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.secondaryText(brightness),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
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
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text(
                          'Exit',
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
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final tabTitles = [
      l10n.homeTabHome,
      l10n.homeTabLeagues,
      'Discover',
      l10n.homeTabMarketplace,
      l10n.homeTabProfile,
    ];

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: GlassScaffold(
        extendBody: true,
        appBar: AppBar(
          title: Text(tabTitles[_index]),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: List.generate(_tabs.length, (i) {
              final built = _built[i];
              return Offstage(
                offstage: _index != i,
                child: TickerMode(
                  enabled: _index == i,
                  child: built ? _tabs[i] : const SizedBox.shrink(),
                ),
              );
            }),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding:
                const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
            child: Glass(
              padding: EdgeInsets.zero,
              borderRadius: 28,
              fill: brightness == Brightness.dark
                  ? AppTheme.darkNavBg
                  : AppTheme.lightNavBg,
              borderColor: AppTheme.cardBorder(brightness),
              child: Theme(
                data: theme.copyWith(
                  navigationBarTheme: NavigationBarThemeData(
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    indicatorColor: AppTheme.limeAccent,
                    labelTextStyle:
                        WidgetStateProperty.resolveWith((states) {
                      final selected =
                          states.contains(WidgetState.selected);
                      return TextStyle(
                        color: selected
                            ? AppTheme.limeAccentDark
                            : const Color(0xFF9CA3AF),
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      );
                    }),
                    iconTheme:
                        WidgetStateProperty.resolveWith((states) {
                      final selected =
                          states.contains(WidgetState.selected);
                      return IconThemeData(
                        color: selected
                            ? AppTheme.limeAccentDark
                            : const Color(0xFF9CA3AF),
                        size: 24,
                      );
                    }),
                  ),
                ),
                child: NavigationBar(
                  height: 68,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  indicatorColor: AppTheme.limeAccent,
                  selectedIndex: _index,
                  onDestinationSelected: _onDestinationSelected,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: const Icon(Icons.home),
                      label: l10n.homeTabHome,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.emoji_events_outlined),
                      selectedIcon: const Icon(Icons.emoji_events),
                      label: l10n.homeTabLeagues,
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: 'Discover',
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.storefront_outlined),
                      selectedIcon: const Icon(Icons.storefront),
                      label: l10n.homeTabMarketplace,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.person_outline),
                      selectedIcon: const Icon(Icons.person),
                      label: l10n.homeTabProfile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HomeTab
// ---------------------------------------------------------------------------

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  void _navigate(BuildContext context, String location) {
    try {
      GoRouter.of(context).push(location);
    } catch (e) {
      debugPrint('[HomeTab] Navigation to $location failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final t = theme.textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final isWeb = kIsWeb;

    final secondary = AppTheme.secondaryText(brightness);
    final tertiary = AppTheme.secondaryText(brightness).withOpacity(0.88);
    final faint = const Color(0xFF9CA3AF);

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 100),
      children: [
        Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(22),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.limeAccent.withOpacity(0.10),
                  ),
                ),
              ),
              Positioned(
                left: -12,
                bottom: -24,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.limeAccentDark.withOpacity(0.06),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.iconCircleBackground(brightness),
                      border: Border.all(
                        color: AppTheme.cardBorder(brightness),
                      ),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.limeAccentDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.homeWelcomeBack,
                          style: t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 23,
                            letterSpacing: -0.5,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Manage leagues, jump into live matches, '
                          'follow organizers, and explore premium experiences.',
                          style: TextStyle(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            _trOr(l10n, 'home_quick_actions_title', 'Quick Actions'),
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: AppTheme.primaryText(brightness),
            ),
          ),
        ),

        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.add_circle_outline_rounded,
                title: l10n.homeQuickCreateLeagueTitle,
                subtitle: l10n.homeQuickCreateLeagueSubtitle,
                gradient: brightness == Brightness.dark
                    ? [
                        AppTheme.limeAccentDark.withOpacity(0.12),
                        AppTheme.darkCard,
                      ]
                    : [
                        const Color(0xFFECFCCB),
                        const Color(0xFFFFFFFF),
                      ],
                onTap: () => _navigate(context, '/leagues/create'),
              ),
            ),
            if (!isWeb) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.live_tv_rounded,
                  title: 'Live Match',
                  subtitle: 'Join or host live match sessions',
                  gradient: brightness == Brightness.dark
                      ? [
                          const Color(0xFF38BDF8).withOpacity(0.16),
                          AppTheme.darkCard,
                        ]
                      : [
                          const Color(0xFFE0F2FE),
                          const Color(0xFFFFFFFF),
                        ],
                  onTap: () => _navigate(context, '/live/join'),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),

        _QuickActionCard(
          icon: Icons.hub_rounded,
          title: _trOr(
            l10n,
            'home_quick_master_leagues_title',
            'Organizer Workspace',
          ),
          subtitle: 'Create and manage premium competition hubs',
          gradient: brightness == Brightness.dark
              ? [
                  AppTheme.limeAccentDark.withOpacity(0.10),
                  AppTheme.darkCard,
                ]
              : [
                  const Color(0xFFECFCCB),
                  const Color(0xFFF8FAFC),
                ],
          onTap: () => _navigate(context, '/master-leagues'),
          isWide: true,
        ),

        const SizedBox(height: 12),

        if (!isWeb)
          _QuickActionCard(
            icon: Icons.headset_mic_rounded,
            title: _trOr(
              l10n,
              'home_quick_voice_room_title',
              'Voice Room',
            ),
            subtitle: _trOr(
              l10n,
              'home_quick_voice_room_subtitle',
              'Create/Join with 8-digit code',
            ),
            gradient: brightness == Brightness.dark
                ? [
                    Colors.purple.withOpacity(0.16),
                    AppTheme.darkCard,
                  ]
                : [
                    const Color(0xFFF3E8FF),
                    const Color(0xFFFFFFFF),
                  ],
            onTap: () => _navigate(context, '/call'),
            isWide: true,
          ),

        const SizedBox(height: 22),

        _FollowedOrganizerFeedPreview(uid: uid),

        const SizedBox(height: 22),

        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            _trOr(l10n, 'home_explore_title', 'Explore'),
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: AppTheme.primaryText(brightness),
            ),
          ),
        ),

        Glass(
          borderRadius: 24,
          padding: const EdgeInsets.all(4),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            children: [
              _ExploreRow(
                icon: Icons.travel_explore_rounded,
                title: 'Organizer Discovery',
                subtitle: 'Featured, verified, and active organizers',
                onTap: () =>
                    _navigate(context, '/organizer-discovery'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.hub_rounded,
                title: _trOr(
                  l10n,
                  'home_explore_master_leagues',
                  'Organizer Workspaces',
                ),
                subtitle: _trOr(
                  l10n,
                  'home_explore_master_leagues_sub',
                  'Trusted organizer hubs for multiple competitions',
                ),
                onTap: () => _navigate(context, '/master-leagues'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.dynamic_feed_rounded,
                title: 'Organizer Feed',
                subtitle: 'Latest updates from organizers you follow',
                onTap: () =>
                    _navigate(context, '/organizer-feed'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.local_fire_department_rounded,
                title: 'Public Feed',
                subtitle: "See what's happening in the community",
                onTap: () => _navigate(context, '/discovery/feed'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.forum_rounded,
                title: _trOr(
                    l10n, 'home_explore_global_chat', 'Global Chat'),
                subtitle: _trOr(
                  l10n,
                  'home_explore_global_chat_sub',
                  'Request access & chat in realtime',
                ),
                onTap: () => _navigate(context, '/global-chat'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.storefront_rounded,
                title: _trOr(
                    l10n, 'home_explore_marketplace', 'Marketplace'),
                subtitle: _trOr(
                  l10n,
                  'home_explore_marketplace_sub',
                  'Browse gaming gear & accessories',
                ),
                onTap: () => _navigate(context, '/marketplace'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.search_rounded,
                title: 'Find Teams',
                subtitle: 'Search public profiles & squads',
                onTap: () => _navigate(context, '/search'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(
                  color: AppTheme.cardBorder(brightness), height: 1),
              _ExploreRow(
                icon: Icons.emoji_events_rounded,
                title: _trOr(
                    l10n, 'home_explore_my_leagues', 'My Leagues'),
                subtitle: _trOr(
                  l10n,
                  'home_explore_my_leagues_sub',
                  'View and manage your leagues',
                ),
                onTap: () {
                  openHomeShellTab(1);
                  GoRouter.of(context).go('/');
                },
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _FollowedOrganizerFeedPreview
// ---------------------------------------------------------------------------

class _FollowedOrganizerFeedPreview extends StatefulWidget {
  const _FollowedOrganizerFeedPreview({required this.uid});
  final String uid;

  @override
  State<_FollowedOrganizerFeedPreview> createState() =>
      _FollowedOrganizerFeedPreviewState();
}

class _FollowedOrganizerFeedPreviewState
    extends State<_FollowedOrganizerFeedPreview> {
  late final OrganizerFeedFirebase _feed;

  bool _loading = true;
  List<OrganizerFeedEvent> _items = const <OrganizerFeedEvent>[];
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _feed = OrganizerFeedFirebase();
    _load();
  }

  @override
  void didUpdateWidget(
      covariant _FollowedOrganizerFeedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _load();
  }

  Future<void> _load() async {
    final uid = widget.uid.trim();
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const <OrganizerFeedEvent>[];
        _hasError = false;
      });
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      final items =
          await _feed.fetchFollowedOrganizerFeedOnce(uid);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items.take(4).toList(growable: false);
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const <OrganizerFeedEvent>[];
        _hasError = true;
      });
    }
  }

  IconData _feedIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return Icons.campaign_outlined;
      case 'competition_created':
        return Icons.emoji_events_outlined;
      case 'verification_approved':
        return Icons.verified_rounded;
      case 'verification_renewed':
        return Icons.refresh_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  Color _feedColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return const Color(0xFF8B5CF6);
      case 'competition_created':
        return const Color(0xFF22C55E);
      case 'verification_approved':
        return const Color(0xFF1D9BF0);
      case 'verification_renewed':
        return const Color(0xFF14B8A6);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final t = theme.textTheme;

    if (widget.uid.isEmpty) {
      return Glass(
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Followed Organizer Feed',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sign in to see updates from organizers you follow.',
              style: t.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Followed Organizer Feed',
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  try {
                    GoRouter.of(context).push('/organizer-feed');
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text(
                  'Open',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasError)
            Text(
              'Unable to load organizer updates right now.',
              style: t.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w800,
              ),
            )
          else if (_items.isEmpty)
            Text(
              'No followed organizer updates yet. Follow organizer '
              'workspaces to see their latest activity here.',
              style: t.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            )
          else
            Column(
              children: _items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () {
                      try {
                        if (item.leagueId.trim().isNotEmpty) {
                          GoRouter.of(context).push(
                            '/leagues/${item.leagueId.trim()}',
                          );
                          return;
                        }
                        if (item.masterLeagueId.trim().isNotEmpty) {
                          GoRouter.of(context).push(
                            '/master-leagues/'
                            '${item.masterLeagueId.trim()}',
                          );
                        }
                      } catch (_) {}
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Glass(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(12),
                      fill: AppTheme.cardColor(brightness),
                      borderColor: AppTheme.cardBorder(brightness),
                      child: Row(
                        children: [
                          Icon(
                            _feedIcon(item.type),
                            color: _feedColor(item.type),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: t.bodyMedium?.copyWith(
                                    color: AppTheme.primaryText(
                                        brightness),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall?.copyWith(
                                    color: AppTheme.secondaryText(
                                        brightness),
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color:
                                AppTheme.secondaryText(brightness),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _QuickActionCard
// ---------------------------------------------------------------------------

class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.isWide = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  final bool isWide;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final secondary = AppTheme.secondaryText(brightness);

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Glass(
          padding: EdgeInsets.zero,
          borderRadius: 22,
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.gradient,
              ),
            ),
            child: widget.isWide
                ? Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.iconCircleBackground(
                              brightness),
                          border: Border.all(
                            color: AppTheme.cardBorder(brightness),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color: AppTheme.limeAccentDark,
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
                              widget.title,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color:
                                    AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              style: TextStyle(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.iconCircleBackground(
                              brightness),
                          border: Border.all(
                            color: AppTheme.cardBorder(brightness),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color: AppTheme.limeAccentDark,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.3,
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

// ---------------------------------------------------------------------------
// _ExploreRow
// ---------------------------------------------------------------------------

class _ExploreRow extends StatelessWidget {
  const _ExploreRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.secondaryColor,
    required this.chevronColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color secondaryColor;
  final Color chevronColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.iconCircleBackground(brightness),
                border: Border.all(
                    color: AppTheme.cardBorder(brightness)),
              ),
              child: Icon(
                icon,
                color: AppTheme.limeAccentDark,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: secondaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: chevronColor,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
