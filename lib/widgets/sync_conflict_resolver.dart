import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class SyncConflictResolver extends StatelessWidget {
  final Map<String, dynamic> localData;
  final Map<String, dynamic> cloudData;

  const SyncConflictResolver({
    super.key,
    required this.localData,
    required this.cloudData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return AlertDialog(
      backgroundColor: AppTheme.cardColor(brightness),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.cardBorder(brightness)),
      ),
      title: Text(
        'Update conflict',
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'We found different versions of this data. Please choose which one to keep.',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _buildOption(
            context,
            'This device',
            (localData['timestamp'] ?? '').toString(),
            isLocal: true,
          ),
          const SizedBox(height: 12),
          _buildOption(
            context,
            'Server',
            (cloudData['timestamp'] ?? '').toString(),
            isLocal: false,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context,
    String title,
    String time, {
    required bool isLocal,
  }) {
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: () => Navigator.pop(context, isLocal),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isLocal
              ? (brightness == Brightness.dark
                  ? AppTheme.limeAccentDark.withOpacity(0.14)
                  : const Color(0xFFECFCCB))
              : AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLocal
                ? (brightness == Brightness.dark
                    ? AppTheme.limeAccentDark.withOpacity(0.24)
                    : const Color(0xFFD9F99D))
                : AppTheme.searchOutline(brightness),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  time.trim().isEmpty ? 'Last updated: —' : 'Last updated: $time',
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.check_circle_outline,
              color: AppTheme.secondaryText(brightness),
            ),
          ],
        ),
      ),
    );
  }
}
