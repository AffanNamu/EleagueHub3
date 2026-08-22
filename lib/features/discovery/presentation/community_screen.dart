// lib/features/discovery/presentation/community_screen.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

/// Simple v1 Community destination. Intentionally minimal — a
/// discussion-list placeholder, expandable later without breaking
/// the Discovery Hub's routing to it.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Community'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Glass(
              borderRadius: 24,
              padding: const EdgeInsets.all(18),
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'eSportlyic Community',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.primaryText(brightness)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Discussions, guides, and community highlights are coming soon. '
                    'In the meantime, check out the Public Feed for the latest activity.',
                    style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600, height: 1.4),
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
