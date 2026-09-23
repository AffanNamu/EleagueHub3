import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/routing/home_shell_tab_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../discovery/data/discovery_providers.dart';
import '../../discovery/presentation/discovery_hub_screen.dart';
import '../../leagues/models/football_category.dart';
import '../../leagues/models/league_format.dart';
import '../../leagues/presentation/leagues_list_screen.dart';
import '../../marketplace/presentation/marketplace_list_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../social/ui/widgets/notification_bell_button.dart';
import 'widgets/home_content_widgets.dart';
import 'widgets/top_bar_profile_avatar_button.dart';

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

    // Skippable ("optional") app-update nudge -- forced updates never
    // reach here at all, since the router redirects to /force-update
    // before any route (including this one) can build. Shown once per
    // build number: dismissing it writes the skipped build number to
    // prefs so it doesn't nag again until a newer one is published.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOptionalUpdateNudge();
    });
  }

  static const _skippedUpdateBuildKey = 'app_update_skipped_build';

  void _maybeShowOptionalUpdateNudge() {
    if (!mounted) return;
    final info = authRouterRefresh.pendingOptionalUpdate;
    if (info == null) return;

    final prefs = ref.read(prefsServiceProvider);
    final skipped = prefs.getInt(_skippedUpdateBuildKey) ?? 0;
    if (skipped >= info.latestBuildNumber) return;

    final theme = Theme.of(context);
    final versionLabel =
        info.latestVersionName.trim().isNotEmpty ? 'v${info.latestVersionName.trim()}' : 'A new version';
    final notes = info.releaseNotes.trim();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$versionLabel of the app is available.', style: theme.textTheme.bodyMedium),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(notes, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              prefs.setInt(_skippedUpdateBuildKey, info.latestBuildNumber);
              Navigator.of(ctx).pop();
            },
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.tryParse(info.storeUrlForThisPlatform.trim());
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
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
                  _trOr(context.l10n, 'home_exit_dialog_title', 'Exit app?'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _trOr(
                    context.l10n,
                    'home_exit_dialog_message',
                    'Are you sure you want to close the app?',
                  ),
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
                        child: Text(
                          _trOr(context.l10n, 'home_exit_dialog_cancel', 'Cancel'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
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
                        child: Text(
                          _trOr(context.l10n, 'home_exit_dialog_confirm', 'Exit'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
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
      _trOr(l10n, 'home_tab_discover', 'Discover'),
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
          actions: const [
            TopBarProfileAvatarButton(),
            NotificationBellButton(),
          ],
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
        // FIXED: was Flutter's stock Material NavigationBar/
        // NavigationDestination -- its label is rendered internally as a
        // bare `Text(label, style: textStyle)` with no maxLines/overflow
        // set (confirmed in the Flutter SDK source itself), so a longer
        // label like "Marketplace" genuinely wraps onto a second line
        // and breaks the bar's layout on narrower phones, or under a
        // larger system font-scaling setting, rather than truncating.
        // NavigationDestination's `label` field only accepts a String
        // (no widget override), so there was no way to add overflow
        // control without either shrinking every device's font size
        // (still breakable under font-scaling) or replacing it with a
        // custom row that has full control -- this is that custom row.
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
              child: SizedBox(
                // A few px taller than a plain nav bar strictly needs, so
                // the center Discover button (the app's landing tab) has
                // room to sit visibly larger than the other four without
                // overflowing.
                height: 78,
                child: Row(
                  children: [
                    _NavBarItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                      label: l10n.homeTabHome,
                      selected: _index == 0,
                      onTap: () => _onDestinationSelected(0),
                    ),
                    _NavBarItem(
                      icon: Icons.emoji_events_outlined,
                      selectedIcon: Icons.emoji_events,
                      label: l10n.homeTabLeagues,
                      selected: _index == 1,
                      onTap: () => _onDestinationSelected(1),
                    ),
                    _CenterNavBarItem(
                      icon: Icons.explore_outlined,
                      selectedIcon: Icons.explore,
                      label: _trOr(l10n, 'home_tab_discover', 'Discover'),
                      selected: _index == 2,
                      onTap: () => _onDestinationSelected(2),
                    ),
                    _NavBarItem(
                      icon: Icons.storefront_outlined,
                      selectedIcon: Icons.storefront,
                      label: l10n.homeTabMarketplace,
                      selected: _index == 3,
                      onTap: () => _onDestinationSelected(3),
                    ),
                    _NavBarItem(
                      icon: Icons.person_outline,
                      selectedIcon: Icons.person,
                      label: l10n.homeTabProfile,
                      selected: _index == 4,
                      onTap: () => _onDestinationSelected(4),
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
// _NavBarItem
// ---------------------------------------------------------------------------

/// A single bottom-nav destination. Custom-built (rather than
/// NavigationDestination) specifically so its label can set
/// maxLines/overflow/softWrap -- see the FIXED comment above this
/// widget's call site for why that control isn't available through the
/// stock Material NavigationBar API.
class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppTheme.limeAccentDark : const Color(0xFF9CA3AF);

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.limeAccent.withOpacity(0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                    ),
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
// _CenterNavBarItem
// ---------------------------------------------------------------------------

/// The middle (Discover) destination -- deliberately larger and more
/// visually prominent than the other four, since Discover is also this
/// app's landing tab (see homeShellTabIndexNotifier's default). A solid
/// lime circle with a soft glow when selected, a lighter tinted circle
/// when not, rather than the other items' plain pill-on-select, so it
/// reads as the bar's featured destination at a glance.
class _CenterNavBarItem extends StatelessWidget {
  const _CenterNavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        selected ? AppTheme.limeAccentDark : const Color(0xFF9CA3AF);

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AppTheme.limeAccent
                        : AppTheme.limeAccent.withOpacity(0.16),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppTheme.limeAccent.withOpacity(0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    color: selected
                        ? AppTheme.darkText
                        : AppTheme.limeAccentDark,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
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
// _HomeTab
// ---------------------------------------------------------------------------

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  /// Navigation helper.
  ///
  /// Uses [GoRouter.of] explicitly instead of the [BuildContext] extension
  /// so that it always resolves the correct router — even when the widget
  /// is mounted inside an [Offstage] subtree or a nested [Navigator].
  void _navigate(BuildContext context, String location) {
    // We use GoRouter.of(context).push() with the FULL path.
    // All paths here start with '/' so they are absolute — GoRouter
    // will not try to resolve them relative to the current shell route.
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
    final isWeb = kIsWeb;

    final secondary = AppTheme.secondaryText(brightness);

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 100),
      children: [
        // ── Home content: hero + promo strip (admin-controlled) ─────────
        // Announcements now show as a modal bottom sheet instead of the
        // old inline banner.
        const HomeAnnouncementTrigger(),
        const HomeContentSection(),

        // ── Welcome hero ────────────────────────────────────────────────
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
                          _trOr(
                            l10n,
                            'home_hero_subtitle',
                            'Manage leagues, jump into live matches, '
                                'follow organizers, and explore premium experiences.',
                          ),
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

        // ── Quick actions heading ────────────────────────────────────────
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

        // ── Create League + Live Match ───────────────────────────────────
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
            // Live Match — mobile only
            if (!isWeb) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.live_tv_rounded,
                  title: _trOr(l10n, 'home_quick_live_match_title', 'Live Match'),
                  subtitle: _trOr(
                    l10n,
                    'home_quick_live_match_subtitle',
                    'Join or host live match sessions',
                  ),
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

        // ── Organizer Workspace ──────────────────────────────────────────
        _QuickActionCard(
          icon: Icons.hub_rounded,
          title: _trOr(
            l10n,
            'home_quick_master_leagues_title',
            'Organizer Workspace',
          ),
          subtitle: _trOr(
            l10n,
            'home_quick_master_leagues_subtitle',
            'Create and manage premium competition hubs',
          ),
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

        // ── Voice Room — mobile only ─────────────────────────────────────
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

        // ── Browse competitions by category / type ─────────────────────
        const _BrowseCompetitionsSection(),

      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _BrowseCompetitionsSection — real categories/types, real counts.
//
// "Browse by category" uses this app's actual FootballCategory enum
// (exactly the 6 supported categories, see football_category.dart) — not
// a generic games list. "Browse by type" uses this app's actual
// LeagueFormat enum (Classic/Group/Series/World Cup/Direct Knockout, see
// league_format.dart). Counts come from footballCategoryCountsProvider /
// leagueFormatCountsProvider (discovery_providers.dart) — real Firestore
// count() aggregations over public leagues, not placeholder numbers.
// Tapping a tile pushes into CompetitionsDiscoveryScreen pre-filtered to
// that category/type.
// ---------------------------------------------------------------------------

class _BrowseCompetitionsSection extends ConsumerWidget {
  const _BrowseCompetitionsSection();

  static const Map<FootballCategory, Color> _categoryColors = {
    FootballCategory.localFootball: Color(0xFF22C55E),
    FootballCategory.eFootball: AppTheme.limeAccentDark,
    FootballCategory.eaSportsFC: Color(0xFF3B82F6),
    FootballCategory.eaSportsFCMobile: Color(0xFF8B5CF6),
    FootballCategory.dreamLeagueSoccer: Color(0xFFF59E0B),
    FootballCategory.totalFootball: Color(0xFF14B8A6),
  };

  static const Map<LeagueFormat, Color> _formatColors = {
    LeagueFormat.classic: Color(0xFFF59E0B),
    LeagueFormat.uclGroup: Color(0xFF3B82F6),
    LeagueFormat.uclSwiss: Color(0xFF8B5CF6),
    LeagueFormat.worldCup: Color(0xFF22C55E),
    LeagueFormat.directKnockout: Color(0xFFEF4444),
  };

  static const Map<LeagueFormat, IconData> _formatIcons = {
    LeagueFormat.classic: Icons.leaderboard_rounded,
    LeagueFormat.uclGroup: Icons.groups_rounded,
    LeagueFormat.uclSwiss: Icons.shuffle_rounded,
    LeagueFormat.worldCup: Icons.public_rounded,
    LeagueFormat.directKnockout: Icons.account_tree_rounded,
  };

  static const Map<LeagueFormat, String> _formatSubtitles = {
    LeagueFormat.classic: 'Season format',
    LeagueFormat.uclGroup: 'Groups + knockout',
    LeagueFormat.uclSwiss: 'Swiss system',
    LeagueFormat.worldCup: 'FIFA-style',
    LeagueFormat.directKnockout: 'Fast & intense',
  };

  void _openCategory(BuildContext context, FootballCategory? category) {
    try {
      GoRouter.of(context).push(
        category == null
            ? '/discovery/competitions'
            : '/discovery/competitions?category=${category.name}',
      );
    } catch (_) {}
  }

  void _openFormat(BuildContext context, LeagueFormat format) {
    try {
      GoRouter.of(context).push(
        '/discovery/competitions?format=${format.name}',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final t = theme.textTheme;

    final categoryCountsAsync = ref.watch(footballCategoryCountsProvider);
    final formatCountsAsync = ref.watch(leagueFormatCountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sports_esports_rounded,
                color: AppTheme.limeAccentDark, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Browse by Category',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryText(brightness),
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openCategory(context, null),
              child: const Text(
                'See All',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: FootballCategory.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final category = FootballCategory.values[i];
              final count = categoryCountsAsync.maybeWhen(
                data: (counts) => counts[category],
                orElse: () => null,
              );
              return _CategoryTile(
                category: category,
                color: _categoryColors[category]!,
                count: count,
                onTap: () => _openCategory(context, category),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Icon(Icons.apps_rounded, color: AppTheme.limeAccentDark, size: 20),
            const SizedBox(width: 8),
            Text(
              'Browse by Type',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: LeagueFormat.values.map((format) {
            final count = formatCountsAsync.maybeWhen(
              data: (counts) => counts[format],
              orElse: () => null,
            );
            return _FormatTile(
              format: format,
              color: _formatColors[format]!,
              icon: _formatIcons[format]!,
              subtitle: _formatSubtitles[format]!,
              count: count,
              onTap: () => _openFormat(context, format),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.color,
    required this.count,
    required this.onTap,
  });

  final FootballCategory category;
  final Color color;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppTheme.cardColor(brightness),
          border: Border.all(color: AppTheme.cardBorder(brightness)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.16),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Icon(category.icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              category.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              count == null ? '—' : '$count Tournaments',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.secondaryText(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.format,
    required this.color,
    required this.icon,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final LeagueFormat format;
  final Color color;
  final IconData icon;
  final String subtitle;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppTheme.cardColor(brightness),
          border: Border.all(color: AppTheme.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.16),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    format.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  Text(
                    count == null ? subtitle : '$count active',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryText(brightness),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
