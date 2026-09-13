// lib/features/home/presentation/widgets/home_content_widgets.dart
//
// Home-tab presentation for the admin-controlled Home Content CMS
// (home_content collection — see home_content_repository.dart). Three
// pieces:
//   - HomeHeroBanner: the top hero slot, renders nothing when there's no
//     active hero (no fake fallback content).
//   - HomePromoStrip: a horizontal row of promo cards, renders nothing
//     when empty.
//   - HomeAnnouncementTrigger: invisible widget that shows the single
//     active announcement as a modal bottom sheet once per new
//     announcement per user, replacing the old inline
//     PlatformAnnouncementBanner.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../data/home_content_repository.dart';

void _navigate(BuildContext context, String route) {
  if (route.trim().isEmpty) return;
  try {
    GoRouter.of(context).push(route);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// HomeHeroBanner
// ---------------------------------------------------------------------------

class HomeHeroBanner extends StatelessWidget {
  const HomeHeroBanner({super.key, required this.items});

  final List<HomeContentItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final hero = items.first;

    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Glass(
        borderRadius: 28,
        padding: EdgeInsets.zero,
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              if (hero.imageUrl.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    hero.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(hero.imageUrl.isNotEmpty ? 0.35 : 0.0),
                        Colors.black.withOpacity(hero.imageUrl.isNotEmpty ? 0.75 : 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hero.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: hero.imageUrl.isNotEmpty ? Colors.white : AppTheme.primaryText(brightness),
                      ),
                    ),
                    if (hero.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        hero.subtitle,
                        style: TextStyle(
                          color: hero.imageUrl.isNotEmpty
                              ? Colors.white.withOpacity(0.85)
                              : AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (hero.ctaRoute.isNotEmpty && hero.ctaLabel.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: () => _navigate(context, hero.ctaRoute),
                        child: Text(
                          hero.ctaLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HomePromoStrip
// ---------------------------------------------------------------------------

class HomePromoStrip extends StatelessWidget {
  const HomePromoStrip({super.key, required this.items});

  final List<HomeContentItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: item.ctaRoute.isEmpty ? null : () => _navigate(context, item.ctaRoute),
            child: Container(
              width: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: AppTheme.cardColor(brightness),
                border: Border.all(color: AppTheme.cardBorder(brightness)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.limeAccent.withOpacity(0.10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: item.imageUrl.isNotEmpty
                        ? Image.network(
                            item.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.campaign_outlined,
                              color: AppTheme.limeAccentDark,
                            ),
                          )
                        : Icon(Icons.campaign_outlined, color: AppTheme.limeAccentDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        if (item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HomeContentSection (hero + promo strip, one owned stream)
// ---------------------------------------------------------------------------

/// Owns a single HomeContentRepository().watchActive() stream (created once
/// in initState) and renders the hero + promo strip from it. Avoids
/// recreating the Firestore query/stream on every parent rebuild, the same
/// class of listener-lifecycle bug this codebase has hit before elsewhere.
class HomeContentSection extends StatefulWidget {
  const HomeContentSection({super.key});

  @override
  State<HomeContentSection> createState() => _HomeContentSectionState();
}

class _HomeContentSectionState extends State<HomeContentSection> {
  late final Stream<List<HomeContentItem>> _stream = HomeContentRepository().watchActive();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HomeContentItem>>(
      stream: _stream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <HomeContentItem>[];
        final hero = items.where((i) => i.type == HomeContentType.hero).toList();
        final promo = items.where((i) => i.type == HomeContentType.promoCard).toList();
        if (hero.isEmpty && promo.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeHeroBanner(items: hero),
            if (promo.isNotEmpty) ...[
              HomePromoStrip(items: promo),
              const SizedBox(height: 22),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HomeAnnouncementTrigger
// ---------------------------------------------------------------------------

class HomeAnnouncementTrigger extends StatefulWidget {
  const HomeAnnouncementTrigger({super.key});

  @override
  State<HomeAnnouncementTrigger> createState() => _HomeAnnouncementTriggerState();
}

class _HomeAnnouncementTriggerState extends State<HomeAnnouncementTrigger> {
  final _repo = HomeContentRepository();
  StreamSubscription<List<HomeContentItem>>? _sub;
  String? _shownForId;

  @override
  void initState() {
    super.initState();
    _sub = _repo.watchActive().listen(_handleItems);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _handleItems(List<HomeContentItem> items) async {
    HomeContentItem? announcement;
    for (final item in items) {
      if (item.type == HomeContentType.announcement) {
        announcement = item;
        break;
      }
    }
    if (announcement == null) return;
    if (_shownForId == announcement.id) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final lastSeen = doc.data()?['lastSeenHomeAnnouncementAtMs'];
        if (lastSeen is int && lastSeen >= announcement.createdAtMs) {
          _shownForId = announcement.id;
          return;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    _shownForId = announcement.id;
    _showSheet(announcement);
  }

  void _showSheet(HomeContentItem announcement) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AnnouncementSheetContent(
        announcement: announcement,
        onDismiss: () {
          unawaited(_repo.markAnnouncementSeen(announcement.createdAtMs));
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AnnouncementSheetContent extends StatelessWidget {
  const _AnnouncementSheetContent({
    required this.announcement,
    required this.onDismiss,
  });

  final HomeContentItem announcement;
  final VoidCallback onDismiss;

  Color _severityColor() {
    switch (announcement.severity) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'info':
      default:
        return const Color(0xFF38BDF8);
    }
  }

  IconData _severityIcon() {
    switch (announcement.severity) {
      case 'critical':
        return Icons.error_outline_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'info':
      default:
        return Icons.campaign_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final color = _severityColor();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(20),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.14),
                      border: Border.all(color: color.withOpacity(0.35)),
                    ),
                    child: Icon(_severityIcon(), color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      announcement.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                  ),
                ],
              ),
              if (announcement.subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  announcement.subtitle,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                  ),
                  onPressed: onDismiss,
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
