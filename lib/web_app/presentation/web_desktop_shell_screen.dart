import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
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

  Future<void> _logoutDesktop() async {
    await WebDesktopSessionStore.clear();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    widget.onUnlink?.call();
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
                borderRadius: 24,
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

  Widget _buildPanel(int index) {
    final items = _navItems;
    if (items.isEmpty) {
      return _ErrorPanel(
        title: 'No navigation items',
        message: 'No sections are currently available.',
        brightness: Theme.of(context).brightness,
      );
    }

    final safeIndex = index.clamp(0, items.length - 1);
    final label = items[safeIndex].label;
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
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
            actions: [
              IconButton(
                tooltip: 'Account',
                onPressed: _openAccountSheet,
                icon: const Icon(Icons.person_outline_rounded),
              ),
            ],
          ),
          body: _buildPanel(selectedIndex),
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
      body: SafeArea(
        child: Row(
          children: [
            Glass(
              borderRadius: 0,
              padding: EdgeInsets.zero,
              fill: AppTheme.cardColor(brightness),
              border: false,
              child: SizedBox(
                width: 96,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    const _BrandLogo(size: 34),
                    const SizedBox(height: 12),
                    Expanded(
                      child: NavigationRail(
                        backgroundColor: Colors.transparent,
                        selectedIndex: selectedIndex,
                        labelType: NavigationRailLabelType.all,
                        groupAlignment: -1,
                        indicatorColor: AppTheme.limeAccent,
                        selectedIconTheme:
                            const IconThemeData(color: _accent),
                        selectedLabelTextStyle: const TextStyle(
                          color: _accent,
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
                        onDestinationSelected: (i) =>
                            setState(() => _selectedIndex = i),
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
                        onPressed: _logoutDesktop,
                        icon: Icon(
                          Icons.logout_rounded,
                          color: AppTheme.secondaryText(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: items[selectedIndex].label,
                    pairedUserName: widget.pairedUserName,
                    onOpenAccount: _openAccountSheet,
                    brightness: brightness,
                  ),
                  Expanded(child: _buildPanel(selectedIndex)),
                ],
              ),
            ),
            if (width >= 960)
              SizedBox(
                width: 290,
                child: Glass(
                  borderRadius: 0,
                  padding: EdgeInsets.zero,
                  fill: AppTheme.cardColor(brightness),
                  border: false,
                  child: _RightPanel(
                    pairedUserUid: widget.pairedUserUid,
                    pairedUserName: widget.pairedUserName,
                    pairedUserEmail: widget.pairedUserEmail,
                    brightness: brightness,
                  ),
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
      body: SafeArea(
        child: Row(
          children: [
            Glass(
              borderRadius: 0,
              padding: EdgeInsets.zero,
              fill: AppTheme.cardColor(brightness),
              border: false,
              child: SizedBox(
                width: 280,
                child: Column(
                  children: [
                    _SidebarHeader(
                      pairedUserName: widget.pairedUserName,
                      pairedUserEmail: widget.pairedUserEmail,
                      brightness: brightness,
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, i) => _SidebarTile(
                          item: items[i],
                          selected: selectedIndex == i,
                          accent: _accent,
                          brightness: brightness,
                          onTap: () => setState(() => _selectedIndex = i),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _logoutDesktop,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Unlink desktop'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: items[selectedIndex].label,
                    pairedUserName: widget.pairedUserName,
                    onOpenAccount: _openAccountSheet,
                    brightness: brightness,
                  ),
                  Expanded(
                    child: _buildPanel(selectedIndex),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 320,
              child: Glass(
                borderRadius: 0,
                padding: EdgeInsets.zero,
                fill: AppTheme.cardColor(brightness),
                border: false,
                child: _RightPanel(
                  pairedUserUid: widget.pairedUserUid,
                  pairedUserName: widget.pairedUserName,
                  pairedUserEmail: widget.pairedUserEmail,
                  brightness: brightness,
                ),
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
    return Glass(
      borderRadius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      fill: AppTheme.cardColor(brightness),
      border: false,
      child: Row(
        children: [
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

class _SidebarHeader extends StatelessWidget {
  final String pairedUserName;
  final String pairedUserEmail;
  final Brightness brightness;

  const _SidebarHeader({
    required this.pairedUserName,
    required this.pairedUserEmail,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final initials = pairedUserName.trim().isNotEmpty
        ? pairedUserName.trim().substring(0, 1).toUpperCase()
        : 'E';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
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
          Glass(
            borderRadius: 16,
            padding: const EdgeInsets.all(12),
            fill: AppTheme.searchBackground(brightness),
            borderColor: AppTheme.searchOutline(brightness),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
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
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Text(
            'Use the Organizers panel to manage organizer workspaces, or select a league from the Leagues panel to manage fixtures, scores, and standings.',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              height: 1.5,
            ),
          ),
        ),
      ],
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

  const _HomePanel({
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
    required this.brightness,
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
            const SizedBox(height: 20),
            Glass(
              borderRadius: 20,
              padding: const EdgeInsets.all(20),
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
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
    return Glass(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      fill: AppTheme.searchBackground(brightness),
      borderColor: AppTheme.searchOutline(brightness),
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

class _DiscoverPanel extends StatelessWidget {
  final Brightness brightness;

  const _DiscoverPanel({required this.brightness});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('master_leagues')
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
              ...docs.take(20).map((doc) {
                final d = doc.data();
                final name = (d['name'] ?? 'Organizer').toString();
                final bio = (d['bio'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(16),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
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
              ...docs.take(20).map((doc) {
                final d = doc.data();
                final name = (d['name'] ?? 'Product').toString();
                final price = (d['price'] ?? '').toString();
                final seller = (d['sellerName'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(16),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
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
