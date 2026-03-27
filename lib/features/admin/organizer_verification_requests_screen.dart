import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_admins_service.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import '../../features/master_leagues/data/organizer_feed_firebase.dart';

class OrganizerVerificationRequestsScreen extends StatefulWidget {
  const OrganizerVerificationRequestsScreen({super.key});

  @override
  State<OrganizerVerificationRequestsScreen> createState() =>
      _OrganizerVerificationRequestsScreenState();
}

class _OrganizerVerificationRequestsScreenState
    extends State<OrganizerVerificationRequestsScreen> {
  String _filter = 'pending';
  bool _busy = false;
  final OrganizerFeedFirebase _feed = OrganizerFeedFirebase();

  bool _isAdmin() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    return AppAdminsService.instance.isPricingAdminUid(uid);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final text = message.trim();
    if (text.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamRequests() {
    return FirebaseFirestore.instance
        .collection('master_league_verification_requests')
        .where('status', isEqualTo: _filter)
        .orderBy('submittedAtMs', descending: true)
        .limit(100)
        .snapshots();
  }

  Future<void> _reviewRequest({
    required String requestId,
    required String masterLeagueId,
    required String ownerId,
    required bool approve,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (adminUid.isEmpty) {
      _snack('Please sign in again.', error: true);
      return;
    }

    final noteCtrl = TextEditingController();

    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve verification' : 'Reject verification'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Review note',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(noteCtrl.text.trim()),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    noteCtrl.dispose();

    if (note == null) return;

    setState(() => _busy = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final requestRef = FirebaseFirestore.instance
          .collection('master_league_verification_requests')
          .doc(requestId);
      final mlRef = FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(masterLeagueId);

      bool approvedRenewal = false;

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final requestSnap = await txn.get(requestRef);
        if (!requestSnap.exists) {
          throw StateError('Verification request not found.');
        }

        final requestData =
            (requestSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final status = (requestData['status'] as String? ?? '')
            .trim()
            .toLowerCase();
        if (status != 'pending') {
          throw StateError('Only pending requests can be reviewed.');
        }

        final requestType =
            (requestData['requestType'] as String? ?? 'initial')
                .trim()
                .toLowerCase();

        final mlSnap = await txn.get(mlRef);
        if (!mlSnap.exists) {
          throw StateError('Master League not found.');
        }

        final mlData =
            (mlSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final currentExpiry =
            ((mlData['verificationExpiresAtMs'] as num?) ?? 0).toInt();

        final updateStatus = approve ? 'approved' : 'rejected';

        txn.update(requestRef, <String, dynamic>{
          'status': updateStatus,
          'reviewedAtMs': now,
          'reviewedBy': adminUid,
          'note': note,
        });

        int nextExpiryMs = currentExpiry;
        if (approve) {
          if (requestType == 'renewal') {
            approvedRenewal = true;
            const durationMs = 90 * 24 * 60 * 60 * 1000;
            final base = currentExpiry > now ? currentExpiry : now;
            nextExpiryMs = base + durationMs;
          } else {
            const durationMs = 90 * 24 * 60 * 60 * 1000;
            nextExpiryMs = now + durationMs;
          }
        } else {
          nextExpiryMs = currentExpiry;
        }

        txn.update(mlRef, <String, dynamic>{
          'verificationStatus': updateStatus,
          'verifiedBadge': approve,
          'verificationApprovedAtMs': approve ? now : 0,
          'verificationExpiresAtMs': approve ? nextExpiryMs : currentExpiry,
          'verificationReviewedBy': adminUid,
          'verificationNote': note,
          'verificationRequestType': requestType,
          'updatedAtMs': now,
        });

        if (approve) {
          final userRef =
              FirebaseFirestore.instance.collection('users').doc(ownerId);
          txn.set(
            userRef,
            <String, dynamic>{
              'lastVerifiedMasterLeagueId': masterLeagueId,
              'updatedAt': now,
            },
            SetOptions(merge: true),
          );
        }
      });

      if (approve) {
        try {
          await _feed.addVerificationApprovedEvent(
            masterLeagueId: masterLeagueId,
            actorId: adminUid,
            actorName: 'Admin',
            isRenewal: approvedRenewal,
          );
        } catch (_) {}
      }

      _snack(
        approve
            ? 'Verification approved successfully.'
            : 'Verification rejected successfully.',
      );
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFF1D9BF0);
      case 'rejected':
        return cs.error;
      case 'pending':
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Color _typeColor(String type, ColorScheme cs) {
    switch (type.trim().toLowerCase()) {
      case 'renewal':
        return const Color(0xFF14B8A6);
      case 'initial':
      default:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_isAdmin()) {
      return GlassScaffold(
        appBar: AppBar(
          title: const Text('Verification Requests'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Glass(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Not authorized.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Verification Requests'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Pricing Admin',
            onPressed: () => context.push('/admin/pricing'),
            icon: const Icon(Icons.price_change_rounded),
          ),
          IconButton(
            tooltip: 'Manage Pricing Admins',
            onPressed: () => context.push('/admin/pricing-admins'),
            icon: const Icon(Icons.admin_panel_settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamRequests(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Glass(
                        borderRadius: 24,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Review organizer verification requests',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ChoiceChip(
                                  label: const Text('Pending'),
                                  selected: _filter == 'pending',
                                  onSelected: (_) => setState(() => _filter = 'pending'),
                                ),
                                ChoiceChip(
                                  label: const Text('Approved'),
                                  selected: _filter == 'approved',
                                  onSelected: (_) => setState(() => _filter = 'approved'),
                                ),
                                ChoiceChip(
                                  label: const Text('Rejected'),
                                  selected: _filter == 'rejected',
                                  onSelected: (_) => setState(() => _filter = 'rejected'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (snap.hasError)
                        Glass(
                          borderRadius: 22,
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${snap.error}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      else if (!snap.hasData)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (docs.isEmpty)
                        Glass(
                          borderRadius: 22,
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'No $_filter verification requests found.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.72),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        ...docs.map((doc) {
                          final data = doc.data();
                          final requestId =
                              (data['requestId'] as String? ?? doc.id).trim();
                          final masterLeagueId =
                              (data['masterLeagueId'] as String? ?? '').trim();
                          final ownerId = (data['ownerId'] as String? ?? '').trim();
                          final status = (data['status'] as String? ?? 'pending').trim();
                          final requestType =
                              (data['requestType'] as String? ?? 'initial')
                                  .trim();
                          final provider = (data['provider'] as String? ?? '').trim();
                          final receiptId = (data['receiptId'] as String? ?? '').trim();
                          final paymentId = (data['paymentId'] as String? ?? '').trim();
                          final note = (data['note'] as String? ?? '').trim();
                          final reviewedBy =
                              (data['reviewedBy'] as String? ?? '').trim();
                          final submittedAtMs =
                              (data['submittedAtMs'] as num?)?.toInt() ?? 0;
                          final reviewedAtMs =
                              (data['reviewedAtMs'] as num?)?.toInt() ?? 0;

                          final statusColor = _statusColor(status, cs);
                          final requestTypeColor = _typeColor(requestType, cs);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Glass(
                              borderRadius: 22,
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          masterLeagueId.isEmpty
                                              ? 'Verification Request'
                                              : 'Master League: $masterLeagueId',
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(999),
                                          color: requestTypeColor.withOpacity(0.14),
                                          border: Border.all(
                                            color: requestTypeColor.withOpacity(0.28),
                                          ),
                                        ),
                                        child: Text(
                                          requestType.toUpperCase(),
                                          style: TextStyle(
                                            color: requestTypeColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(999),
                                          color: statusColor.withOpacity(0.14),
                                          border: Border.all(
                                            color: statusColor.withOpacity(0.28),
                                          ),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _kv(theme, cs, 'Request ID', requestId),
                                  _kv(theme, cs, 'Request Type', requestType),
                                  _kv(theme, cs, 'Owner UID', ownerId),
                                  _kv(theme, cs, 'Provider', provider.isEmpty ? '—' : provider),
                                  _kv(theme, cs, 'Receipt ID', receiptId.isEmpty ? '—' : receiptId),
                                  _kv(theme, cs, 'Payment ID', paymentId.isEmpty ? '—' : paymentId),
                                  _kv(
                                    theme,
                                    cs,
                                    'Submitted',
                                    submittedAtMs > 0
                                        ? DateTime.fromMillisecondsSinceEpoch(submittedAtMs)
                                            .toLocal()
                                            .toString()
                                        : '—',
                                  ),
                                  if (reviewedAtMs > 0)
                                    _kv(
                                      theme,
                                      cs,
                                      'Reviewed',
                                      DateTime.fromMillisecondsSinceEpoch(reviewedAtMs)
                                          .toLocal()
                                          .toString(),
                                    ),
                                  if (reviewedBy.isNotEmpty)
                                    _kv(theme, cs, 'Reviewed By', reviewedBy),
                                  if (note.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Note:',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.70),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      note,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.82),
                                        fontWeight: FontWeight.w700,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: masterLeagueId.isEmpty
                                            ? null
                                            : () => context.push('/master-leagues/$masterLeagueId'),
                                        icon: const Icon(Icons.open_in_new_rounded),
                                        label: const Text('Open Master League'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: ownerId.isEmpty
                                            ? null
                                            : () async {
                                                await Clipboard.setData(
                                                  ClipboardData(text: ownerId),
                                                );
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Owner UID copied'),
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              },
                                        icon: const Icon(Icons.copy_rounded),
                                        label: const Text('Copy Owner UID'),
                                      ),
                                      if (status == 'pending') ...[
                                        FilledButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewRequest(
                                                    requestId: requestId,
                                                    masterLeagueId: masterLeagueId,
                                                    ownerId: ownerId,
                                                    approve: true,
                                                  ),
                                          icon: const Icon(Icons.verified_rounded),
                                          label: Text(
                                            requestType.toLowerCase() == 'renewal'
                                                ? 'Approve Renewal'
                                                : 'Approve',
                                            style: const TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                        FilledButton.tonalIcon(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewRequest(
                                                    requestId: requestId,
                                                    masterLeagueId: masterLeagueId,
                                                    ownerId: ownerId,
                                                    approve: false,
                                                  ),
                                          icon: const Icon(Icons.close_rounded),
                                          label: Text(
                                            requestType.toLowerCase() == 'renewal'
                                                ? 'Reject Renewal'
                                                : 'Reject',
                                            style: const TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.68),
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
