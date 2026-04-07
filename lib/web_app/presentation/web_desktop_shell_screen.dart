import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import 'screens/web_create_master_league_screen.dart';
import 'screens/web_league_management_screen.dart';
import 'screens/web_master_leagues_list_screen.dart';
import 'screens/web_pricing_admin_screen.dart';
import 'web_desktop_session_store.dart';

class WebDesktopShellScreen extends StatefulWidget {
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;
  final VoidCallback? onUnlink;

  const WebDesktopShellScreen({
    super.key,
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
    this.onUnlink,
  });

  @override
  State<WebDesktopShellScreen> createState() =>
      _WebDesktopShellScreenState();
}

class _WebDesktopShellScreenState extends State<WebDesktopShellScreen>
    with WidgetsBindingObserver {
  static const String _staticAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  static const Color _accent = AppTheme.limeAccentDark;

  int _selectedIndex = 0;
  bool _isAdmin = false;
  bool _showCreateWorkspace = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAdmin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  Future<void> _checkAdmin() async {
    final uid = widget.pairedUserUid.trim();
    if (uid.isEmpty) return;

    if (uid == _staticAdminUid) {
      if (mounted) {
        setState(() => _isAdmin = true);
      }
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('app')
          .doc('admins')
          .get();
      if (!snap.exists) return;
      final list = snap.data()?['pricingAdmins'];
      if (list is List &&
          list.any((v) => v.toString().trim() == uid)) {
        if (mounted) {
          setState(() => _isAdmin = true);
        }
      }
    } catch (_) {}
  }

  List<_NavItem> get _navItems => [
        const _NavItem(
          label: 'Home',
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
        ),
        const _NavItem(
          label: 'Leagues',
          icon: Icons.emoji_events_outlined,
          activeIcon: Icons.emoji_events_rounded,
        ),
        const _NavItem(
          label: 'Organizers',
          icon: Icons.hub_outlined,
          activeIcon: Icons.hub_rounded,
        ),
        const _NavItem(
          label: 'Discover',
          icon: Icons.travel_explore_outlined,
          activeIcon: Icons.travel_explore_rounded,
        ),
        const _NavItem(
          label: 'Marketplace',
          icon: Icons.storefront_outlined,
          activeIcon: Icons.storefront_rounded,
        ),
        if (_isAdmin)
          const _NavItem(
            label: 'Admin',
            icon: Icons.admin_panel_settings_outlined,
            activeIcon: Icons.admin_panel_settings_rounded,
          ),
      ];

  int get _safeSelectedIndex {
    final items = _navItems;
    if (items.isEmpty) return 0;
    if (_selectedIndex < 0) return 0;
    if (_selectedIndex >= items.length) return 0;
    return _selectedIndex;
  }

  String get _currentTitle {
    if (_showCreateWorkspace) return 'Create Workspace';
    final items = _navItems;
    if (items.isEmpty) return 'Home';
    return items[_safeSelectedIndex].label;
  }

  Future<void> _logoutDesktop() async {
    await WebDesktopSessionStore.clear();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    widget.onUnlink?.call();
  }

  void _openPanelByLabel(String label) {
    final index = _navItems.indexWhere((e) => e.label == label);
    if (index < 0) return;
    if (!mounted) return;
    setState(() {
      _showCreateWorkspace = false;
      _selectedIndex = index;
    });
  }

  void _openCreateWorkspace() {
    if (!mounted) return;
    setState(() {
      _showCreateWorkspace = true;
    });
  }

  void _openAccountSheet() {
    final brightness = Theme.of(context).brightness;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Glass(
                borderRadius: 22,
                padding: const EdgeInsets.all(20),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Linked account',
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _InfoRowSimple(
                      label: 'Name',
                      value: widget.pairedUserName,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 8),
                    _InfoRowSimple(
                      label: 'Email',
                      value: widget.pairedUserEmail,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 8),
                    _InfoRowSimple(
                      label: 'UID',
                      value: widget.pairedUserUid,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _logoutDesktop();
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Unlink desktop'),
                      ),
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

  Widget _buildCenterPanel() {
    if (_showCreateWorkspace) {
      return const WebCreateMasterLeagueScreen();
    }

    final items = _navItems;
    if (items.isEmpty) {
      return _ErrorPanel(
        title: 'No navigation items',
        message: 'No sections are currently available.',
        brightness: Theme.of(context).brightness,
      );
    }

    final label = items[_safeSelectedIndex].label;
    final brightness = Theme.of(context).brightness;

    try {
      switch (label) {
        case 'Leagues':
          return WebLeagueManagementScreen(
            pairedUserUid: widget.pairedUserUid,
          );
        case 'Organizers':
          return const WebMasterLeaguesListScreen();
        case 'Admin':
          return WebPricingAdminScreen(
            pairedUserUid: widget.pairedUserUid,
          );
        case 'Discover':
          return _DiscoverPanel(brightness: brightness);
        case 'Marketplace':
          return _MarketplacePanel(brightness: brightness);
        default:
          return _HomePanel(
            pairedUserUid: widget.pairedUserUid,
            pairedUserName: widget.pairedUserName,
            pairedUserEmail: widget.pairedUserEmail,
            brightness: brightness,
            onOpenLeagues: () => _openPanelByLabel('Leagues'),
            onOpenOrganizers: () => _openPanelByLabel('Organizers'),
            onOpenDiscover: () => _openPanelByLabel('Discover'),
            onOpenMarketplace: () => _openPanelByLabel('Marketplace'),
            onOpenCreateWorkspace: _openCreateWorkspace,
          );
      }
    } catch (e) {
      return _ErrorPanel(
        title: 'Screen failed to load',
        message: e.toString(),
        brightness: brightness,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final brightness = Theme.of(context).brightness;
    final items = _navItems;
    final selectedIndex = _safeSelectedIndex;

    if (width < 760) {
      return _buildMobileLayout(context, items, selectedIndex, brightness);
    }
    if (width < 1180) {
      return _buildTabletLayout(context, items, selectedIndex, brightness);
    }
    return _buildDesktopLayout(context, items, selectedIndex, brightness);
  }

  Widget _buildMobileLayout(
    BuildContext context,
    List<_NavItem> items,
    int selectedIndex,
    Brightness brightness,
  ) {
    return GlassScaffold(
      useBubbles: false,
      bottomNavigationBar: _showCreateWorkspace
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) {
                setState(() {
                  _showCreateWorkspace = false;
                  _selectedIndex = i;
                });
              },
              destinations: items
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
      body: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            titleSpacing: 12,
            title: Row(
              children: [
                const _BrandLogo(size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'eSportlyic Web',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            leading: _showCreateWorkspace
                ? IconButton(
                    tooltip: 'Back',
                    onPressed: () {
                      setState(() => _showCreateWorkspace = false);
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            actions: [
              IconButton(
                tooltip: 'Account',
                onPressed: _openAccountSheet,
                icon: const Icon(Icons.person_outline_rounded),
              ),
            ],
          ),
          body: _buildCenterPanel(),
        ),
      ),
    );
  }

  Widget _buildTabletLayout(
    BuildContext context,
    List<_NavItem> items,
    int selectedIndex,
    Brightness brightness,
  ) {
    final width = MediaQuery.of(context).size.width;

    return GlassScaffold(
      useBubbles: false,
      body: SafeArea(
        child: Row(
          children: [
            if (!_showCreateWorkspace)
              _TabletSidebar(
                items: items,
                selectedIndex: selectedIndex,
                brightness: brightness,
                onSelect: (i) => setState(() {
                  _showCreateWorkspace = false;
                  _selectedIndex = i;
                }),
                onLogout: _logoutDesktop,
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: _currentTitle,
                    pairedUserName: widget.pairedUserName,
                    onOpenAccount: _openAccountSheet,
                    brightness: brightness,
                    showBack: _showCreateWorkspace,
                    onBack: () => setState(() => _showCreateWorkspace = false),
                  ),
                  Expanded(child: _buildCenterPanel()),
                ],
              ),
            ),
            if (width >= 980 && !_showCreateWorkspace)
              SizedBox(
                width: 280,
                child: _RightPanel(
                  pairedUserUid: widget.pairedUserUid,
                  pairedUserName: widget.pairedUserName,
                  pairedUserEmail: widget.pairedUserEmail,
                  brightness: brightness,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    List<_NavItem> items,
    int selectedIndex,
    Brightness brightness,
  ) {
    return GlassScaffold(
      useBubbles: false,
      body: SafeArea(
        child: Row(
          children: [
            if (!_showCreateWorkspace)
              _DesktopSidebar(
                items: items,
                selectedIndex: selectedIndex,
                brightness: brightness,
                pairedUserName: widget.pairedUserName,
                pairedUserEmail: widget.pairedUserEmail,
                onSelect: (i) => setState(() {
                  _showCreateWorkspace = false;
                  _selectedIndex = i;
                }),
                onLogout: _logoutDesktop,
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: _currentTitle,
                    pairedUserName: widget.pairedUserName,
                    onOpenAccount: _openAccountSheet,
                    brightness: brightness,
                    showBack: _showCreateWorkspace,
                    onBack: () => setState(() => _showCreateWorkspace = false),
                  ),
                  Expanded(child: _buildCenterPanel()),
                ],
              ),
            ),
            if (!_showCreateWorkspace)
              SizedBox(
                width: 300,
                child: _RightPanel(
                  pairedUserUid: widget.pairedUserUid,
                  pairedUserName: widget.pairedUserName,
                  pairedUserEmail: widget.pairedUserEmail,
                  brightness: brightness,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class _TopBar extends StatelessWidget {
  final String title;
  final String pairedUserName;
  final VoidCallback onOpenAccount;
  final Brightness brightness;
  final bool showBack;
  final VoidCallback? onBack;

  const _TopBar({
    required this.title,
    required this.pairedUserName,
    required this.onOpenAccount,
    required this.brightness,
    this.showBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorder(brightness)),
        ),
      ),
      child: Row(
        children: [
          if (showBack) ...[
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpenAccount,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.searchBackground(brightness),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.searchOutline(brightness)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.laptop_mac_rounded,
                    color: AppTheme.limeAccentDark,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pairedUserName.trim().isEmpty ? 'Linked' : pairedUserName,
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletSidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final Brightness brightness;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _TabletSidebar({
    required this.items,
    required this.selectedIndex,
    required this.brightness,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        border: Border(
          right: BorderSide(color: AppTheme.cardBorder(brightness)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const _BrandLogo(size: 32),
          const SizedBox(height: 12),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: selectedIndex,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              indicatorColor: AppTheme.limeAccent,
              selectedIconTheme:
                  const IconThemeData(color: AppTheme.limeAccentDark),
              selectedLabelTextStyle: const TextStyle(
                color: AppTheme.limeAccentDark,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
              unselectedIconTheme: IconThemeData(
                color: AppTheme.secondaryText(brightness),
              ),
              unselectedLabelTextStyle: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              onDestinationSelected: onSelect,
              destinations: items
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: IconButton(
              tooltip: 'Unlink desktop',
              onPressed: onLogout,
              icon: Icon(
                Icons.logout_rounded,
                color: AppTheme.secondaryText(brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final Brightness brightness;
  final String pairedUserName;
  final String pairedUserEmail;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _DesktopSidebar({
    required this.items,
    required this.selectedIndex,
    required this.brightness,
    required this.pairedUserName,
    required this.pairedUserEmail,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final initials = pairedUserName.trim().isNotEmpty
        ? pairedUserName.trim().substring(0, 1).toUpperCase()
        : 'E';

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        border: Border(
          right: BorderSide(color: AppTheme.cardBorder(brightness)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    const _BrandLogo(size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'eSportlyic Web',
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.searchBackground(brightness),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppTheme.searchOutline(brightness)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            AppTheme.iconCircleBackground(brightness),
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pairedUserName.trim().isNotEmpty
                                  ? pairedUserName
                                  : 'eSportlyic User',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (pairedUserEmail.trim().isNotEmpty)
                              Text(
                                pairedUserEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _SidebarTile(
                item: items[i],
                selected: selectedIndex == i,
                accent: AppTheme.limeAccentDark,
                brightness: brightness,
                onTap: () => onSelect(i),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Unlink desktop'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final Color accent;
  final Brightness brightness;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.accent,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? AppTheme.primaryText(brightness)
        : AppTheme.secondaryText(brightness);

    return Material(
      color: selected
          ? (brightness == Brightness.dark
              ? AppTheme.limeAccentDark.withOpacity(0.10)
              : const Color(0xFFECFCCB))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                color: selected ? accent : fg,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;
  final Brightness brightness;

  const _RightPanel({
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        border: Border(
          left: BorderSide(color: AppTheme.cardBorder(brightness)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FlatPanel(
            brightness: brightness,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Linked account',
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRowSimple(
                  label: 'Name',
                  value: pairedUserName.isEmpty ? 'N/A' : pairedUserName,
                  brightness: brightness,
                ),
                const SizedBox(height: 8),
                _InfoRowSimple(
                  label: 'Email',
                  value: pairedUserEmail.isEmpty ? 'N/A' : pairedUserEmail,
                  brightness: brightness,
                ),
                const SizedBox(height: 8),
                _InfoRowSimple(
                  label: 'UID',
                  value: pairedUserUid.isEmpty ? 'N/A' : pairedUserUid,
                  brightness: brightness,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _FlatPanel(
            brightness: brightness,
            child: Text(
              'This shell was simplified for speed. Home quick actions open organizer workspaces and workspace creation directly with less UI overhead.',
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlatPanel extends StatelessWidget {
  final Brightness brightness;
  final Widget child;

  const _FlatPanel({
    required this.brightness,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: child,
    );
  }
}

class _InfoRowSimple extends StatelessWidget {
  final String label;
  final String value;
  final Brightness brightness;

  const _InfoRowSimple({
    required this.label,
    required this.value,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.secondaryText(brightness),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        SelectableText(
          value,
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final double size;

  const _BrandLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 10,
      height: size + 10,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.limeAccent,
      ),
      padding: const EdgeInsets.all(5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.sports_esports_rounded,
            color: AppTheme.darkText,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String title;
  final String message;
  final Brightness brightness;

  const _ErrorPanel({
    required this.title,
    required this.message,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(20),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppTheme.limeAccentDark,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePanel extends StatelessWidget {
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;
  final Brightness brightness;
  final VoidCallback onOpenLeagues;
  final VoidCallback onOpenOrganizers;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenMarketplace;
  final VoidCallback onOpenCreateWorkspace;

  const _HomePanel({
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
    required this.brightness,
    required this.onOpenLeagues,
    required this.onOpenOrganizers,
    required this.onOpenDiscover,
    required this.onOpenMarketplace,
    required this.onOpenCreateWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(pairedUserUid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final teamName = (data['teamName'] ?? '').toString().trim();
        final width = MediaQuery.of(context).size.width;
        final compact = width < 980;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Welcome back${pairedUserName.trim().isNotEmpty ? ', $pairedUserName' : ''}',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pairedUserEmail.trim().isNotEmpty
                  ? pairedUserEmail
                  : 'Your eSportlyic desktop session is active.',
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            _FlatPanel(
              brightness: brightness,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick stats',
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickStat(
                          label: 'Status',
                          value: 'Linked',
                          icon: Icons.link_rounded,
                          brightness: brightness,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickStat(
                          label: 'Mode',
                          value: 'Desktop',
                          icon: Icons.laptop_mac_rounded,
                          brightness: brightness,
                        ),
                      ),
                      if (teamName.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickStat(
                            label: 'Team',
                            value: teamName,
                            icon: Icons.shield_rounded,
                            brightness: brightness,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quick actions',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            if (compact)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _HomeActionCard(
                          icon: Icons.hub_rounded,
                          title: 'Organizers',
                          subtitle: 'Open organizer workspaces',
                          brightness: brightness,
                          onTap: onOpenOrganizers,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HomeActionCard(
                          icon: Icons.add_circle_outline_rounded,
                          title: 'Create',
                          subtitle: 'Create a workspace now',
                          brightness: brightness,
                          onTap: onOpenCreateWorkspace,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _HomeActionCard(
                          icon: Icons.travel_explore_rounded,
                          title: 'Discover',
                          subtitle: 'Browse public organizers',
                          brightness: brightness,
                          onTap: onOpenDiscover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HomeActionCard(
                          icon: Icons.storefront_rounded,
                          title: 'Marketplace',
                          subtitle: 'Open products and offers',
                          brightness: brightness,
                          onTap: onOpenMarketplace,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.7,
                children: [
                  _HomeActionCard(
                    icon: Icons.hub_rounded,
                    title: 'Organizers',
                    subtitle: 'Open organizer workspaces',
                    brightness: brightness,
                    onTap: onOpenOrganizers,
                  ),
                  _HomeActionCard(
                    icon: Icons.add_circle_outline_rounded,
                    title: 'Create',
                    subtitle: 'Create a workspace now',
                    brightness: brightness,
                    onTap: onOpenCreateWorkspace,
                  ),
                  _HomeActionCard(
                    icon: Icons.travel_explore_rounded,
                    title: 'Discover',
                    subtitle: 'Browse public organizers',
                    brightness: brightness,
                    onTap: onOpenDiscover,
                  ),
                  _HomeActionCard(
                    icon: Icons.storefront_rounded,
                    title: 'Marketplace',
                    subtitle: 'Open products and offers',
                    brightness: brightness,
                    onTap: onOpenMarketplace,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Brightness brightness;

  const _QuickStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.limeAccentDark, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Brightness brightness;
  final VoidCallback onTap;

  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardColor(brightness),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder(brightness)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.limeAccentDark.withOpacity(0.12),
                ),
                child: Icon(
                  icon,
                  color: AppTheme.limeAccentDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.secondaryText(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverPanel extends StatelessWidget {
  final Brightness brightness;

  const _DiscoverPanel({required this.brightness});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('master_leagues')
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _ErrorPanel(
            title: 'Failed to load organizers',
            message: snap.error.toString(),
            brightness: brightness,
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Organizer discovery',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty)
              Text(
                'No organizers yet.',
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                ),
              )
            else
              ...docs.map((doc) {
                final d = doc.data();
                final name = (d['name'] ?? 'Organizer').toString();
                final bio = (d['bio'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FlatPanel(
                    brightness: brightness,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            bio,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _MarketplacePanel extends StatelessWidget {
  final Brightness brightness;

  const _MarketplacePanel({required this.brightness});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('marketplace_products')
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _ErrorPanel(
            title: 'Failed to load marketplace',
            message: snap.error.toString(),
            brightness: brightness,
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Marketplace',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty)
              Text(
                'No products yet.',
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                ),
              )
            else
              ...docs.map((doc) {
                final d = doc.data();
                final name = (d['name'] ?? 'Product').toString();
                final price = (d['price'] ?? '').toString();
                final seller = (d['sellerName'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FlatPanel(
                    brightness: brightness,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (seller.isNotEmpty)
                                Text(
                                  seller,
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (price.isNotEmpty)
                          Text(
                            price,
                            style: TextStyle(
                              color: AppTheme.limeAccentDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
