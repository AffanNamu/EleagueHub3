import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:eleaguehub3/core/theme/app_theme.dart';
import 'package:eleaguehub3/core/widgets/glass.dart';
import 'package:eleaguehub3/features/leagues/data/announcements_firebase.dart';

class ReactiveAnnouncementsList extends StatelessWidget {
  final String leagueId;
  final LeagueAnnouncementsFirebase _annRepo = LeagueAnnouncementsFirebase();

  ReactiveAnnouncementsList({super.key, required this.leagueId});

  DateTime _resolveTimestamp(dynamic ann) {
    try {
      final v = (ann as dynamic).timestamp;
      if (v is DateTime) return v;
    } catch (_) {}

    try {
      final ms = (ann as dynamic).createdAtMs;
      if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}

    try {
      final ms = (ann as dynamic).createdAt;
      if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}

    try {
      final ms = (ann as dynamic).updatedAtMs;
      if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}

    return DateTime.now();
  }

  String _resolveTitle(dynamic ann) {
    try {
      final v = (ann as dynamic).title;
      return (v == null) ? '' : v.toString();
    } catch (_) {
      return '';
    }
  }

  String _resolveMessage(dynamic ann) {
    try {
      final v = (ann as dynamic).message;
      return (v == null) ? '' : v.toString();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return StreamBuilder<List<dynamic>>(
      stream: _annRepo.watchLeagueAnnouncements(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AppTheme.limeAccentDark),
          );
        }

        final announcements = snapshot.data ?? const <dynamic>[];

        if (announcements.isEmpty) {
          return Center(
            child: Text(
              'No announcements yet',
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: announcements.length,
          itemBuilder: (context, index) {
            final ann = announcements[index];

            final title = _resolveTitle(ann);
            final message = _resolveMessage(ann);
            final time = DateFormat('HH:mm').format(_resolveTimestamp(ann));

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Glass(
                borderRadius: 18,
                padding: const EdgeInsets.all(12),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title.toUpperCase(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.limeAccentDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          time,
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
