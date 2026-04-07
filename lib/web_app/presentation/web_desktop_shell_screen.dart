import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  State<WebDesktopShellScreen> createState() => _WebDesktopShellScreenState();
}

class _WebDesktopShellScreenState extends State<WebDesktopShellScreen>
    with WidgetsBindingObserver {
  static const String _staticAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  int _selectedIndex = 0;
  bool _isAdmin = false;

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
      if (mounted) setState(() => _isAdmin = true);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('app')
          .doc('admins')
          .get();
      if (!snap.exists) return;
      final list = snap.data()?['pricingAdmins'];
      if (list is List && list.any((v) => v.toString().trim() == uid)) {
        if (mounted) setState(() => _isAdmin = true);
      }
    } catch (_) {}
  }

  List<_NavItem> get _navItems => [
        const _NavItem(
          label: 'Home',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
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
    if (_selectedIndex < 0 || _selectedIndex >= items.length) return 0;
    return _selectedIndex;
  }

  String get _currentTitle {
    final items = _navItems;
    if (items.isEmpty) return 'Dashboard';
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
    setState(() => _selectedIndex = index);
  }

  void _openCreateWorkspace() => context.push('/master-leagues/create');
  void _openCreateLeague() => context.push('/leagues/create');

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
                borderRadius: 28,
                padding: const EdgeInsets.all(24),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.limeAccent.withOpacity(0.1),
                          ),
                          child: const Icon(
                            Icons.laptop_mac_rounded,
                            color: AppTheme.limeAccentDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Active Desktop Session',
                            style: TextStyle(
                              color: AppTheme.primaryText(brightness),
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _InfoRowPremium(
                      label: 'Account Name',
                      value: widget.pairedUserName,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 12),
                    _InfoRowPremium(
                      label: 'Email Address',
                      value: widget.pairedUserEmail,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 12),
                    _InfoRowPremium(
                      label: 'Session ID',
                      value: widget.pairedUserUid,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.15),
                          foregroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _logoutDesktop();
                        },
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text(
                          'Unlink Device',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
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
    final items = _navItems;
    if (items.isEmpty) return const SizedBox.shrink();

    final label = items[_safeSelectedIndex].label;
    final brightness = Theme.of(context).brightness;

    try {
      switch (label) {
        case 'Leagues':
          return WebLeagueManagementScreen(pairedUserUid: widget.pairedUserUid);
        case 'Organizers':
          return const WebMasterLeaguesListScreen();
        case 'Admin':
          return WebPricingAdminScreen(pairedUserUid: widget.pairedUserUid);
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
            onOpenOrganizers: () => context.push('/master-leagues'),
            onOpenDiscover: () => context.push('/organizer-discovery'),
            onOpenMarketplace: () => context.push('/marketplace'),
            onOpenCreateWorkspace: _openCreateWorkspace,
            onOpenCreateLeague: _openCreateLeague,
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

  Widget _buildMobileLayout(BuildContext context, List<_NavItem> items,
      int selectedIndex, Brightness brightness) {
    return GlassScaffold(
      useBubbles: false,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Glass(
            padding: EdgeInsets.zero,
            borderRadius: 28,
            fill: brightness == Brightness.dark
                ? AppTheme.darkNavBg
                : AppTheme.lightNavBg,
            borderColor: AppTheme.cardBorder(brightness),
            child: Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme: NavigationBarThemeData(
                  backgroundColor: Colors.transparent,
                  indicatorColor: AppTheme.limeAccent,
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return TextStyle(
                      color: selected
                          ? AppTheme.limeAccentDark
                          : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    );
                  }),
                ),
              ),
              child: NavigationBar(
                height: 68,
                selectedIndex: selectedIndex,
                onDestinationSelected: (i) =>
                    setState(() => _selectedIndex = i),
                destinations: items
                    .take(5)
                    .map((item) => NavigationDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.activeIcon),
                          label: item.label,
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                const _BrandLogo(size: 28),
                const SizedBox(width: 12),
                Text(
                  _currentTitle,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                padding: const EdgeInsets.only(right: 12),
                tooltip: 'Account',
                onPressed: _openAccountSheet,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.iconCircleBackground(brightness),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppTheme.cardBorder(brightness)),
                  ),
                  child:
                      const Icon(Icons.person_outline_rounded, size: 20),
                ),
              ),
            ],
          ),
          body: _buildCenterPanel(),
        ),
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, List<_NavItem> items,
      int selectedIndex, Brightness brightness) {
    return GlassScaffold(
      useBubbles: false,
      body: SafeArea(
        child: Row(
          children: [
            _TabletSidebar(
              items: items,
              selectedIndex: selectedIndex,
              brightness: brightness,
              onSelect: (i) => setState(() => _selectedIndex = i),
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
                  ),
                  Expanded(child: _buildCenterPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, List<_NavItem> items,
      int selectedIndex, Brightness brightness) {
    return GlassScaffold(
      useBubbles: false,
      body: SafeArea(
        child: Row(
          children: [
            _DesktopSidebar(
              items: items,
              selectedIndex: selectedIndex,
              brightness: brightness,
              pairedUserName: widget.pairedUserName,
              pairedUserEmail: widget.pairedUserEmail,
              onSelect: (i) => setState(() => _selectedIndex = i),
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
                  ),
                  Expanded(child: _buildCenterPanel()),
                ],
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

  const _TopBar({
    required this.title,
    required this.pairedUserName,
    required this.onOpenAccount,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness).withOpacity(0.5),
        border: Border(
            bottom: BorderSide(color: AppTheme.cardBorder(brightness))),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpenAccount,
            child: Glass(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              fill: AppTheme.searchBackground(brightness),
              borderColor: AppTheme.searchOutline(brightness),
              child: Row(
                children: [
                  const Icon(
                    Icons.laptop_mac_rounded,
                    color: AppTheme.limeAccentDark,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    pairedUserName.trim().isEmpty
                        ? 'Session Active'
                        : pairedUserName,
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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
      width: 100,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness).withOpacity(0.4),
        border: Border(
            right: BorderSide(color: AppTheme.cardBorder(brightness))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const _BrandLogo(size: 38),
          const SizedBox(height: 24),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: selectedIndex,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              indicatorColor: AppTheme.limeAccent,
              selectedIconTheme: const IconThemeData(
                  color: AppTheme.limeAccentDark, size: 26),
              selectedLabelTextStyle: const TextStyle(
                color: AppTheme.limeAccentDark,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
              unselectedIconTheme: IconThemeData(
                color: AppTheme.secondaryText(brightness),
                size: 24,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              onDestinationSelected: onSelect,
              destinations: items
                  .map((item) => NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.activeIcon),
                        label: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(item.label),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: IconButton(
              tooltip: 'Unlink',
              onPressed: onLogout,
              icon: Icon(Icons.logout_rounded,
                  color: AppTheme.secondaryText(brightness)),
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
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness).withOpacity(0.4),
        border: Border(
            right: BorderSide(color: AppTheme.cardBorder(brightness))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Row(
              children: [
                const _BrandLogo(size: 32),
                const SizedBox(width: 14),
                Text(
                  'eSportlyic',
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _SidebarTile(
                item: items[i],
                selected: selectedIndex == i,
                brightness: brightness,
                onTap: () => onSelect(i),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Glass(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              fill: AppTheme.searchBackground(brightness),
              borderColor: AppTheme.searchOutline(brightness),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workspace Link',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                            color: AppTheme.cardBorder(brightness)),
                        foregroundColor:
                            AppTheme.primaryText(brightness),
                      ),
                      onPressed: onLogout,
                      icon:
                          const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Unlink Desktop',
                          style:
                              TextStyle(fontWeight: FontWeight.w800)),
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

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final Brightness brightness;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final fg = selected
        ? AppTheme.limeAccentDark
        : AppTheme.secondaryText(brightness);
    final bg = selected
        ? (isDark
            ? AppTheme.limeAccentDark.withOpacity(0.12)
            : const Color(0xFFECFCCB))
        : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(selected ? item.activeIcon : item.icon,
                  color: fg, size: 22),
              const SizedBox(width: 14),
              Text(
                item.label,
                style: TextStyle(
                  color: selected
                      ? AppTheme.primaryText(brightness)
                      : fg,
                  fontWeight:
                      selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRowPremium extends StatelessWidget {
  final String label;
  final String value;
  final Brightness brightness;

  const _InfoRowPremium({
    required this.label,
    required this.value,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value.isEmpty ? 'N/A' : value,
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

class _BrandLogo extends StatelessWidget {
  final double size;
  const _BrandLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 12,
      height: size + 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.4),
        color: AppTheme.limeAccent,
        boxShadow: [
          BoxShadow(
            color: AppTheme.limeAccent.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: EdgeInsets.all(size * 0.15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.sports_esports_rounded,
            color: AppTheme.darkText,
            size: size * 0.6,
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
          borderRadius: 24,
          padding: const EdgeInsets.all(32),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withOpacity(0.1),
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    height: 1.5),
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
  final VoidCallback onOpenCreateLeague;

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
    required this.onOpenCreateLeague,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(pairedUserUid)
          .snapshots(),
      builder: (context, snap) {
        final width = MediaQuery.of(context).size.width;
        final isMobile = width < 760;
        final isDark = brightness == Brightness.dark;

        return ListView(
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          physics: const BouncingScrollPhysics(),
          children: [
            Glass(
              borderRadius: 28,
              padding: const EdgeInsets.all(24),
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Stack(
                children: [
                  Positioned(
                    right: -30,
                    top: -30,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.limeAccent.withOpacity(0.08),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              AppTheme.iconCircleBackground(brightness),
                          border: Border.all(
                              color: AppTheme.cardBorder(brightness)),
                        ),
                        child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppTheme.limeAccentDark,
                            size: 32),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back${pairedUserName.trim().isNotEmpty ? ', $pairedUserName' : ''}',
                              style: TextStyle(
                                color:
                                    AppTheme.primaryText(brightness),
                                fontSize: isMobile ? 22 : 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Manage leagues, follow organizers, and explore premium experiences seamlessly from the web.',
                              style: TextStyle(
                                color: AppTheme.secondaryText(
                                    brightness),
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
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
            const SizedBox(height: 32),
            Text(
              'Quick Actions',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isMobile ? 1 : 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: isMobile ? 3.0 : 3.5,
              children: [
                _PremiumActionCard(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Create League',
                  subtitle: '3-step wizard',
                  gradient: isDark
                      ? [
                          AppTheme.limeAccentDark.withOpacity(0.12),
                          AppTheme.darkCard
                        ]
                      : [
                          const Color(0xFFECFCCB),
                          const Color(0xFFFFFFFF)
                        ],
                  iconColor: AppTheme.limeAccentDark,
                  brightness: brightness,
                  onTap: onOpenCreateLeague,
                ),
                _PremiumActionCard(
                  icon: Icons.hub_rounded,
                  title: 'Organizer Workspace',
                  subtitle: 'Premium hubs',
                  gradient: isDark
                      ? [
                          AppTheme.limeAccentDark.withOpacity(0.08),
                          AppTheme.darkCard
                        ]
                      : [
                          const Color(0xFFECFCCB),
                          const Color(0xFFF8FAFC)
                        ],
                  iconColor: AppTheme.limeAccentDark,
                  brightness: brightness,
                  onTap: onOpenOrganizers,
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Explore eSportlyic',
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
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
                    subtitle:
                        'Featured, verified, and active organizers',
                    onTap: onOpenDiscover,
                    brightness: brightness,
                  ),
                  Divider(
                      color: AppTheme.cardBorder(brightness),
                      height: 1),
                  _ExploreRow(
                    icon: Icons.storefront_rounded,
                    title: 'Marketplace',
                    subtitle: 'Browse gaming gear & accessories',
                    onTap: onOpenMarketplace,
                    brightness: brightness,
                  ),
                  Divider(
                      color: AppTheme.cardBorder(brightness),
                      height: 1),
                  _ExploreRow(
                    icon: Icons.emoji_events_rounded,
                    title: 'My Leagues',
                    subtitle:
                        'View and manage your current leagues',
                    onTap: onOpenLeagues,
                    brightness: brightness,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PremiumActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final Color iconColor;
  final Brightness brightness;
  final VoidCallback onTap;

  const _PremiumActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.iconColor,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: brightness == Brightness.dark
            ? [
                BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ]
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              border: Border.all(
                  color: AppTheme.cardBorder(brightness)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        AppTheme.iconCircleBackground(brightness),
                    border: Border.all(
                        color: AppTheme.cardBorder(brightness)),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color:
                              AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.secondaryText(
                                  brightness)
                              .withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.secondaryText(brightness)
                      .withOpacity(0.5),
                  size: 20,
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
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Brightness brightness;

  const _ExploreRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.iconCircleBackground(brightness),
                border: Border.all(
                    color: AppTheme.cardBorder(brightness)),
              ),
              child: const Icon(Icons.arrow_forward_rounded,
                  color: AppTheme.limeAccentDark, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color:
                          AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppTheme.secondaryText(brightness)
                    .withOpacity(0.5),
                size: 24),
          ],
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
    return Center(
      child: Text(
        'Lightweight Discover View\n(Or use the Quick Actions on Home)',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.secondaryText(brightness)),
      ),
    );
  }
}

class _MarketplacePanel extends StatelessWidget {
  final Brightness brightness;
  const _MarketplacePanel({required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Lightweight Marketplace View\n(Or use the Quick Actions on Home)',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.secondaryText(brightness)),
      ),
    );
  }
}
