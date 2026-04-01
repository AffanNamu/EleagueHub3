import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/empty_state.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();

  String? _processingRequestId;
  String _searchQuery = '';

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
        error: true,
      );

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _setStatus(String requestId, String status) async {
    if (_processingRequestId != null) return;

    setState(() => _processingRequestId = requestId);
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
      if (mounted) setState(() => _processingRequestId = null);
    } catch (e) {
      if (mounted) setState(() => _processingRequestId = null);
      _toastErr(e);
    }
  }

  int _intFrom(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return 'Unknown time';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _shortUserId(String userId) {
    final s = userId.trim();
    if (s.length <= 18) return s;
    return '${s.substring(0, 10)}…${s.substring(s.length - 6)}';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySearch(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _searchQuery.trim();
    if (q.isEmpty) return docs;

    return docs.where((d) {
      final data = d.data();
      final userId = (data['userId'] as String? ?? d.id).trim().toLowerCase();
      final userName = (data['userName'] as String? ?? 'User').trim().toLowerCase();
      return userId.contains(q) || userName.contains(q);
    }).toList(growable: false);
  }

  Widget _topSummaryCard(BuildContext context, int count) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withOpacity(0.12),
              border: Border.all(color: cs.primary.withOpacity(0.24)),
            ),
            child: Icon(Icons.admin_panel_settings_rounded, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Global Chat Requests',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count == 1
                      ? '1 user is waiting for approval to enter Global Chat.'
                      : '$count users are waiting for approval to enter Global Chat.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.68),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: cs.onSurface.withOpacity(0.65)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search by user name or user id...',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.trim().isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () => _searchCtrl.clear(),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }

  Widget _requestCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final data = d.data();

    final userId = (data['userId'] as String? ?? d.id).trim();
    final userName = (data['userName'] as String? ?? 'User').trim();
    final userPhoto = (data['userPhoto'] as String? ?? '').trim();
    final createdAtMs = _intFrom(data['createdAtMs'], fallback: 0);
    final updatedAtMs = _intFrom(data['updatedAtMs'], fallback: 0);

    final createdText = _fmtTime(createdAtMs);
    final updatedText = _fmtTime(updatedAtMs);

    final processingThis = _processingRequestId == d.id;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.primary.withOpacity(0.12),
                backgroundImage: userPhoto.isEmpty ? null : NetworkImage(userPhoto),
                child: userPhoto.isEmpty
                    ? Icon(
                        Icons.person_outline_rounded,
                        color: cs.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName.isEmpty ? 'User' : userName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortUserId(userId),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.60),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withOpacity(0.28),
                  ),
                ),
                child: const Text(
                  'PENDING',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(
            label: 'Requested',
            value: createdText,
          ),
          _InfoLine(
            label: 'Last updated',
            value: updatedText,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: processingThis
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: userId));
                          if (!context.mounted) return;
                          _toast('Copied user id');
                        },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text(
                    'Copy ID',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: processingThis
                      ? null
                      : () => _setStatus(d.id, 'approved'),
                  icon: processingThis
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    processingThis ? 'Please wait...' : 'Approve',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: processingThis
                  ? null
                  : () => _setStatus(d.id, 'rejected'),
              icon: const Icon(Icons.close_rounded),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withOpacity(0.24)),
              ),
              label: const Text(
                'Reject',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Global Chat Requests'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
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
              err is Object ? err : Exception('unknown'),
            );

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
                  borderRadius: 26,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 36,
                      ),
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
                            color: theme.colorScheme.onSurface.withOpacity(0.45),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final docs = snap.data?.docs ?? const [];
          final sorted = docs.toList()
            ..sort((a, b) {
              final ams = _intFrom(a.data()['createdAtMs'], fallback: 0);
              final bms = _intFrom(b.data()['createdAtMs'], fallback: 0);
              return bms.compareTo(ams);
            });

          final filtered = _applySearch(sorted);

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _topSummaryCard(context, docs.length),
                const SizedBox(height: 14),
                _searchBar(context),
                const SizedBox(height: 14),
                if (docs.isEmpty)
                  const EmptyState(
                    title: 'No pending requests',
                    message: 'All global chat access requests have been handled.',
                    icon: Icons.inbox_outlined,
                  )
                else if (filtered.isEmpty)
                  const EmptyState(
                    title: 'No matching requests',
                    message: 'Try another search term for user name or id.',
                    icon: Icons.search_off_rounded,
                  )
                else
                  ...filtered.map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _requestCard(context, d),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.60),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
