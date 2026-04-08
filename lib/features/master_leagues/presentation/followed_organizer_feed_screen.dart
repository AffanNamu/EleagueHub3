import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/organizer_feed_firebase.dart';
import '../domain/organizer_feed_event.dart';

// ---------------------------------------------------------------------------
// Breakpoints — self-contained
// ---------------------------------------------------------------------------

class _BP {
  static const double tablet  = 760;
  static const double desktop = 900;
}

// ---------------------------------------------------------------------------
// FollowedOrganizerFeedScreen
// ---------------------------------------------------------------------------

class FollowedOrganizerFeedScreen extends StatefulWidget {
  const FollowedOrganizerFeedScreen({super.key});

  @override
  State<FollowedOrganizerFeedScreen> createState() =>
      _FollowedOrganizerFeedScreenState();
}

class _FollowedOrganizerFeedScreenState
    extends State<FollowedOrganizerFeedScreen> {
  late final OrganizerFeedFirebase _feed;

  bool   _loading = true;
  List<OrganizerFeedEvent> _items = const <OrganizerFeedEvent>[];
  String? _error;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _feed = OrganizerFeedFirebase();
    _load();
  }

  // ── safe navigation ────────────────────────────────────────────────────────

  void _safePush(String location) {
    try {
      GoRouter.of(context).push(location);
    } catch (e) {
      debugPrint(
          '[FollowedFeed] push($location) failed: $e');
    }
  }

  void _safePop() {
    try {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/');
      }
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  // ── data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items   = const <OrganizerFeedEvent>[];
        _error   = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error   = null;
      });
    }

    try {
      final items =
          await _feed.fetchFollowedOrganizerFeedOnce(uid);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items   = items;
        _error   = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items   = const <OrganizerFeedEvent>[];
        _error   =
            'Unable to load organizer updates right now.';
      });
    }
  }

  // ── feed helpers ───────────────────────────────────────────────────────────

  IconData _feedIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return Icons.campaign_outlined;
      case 'competition_created':
        return Icons.emoji_events_outlined;
      case 'verification_approved':
        return Icons.verified_rounded;
      case 'verification_renewed':
        return Icons.refresh_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  Color _feedColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return const Color(0xFF8B5CF6);
      case 'competition_created':
        return const Color(0xFF22C55E);
      case 'verification_approved':
        return const Color(0xFF1D9BF0);
      case 'verification_renewed':
        return const Color(0xFF14B8A6);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatWhen(int ms) {
    if (ms <= 0) return 'Unknown time';
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms)
          .toLocal()
          .toString()
          .split('.')
          .first;
    } catch (_) {
      return 'Unknown time';
    }
  }

  // ── feed item tap ──────────────────────────────────────────────────────────

  void _onItemTap(OrganizerFeedEvent item) {
    if (item.leagueId.trim().isNotEmpty) {
      _safePush('/leagues/${item.leagueId.trim()}');
      return;
    }
    if (item.masterLeagueId.trim().isNotEmpty) {
      _safePush(
          '/master-leagues/${item.masterLeagueId.trim()}');
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title:           const Text('Followed Organizer Feed'),
        backgroundColor: Colors.transparent,
        elevation:       0,
        // Explicit leading — prevents shell navigator from
        // intercepting back on web
        leading: IconButton(
          icon:     const Icon(Icons.arrow_back),
          tooltip:  'Back',
          onPressed: _safePop,
        ),
      ),
      body: SafeArea(
        // RefreshIndicator wraps LayoutBuilder + scroll area.
        // ConstrainedBox is placed INSIDE so the pull gesture
        // works across the full screen width on all devices.
        child: RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w         = constraints.maxWidth;
              final isDesktop = w >= _BP.desktop;
              final hPad      = w < _BP.tablet ? 16.0 : 24.0;

              // Signed-out state
              if (uid.isEmpty) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                      horizontal: hPad, vertical: 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: 480),
                      child: const EmptyState(
                        title:   'Sign in required',
                        message:
                            'Please sign in to view updates '
                            'from organizers you follow.',
                        icon: Icons.dynamic_feed_rounded,
                      ),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                    hPad, 12, hPad, 24),
                child: Center(
                  child: ConstrainedBox(
                    // Wider on desktop — grid uses the space
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 1100 : 780,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // ── Header card ─────────────────────────────
                        Glass(
                          borderRadius: 28,
                          padding: const EdgeInsets.all(18),
                          fill: AppTheme.cardColor(brightness),
                          borderColor:
                              AppTheme.cardBorder(brightness),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Organizer Feed',
                                style: theme.textTheme
                                    .titleLarge
                                    ?.copyWith(
                                  fontWeight:
                                      FontWeight.w900,
                                  letterSpacing: -0.3,
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Latest updates from the '
                                'organizer workspaces '
                                'you follow.',
                                style: theme.textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                  color:
                                      AppTheme.secondaryText(
                                          brightness),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Loading ──────────────────────────────────
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 40),
                            child: Center(
                                child:
                                    CircularProgressIndicator()),
                          )

                        // ── Error ────────────────────────────────────
                        else if (_error != null)
                          Glass(
                            borderRadius: 24,
                            padding:
                                const EdgeInsets.all(18),
                            fill: AppTheme.cardColor(
                                brightness),
                            borderColor:
                                AppTheme.cardBorder(
                                    brightness),
                            child: Text(
                              _error!,
                              style: theme.textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                color: theme
                                    .colorScheme.error,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )

                        // ── Empty ────────────────────────────────────
                        else if (_items.isEmpty)
                          const EmptyState(
                            title: 'No updates yet',
                            message:
                                'Follow organizer workspaces '
                                'to see their latest activity '
                                'here.',
                            icon: Icons.dynamic_feed_rounded,
                          )

                        // ── Feed items ───────────────────────────────
                        else
                          _buildFeedContent(
                            context,
                            theme,
                            brightness,
                            isDesktop,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Feed content ───────────────────────────────────────────────────────────
  // Mobile: single-column ListView.separated
  // Desktop: two-column Wrap grid

  Widget _buildFeedContent(
    BuildContext context,
    ThemeData    theme,
    Brightness   brightness,
    bool         isDesktop,
  ) {
    if (isDesktop && _items.length > 1) {
      return Wrap(
        spacing:    16,
        runSpacing: 16,
        children: _items.map((item) {
          return SizedBox(
            width: 500,
            child: _FeedItemCard(
              item:       item,
              theme:      theme,
              brightness: brightness,
              feedIcon:   _feedIcon,
              feedColor:  _feedColor,
              formatWhen: _formatWhen,
              onTap:      () => _onItemTap(item),
            ),
          );
        }).toList(),
      );
    }

    // Single column — mobile / tablet / single item on desktop
    return ListView.separated(
      shrinkWrap:  true,
      physics:     const NeverScrollableScrollPhysics(),
      itemCount:   _items.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _items[index];
        return _FeedItemCard(
          item:       item,
          theme:      theme,
          brightness: brightness,
          feedIcon:   _feedIcon,
          feedColor:  _feedColor,
          formatWhen: _formatWhen,
          onTap:      () => _onItemTap(item),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _FeedItemCard — extracted widget prevents eager list rendering overhead
// ---------------------------------------------------------------------------

class _FeedItemCard extends StatelessWidget {
  const _FeedItemCard({
    required this.item,
    required this.theme,
    required this.brightness,
    required this.feedIcon,
    required this.feedColor,
    required this.formatWhen,
    required this.onTap,
  });

  final OrganizerFeedEvent item;
  final ThemeData          theme;
  final Brightness         brightness;
  final IconData           Function(String) feedIcon;
  final Color              Function(String) feedColor;
  final String             Function(int)    formatWhen;
  final VoidCallback       onTap;

  @override
  Widget build(BuildContext context) {
    final color = feedColor(item.type);
    final icon  = feedIcon(item.type);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap:        onTap,
      child: Glass(
        borderRadius: 22,
        padding:      const EdgeInsets.all(14),
        fill:         AppTheme.cardColor(brightness),
        borderColor:  AppTheme.cardBorder(brightness),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon circle
            Container(
              width:  42,
              height: 42,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  color.withOpacity(0.12),
                border: Border.all(
                    color: color.withOpacity(0.22)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(
                      color: AppTheme.primaryText(
                          brightness),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(
                      color: AppTheme.secondaryText(
                          brightness),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing:    8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        label: item.actorName
                                .trim()
                                .isEmpty
                            ? 'Organizer'
                            : item.actorName.trim(),
                        icon:  Icons.person_outline_rounded,
                        color: AppTheme.limeAccentDark,
                      ),
                      _MetaChip(
                        label: formatWhen(item.createdAtMs),
                        icon:  Icons.schedule_rounded,
                        color: AppTheme.limeAccentDark,
                      ),
                      if (item.masterLeagueId
                          .trim()
                          .isNotEmpty)
                        _MetaChip(
                          label: item.masterLeagueId.trim(),
                          icon:  Icons.hub_rounded,
                          color: const Color(0xFF14B8A6),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.secondaryText(brightness),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MetaChip — unchanged from original, good encapsulation
// ---------------------------------------------------------------------------

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String   label;
  final IconData icon;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(
            brightness == Brightness.dark ? 0.10 : 0.08),
        border: Border.all(
          color: color.withOpacity(
              brightness == Brightness.dark ? 0.22 : 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color:      AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w800,
              fontSize:   12,
            ),
          ),
        ],
      ),
    );
  }
}
