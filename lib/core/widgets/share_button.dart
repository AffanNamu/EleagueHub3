// lib/core/widgets/share_button.dart
//
// ShareButton — drop this into any screen's AppBar actions or body to
// offer a consistent, branded share experience across the app:
//   WhatsApp · Telegram · Facebook · X · Copy Link · SMS · More
//
// Usage:
//   ShareButton(
//     entity: ShareableEntity(type: ShareableEntityType.userProfile,
//                              username: profile.usernameLower),
//     title: profile.displayName,
//     description: 'Professional eFootball Player',
//   )
//
// This widget is intentionally UI-only — all link building and channel
// launching is delegated to [ShareService] / [LinkGenerator], so this
// same widget works unmodified for every current and future shareable
// entity type.
import 'package:flutter/material.dart';

import '../routing/route_resolver.dart';
import '../sharing/share_service.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.entity,
    required this.title,
    this.description = '',
    this.icon = Icons.share_rounded,
    this.tooltip = 'Share',
    this.asIconButton = true,
  });

  /// The entity being shared — e.g.
  /// `ShareableEntity(type: ShareableEntityType.competition, id: leagueId)`.
  final ShareableEntity entity;

  /// Human-readable title used in share text (e.g. profile display name,
  /// competition name, post author name).
  final String title;

  /// Optional short description appended to share text.
  final String description;

  final IconData icon;
  final String tooltip;

  /// If true, renders as an [IconButton] (good for AppBar actions). If
  /// false, renders as a full-width [OutlinedButton] with a label (good
  /// for body content, e.g. below a profile header).
  final bool asIconButton;

  @override
  Widget build(BuildContext context) {
    if (asIconButton) {
      return IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: () => showShareSheet(
          context,
          entity: entity,
          title: title,
          description: description,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: () => showShareSheet(
        context,
        entity: entity,
        title: title,
        description: description,
      ),
      icon: Icon(icon, size: 18),
      label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

/// Shows the branded share bottom sheet. Exposed as a top-level function so
/// non-button call sites (e.g. a "More actions" menu item) can trigger the
/// same sheet without instantiating [ShareButton].
Future<void> showShareSheet(
  BuildContext context, {
  required ShareableEntity entity,
  required String title,
  String description = '',
}) {
  final payload = ShareService.instance.buildPayload(
    entity: entity,
    title: title,
    description: description,
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ShareSheet(payload: payload),
  );
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.payload});
  final SharePayload payload;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);

    Widget channelTile({
      required IconData icon,
      required String label,
      required Color color,
      required Future<void> Function() onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await onTap();
          if (context.mounted) Navigator.of(context).pop();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.30)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(18),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.ios_share_rounded, color: AppTheme.limeAccentDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Share',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  channelTile(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => ShareService.instance.shareToWhatsApp(payload),
                  ),
                  channelTile(
                    icon: Icons.send_rounded,
                    label: 'Telegram',
                    color: const Color(0xFF229ED9),
                    onTap: () => ShareService.instance.shareToTelegram(payload),
                  ),
                  channelTile(
                    icon: Icons.facebook_rounded,
                    label: 'Facebook',
                    color: const Color(0xFF1877F2),
                    onTap: () => ShareService.instance.shareToFacebook(payload),
                  ),
                  channelTile(
                    icon: Icons.close_rounded,
                    label: 'X',
                    color: AppTheme.primaryText(brightness),
                    onTap: () => ShareService.instance.shareToX(payload),
                  ),
                  channelTile(
                    icon: Icons.sms_rounded,
                    label: 'SMS',
                    color: const Color(0xFF34C759),
                    onTap: () => ShareService.instance.shareViaSms(payload),
                  ),
                  channelTile(
                    icon: Icons.link_rounded,
                    label: 'Copy Link',
                    color: AppTheme.limeAccentDark,
                    onTap: () => ShareService.instance.copyLink(payload),
                  ),
                  channelTile(
                    icon: Icons.more_horiz_rounded,
                    label: 'More',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => ShareService.instance.shareViaSystemSheet(payload),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.searchBackground(brightness),
                  border: Border.all(color: AppTheme.searchOutline(brightness)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        payload.link.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.copy_rounded,
                        size: 16, color: AppTheme.secondaryText(brightness)),
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
