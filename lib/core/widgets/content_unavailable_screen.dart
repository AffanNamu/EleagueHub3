// lib/core/widgets/content_unavailable_screen.dart
//
// ContentUnavailableScreen — shown whenever a deep link or shared link
// resolves to nothing (deleted content, revoked privacy, bad id, unknown
// username). Never crashes, never shows a raw exception — this is the
// universal "soft landing" for the whole sharing/deep-linking system.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

class ContentUnavailableScreen extends StatelessWidget {
  const ContentUnavailableScreen({
    super.key,
    this.message = 'This content is unavailable.',
    this.subtitle =
        'It may have been removed, made private, or the link may be incorrect.',
  });

  final String message;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: AppTheme.navyBgSoft,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link_off_rounded,
                color: AppTheme.limeAccentDark,
                size: 60,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                ),
                onPressed: () {
                  try {
                    GoRouter.of(context).go('/');
                  } catch (_) {}
                },
                icon: const Icon(Icons.home_rounded),
                label: const Text(
                  'Go to Home',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
