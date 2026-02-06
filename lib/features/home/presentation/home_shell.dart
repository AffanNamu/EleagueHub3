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
import '../../social/domain/announcement.dart';
import '../../social/ui/widgets/glass_announcement.dart';

String _trOr(AppLocalizations l10n, String key, String fallback) {
  final v = l10n.tr(key);
  return v == key ? fallback : v;
}

/// HomeShell: Main tabbed scaffold for the app
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  late final List<Widget> _tabs;

  /// Lazy tab instantiation: we only build a tab the first time it's visited,
  /// and then keep its state alive (prevents reload loops / re-fetching).
  late final List<bool> _built;

  bool _overlayEnabled = false;
  bool _overlayGranted = false;

  // Prevent spamming platform calls from rebuilds.
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
            _trOr(
              l10n,
              'live_overlay_turn_off_body',
              'This will hide the floating voice/message controls.',
            ),
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
      setState(() {
        _overlayEnabled = false;
      });

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
            'This shows a floating voice/message control above other apps (games, browser). Android will ask for an “Appear on top” permission.',
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
        content: Text(_trOr(l10n, 'live_overlay_permission_snackbar', 'Grant the overlay permission, then return to the app.')),
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

    // Keep Android overlay quick messages in sync with Firestore (premium custom) as the user changes them.
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

    final overlayIconColor = !_overlayEnabled
        ? null
        : (_overlayGranted ? const Color(0xFF22C55E) : const Color(0xFFF59E0B));

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(theme.brightness),
        ),
        child: Scaffold(
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
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                borderRadius: 22,
                child: NavigationBar(
                  height: 64,
                  backgroundColor: Colors.transparent,
                  indicatorColor: colorScheme.primary.withOpacity(0.18),
                  selectedIndex: _index,
                  onDestinationSelected: _onDestinationSelected,
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
    );
  }
}

/// HomeTab: Default landing tab with quick cards & announcements
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  List<Announcement> _mockAnnouncements(AppLocalizations l10n) {
    return [
      Announcement(
        title: l10n.homeAnnouncement1Title,
        message: l10n.homeAnnouncement1Message,
        time: l10n.homeAnnouncement1Time,
      ),
      Announcement(
        title: l10n.homeAnnouncement2Title,
        message: l10n.homeAnnouncement2Message,
        time: l10n.homeAnnouncement2Time,
      ),
      Announcement(
        title: l10n.homeAnnouncement3Title,
        message: l10n.homeAnnouncement3Message,
        time: l10n.homeAnnouncement3Time,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = theme.textTheme;

    final onBg = theme.colorScheme.onBackground;
    final onSurface = theme.colorScheme.onSurface;

    final announcements = _mockAnnouncements(l10n);

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
      children: [
        Glass(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.homeWelcomeBack,
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.homeMvpDescription,
                style: t.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.72),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.homeAnnouncementsTitle,
          style: t.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: onBg.withOpacity(0.92),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: announcements.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final a = announcements[index];
              return GlassAnnouncement(
                title: a.title,
                message: a.message,
                time: a.time,
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        // Quick actions
        Glass(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _QuickCard(
                      icon: Icons.add_circle_outline,
                      title: l10n.homeQuickCreateLeagueTitle,
                      subtitle: l10n.homeQuickCreateLeagueSubtitle,
                      onTap: () => context.push('/leagues/create'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickCard(
                      icon: Icons.confirmation_number_outlined,
                      title: l10n.homeQuickJoinLiveTitle,
                      subtitle: l10n.homeQuickJoinLiveSubtitle,
                      onTap: () => context.push('/live/join'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _QuickCard(
                icon: Icons.headset_mic_outlined,
                title: _trOr(l10n, 'home_quick_voice_room_title', 'Voice Room'),
                subtitle: _trOr(l10n, 'home_quick_voice_room_subtitle', 'Create/Join with 8-digit code'),
                onTap: () => context.push('/call'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// QuickCard: Small card for home actions
class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 28,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withOpacity(0.70),
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
