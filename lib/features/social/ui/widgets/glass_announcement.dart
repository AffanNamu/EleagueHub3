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
                const Icon(
                  Icons.campaign,
                  color: Colors.cyanAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Marquee or static text for the message
            SizedBox(
              height: 32,
              child: marquee
                  ? Marquee(
                      text: message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
            const Spacer(),
            Text(
              time,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
