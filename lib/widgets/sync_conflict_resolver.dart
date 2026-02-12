import 'dart:ui';

import 'package:flutter/material.dart';

/// Legacy conflict UI kept for compatibility.
///
/// ONLINE-ONLY NOTE:
/// In this architecture there is no local source-of-truth and no background sync.
/// If this dialog is still triggered by older flows, it should be treated as
/// a simple "choose which version to keep" prompt (manual resolution), without
/// promising any offline sync behavior.
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
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white24),
        ),
        title: const Text(
          'Update conflict',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'We found different versions of this data. Please choose which one to keep.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    String title,
    String time, {
    required bool isLocal,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, isLocal),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isLocal ? Colors.blueAccent.withOpacity(0.30) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(
                  time.trim().isEmpty ? 'Last updated: —' : 'Last updated: $time',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
            const Icon(Icons.check_circle_outline, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
