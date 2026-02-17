import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

class GlobalChatAdminRequestsScreen extends StatefulWidget {
  const GlobalChatAdminRequestsScreen({super.key});

  @override
  State<GlobalChatAdminRequestsScreen> createState() =>
      _GlobalChatAdminRequestsScreenState();
}

class _GlobalChatAdminRequestsScreenState
    extends State<GlobalChatAdminRequestsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _busy = false;

  final String _statusFilter = 'pending';

  void _toast(String msg, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? cs.error : null,
        content: Text(msg),
      ),
    );
  }

  void _toastErr(Object e) => _toast(
      UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      error: true);

  // ── FIXED: use .update() instead of .set(merge:true) ──
  Future<void> _setStatus(String requestId, String status) async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      final now = DateTime.now().millisecondsSinceEpoch;

      await _firestore.collection('globalChatRequests').doc(requestId).update(
        <String, dynamic>{
          'status': status,
          'updatedAtMs': now,
        },
      );

      _toast('Updated: $status');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toastErr(e);
    }
  }

  int _intFrom(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
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
              .where('status', isEqualTo: _statusFilter)
              .limit(200)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              final err = snap.error;

              String msg = UserFriendlyError.toMessage(
                  err is Object ? err : Exception('unknown'));

              if (err is FirebaseException) {
                if (err.code == 'permission-denied') {
                  msg =
                      'Super admin only. You do not have permission to view requests.';
                } else if (err.code == 'failed-precondition') {
                  msg =
                      'Firestore requires an index for this query.\n\nOpen Firebase Console → Firestore → Indexes and create the suggested index.';
                }
              }

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Glass(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.error, size: 36),
                        const SizedBox(height: 10),
                        Text(
                          msg,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (kDebugMode && err != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            err.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.45),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  'No pending requests',
                  style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                      fontWeight: FontWeight.w700),
                ),
              );
            }

            final sorted = docs.toList()
              ..sort((a, b) {
                final ams =
                    _intFrom(a.data()['createdAtMs'], fallback: 0);
                final bms =
                    _intFrom(b.data()['createdAtMs'], fallback: 0);
                return bms.compareTo(ams);
              });

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final d = sorted[i];
                final data = d.data();

                final userId =
                    (data['userId'] as String? ?? d.id).trim();
                final userName =
                    (data['userName'] as String? ?? 'User').trim();
                final userPhoto =
                    (data['userPhoto'] as String? ?? '').trim();

                return Glass(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                theme.colorScheme.onSurface.withOpacity(0.08),
                            backgroundImage: userPhoto.isEmpty
                                ? null
                                : NetworkImage(userPhoto),
                            child: userPhoto.isEmpty
                                ? Icon(Icons.person_outline,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.55))
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  userId,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.55),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _setStatus(d.id, 'approved'),
                              child: const Text('Approve'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _setStatus(d.id, 'rejected'),
                              child: const Text('Reject'),
                            ),
                          ),
                        ],
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
