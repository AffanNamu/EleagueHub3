import 'package:flutter/material.dart';

import '../../../core/services/account_deletion_service.dart';
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

  // Step 2 — Optional feedback form
  final feedback = await _showFeedbackDialog(context);

  // feedback == null means the user dismissed the feedback dialog with X
  // We still allow deletion in that case (feedback is optional).
  // feedback is a _FeedbackResult when the user taps Continue or Skip.
  if (!context.mounted) return false;

  // Step 3 — Deletion with loading indicator
  final result = await _performDeletion(
    context,
    feedbackReason: feedback?.reason,
    feedbackText: feedback?.text,
  );

  return result;
}

// ---------------------------------------------------------------------------
// Step 1 — Warning + second confirmation dialog
// ---------------------------------------------------------------------------

Future<bool?> _showWarningDialog(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: theme.brightness == Brightness.dark
            ? const Color(0xFF1E1E2E)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 360,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Danger icon ──────────────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.10),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.30),
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
                'Delete Account',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              // ── Warning message ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.20),
                  ),
                ),
                child: Column(
                  children: [
                    _warningRow(
                      Icons.warning_amber_rounded,
                      'This action is permanent.',
                      theme,
                    ),
                    const SizedBox(height: 8),
                    _warningRow(
                      Icons.cloud_off_rounded,
                      'All your data will be deleted and cannot be recovered.',
                      theme,
                    ),
                    const SizedBox(height: 8),
                    _warningRow(
                      Icons.emoji_events_outlined,
                      'Your leagues, compilations and profile will be removed.',
                      theme,
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
                      color: cs.onSurface.withOpacity(0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    foregroundColor: cs.onSurface,
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
                    'Yes, Delete My Account',
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
      );
    },
  );
}

Widget _warningRow(IconData icon, String text, ThemeData theme) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Colors.redAccent, size: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.redAccent,
            fontWeight: FontWeight.w700,
            height: 1.35,
            fontSize: 12,
          ),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Step 2 — Optional feedback dialog
// ---------------------------------------------------------------------------

class _FeedbackResult {
  const _FeedbackResult({required this.reason, this.text});
  final String reason;
  final String? text;
}

const List<String> _feedbackOptions = [
  'Too many ads',
  'App is not useful',
  'Found a better app',
  'Bugs or issues',
  'Other',
];

Future<_FeedbackResult?> _showFeedbackDialog(BuildContext context) {
  return showDialog<_FeedbackResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _FeedbackDialog(),
  );
}

class _FeedbackDialog extends StatefulWidget {
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  String? _selectedReason;
  final TextEditingController _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor:
          isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary.withOpacity(0.10),
                    ),
                    child: Icon(
                      Icons.feedback_outlined,
                      color: cs.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Why are you leaving?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Optional — helps us improve',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withOpacity(0.55),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Reason chips ─────────────────────────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _feedbackOptions.map((option) {
                  final selected = _selectedReason == option;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedReason = option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: selected
                            ? cs.primary.withOpacity(0.15)
                            : onSurface.withOpacity(0.05),
                        border: Border.all(
                          color: selected
                              ? cs.primary.withOpacity(0.60)
                              : onSurface.withOpacity(0.12),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        option,
                        style: TextStyle(
                          color: selected
                              ? cs.primary
                              : onSurface.withOpacity(0.75),
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // ── "Other" text input ────────────────────────────────────────
              if (_selectedReason == 'Other') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _otherCtrl,
                  maxLines: 3,
                  maxLength: 300,
                  style: TextStyle(
                    color: onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tell us more (optional)…',
                    hintStyle: TextStyle(
                      color: onSurface.withOpacity(0.40),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: onSurface.withOpacity(0.20),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: onSurface.withOpacity(0.15),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: cs.primary.withOpacity(0.60),
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                    filled: true,
                    fillColor: onSurface.withOpacity(0.04),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ── Buttons ──────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final reason =
                        _selectedReason ?? 'Not specified';
                    final text = _selectedReason == 'Other'
                        ? _otherCtrl.text.trim()
                        : null;
                    Navigator.of(context).pop(
                      _FeedbackResult(reason: reason, text: text),
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
                    'Continue to Delete',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const _FeedbackResult(reason: 'Skipped'),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: onSurface.withOpacity(0.60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Skip & Delete',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
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
        content: Text('Account deleted successfully.'),
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
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Sign In Required',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            result.errorMessage ??
                'Please sign in again before deleting your account.',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
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
          result.errorMessage ?? 'Account deletion failed. Please try again.',
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
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor:
          isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Deleting Account',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Removing your data permanently.\nPlease wait…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: onSurface.withOpacity(0.55),
                fontWeight: FontWeight.w600,
                height: 1.45,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
