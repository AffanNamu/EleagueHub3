import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

import '../../../../core/widgets/glass.dart';

class GlassAnnouncement extends StatelessWidget {
  final String title;
  final String message;
  final String time;

  /// If true, the message will scroll like a marquee.
  final bool marquee;

  const GlassAnnouncement({
    super.key,
    required this.title,
    required this.message,
    required this.time,
    this.marquee = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      color: onSurface,
      fontWeight: FontWeight.w900,
    );

    final msgStyle = theme.textTheme.bodySmall?.copyWith(
      color: onSurface.withOpacity(0.72),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      color: onSurface.withOpacity(0.45),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    return SizedBox(
      width: 280,
      child: Glass(
        borderRadius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.campaign,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: marquee
                  ? Marquee(
                      text: message,
                      style: msgStyle,
                      blankSpace: 40,
                      velocity: 25,
                      pauseAfterRound: const Duration(seconds: 1),
                      startPadding: 0,
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: msgStyle,
                      ),
                    ),
            ),
            const Spacer(),
            Text(
              time,
              style: timeStyle,
            ),
          ],
        ),
      ),
    );
  }
}
