import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../features/master_leagues/data/organizer_feed_firebase.dart';
import '../../../features/master_leagues/domain/organizer_feed_event.dart';

class WebFollowedOrganizerFeedScreen extends StatefulWidget {
  final Function(String leagueId)? onLeagueTap;
  final Function(String masterLeagueId)? onMasterLeagueTap;

  const WebFollowedOrganizerFeedScreen({super.key, this.onLeagueTap, this.onMasterLeagueTap});

  @override
  State<WebFollowedOrganizerFeedScreen> createState() =>
      _WebFollowedOrganizerFeedScreenState();
}

class _WebFollowedOrganizerFeedScreenState
    extends State<WebFollowedOrganizerFeedScreen> {
  late final OrganizerFeedFirebase _feed;

  bool _loading = true;
  List<OrganizerFeedEvent> _items = const <OrganizerFeedEvent>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _feed = OrganizerFeedFirebase();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);

    try {
      final items = await _feed.fetchFollowedOrganizerFeedOnce(uid);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load organizer updates.';
      });
    }
  }

  IconData _feedIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement': return Icons.campaign_outlined;
      case 'competition_created': return Icons.emoji_events_outlined;
      case 'verification_approved': return Icons.verified_rounded;
      default: return Icons.bolt_rounded;
    }
  }

  Color _feedColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement': return const Color(0xFF8B5CF6);
      case 'competition_created': return const Color(0xFF22C55E);
      case 'verification_approved': return const Color(0xFF1D9BF0);
      default: return const Color(0xFF64748B);
    }
  }

  String _formatWhen(int ms) {
    if (ms <= 0) return 'Unknown time';
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toString().split('.').first;
    } catch (_) {
      return 'Unknown time';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    return SelectionArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(32),
            children: [
              Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(32),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Organizer Feed',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Updates, announcements, and new competitions from the organizers you follow.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (uid.isEmpty)
                const EmptyState(title: 'Sign in required', message: 'Sign in to view updates.', icon: Icons.dynamic_feed_rounded)
              else if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
              else if (_error != null)
                Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
              else if (_items.isEmpty)
                const EmptyState(title: 'No updates yet', message: 'Follow organizers to see their activity here.', icon: Icons.dynamic_feed_rounded)
              else
                ..._items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (item.leagueId.trim().isNotEmpty) widget.onLeagueTap?.call(item.leagueId.trim());
                        else if (item.masterLeagueId.trim().isNotEmpty) widget.onMasterLeagueTap?.call(item.masterLeagueId.trim());
                      },
                      child: Glass(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(24),
                        fill: AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 56, height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _feedColor(item.type).withOpacity(0.12),
                                border: Border.all(color: _feedColor(item.type).withOpacity(0.22)),
                              ),
                              child: Icon(_feedIcon(item.type), color: _feedColor(item.type), size: 28),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: AppTheme.primaryText(brightness),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.message,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: AppTheme.secondaryText(brightness),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12, runSpacing: 12,
                                    children: [
                                      _WebMetaChip(label: item.actorName.isEmpty ? 'Organizer' : item.actorName, icon: Icons.person, color: AppTheme.limeAccentDark),
                                      _WebMetaChip(label: _formatWhen(item.createdAtMs), icon: Icons.schedule, color: AppTheme.limeAccentDark),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(brightness), size: 32),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebMetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _WebMetaChip({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
