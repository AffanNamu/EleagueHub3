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

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
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
    final granted = await OverlayPlatform.isOverlayPermissionGranted();
    if (!mounted) return;
    setState(() {
      _overlayEnabled = enabled;
      _overlayGranted = granted;
    });
    if (enabled && granted) {
      await OverlayPlatform.startGlobalOverlay();
    }
  }

  Future<void> _toggleOverlayFromHome() async {
    final prefs = ref.read(prefsServiceProvider);
    final l10n = context.l10n;
    if (_overlayEnabled) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_trOr(l10n, 'live_overlay_turn_off_title', 'Turn off overlay?')),
          content: Text(
            _trOr(l10n, 'live_overlay_turn_off_body', 'This will hide the floating voice/message controls.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_trOr(l10n, 'common_cancel', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_trOr(l10n, 'common_turn_off', 'Turn off')),
            ),
          ],
        ),
      );

      if (sure != true) return;

      await prefs.setLiveOverlayEnabled(false);
      await OverlayPlatform.stopGlobalOverlay();

      if (!mounted) return;
      setState(() => _overlayEnabled = false);
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_trOr(l10n, 'live_overlay_enable_title', 'Enable floating overlay?')),
        content: Text(
          _trOr(
            l10n,
            'live_overlay_enable_body',
            'This shows a floating voice/message control above other apps. Android will ask for "Appear on top" permission.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_trOr(l10n, 'common_cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_trOr(l10n, 'common_continue', 'Continue')),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    await prefs.setLiveOverlayEnabled(true);

    final granted = await OverlayPlatform.isOverlayPermissionGranted();
    if (!mounted) return;

    setState(() {
      _overlayEnabled = true;
      _overlayGranted = granted;
    });

    if (granted) {
      await OverlayPlatform.startGlobalOverlay();
      return;
    }

    await OverlayPlatform.requestOverlayPermission();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _trOr(l10n, 'live_overlay_permission_snackbar', 'Grant the overlay permission, then return to the app.'),
        ),
      ),
    );
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
        content: const Text('Are you sure you want to close the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
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
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isLight = brightness == Brightness.light;

    final overlayQuick = ref.watch(overlayQuickMessagesProvider);
    final quickHash = overlayQuick.join('\u0001');
    if (quickHash != _lastOverlayQuickHash) {
      _lastOverlayQuickHash = quickHash;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(OverlayPlatform.setOverlayQuickMessages(overlayQuick));
      });
    }

    final tabTitles = [
      l10n.homeTabHome,
      l10n.homeTabLeagues,
      l10n.homeTabLive,
      l10n.homeTabMarketplace,
      l10n.homeTabProfile,
    ];

    final overlayIcon = !_overlayEnabled
        ? Icons.picture_in_picture_alt_outlined
        : (_overlayGranted ? Icons.picture_in_picture_alt : Icons.warning_amber_rounded);

    final overlayIconColor =
        !_overlayEnabled ? null : (_overlayGranted ? const Color(0xFF22C55E) : const Color(0xFFF59E0B));

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.backgroundGradient(brightness),
              ),
            ),
          ),

          // Match GlassScaffold premium ambient glow (light mode only).
          if (isLight)
            Positioned(
              top: -120,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x337AB6FF),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            appBar: AppBar(
              title: Text(tabTitles[_index]),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: _overlayEnabled
                      ? (_overlayGranted
                          ? _trOr(l10n, 'live_overlay_on_tooltip', 'Overlay is ON')
                          : _trOr(l10n, 'live_overlay_permission_needed_tooltip', 'Overlay needs permission'))
                      : _trOr(l10n, 'live_overlay_off_tooltip', 'Overlay is OFF'),
                  onPressed: _toggleOverlayFromHome,
                  icon: Icon(overlayIcon, color: overlayIconColor),
                ),
                IconButton(
                  tooltip: l10n.homeSettingsTooltip,
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                ),
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
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
                child: Glass(
                  padding: EdgeInsets.zero,
                  borderRadius: 28,
                  child: Theme(
                    data: theme.copyWith(
                      navigationBarTheme: NavigationBarThemeData(
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        indicatorColor: colorScheme.primary.withOpacity(0.18),
                        labelTextStyle: WidgetStateProperty.resolveWith((states) {
                          final selected = states.contains(WidgetState.selected);
                          return TextStyle(
                            color: selected ? colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.55),
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          );
                        }),
                        iconTheme: WidgetStateProperty.resolveWith((states) {
                          final selected = states.contains(WidgetState.selected);
                          return IconThemeData(
                            color: selected ? colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.55),
                            size: 24,
                          );
                        }),
                      ),
                    ),
                    child: NavigationBar(
                      height: 68,
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      indicatorColor: colorScheme.primary.withOpacity(0.18),
                      selectedIndex: _index,
                      onDestinationSelected: _onDestinationSelected,
                      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
                        NavigationDestination(
                          icon: const Icon(Icons.public_outlined),
                          selectedIcon: const Icon(Icons.public),
                          label: l10n.homeTabLive,
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
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = theme.textTheme;

    final secondary = cs.onSurface.withOpacity(0.55);
    final tertiary = cs.onSurface.withOpacity(0.45);
    final faint = cs.onSurface.withOpacity(0.30);

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 100),
      children: [
        Glass(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withOpacity(0.35),
                      cs.primary.withOpacity(0.10),
                    ],
                  ),
                ),
                child: Icon(Icons.sports_esports_rounded, color: cs.primary, size: 26),
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
                        fontSize: 22,
                        letterSpacing: -0.5,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.homeMvpDescription,
                      style: TextStyle(
                        color: secondary,
                        fontWeight: FontWeight.w600,
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
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            _trOr(l10n, 'home_quick_actions_title', 'Quick Actions'),
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: cs.onSurface,
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
                gradient: [
                  cs.primary.withOpacity(0.20),
                  cs.primary.withOpacity(0.05),
                ],
                onTap: () => context.push('/leagues/create'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.confirmation_number_outlined,
                title: l10n.homeQuickJoinLiveTitle,
                subtitle: l10n.homeQuickJoinLiveSubtitle,
                gradient: [
                  const Color(0xFF00E676).withOpacity(0.20),
                  const Color(0xFF00E676).withOpacity(0.05),
                ],
                onTap: () => context.push('/live/join'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _QuickActionCard(
          icon: Icons.headset_mic_rounded,
          title: _trOr(l10n, 'home_quick_voice_room_title', 'Voice Room'),
          subtitle: _trOr(l10n, 'home_quick_voice_room_subtitle', 'Create/Join with 8-digit code'),
          gradient: [
            Colors.purple.withOpacity(0.20),
            Colors.purple.withOpacity(0.05),
          ],
          onTap: () => context.push('/call'),
          isWide: true,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            _trOr(l10n, 'home_explore_title', 'Explore'),
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: cs.onSurface,
            ),
          ),
        ),
        Glass(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              _ExploreRow(
                icon: Icons.forum_rounded,
                title: _trOr(l10n, 'home_explore_global_chat', 'Global Chat'),
                subtitle: _trOr(l10n, 'home_explore_global_chat_sub', 'Request access & chat in realtime'),
                onTap: () => context.push('/global-chat'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(color: cs.onSurface.withOpacity(0.08), height: 1),
              _ExploreRow(
                icon: Icons.public_rounded,
                title: _trOr(l10n, 'home_explore_global_leagues', 'Global Leagues'),
                subtitle: _trOr(l10n, 'home_explore_global_leagues_sub', 'Discover & join public leagues'),
                onTap: () => context.push('/global-live'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(color: cs.onSurface.withOpacity(0.08), height: 1),
              _ExploreRow(
                icon: Icons.storefront_rounded,
                title: _trOr(l10n, 'home_explore_marketplace', 'Marketplace'),
                subtitle: _trOr(l10n, 'home_explore_marketplace_sub', 'Browse gaming gear & accessories'),
                onTap: () => context.push('/marketplace'),
                secondaryColor: tertiary,
                chevronColor: faint,
              ),
              Divider(color: cs.onSurface.withOpacity(0.08), height: 1),
              _ExploreRow(
                icon: Icons.emoji_events_rounded,
                title: _trOr(l10n, 'home_explore_my_leagues', 'My Leagues'),
                subtitle: _trOr(l10n, 'home_explore_my_leagues_sub', 'View and manage your leagues'),
                onTap: () => context.push('/leagues'),
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

class _QuickActionCardState extends State<_QuickActionCard> with SingleTickerProviderStateMixin {
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
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
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
    final cs = theme.colorScheme;

    final secondary = cs.onSurface.withOpacity(0.50);
    final tertiary = cs.onSurface.withOpacity(0.45);
    final faint = cs.onSurface.withOpacity(0.30);

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Glass(
          padding: EdgeInsets.zero,
          borderRadius: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.onSurface.withOpacity(0.06),
                          border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                        ),
                        child: Icon(widget.icon, color: cs.primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              style: TextStyle(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 16, color: faint),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.onSurface.withOpacity(0.06),
                          border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                        ),
                        child: Icon(widget.icon, color: cs.primary, size: 20),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tertiary,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withOpacity(0.12),
              ),
              child: Icon(icon, color: cs.primary, size: 20),
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
                      color: cs.onSurface,
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
            Icon(Icons.chevron_right_rounded, color: chevronColor, size: 22),
          ],
        ),
      ),
    );
  }
}
