// lib/features/feed/presentation/widgets/edit_post_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/locale/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/public_feed_repository.dart';
import '../../models/public_post.dart';

/// Shows the "edit post" bottom sheet for a post's author, within
/// PublicFeedRepository.editWindow of when it was created. Only the
/// text is editable -- media/audio stay exactly as posted, shown here
/// as a non-editable preview so the author can see what their edited
/// caption will sit alongside.
Future<bool?> showEditPostSheet(
  BuildContext context, {
  required PublicPost post,
}) {
  final textController = TextEditingController(text: post.text);
  final l10n = context.l10n;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final brightness = Theme.of(ctx).brightness;
      bool busy = false;
      String? error;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final text = textController.text.trim();
            if (text.isEmpty && post.mediaUrl.isEmpty && post.audioUrl.isEmpty) {
              setSheetState(() => error = l10n.tr('create_post_empty_error'));
              return;
            }

            setSheetState(() {
              busy = true;
              error = null;
            });

            try {
              await PublicFeedRepository().editPost(postId: post.postId, text: text);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(true);
            } catch (e) {
              setSheetState(() {
                busy = false;
                error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(brightness),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.cardBorder(brightness)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('edit_post_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('edit_post_subtitle'),
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: textController,
                      maxLength: 2000,
                      maxLines: 4,
                      enabled: !busy,
                      autofocus: true,
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.tr('create_post_hint'),
                        hintStyle: TextStyle(color: AppTheme.secondaryText(brightness)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppTheme.cardBorder(brightness)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppTheme.cardBorder(brightness)),
                        ),
                      ),
                    ),
                    if (post.mediaUrl.isNotEmpty || post.audioUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            post.audioUrl.isNotEmpty ? Icons.audiotrack_outlined : Icons.image_outlined,
                            size: 16,
                            color: AppTheme.secondaryText(brightness),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.tr('edit_post_media_unchanged_note'),
                              style: TextStyle(
                                color: AppTheme.secondaryText(brightness),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.darkText),
                              )
                            : Text(l10n.tr('edit_post_save_button'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() => textController.dispose());
}
