import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import 'web_desktop_session_store.dart';

class WebDesktopShellScreen extends StatefulWidget {
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;

  const WebDesktopShellScreen({
    super.key,
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
  });

  @override
  State<WebDesktopShellScreen> createState() => _WebDesktopShellScreenState();
}

class _WebDesktopShellScreenState extends State<WebDesktopShellScreen> {
  static const Color _accent = AppTheme.navyAccent;

  int _selectedIndex = 0;

  final List<_DesktopNavItem> _items = const [
    _DesktopNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
    ),
    _DesktopNavItem(
      label: 'Leagues',
      icon: Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events,
    ),
    _DesktopNavItem(
      label: 'Discover',
      icon: Icons.travel_explore_outlined,
      activeIcon: Icons.travel_explore,
    ),
    _DesktopNavItem(
      label: 'Marketplace',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront,
    ),
  ];

  Future<void> _logoutDesktop() async {
    await WebDesktopSessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/desktop', (route) => false);
  }

  void _openLinkedAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Glass(
                borderRadius: 24,
                padding: EdgeInsets.zero,
                fill: Colors.white.withOpacity(0.08),
                borderColor: Colors.white.withOpacity(0.10),
                child: _DesktopRightPanel(
                  pairedUserUid: widget.pairedUserUid,
                  pairedUserName: widget.pairedUserName,
                  pairedUserEmail: widget.pairedUserEmail,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPanels() {
    return [
      _DesktopHomePanel(
        pairedUserUid: widget.pairedUserUid,
        pairedUserName: widget.pairedUserName,
        pairedUserEmail: widget.pairedUserEmail,
      ),
      _DesktopLeaguesPanel(
        pairedUserUid: widget.pairedUserUid,
      ),
      const _DesktopDiscoverPanel(),
      const _DesktopMarketplacePanel(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final panels = _buildPanels();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 760) {
          return _buildMobileLayout(context, panels);
        }

        if (width < 1180) {
          return _buildTabletLayout(context, panels);
        }

        return _buildDesktopLayout(context, panels);
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context, List<Widget> panels) {
    final currentItem = _items[_selectedIndex];

    return GlassScaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: _items
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
                const _BrandLogo(size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'eSportlyic Web',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Linked account',
                onPressed: _openLinkedAccountSheet,
                icon: const Icon(Icons.person_outline),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'unlink') {
                    await _logoutDesktop();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'unlink',
                    child: Text('Unlink desktop'),
                  ),
                ],
              ),
            ],
          ),
          drawer: Drawer(
            backgroundColor: const Color(0xFF0E223F),
            child: SafeArea(
              child: Column(
                children: [
                  _DesktopSidebarHeader(
                    pairedUserName: widget.pairedUserName,
                    pairedUserEmail: widget.pairedUserEmail,
                    showBrandName: true,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final selected = _selectedIndex == index;
                        return _DesktopSidebarTile(
                          item: item,
                          selected: selected,
                          accent: _accent,
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _logoutDesktop,
                        icon: const Icon(Icons.logout),
                        label: const Text('Unlink desktop'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              _CompactTopBanner(
                title: currentItem.label,
                pairedUserName: widget.pairedUserName,
              ),
              Expanded(child: panels[_selectedIndex]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, List<Widget> panels) {
    final currentItem = _items[_selectedIndex];
    final showRightPanel = MediaQuery.of(context).size.width >= 960;

    return GlassScaffold(
      body: SafeArea(
        child: Row(
          children: [
            Glass(
              borderRadius: 0,
              padding: EdgeInsets.zero,
              fill: Colors.white.withOpacity(0.05),
              border: false,
              child: SizedBox(
                width: 96,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    const _BrandLogo(size: 36),
                    const SizedBox(height: 12),
                    Expanded(
                      child: NavigationRail(
                        backgroundColor: Colors.transparent,
                        selectedIndex: _selectedIndex,
                        labelType: NavigationRailLabelType.all,
                        groupAlignment: -1,
                        indicatorColor: _accent.withOpacity(0.16),
                        selectedIconTheme: const IconThemeData(color: _accent),
                        selectedLabelTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        unselectedIconTheme:
                            IconThemeData(color: Colors.white.withOpacity(0.72)),
                        unselectedLabelTextStyle: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontWeight: FontWeight.w700,
                        ),
                        onDestinationSelected: (index) {
                          setState(() => _selectedIndex = index);
                        },
                        destinations: _items
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
                        icon: const Icon(Icons.logout, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _DesktopTopBar(
                    title: currentItem.label,
                    pairedUserName: widget.pairedUserName,
                    onOpenAccount: _openLinkedAccountSheet,
                  ),
                  Expanded(child: panels[_selectedIndex]),
                ],
              ),
            ),
            if (showRightPanel)
              SizedBox(
                width: 300,
                child: Glass(
                  borderRadius: 0,
                  padding: EdgeInsets.zero,
                  fill: Colors.white.withOpacity(0.05),
                  border: false,
                  child: _DesktopRightPanel(
                    pairedUserUid: widget.pairedUserUid,
                    pairedUserName: widget.pairedUserName,
                    pairedUserEmail: widget.pairedUserEmail,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, List<Widget> panels) {
    return GlassScaffold(
      body: SafeArea(
        child: Row(
          children: [
            Glass(
              borderRadius: 0,
              padding: EdgeInsets.zero,
              fill: Colors.white.withOpacity(0.05),
              border: false,
              child: SizedBox(
                width: 308,
                child: Column(
                  children: [
                    _DesktopSidebarHeader(
                      pairedUserName: widget.pairedUserName,
                      pairedUserEmail: widget.pairedUserEmail,
                      showBrandName: true,
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final selected = _selectedIndex == index;
                          return _DesktopSidebarTile(
                            item: item,
                            selected: selected,
                            accent: _accent,
                            onTap: () => setState(() => _selectedIndex = index),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _logoutDesktop,
                          icon: const Icon(Icons.logout),
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
                  _DesktopTopBar(
                    title: _items[_selectedIndex].label,
                    pairedUserName: widget.pairedUserName,
                    onOpenAccount: _openLinkedAccountSheet,
                  ),
                  Expanded(child: panels[_selectedIndex]),
                ],
              ),
            ),
            SizedBox(
              width: 340,
              child: Glass(
                borderRadius: 0,
                padding: EdgeInsets.zero,
                fill: Colors.white.withOpacity(0.05),
                border: false,
                child: _DesktopRightPanel(
                  pairedUserUid: widget.pairedUserUid,
                  pairedUserName: widget.pairedUserName,
                  pairedUserEmail: widget.pairedUserEmail,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTopBanner extends StatelessWidget {
  final String title;
  final String pairedUserName;

  const _CompactTopBanner({
    required this.title,
    required this.pairedUserName,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      fill: Colors.white.withOpacity(0.05),
      border: false,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_rounded, color: AppTheme.navyAccent, size: 16),
                const SizedBox(width: 6),
                Text(
                  pairedUserName.trim().isEmpty ? 'Linked' : pairedUserName,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

class _DesktopSidebarHeader extends StatelessWidget {
  final String pairedUserName;
  final String pairedUserEmail;
  final bool showBrandName;

  const _DesktopSidebarHeader({
    required this.pairedUserName,
    required this.pairedUserEmail,
    this.showBrandName = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials = pairedUserName.trim().isNotEmpty
        ? pairedUserName.trim().substring(0, 1).toUpperCase()
        : 'E';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        children: [
          if (showBrandName) ...[
            Row(
              children: [
                const _BrandLogo(size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'eSportlyic Web',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Glass(
            borderRadius: 20,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            fill: Colors.white.withOpacity(0.05),
            borderColor: Colors.white.withOpacity(0.08),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.navyAccent.withOpacity(0.22),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pairedUserEmail.trim().isNotEmpty
                            ? pairedUserEmail
                            : 'Desktop linked',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 12,
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

class _DesktopSidebarTile extends StatelessWidget {
  final _DesktopNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  const _DesktopSidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.white.withOpacity(0.72);

    return Material(
      color: selected ? Colors.white.withOpacity(0.06) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                color: selected ? accent : fg,
              ),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  final String title;
  final String pairedUserName;
  final VoidCallback onOpenAccount;

  const _DesktopTopBar({
    required this.title,
    required this.pairedUserName,
    required this.onOpenAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      fill: Colors.white.withOpacity(0.05),
      border: false,
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onOpenAccount,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.laptop_mac, color: AppTheme.navyAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Linked as ${pairedUserName.trim().isEmpty ? 'user' : pairedUserName}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontWeight: FontWeight.w600,
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

class _DesktopHomePanel extends StatelessWidget {
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;

  const _DesktopHomePanel({
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
  });

  @override
  Widget build(BuildContext context) {
    final userDoc =
        FirebaseFirestore.instance.collection('users').doc(pairedUserUid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final teamName = (data['teamName'] ?? '').toString().trim();
        final photoUrl = (data['photoUrl'] ?? data['profileImageUrl'] ?? '')
            .toString()
            .trim();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Welcome back${pairedUserName.trim().isNotEmpty ? ', $pairedUserName' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pairedUserEmail.trim().isNotEmpty
                  ? pairedUserEmail
                  : 'Your eSportlyic desktop companion session is active.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _DesktopProfileCard(
              name: pairedUserName,
              email: pairedUserEmail,
              teamName: teamName,
              photoUrl: photoUrl,
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(
                  child: _DesktopStatCard(
                    title: 'Desktop Status',
                    value: 'Linked',
                    accent: AppTheme.navyAccent,
                    icon: Icons.link,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _DesktopStatCard(
                    title: 'Session Mode',
                    value: 'Companion',
                    accent: Color(0xFF38BDF8),
                    icon: Icons.devices,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _DesktopStatCard(
                    title: 'Web Access',
                    value: 'Active',
                    accent: Color(0xFF22C55E),
                    icon: Icons.public,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _DesktopPlaceholderSection(
              title: 'Live account connected',
              subtitle:
                  'Your eSportlyic desktop shell is connected to your live Firestore profile and league data.',
            ),
          ],
        );
      },
    );
  }
}

class _DesktopProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String teamName;
  final String photoUrl;

  const _DesktopProfileCard({
    required this.name,
    required this.email,
    required this.teamName,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.trim().isNotEmpty;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(22),
      fill: Colors.white.withOpacity(0.06),
      borderColor: Colors.white.withOpacity(0.08),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppTheme.navyAccent.withOpacity(0.18),
            backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
            child: hasPhoto
                ? null
                : Text(
                    name.trim().isNotEmpty
                        ? name.trim().substring(0, 1).toUpperCase()
                        : 'E',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isNotEmpty ? name : 'eSportlyic User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                if (email.trim().isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                    ),
                  ),
                if (teamName.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Team: $teamName',
                    style: const TextStyle(
                      color: AppTheme.navyAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopStatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color accent;
  final IconData icon;

  const _DesktopStatCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      fill: Colors.white.withOpacity(0.06),
      borderColor: Colors.white.withOpacity(0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopPlaceholderSection extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DesktopPlaceholderSection({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(22),
      fill: Colors.white.withOpacity(0.06),
      borderColor: Colors.white.withOpacity(0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopLeaguesPanel extends StatelessWidget {
  final String pairedUserUid;

  const _DesktopLeaguesPanel({
    required this.pairedUserUid,
  });

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('leagues').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: _DesktopPlaceholderSection(
              title: 'Leagues',
              subtitle: 'Could not load leagues: ${snapshot.error}',
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.where((doc) {
          final d = doc.data();
          final organizerUid = (d['organizerUid'] ?? '').toString().trim();
          final ownerUid = (d['ownerUid'] ?? '').toString().trim();
          final organizerUserId = (d['organizerUserId'] ?? '').toString().trim();
          final ownerId = (d['ownerId'] ?? '').toString().trim();
          final memberIds = (d['memberIds'] is List)
              ? List<String>.from(
                  (d['memberIds'] as List).map((e) => e.toString()),
                )
              : <String>[];

          return organizerUid == pairedUserUid ||
              ownerUid == pairedUserUid ||
              organizerUserId == pairedUserUid ||
              ownerId == pairedUserUid ||
              memberIds.contains(pairedUserUid);
        }).toList();

        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: _DesktopPlaceholderSection(
              title: 'Leagues',
              subtitle: 'No connected leagues found yet for this paired account.',
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your leagues',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${docs.length} league(s) found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
              ),
            ),
            const SizedBox(height: 20),
            ...docs.map((doc) {
              final d = doc.data();
              final name = (d['name'] ?? 'League').toString();
              final season = (d['season'] ?? '').toString();
              final region = (d['region'] ?? '').toString();
              final code = (d['code'] ?? '').toString();
              final format = (d['format'] ?? '').toString();

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(18),
                  fill: Colors.white.withOpacity(0.06),
                  borderColor: Colors.white.withOpacity(0.08),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: AppTheme.navyAccent.withOpacity(0.14),
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: AppTheme.navyAccent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (season.trim().isNotEmpty)
                                  _LeagueMetaChip(text: season),
                                if (region.trim().isNotEmpty)
                                  _LeagueMetaChip(text: region),
                                if (format.trim().isNotEmpty)
                                  _LeagueMetaChip(text: format),
                                if (code.trim().isNotEmpty)
                                  _LeagueMetaChip(text: 'Code: $code'),
                              ],
                            ),
                          ],
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

class _LeagueMetaChip extends StatelessWidget {
  final String text;

  const _LeagueMetaChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.78),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DesktopDiscoverPanel extends StatelessWidget {
  const _DesktopDiscoverPanel();

  @override
  Widget build(BuildContext context) {
    final stream =
        FirebaseFirestore.instance.collection('master_leagues').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Organizer discovery',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Browse organizer workspaces',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
              ),
            ),
            const SizedBox(height: 20),
            if (docs.isEmpty)
              const _DesktopPlaceholderSection(
                title: 'No organizers yet',
                subtitle: 'Organizer workspaces will appear here once available.',
              )
            else
              ...docs.take(12).map((doc) {
                final d = doc.data();
                final name = (d['name'] ?? 'Organizer').toString();
                final bio = (d['bio'] ?? '').toString();
                final plan = (d['plan'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(18),
                    fill: Colors.white.withOpacity(0.06),
                    borderColor: Colors.white.withOpacity(0.08),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        if (plan.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _LeagueMetaChip(text: 'Plan: $plan'),
                        ],
                        if (bio.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            bio,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.70),
                              height: 1.45,
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

class _DesktopMarketplacePanel extends StatelessWidget {
  const _DesktopMarketplacePanel();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('marketplace_products')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Marketplace',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Desktop browsing for products',
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
              ),
            ),
            const SizedBox(height: 20),
            if (docs.isEmpty)
              const _DesktopPlaceholderSection(
                title: 'No marketplace products yet',
                subtitle: 'Products will appear here when available.',
              )
            else
              ...docs.take(12).map((doc) {
                final d = doc.data();
                final name = (d['name'] ?? 'Product').toString();
                final price = (d['price'] ?? '').toString();
                final sellerName = (d['sellerName'] ?? '').toString();
                final category = (d['category'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(18),
                    fill: Colors.white.withOpacity(0.06),
                    borderColor: Colors.white.withOpacity(0.08),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (price.trim().isNotEmpty)
                              _LeagueMetaChip(text: price),
                            if (sellerName.trim().isNotEmpty)
                              _LeagueMetaChip(text: sellerName),
                            if (category.trim().isNotEmpty)
                              _LeagueMetaChip(text: category),
                          ],
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

class _DesktopRightPanel extends StatelessWidget {
  final String pairedUserUid;
  final String pairedUserName;
  final String pairedUserEmail;

  const _DesktopRightPanel({
    required this.pairedUserUid,
    required this.pairedUserName,
    required this.pairedUserEmail,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Glass(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          fill: Colors.white.withOpacity(0.06),
          borderColor: Colors.white.withOpacity(0.08),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Linked account',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 14),
              _InfoRow(
                label: 'Name',
                value: pairedUserName.isEmpty ? 'N/A' : pairedUserName,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: 'Email',
                value: pairedUserEmail.isEmpty ? 'N/A' : pairedUserEmail,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: 'UID',
                value: pairedUserUid.isEmpty ? 'N/A' : pairedUserUid,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Glass(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          fill: Colors.white.withOpacity(0.06),
          borderColor: Colors.white.withOpacity(0.08),
          child: Text(
            'This panel is ready for selected item details such as league profile, organizer details, marketplace item info, or recent activity.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.56),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DesktopNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _DesktopNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
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
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.navyAccent,
        boxShadow: [
          BoxShadow(
            color: AppTheme.navyAccent.withOpacity(0.24),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.sports_esports,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
