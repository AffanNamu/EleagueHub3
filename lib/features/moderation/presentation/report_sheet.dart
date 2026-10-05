// lib/features/moderation/presentation/report_sheet.dart
//
// Shared "Report" bottom sheet, reused across every UGC surface (chat
// messages, feed posts, feed comments, and the original profile report
// entry point) so Apple's Guideline 1.2 "report objectionable content"
// requirement is satisfied consistently everywhere instead of once per
// surface. Submits through ReportRepository.submitReport, which already
// generalizes over ReportTargetType (profile/message/post/comment).

import 'package:flutter/material.dart';

import '../../../core/locale/app_localizations.dart';
import '../data/report_repository.dart';
import '../models/user_report.dart';

/// Opens the report bottom sheet. [targetUserId] must be the author of the
/// content being reported (or the profile itself for
/// [ReportTargetType.profile]). [contextId]/[contextLocation] let the
/// admin review queue locate the specific message/post/comment.
void showReportSheet(
  BuildContext context, {
  required String targetUserId,
  required String targetType,
  String contextId = '',
  String contextLocation = '',
}) {
  final ReportRepository reportRepo = ReportRepository();
  final reasons = [
    UserReportReason.spam,
    UserReportReason.harassment,
    UserReportReason.impersonation,
    UserReportReason.cheating,
    UserReportReason.other,
  ];

  final l10n = context.l10n;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      String? selectedReason;
      final detailsController = TextEditingController();
      bool submitting = false;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
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
                      targetType == ReportTargetType.profile
                          ? l10n.tr('public_profile_report_sheet_title')
                          : l10n.tr('moderation_report_content_sheet_title'),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: reasons
                          .map((r) => ChoiceChip(
                                label: Text(UserReportReason.label(r)),
                                selected: selectedReason == r,
                                onSelected: (_) => setSheetState(() => selectedReason = r),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: InputDecoration(
                          hintText: l10n.tr('public_profile_report_details_hint')),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (selectedReason == null || submitting)
                            ? null
                            : () async {
                                setSheetState(() => submitting = true);
                                try {
                                  await reportRepo.submitReport(
                                    targetUserId: targetUserId,
                                    reason: selectedReason!,
                                    details: detailsController.text,
                                    targetType: targetType,
                                    contextId: contextId,
                                    contextLocation: contextLocation,
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          l10n.tr('public_profile_report_submitted_snackbar')),
                                    ),
                                  );
                                } catch (e) {
                                  setSheetState(() => submitting = false);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx)
                                      .showSnackBar(SnackBar(content: Text(e.toString())));
                                }
                              },
                        child: submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.tr('public_profile_submit_report_button')),
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
  );
}
