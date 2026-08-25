import 'package:flutter/material.dart';

import '../../../../../core/errors/user_friendly_error.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../data/discussions_repository.dart';

/// Shows the "start a discussion" bottom sheet. Any signed-in user may
/// post — Discussions is not Pro/Elite-gated.
Future<bool?> showCreateDiscussionSheet(
  BuildContext context, {
  required String authorDisplayName,
  required String authorPhotoUrl,
}) {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final brightness = Theme.of(ctx).brightness;
      bool busy = false;
      String? error;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final title = titleController.text.trim();
            if (title.isEmpty) {
              setSheetState(() => error = 'Please add a title.');
              return;
            }
            setSheetState(() {
              busy = true;
              error = null;
            });
            try {
              await DiscussionsRepository().createThread(
                authorDisplayName: authorDisplayName,
                authorPhotoUrl: authorPhotoUrl,
                title: title,
                body: bodyController.text,
              );
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start a Discussion',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleController,
                      maxLength: 140,
                      enabled: !busy,
                      decoration: const InputDecoration(hintText: 'Title'),
                    ),
                    TextField(
                      controller: bodyController,
                      maxLength: 4000,
                      maxLines: 5,
                      enabled: !busy,
                      decoration: const InputDecoration(hintText: 'Share more detail (optional)'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkText),
                              )
                            : const Text('Post Discussion', style: TextStyle(fontWeight: FontWeight.w900)),
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
  ).whenComplete(() {
    titleController.dispose();
    bodyController.dispose();
  });
}
