import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/glass_search_bar.dart';
import '../../leagues/data/leagues_repository_local.dart' show LeagueJoinMode;
import '../../leagues/domain/models/global_public_league.dart';
import '../../leagues/logic/global_public_league_join_service.dart';
import '../../leagues/logic/global_public_leagues_providers.dart';
import '../../leagues/utils/current_user.dart';

class GlobalLiveLeaguesScreen extends ConsumerStatefulWidget {
  const GlobalLiveLeaguesScreen({super.key});

  @override
  ConsumerState<GlobalLiveLeaguesScreen> createState() => _GlobalLiveLeaguesScreenState();
}

class _GlobalLiveLeaguesScreenState extends ConsumerState<GlobalLiveLeaguesScreen>
    with TickerProviderStateMixin {
  String? _joiningLeagueId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final AnimationController _headerController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _headerFade = CurvedAnimation(parent: _headerController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerController, curve: Curves.easeOutCubic));
    _headerController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _headerController.dispose();
    super.dispose();
  }

  List<GlobalPublicLeague> _filter(List<GlobalPublicLeague> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((item) {
      final name = item.league.name.toLowerCase();
      final region = item.league.region.toLowerCase();
      final season = item.league.season.toLowerCase();
      return name.contains(_searchQuery) ||
          region.contains(_searchQuery) ||
          season.contains(_searchQuery);
    }).toList();
  }

  String _statusLabel(GlobalPublicLeague item) {
    if (item.isFinished) return 'FINISHED';
    if (item.isFullComputed) return 'FULL';
    return 'OPEN';
  }

  Color _statusColor(GlobalPublicLeague item, ColorScheme cs) {
    if (item.isFinished) return cs.onSurface.withOpacity(0.55);
    if (item.isFullComputed) return cs.error;
    return const Color(0xFF00E676);
  }

  Future<void> _showJoinModeSheet(GlobalPublicLeague item) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (item.isFinished) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This league is finished.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final LeagueJoinMode? selected = await showModalBottomSheet<LeagueJoinMode>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom).add(const EdgeInsets.all(12)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary.withOpacity(0.3),
                                cs.primary.withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: Icon(Icons.group_add_rounded, color: cs.primary, size: 26),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Join League',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.league.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(0.60),
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _JoinModeTile(
                          icon: Icons.sports_soccer,
                          title: 'Join as Participant',
                          subtitle: item.isFullComputed
                              ? 'League is currently full. You can still join as a viewer.'
                              : 'Counts towards league capacity and lets you participate.',
                          badge: item.isFullComputed ? 'FULL' : null,
                          badgeColor: item.isFullComputed ? cs.error : cs.primary,
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.participant),
                        ),
                        const SizedBox(height: 10),
                        _JoinModeTile(
                          icon: Icons.visibility_outlined,
                          title: 'Join as Viewer',
                          subtitle: 'View league content without taking a participant slot.',
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.viewer),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withOpacity(0.6),
                            ),
                            child: const Text('Cancel'),
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
      },
    );

    if (!mounted || selected == null) return;
    await _join(item, selected);
  }

  Future<void> _join(GlobalPublicLeague item, LeagueJoinMode mode) async {
    if (_joiningLeagueId == item.league.id) return;

    setState(() => _joiningLeagueId = item.league.id);

    try {
      final userId = await CurrentUser.getOrCreateUserId();

      final service = ref.read(globalPublicLeagueJoinServiceProvider);
      final result = await service.joinPublicLeague(
        league: item,
        userId: userId,
        mode: mode,
      );

      if (!mounted) return;

      if (result.status == GlobalPublicLeagueJoinStatus.finished) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This league is finished.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (result.status == GlobalPublicLeagueJoinStatus.privateLeague) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This league is private.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (result.status == GlobalPublicLeagueJoinStatus.full) {
        if (mode == LeagueJoinMode.participant) {
          final joinViewer = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                backgroundColor: Theme.of(ctx).colorScheme.surface,
                title: const Text('League is full'),
                content: const Text(
                    'No participant slots left. Do you want to join as a viewer instead?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Join as viewer'),
                  ),
                ],
              );
            },
          );

          if (joinViewer == true) {
            await _join(item, LeagueJoinMode.viewer);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('League is full.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50)));
        context.push('/leagues/${item.league.id}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Join failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _joiningLeagueId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncLeagues = ref.watch(globalPublicLeaguesStreamProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Glass(
            padding: const EdgeInsets.all(8),
            borderRadius: 12,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white.withOpacity(0.9)),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                // ── Header inside Glass ──
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Glass(
                        borderRadius: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
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
                              child: const Center(
                                child: Text('🌐', style: TextStyle(fontSize: 22)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Global Leagues',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  asyncLeagues.when(
                                    data: (items) => Text(
                                      '${items.length} active league${items.length == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    loading: () => Text(
                                      'Loading...',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.45),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    error: (_, __) => Text(
                                      'Error loading',
                                      style: TextStyle(
                                        color: cs.error.withOpacity(0.8),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Search Bar ──
                GlassSearchBar(
                  controller: _searchController,
                  onChanged: (_) {},
                ),

                // ── Content ──
                Expanded(
                  child: asyncLeagues.when(
                    loading: () => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: cs.primary),
                          const SizedBox(height: 16),
                          Text(
                            'Discovering leagues...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Glass(
                        borderRadius: 24,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.error.withOpacity(0.15),
                              ),
                              child: Icon(Icons.error_outline_rounded, color: cs.error, size: 30),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Failed to load leagues',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$e',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (allItems) {
                      final items = _filter(allItems);

                      if (allItems.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Glass(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        cs.primary.withOpacity(0.3),
                                        cs.primary.withOpacity(0.08),
                                      ],
                                    ),
                                  ),
                                  child: Icon(Icons.public_rounded, color: cs.primary, size: 32),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No Public Leagues',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Discover public leagues from the\nglobal community.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.50),
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Glass(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, color: Colors.white.withOpacity(0.4), size: 40),
                                const SizedBox(height: 12),
                                Text(
                                  'No leagues match your search',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _AnimatedLeagueCard(
                            index: index,
                            child: _LeagueCard(
                              item: item,
                              joining: _joiningLeagueId == item.league.id,
                              statusLabel: _statusLabel(item),
                              statusColor: _statusColor(item, cs),
                              onJoin: () => _showJoinModeSheet(item),
                            ),
                          );
                        },
                      );
                    },
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

// ─────────────────────────────────────────────
// Animated wrapper for staggered list entry
// ─────────────────────────────────────────────
class _AnimatedLeagueCard extends StatefulWidget {
  const _AnimatedLeagueCard({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_AnimatedLeagueCard> createState() => _AnimatedLeagueCardState();
}

class _AnimatedLeagueCardState extends State<_AnimatedLeagueCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: math.min(widget.index * 80, 400)), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}

// ─────────────────────────────────────────────
// Premium League Card using Glass
// ─────────────────────────────────────────────
class _LeagueCard extends StatefulWidget {
  const _LeagueCard({
    required this.item,
    required this.joining,
    required this.statusLabel,
    required this.statusColor,
    required this.onJoin,
  });

  final GlobalPublicLeague item;
  final bool joining;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onJoin;

  @override
  State<_LeagueCard> createState() => _LeagueCardState();
}

class _LeagueCardState extends State<_LeagueCard> with SingleTickerProviderStateMixin {
  late final AnimationController _tapCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _tapCtrl.forward();
  void _onTapUp(TapUpDetails _) => _tapCtrl.reverse();
  void _onTapCancel() => _tapCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final item = widget.item;
    final joining = widget.joining;

    final subtitleParts = <String>[
      item.league.format.displayName,
      item.league.season,
      item.league.region,
    ];
    if (item.league.viewerCapacity > 0) {
      subtitleParts.add('${item.league.viewerCapacity} Viewers');
    }

    final participantText = item.registeredCount == null
        ? '${item.league.maxTeams}'
        : '${item.registeredCount}/${item.league.maxTeams}';

    final desc = item.league.description.trim();

    final isLive = !item.isFinished && !item.isFullComputed;

    return AnimatedBuilder(
      listenable: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: Glass(
          borderRadius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: logo + info + status ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeagueThumb(
                    leagueImageUrl: item.league.leagueImageUrl,
                    sponsorImageUrl: item.league.sponsorImageUrl,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.league.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 13,
                              color: Colors.amber.withOpacity(0.8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.league.organizerName.isNotEmpty
                                    ? item.league.organizerName
                                    : 'Organizer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.55),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(
                    label: widget.statusLabel,
                    color: widget.statusColor,
                    isLive: isLive,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Info chips row ──
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _InfoChip(
                    icon: Icons.people_alt_rounded,
                    label: participantText,
                  ),
                  _InfoChip(
                    icon: Icons.sports_rounded,
                    label: item.league.format.displayName,
                  ),
                  _InfoChip(
                    icon: Icons.public_rounded,
                    label: item.league.region.isNotEmpty ? item.league.region : 'Global',
                  ),
                  if (item.league.viewerCapacity > 0)
                    _InfoChip(
                      icon: Icons.visibility_rounded,
                      label: '${item.league.viewerCapacity}',
                    ),
                ],
              ),

              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ── Join button ──
              SizedBox(
                width: double.infinity,
                height: 44,
                child: _PremiumJoinButton(
                  joining: joining,
                  disabled: joining || item.isFinished,
                  onPressed: widget.onJoin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Status Badge with optional pulse for OPEN
// ─────────────────────────────────────────────
class _StatusBadge extends StatefulWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    this.isLive = false,
  });
  final String label;
  final Color color;
  final bool isLive;

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isLive) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusBadge old) {
    super.didUpdateWidget(old);
    if (widget.isLive && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isLive && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _pulse,
      builder: (context, child) {
        final opacity = widget.isLive ? 0.7 + (_pulse.value * 0.3) : 1.0;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.color.withOpacity(0.40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isLive) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              widget.label,
              style: TextStyle(
                color: widget.color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Info chip
// ─────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Premium Join Button
// ─────────────────────────────────────────────
class _PremiumJoinButton extends StatelessWidget {
  const _PremiumJoinButton({
    required this.joining,
    required this.disabled,
    required this.onPressed,
  });
  final bool joining;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: disabled
                ? null
                : LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      cs.primary,
                      cs.primary.withOpacity(0.75),
                    ],
                  ),
            color: disabled ? Colors.white.withOpacity(0.08) : null,
            border: Border.all(
              color: disabled
                  ? Colors.white.withOpacity(0.08)
                  : cs.primary.withOpacity(0.40),
            ),
          ),
          child: Center(
            child: joining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.login_rounded,
                        size: 18,
                        color: disabled
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Join League',
                        style: TextStyle(
                          color: disabled
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 0.3,
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

// ─────────────────────────────────────────────
// League thumbnail
// ─────────────────────────────────────────────
class _LeagueThumb extends StatelessWidget {
  const _LeagueThumb({
    required this.leagueImageUrl,
    required this.sponsorImageUrl,
  });

  final String leagueImageUrl;
  final String sponsorImageUrl;

  Uint8List? _tryDecodeDataUri(String raw) {
    final s = raw.trim();
    if (!s.startsWith('data:image')) return null;
    final idx = s.indexOf('base64,');
    if (idx < 0) return null;
    final b64 = s.substring(idx + 'base64,'.length);
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Widget _imgOrCup(BuildContext context, String url, {BoxFit fit = BoxFit.cover}) {
    final cs = Theme.of(context).colorScheme;
    final u = url.trim();
    final bytes = u.isEmpty ? null : _tryDecodeDataUri(u);

    if (bytes != null) {
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }

    if (u.isNotEmpty) {
      return Image.network(
        u,
        fit: fit,
        errorBuilder: (_, __, ___) => Icon(Icons.emoji_events_rounded, color: cs.primary, size: 24),
        loadingBuilder: (context, w, event) {
          if (event == null) return w;
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          );
        },
      );
    }

    return Icon(Icons.emoji_events_rounded, color: cs.primary, size: 24);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sponsor = sponsorImageUrl.trim();

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(0.25),
            cs.primary.withOpacity(0.08),
          ],
        ),
        border: Border.all(color: cs.primary.withOpacity(0.25), width: 1.5),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _imgOrCup(context, leagueImageUrl),
            if (sponsor.isNotEmpty)
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.30)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: _imgOrCup(context, sponsor, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Join mode tile (bottom sheet)
// ─────────────────────────────────────────────
class _JoinModeTile extends StatelessWidget {
  const _JoinModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? cs.primary).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: (badgeColor ?? cs.primary).withOpacity(0.30)),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: badgeColor ?? cs.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.50),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.3,
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

// ─────────────────────────────────────────────
// AnimatedBuilder alias
// ─────────────────────────────────────────────
class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  Animation<dynamic> get animation => listenable as Animation<dynamic>;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
