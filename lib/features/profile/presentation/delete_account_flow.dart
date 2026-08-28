import 'package:flutter/material.dart';

import '../../../core/services/account_deletion_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';

// ---------------------------------------------------------------------------
// Public entry-point
//
// Call this from the settings screen.
// Returns `true` if the account was successfully deleted.
// Returns `false` if the user cancelled or deletion failed.
// ---------------------------------------------------------------------------

Future<bool> showDeleteAccountFlow(BuildContext context) async {
  // Step 1 — Warning dialog
  final confirmed = await _showWarningDialog(context);
  if (confirmed != true) return false;

  if (!context.mounted) return false;

  // Step 2 — Beautiful Feedback Form
  final feedback = await _showFeedbackDialog(context);

  // feedback == null means the user dismissed the feedback dialog with X
  if (feedback == null) return false;

  if (!context.mounted) return false;

  // Step 3 — Deletion with loading indicator
  final result = await _performDeletion(
    context,
    feedbackReason: feedback.reason,
    feedbackText: feedback.text,
  );

  return result;
}

// ---------------------------------------------------------------------------
// Step 1 — Warning + second confirmation dialog
// ---------------------------------------------------------------------------

Future<bool?> _showWarningDialog(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final brightness = theme.brightness;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(28),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Danger icon ──────────────────────────────────────────────
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withOpacity(0.10),
                    border: Border.all(
                      color: Colors.redAccent.withOpacity(0.30),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.redAccent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Title ────────────────────────────────────────────────────
                Text(
                  'Close Account',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: AppTheme.primaryText(brightness),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),

                // ── Warning message ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.redAccent.withOpacity(0.15),
                    ),
                  ),
                  child: Column(
                    children: [
                      _warningRow(
                        Icons.warning_amber_rounded,
                        'This action is permanent and cannot be undone.',
                        theme,
                        brightness,
                      ),
                      const SizedBox(height: 10),
                      _warningRow(
                        Icons.cloud_off_rounded,
                        'All your personal data, matches, and stats will be wiped.',
                        theme,
                        brightness,
                      ),
                      const SizedBox(height: 10),
                      _warningRow(
                        Icons.emoji_events_outlined,
                        'Your leagues and tournament access will be lost.',
                        theme,
                        brightness,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Buttons ──────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: AppTheme.cardBorder(brightness),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      foregroundColor: AppTheme.primaryText(brightness),
                    ),
                    child: const Text(
                      'Cancel — Keep My Account',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Yes, Close My Account',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _warningRow(IconData icon, String text, ThemeData theme, Brightness brightness) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Colors.redAccent, size: 18),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.primaryText(brightness).withOpacity(0.85),
            fontWeight: FontWeight.w700,
            height: 1.4,
            fontSize: 13,
          ),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Step 2 — Beautiful Form Dialog
// ---------------------------------------------------------------------------

class _FeedbackResult {
  const _FeedbackResult({required this.reason, this.text});
  final String reason;
  final String? text;
}

const List<String> _feedbackOptions = [
  'I don\'t understand how to use the app',
  'I have privacy concerns',
  'The app is too buggy or slow',
  'I found a better alternative',
  'I receive too many notifications',
  'Other',
];

Future<_FeedbackResult?> _showFeedbackDialog(BuildContext context) {
  return showDialog<_FeedbackResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FeedbackDialog(),
  );
}

class _FeedbackDialog extends StatefulWidget {
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final Set<String> _selectedReasons = {};
  final TextEditingController _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _toggleReason(String reason) {
    setState(() {
      if (_selectedReasons.contains(reason)) {
        _selectedReasons.remove(reason);
      } else {
        _selectedReasons.add(reason);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final onSurface = theme.colorScheme.onSurface;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Glass(
        borderRadius: 28,
        padding: const EdgeInsets.all(24),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.iconCircleBackground(brightness),
                      border: Border.all(color: AppTheme.cardBorder(brightness)),
                    ),
                    child: Icon(
                      Icons.sentiment_dissatisfied_rounded,
                      color: AppTheme.limeAccentDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'We\'re sad to see you go',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Please tell us why so we can improve.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: Icon(Icons.close, color: AppTheme.secondaryText(brightness)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Scrollable Form ──────────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select all that apply:',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._feedbackOptions.map((option) {
                        final isSelected = _selectedReasons.contains(option);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => _toggleReason(option),
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: isSelected
                                    ? AppTheme.limeAccent.withOpacity(0.15)
                                    : onSurface.withOpacity(0.04),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.limeAccentDark.withOpacity(0.5)
                                      : onSurface.withOpacity(0.1),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: isSelected
                                        ? AppTheme.limeAccentDark
                                        : AppTheme.secondaryText(brightness),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      option,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppTheme.primaryText(brightness)
                                            : AppTheme.secondaryText(brightness),
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 12),
                      Text(
                        'Tell us more (Optional):',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otherCtrl,
                        maxLines: 4,
                        maxLength: 500,
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Any additional feedback...',
                          hintStyle: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppTheme.cardBorder(brightness),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: onSurface.withOpacity(0.15),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppTheme.limeAccentDark,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                          filled: true,
                          fillColor: onSurface.withOpacity(0.04),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Footer Buttons ───────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        const _FeedbackResult(reason: 'Skipped'),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppTheme.secondaryText(brightness),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        final reason = _selectedReasons.isEmpty
                            ? 'No reason given'
                            : _selectedReasons.join(', ');
                        final text = _otherCtrl.text.trim();
                        Navigator.of(context).pop(
                          _FeedbackResult(reason: reason, text: text.isEmpty ? null : text),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Close Account',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Perform deletion with loading overlay
// ---------------------------------------------------------------------------

Future<bool> _performDeletion(
  BuildContext context, {
  String? feedbackReason,
  String? feedbackText,
}) async {
  // Show a non-dismissible loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DeletionLoadingDialog(),
  );

  AccountDeletionResult result;
  try {
    result = await AccountDeletionService.instance.deleteAccount(
      feedbackReason: feedbackReason,
      feedbackText: feedbackText,
    );
  } catch (e) {
    result = AccountDeletionResult.failure(e.toString());
  }

  // Close the loading dialog
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  if (!context.mounted) return result.success;

  if (result.success) {
    // Show brief success snack before router redirect takes over
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account Closed successfully.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    return true;
  }

  // ── Handle re-auth required ──────────────────────────────────────────────
  if (result.requiresReauth == true) {
    await showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final brightness = theme.brightness;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Glass(
            borderRadius: 24,
            padding: const EdgeInsets.all(24),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sign In Required',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  result.errorMessage ??
                      'Please sign in again before deleting your account to verify your identity.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: AppTheme.secondaryText(brightness),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return false;
  }

  // ── Generic error ────────────────────────────────────────────────────────
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.errorMessage ?? 'Account closing failed. Please try again.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  return false;
}

// ---------------------------------------------------------------------------
// Loading dialog widget
// ---------------------------------------------------------------------------

class _DeletionLoadingDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(32),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Closing Account',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppTheme.primaryText(brightness),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Removing your data permanently.\nPlease wait…',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
