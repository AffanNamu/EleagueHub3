// lib/features/auth/presentation/force_update_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

/// Shown in place of the main app whenever
/// AuthRouterRefresh.forceUpdateRequired is true (a live listener on
/// app_config/app_update -- see app_router.dart). The router's redirect
/// sends every route here while that holds, with no way back: there's no
/// AppBar back button and the "Update Now" button opens the store link
/// rather than dismissing this screen. Once the admin dashboard raises
/// forceUpdate back to false, or once the user actually updates (the
/// installed build number catches up), the same listener flips
/// forceUpdateRequired back to false and the router redirects away
/// automatically.
class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({super.key});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _opening = false;

  Future<void> _openStore() async {
    final info = authRouterRefresh.forceUpdateInfo;
    final url = info?.storeUrlForThisPlatform.trim() ?? '';
    if (url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    setState(() => _opening = true);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort: if the store can't be opened, the user stays on
      // this screen and can retry.
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final info = authRouterRefresh.forceUpdateInfo;
    final versionLabel = (info?.latestVersionName.trim() ?? '').isNotEmpty
        ? 'v${info!.latestVersionName.trim()}'
        : 'the latest version';
    final notes = info?.releaseNotes.trim() ?? '';

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Update Required'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Glass(
              padding: EdgeInsets.zero,
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update_rounded,
                      size: 44,
                      color: AppTheme.limeAccentDark,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A required update is available',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You need to update to $versionLabel to keep using '
                      'the app.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        notes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
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
                        onPressed: _opening ? null : _openStore,
                        child: _opening
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.darkText,
                                ),
                              )
                            : const Text('Update Now'),
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
  }
}
