import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/platform/overlay_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../leagues/presentation/leagues_list_screen.dart';
import '../../live/logic/quick_messages_controller.dart';
import '../../live/presentation/live_list_screen.dart';
import '../../marketplace/presentation/marketplace_list_screen.dart';
import '../../profile/presentation/profile_screen.dart';

String _trOr(AppLocalizations l10n, String key, String fallback) {
  final v = l10n.tr(key);
  return v == key ? fallback : v;
}

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

  bool _overlayEnabled = false;
  bool _overlayGranted = false;

  String _lastOverlayQuickHash = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabs = const [
      _HomeTab(),
      LeaguesListScreen(),
      LiveListScreen(),
      MarketplaceListScreen(),
      ProfileScreen(),
    ];

    _built = List<bool>.filled(_tabs.length, false);
    _built[_index] = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadOverlayStateAndMaybeStart());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadOverlayStateAndMaybeStart());
    }
  }

  Future<void> _loadOverlayStateAndMaybeStart() async {
    final prefs = ref.read(prefsServiceProvider);
    final enabled = prefs.liveOverlayEnabled();
    final granted =
        await OverlayPlatform.isOverlayPermissionGranted();

    if (!mounted) return;

    setState(() {
      _overlayEnabled = enabled;
      _overlayGranted = granted;
    });

    if (enabled && granted) {
      await OverlayPlatform.startGlobalOverlay();
    }
  }

  void _selectTab(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _built[i] = true;
    });
  }

  void _onDestinationSelected(int i) {
    if (i == 2) {
      if (i != _index) {
        setState(() {
          _index = i;
          _built[i] = true;
        });
      }
      context.push('/global-live');
      return;
    }
    _selectTab(i);
  }

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
      builder: (ctx) => AlertDialog(
        title: const Text('Exit app?'),
        content:
            const Text('Are you sure you want to close the app?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final overlayQuick =
        ref.watch(overlayQuickMessagesProvider);

    final quickHash = overlayQuick.join('\u0001');

    if (quickHash != _lastOverlayQuickHash) {
      _lastOverlayQuickHash = quickHash;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
            OverlayPlatform.setOverlayQuickMessages(
                overlayQuick));
      });
    }

    final tabTitles = [
      l10n.homeTabHome,
      l10n.homeTabLeagues,
      l10n.homeTabLive,
      l10n.homeTabMarketplace,
      l10n.homeTabProfile,
    ];

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Container(
        decoration: BoxDecoration(
          gradient:
              AppTheme.backgroundGradient(
                  theme.brightness),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,

          // ─────────────────────────
          // PREMIUM APP BAR
          // ─────────────────────────
          appBar: AppBar(
            elevation: 0,
            backgroundColor:
                Colors.transparent,
            title: Text(
              tabTitles[_index],
              style: theme.textTheme.titleLarge
                  ?.copyWith(
                fontWeight:
                    FontWeight.w900,
                letterSpacing:
                    -0.3,
                color: onSurface,
              ),
            ),
            centerTitle: false,
          ),

          // BODY
          body: SafeArea(
            bottom: false,
            child: Stack(
              children:
                  List.generate(
                _tabs.length,
                (i) {
                  final built =
                      _built[i];
                  return Offstage(
                    offstage:
                        _index != i,
                    child:
                        TickerMode(
                      enabled:
                          _index ==
                              i,
                      child: built
                          ? _tabs[i]
                          : const SizedBox
                              .shrink(),
                    ),
                  );
                },
              ),
            ),
          ),

          // FLOATING PREMIUM DOCK NAV
          bottomNavigationBar:
              SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                          16, 0, 16, 12),
              child: Glass(
                borderRadius: 30,
                padding:
                    EdgeInsets.zero,
                child: Container(
                  height: 70,
                  padding:
                      const EdgeInsets
                          .symmetric(
                              horizontal:
                                  6),
                  child: NavigationBar(
                    backgroundColor:
                        Colors
                            .transparent,
                    surfaceTintColor:
                        Colors
                            .transparent,
                    indicatorColor:
                        cs.primary
                            .withOpacity(
                                0.18),
                    selectedIndex:
                        _index,
                    onDestinationSelected:
                        _onDestinationSelected,
                    labelBehavior:
                        NavigationDestinationLabelBehavior
                            .alwaysShow,
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(
                            Icons
                                .home_outlined),
                        selectedIcon:
                            const Icon(
                                Icons.home),
                        label: l10n
                            .homeTabHome,
                      ),
                      NavigationDestination(
                        icon: const Icon(
                            Icons
                                .emoji_events_outlined),
                        selectedIcon:
                            const Icon(
                                Icons
                                    .emoji_events),
                        label: l10n
                            .homeTabLeagues,
                      ),
                      NavigationDestination(
                        icon: const Icon(
                            Icons
                                .public_outlined),
                        selectedIcon:
                            const Icon(
                                Icons
                                    .public),
                        label: l10n
                            .homeTabLive,
                      ),
                      NavigationDestination(
                        icon: const Icon(
                            Icons
                                .storefront_outlined),
                        selectedIcon:
                            const Icon(
                                Icons
                                    .storefront),
                        label: l10n
                            .homeTabMarketplace,
                      ),
                      NavigationDestination(
                        icon: const Icon(
                            Icons
                                .person_outline),
                        selectedIcon:
                            const Icon(
                                Icons
                                    .person),
                        label: l10n
                            .homeTabProfile,
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
} // ─────────────────────────────────────────────
// HOME TAB (Refined + Premium Depth)
// ─────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = theme.textTheme;
    final onSurface = cs.onSurface;

    final secondary = onSurface.withOpacity(0.55);
    final tertiary = onSurface.withOpacity(0.45);
    final faint = onSurface.withOpacity(0.30);

    return ListView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      padding:
          const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        // ── Welcome Card ──
        Glass(
          borderRadius: 26,
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withOpacity(0.35),
                      cs.primary.withOpacity(0.08),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.sports_esports_rounded,
                  color: cs.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeWelcomeBack,
                      style:
                          t.titleLarge?.copyWith(
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 22,
                        letterSpacing:
                            -0.5,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.homeMvpDescription,
                      style: TextStyle(
                        color: secondary,
                        fontWeight:
                            FontWeight.w600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Quick Actions Title ──
        Padding(
          padding:
              const EdgeInsets.only(left: 6),
          child: Text(
            _trOr(l10n,
                'home_quick_actions_title',
                'Quick Actions'),
            style: t.titleMedium
                ?.copyWith(
              fontWeight:
                  FontWeight.w900,
              letterSpacing:
                  -0.3,
              color: onSurface,
            ),
          ),
        ),

        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons
                    .add_circle_outline_rounded,
                title: l10n
                    .homeQuickCreateLeagueTitle,
                subtitle: l10n
                    .homeQuickCreateLeagueSubtitle,
                gradient: [
                  cs.primary
                      .withOpacity(0.20),
                  cs.primary
                      .withOpacity(0.05),
                ],
                onTap: () =>
                    context.push(
                        '/leagues/create'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _QuickActionCard(
                icon: Icons
                    .confirmation_number_outlined,
                title: l10n
                    .homeQuickJoinLiveTitle,
                subtitle: l10n
                    .homeQuickJoinLiveSubtitle,
                gradient: [
                  const Color(
                          0xFF00E676)
                      .withOpacity(0.20),
                  const Color(
                          0xFF00E676)
                      .withOpacity(0.05),
                ],
                onTap: () =>
                    context.push(
                        '/live/join'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        _QuickActionCard(
          icon:
              Icons.headset_mic_rounded,
          title: _trOr(
              l10n,
              'home_quick_voice_room_title',
              'Voice Room'),
          subtitle: _trOr(
              l10n,
              'home_quick_voice_room_subtitle',
              'Create/Join with 8-digit code'),
          gradient: [
            Colors.purple
                .withOpacity(0.20),
            Colors.purple
                .withOpacity(0.05),
          ],
          onTap: () =>
              context.push('/call'),
          isWide: true,
        ),

        const SizedBox(height: 32),

        // ── Explore Title ──
        Padding(
          padding:
              const EdgeInsets.only(left: 6),
          child: Text(
            _trOr(l10n,
                'home_explore_title',
                'Explore'),
            style: t.titleMedium
                ?.copyWith(
              fontWeight:
                  FontWeight.w900,
              letterSpacing:
                  -0.3,
              color: onSurface,
            ),
          ),
        ),

        const SizedBox(height: 14),

        Glass(
          borderRadius: 22,
          padding:
              const EdgeInsets.all(6),
          child: Column(
            children: [
              _ExploreRow(
                icon:
                    Icons.forum_rounded,
                title: _trOr(
                    l10n,
                    'home_explore_global_chat',
                    'Global Chat'),
                subtitle: _trOr(
                    l10n,
                    'home_explore_global_chat_sub',
                    'Realtime conversation'),
                onTap: () =>
                    context.push(
                        '/global-chat'),
                secondaryColor:
                    tertiary,
                chevronColor:
                    faint,
              ),
              Divider(
                  color: onSurface
                      .withOpacity(
                          0.08),
                  height: 1),
              _ExploreRow(
                icon:
                    Icons.public_rounded,
                title: _trOr(
                    l10n,
                    'home_explore_global_leagues',
                    'Global Leagues'),
                subtitle: _trOr(
                    l10n,
                    'home_explore_global_leagues_sub',
                    'Discover & join'),
                onTap: () =>
                    context.push(
                        '/global-live'),
                secondaryColor:
                    tertiary,
                chevronColor:
                    faint,
              ),
              Divider(
                  color: onSurface
                      .withOpacity(
                          0.08),
                  height: 1),
              _ExploreRow(
                icon: Icons
                    .storefront_rounded,
                title: _trOr(
                    l10n,
                    'home_explore_marketplace',
                    'Marketplace'),
                subtitle: _trOr(
                    l10n,
                    'home_explore_marketplace_sub',
                    'Browse gaming gear'),
                onTap: () =>
                    context.push(
                        '/marketplace'),
                secondaryColor:
                    tertiary,
                chevronColor:
                    faint,
              ),
            ],
          ),
        ),
      ],
    );
  }
} // ─────────────────────────────────────────────
// Quick Action Card
// ─────────────────────────────────────────────

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
  State<_QuickActionCard> createState() =>
      _QuickActionCardState();
}

class _QuickActionCardState
    extends State<_QuickActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 100),
      reverseDuration:
          const Duration(milliseconds: 180),
    );

    _scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeInOut,
      ),
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
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final secondary =
        onSurface.withOpacity(0.55);
    final tertiary =
        onSurface.withOpacity(0.45);
    final faint =
        onSurface.withOpacity(0.30);

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(
              scale: _scale.value,
              child: child),
      child: GestureDetector(
        onTapDown: (_) =>
            _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () =>
            _ctrl.reverse(),
        child: Glass(
          borderRadius: 22,
          padding: EdgeInsets.zero,
          child: Container(
            padding:
                const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                      22),
              gradient:
                  LinearGradient(
                colors:
                    widget.gradient,
              ),
            ),
            child: widget.isWide
                ? Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration:
                            BoxDecoration(
                          shape: BoxShape
                              .circle,
                          color: onSurface
                              .withOpacity(
                                  0.06),
                          border: Border.all(
                            color: onSurface
                                .withOpacity(
                                    0.10),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color:
                              cs.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(
                          width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              widget.title,
                              style: theme
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                fontWeight:
                                    FontWeight
                                        .w900,
                                color:
                                    onSurface,
                              ),
                            ),
                            const SizedBox(
                                height:
                                    4),
                            Text(
                              widget
                                  .subtitle,
                              style:
                                  TextStyle(
                                color:
                                    secondary,
                                fontSize:
                                    12,
                                fontWeight:
                                    FontWeight
                                        .w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons
                            .arrow_forward_ios_rounded,
                        size: 16,
                        color: faint,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration:
                            BoxDecoration(
                          shape: BoxShape
                              .circle,
                          color: onSurface
                              .withOpacity(
                                  0.06),
                          border: Border.all(
                            color: onSurface
                                .withOpacity(
                                    0.10),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color:
                              cs.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(
                          height: 12),
                      Text(
                        widget.title,
                        style: theme
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                          fontWeight:
                              FontWeight
                                  .w900,
                          color:
                              onSurface,
                        ),
                      ),
                      const SizedBox(
                          height: 4),
                      Text(
                        widget.subtitle,
                        style:
                            TextStyle(
                          color:
                              tertiary,
                          fontSize:
                              11,
                          fontWeight:
                              FontWeight
                                  .w600,
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

// ─────────────────────────────────────────────
// Explore Row
// ─────────────────────────────────────────────

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
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(
              16),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(
                shape: BoxShape
                    .circle,
                color: cs.primary
                    .withOpacity(
                        0.12),
              ),
              child: Icon(icon,
                  color:
                      cs.primary,
                  size: 20),
            ),
            const SizedBox(
                width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style: theme
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                      fontWeight:
                          FontWeight
                              .w900,
                      color:
                          onSurface,
                    ),
                  ),
                  const SizedBox(
                      height: 4),
                  Text(
                    subtitle,
                    style:
                        TextStyle(
                      color:
                          secondaryColor,
                      fontSize:
                          12,
                      fontWeight:
                          FontWeight
                              .w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons
                  .chevron_right_rounded,
              color:
                  chevronColor,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

