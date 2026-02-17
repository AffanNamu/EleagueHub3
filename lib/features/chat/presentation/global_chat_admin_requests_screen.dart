import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

class GlobalChatAdminRequestsScreen extends StatefulWidget {
  const GlobalChatAdminRequestsScreen({super.key});

  @override
  State<GlobalChatAdminRequestsScreen> createState() => _GlobalChatAdminRequestsScreenState();
}

class _GlobalChatAdminRequestsScreenState extends State<GlobalChatAdminRequestsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _busy = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  void _toastErr(Object e) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color.alphaBlend(cs.error.withOpacity(0.20), const Color(0xFF0B1220)),
        content: Text(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'))),
      ),
    );
  }

  Future<void> _setStatus(String requestId, String status) async {
    setState(() => _busy = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      final now = DateTime.now().millisecondsSinceEpoch;

      await _firestore.collection('globalChatRequests').doc(requestId).set(
        <String, dynamic>{
          'status': status,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      _toast('Updated: $status');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toastErr(e is Object ? e : Exception('unknown'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient(theme.brightness),
      ),
      child: GlassScaffold(
        appBar: AppBar(
          title: const Text('Global Chat Requests'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('globalChatRequests')
              .where('status', isEqualTo: 'pending')
              .orderBy('createdAtMs', descending: true)
              .limit(200)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(UserFriendlyError.toMessage(snap.error is Object ? snap.error! : Exception('unknown'))),
                ),
              );
            }

            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  'No pending requests',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.55), fontWeight: FontWeight.w700),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data();

                final userId = (data['userId'] as String? ?? d.id).trim();
                final userName = (data['userName'] as String? ?? 'User').trim();
                final userPhoto = (data['userPhoto'] as String? ?? '').trim();

                return Glass(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.08),
                        backgroundImage: userPhoto.isEmpty ? null : NetworkImage(userPhoto),
                        child: userPhoto.isEmpty
                            ? Icon(Icons.person_outline, color: theme.colorScheme.onSurface.withOpacity(0.55))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              userId,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _busy ? null : () => _setStatus(d.id, 'approved'),
                        child: const Text('Approve'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _setStatus(d.id, 'rejected'),
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
