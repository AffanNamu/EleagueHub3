import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final panels = [
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

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF111B21),
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Column(
                children: [
                  _DesktopSidebarHeader(
                    pairedUserName: widget.pairedUserName,
                    pairedUserEmail: widget.pairedUserEmail,
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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withOpacity(0.10)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _DesktopTopBar(
                    title: _items[_selectedIndex].label,
                    pairedUserName: widget.pairedUserName,
                  ),
                  Expanded(
                    child: Container(
                      color: const Color(0xFF202C33),
                      child: panels[_selectedIndex],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 340,
              decoration: BoxDecoration(
                color: const Color(0xFF111B21),
                border: Border(
                  left: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: _DesktopRightPanel(
                pairedUserUid: widget.pairedUserUid,
                pairedUserName: widget.pairedUserName,
                pairedUserEmail: widget.pairedUserEmail,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebarHeader extends StatelessWidget {
  final String pairedUserName;
  final String pairedUserEmail;

  const _DesktopSidebarHeader({
    required this.pairedUserName,
    required this.pairedUserEmail,
  });

  @override
  Widget build(BuildContext context) {
    final initials = pairedUserName.trim().isNotEmpty
        ? pairedUserName.trim().substring(0, 1).toUpperCase()
        : 'E';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF25D366),
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
                  pairedUserName.trim().isNotEmpty ? pairedUserName : 'EleagueHub User',
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
                  pairedUserEmail.trim().isNotEmpty ? pairedUserEmail : 'Desktop linked',
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
    );
  }
}

class _DesktopSidebarTile extends StatelessWidget {
  final _DesktopNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopSidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.white.withOpacity(0.72);

    return Material(
      color: selected ? const Color(0xFF202C33) : Colors.transparent,
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
                color: fg,
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

  const _DesktopTopBar({
    required this.title,
    required this.pairedUserName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF111B21),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.laptop_mac, color: Color(0xFF25D366), size: 18),
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
    final userDoc = FirebaseFirestore.instance.collection('users').doc(pairedUserUid);

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
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pairedUserEmail.trim().isNotEmpty
                  ? pairedUserEmail
                  : 'Your desktop companion session is active.',
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
                    accent: Color(0xFF25D366),
                    icon: Icons.link,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _DesktopStatCard(
                    title: 'Session Mode',
                    value: 'Companion',
                    accent: Color(0xFF00A884),
                    icon: Icons.devices,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _DesktopStatCard(
                    title: 'Web Access',
                    value: 'Active',
                    accent: Color(0xFF53BDEB),
                    icon: Icons.public,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _DesktopPlaceholderSection(
              title: 'Real data connected',
              subtitle: 'Your desktop shell is now connected to live Firestore profile and leagues data. Next we can connect organizer discovery and marketplace content.',
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

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2C34), Color(0xFF182229)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(0xFF25D366).withOpacity(0.18),
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
                  name.trim().isNotEmpty ? name : 'EleagueHub User',
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
                      color: Color(0xFF25D366),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111B21),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
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
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111B21),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
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
                fontWeight: FontWeight.w800,
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
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B21),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF25D366).withOpacity(0.15),
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: Color(0xFF25D366),
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
    final stream = FirebaseFirestore.instance.collection('master_leagues').snapshots();

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
                fontWeight: FontWeight.w800,
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
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111B21),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
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
    final stream =
        FirebaseFirestore.instance.collection('marketplace_products').snapshots();

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
                fontWeight: FontWeight.w800,
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
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111B21),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
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
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF202C33),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
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
              _InfoRow(label: 'Name', value: pairedUserName.isEmpty ? 'N/A' : pairedUserName),
              const SizedBox(height: 10),
              _InfoRow(label: 'Email', value: pairedUserEmail.isEmpty ? 'N/A' : pairedUserEmail),
              const SizedBox(height: 10),
              _InfoRow(label: 'UID', value: pairedUserUid.isEmpty ? 'N/A' : pairedUserUid),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF202C33),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Text(
            'This panel is now ready for selected item details such as league profile, organizer details, marketplace item info, or activity.',
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
