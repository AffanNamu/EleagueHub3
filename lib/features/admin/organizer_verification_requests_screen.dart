import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_admins_service.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import '../../features/master_leagues/data/organizer_feed_firebase.dart';
import '../../features/master_leagues/domain/organizer_verification_request.dart';

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

  /// action: 'approve' | 'reject' | 'info_requested'
  Future<void> _reviewRequest({
    required OrganizerVerificationRequest req,
    required String action,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (adminUid.isEmpty) {
      _snack('Please sign in again.', error: true);
      return;
    }

    final noteCtrl = TextEditingController();
    final requiresNote = action != 'approve';

    final titleFor = {
      'approve': 'Approve verification',
      'reject': 'Reject verification',
      'info_requested': 'Request additional information',
    }[action]!;

    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titleFor),
        content: TextField(
          controller: noteCtrl,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(
            labelText: requiresNote ? 'Review note (required)' : 'Review note (optional)',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = noteCtrl.text.trim();
              if (requiresNote && text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            child: Text(titleFor),
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
          .doc(req.requestId);
      final mlRef = FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(req.masterLeagueId);

      bool approvedRenewal = false;

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final requestSnap = await txn.get(requestRef);
        if (!requestSnap.exists) {
          throw StateError('Verification request not found.');
        }

        final requestData =
            (requestSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final status =
            (requestData['status'] as String? ?? '').trim().toLowerCase();
        if (status != 'pending' && status != 'info_requested') {
          throw StateError('Only pending requests can be reviewed.');
        }

        final requestType =
            (requestData['requestType'] as String? ?? 'initial')
                .trim()
                .toLowerCase();
        final logoUrl = (requestData['logoUrl'] as String? ?? '').trim();

        final mlSnap = await txn.get(mlRef);
        if (!mlSnap.exists) {
          throw StateError('Master League not found.');
        }

        final mlData =
            (mlSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final currentExpiry =
            ((mlData['verificationExpiresAtMs'] as num?) ?? 0).toInt();
        final currentLogoUrl = (mlData['logoUrl'] as String? ?? '').trim();

        final newRequestStatus = switch (action) {
          'approve' => 'approved',
          'reject' => 'rejected',
          _ => 'info_requested',
        };

        txn.update(requestRef, <String, dynamic>{
          'status': newRequestStatus,
          'reviewedAtMs': now,
          'reviewedBy': adminUid,
          'note': note,
        });

        if (action == 'info_requested') {
          txn.update(mlRef, <String, dynamic>{
            'verificationStatus': 'info_requested',
            'verifiedBadge': false,
            'verificationReviewedBy': adminUid,
            'verificationNote': note,
            'verificationRequestType': requestType,
            'updatedAtMs': now,
          });
          return;
        }

        final approve = action == 'approve';
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
        }

        final mlUpdate = <String, dynamic>{
          'verificationStatus': newRequestStatus,
          'verifiedBadge': approve,
          'verificationApprovedAtMs': approve ? now : 0,
          'verificationExpiresAtMs': approve ? nextExpiryMs : currentExpiry,
          'verificationReviewedBy': adminUid,
          'verificationNote': note,
          'verificationRequestType': requestType,
          'updatedAtMs': now,
        };

        // Propagate the approved logo as the organizer's official
        // identity, but never overwrite a logo the owner already set.
        if (approve && logoUrl.isNotEmpty && currentLogoUrl.isEmpty) {
          mlUpdate['logoUrl'] = logoUrl;
        }

        txn.update(mlRef, mlUpdate);

        if (approve) {
          final userRef =
              FirebaseFirestore.instance.collection('users').doc(req.ownerId);
          txn.set(
            userRef,
            <String, dynamic>{
              'lastVerifiedMasterLeagueId': req.masterLeagueId,
              'updatedAt': now,
            },
            SetOptions(merge: true),
          );
        }
      });

      if (action == 'approve') {
        try {
          await _feed.addVerificationApprovedEvent(
            masterLeagueId: req.masterLeagueId,
            actorId: adminUid,
            actorName: 'Admin',
            isRenewal: approvedRenewal,
          );
        } catch (_) {}
      }

      _snack(switch (action) {
        'approve' => 'Verification approved successfully.',
        'reject' => 'Verification rejected successfully.',
        _ => 'Additional information requested from the applicant.',
      });
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
      case 'info_requested':
        return const Color(0xFFF59E0B);
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
                  constraints: const BoxConstraints(maxWidth: 900),
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
                              'Review organizer verification applications',
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
                                  label: const Text('Info Requested'),
                                  selected: _filter == 'info_requested',
                                  onSelected: (_) =>
                                      setState(() => _filter = 'info_requested'),
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
                            'No $_filter verification applications found.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.72),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        ...docs.map((doc) {
                          final req = OrganizerVerificationRequest.fromDoc(doc);
                          final statusColor = _statusColor(req.status, cs);
                          final requestTypeColor = _typeColor(req.requestType, cs);

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
                                      if (req.logoUrl.trim().isNotEmpty) ...[
                                        ClipOval(
                                          child: Image.network(
                                            req.logoUrl,
                                            width: 36,
                                            height: 36,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox(width: 36, height: 36),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Text(
                                          req.orgName.trim().isNotEmpty
                                              ? req.orgName
                                              : (req.masterLeagueId.isEmpty
                                                  ? 'Verification Request'
                                                  : 'Master League: ${req.masterLeagueId}'),
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
                                          req.requestType.toUpperCase(),
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
                                          req.status.toUpperCase(),
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
                                  if (req.isLegacyPaymentOnly)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'Legacy request \u2014 submitted before the '
                                        'application form existed. Payment info only.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withOpacity(0.55),
                                          fontWeight: FontWeight.w700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    )
                                  else ...[
                                    _kv(theme, cs, 'Org type', req.orgType.isEmpty ? '\u2014' : req.orgType),
                                    _kv(theme, cs, 'Country', req.orgCountry.isEmpty ? '\u2014' : req.orgCountry),
                                    _kv(theme, cs, 'Location',
                                        [req.orgCity, req.orgRegion].where((s) => s.isNotEmpty).join(', ').ifEmptyDash()),
                                    _kv(theme, cs, 'Applicant', req.applicantFullName.isEmpty ? '\u2014' : req.applicantFullName),
                                    _kv(theme, cs, 'Role', req.applicantRole.isEmpty ? '\u2014' : req.applicantRole),
                                    _kv(theme, cs, 'Email', req.contactEmail.isEmpty ? '\u2014' : req.contactEmail),
                                    _kv(theme, cs, 'Phone', req.contactPhone.isEmpty ? '\u2014' : req.contactPhone),
                                    _kv(theme, cs, 'Website', req.website.isEmpty ? '\u2014' : req.website),
                                    if (req.orgDescription.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('What they do:',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.70),
                                              fontWeight: FontWeight.w900)),
                                      Text(req.orgDescription,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.82),
                                              fontWeight: FontWeight.w700, height: 1.35)),
                                    ],
                                    if (req.verificationReason.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('Why they want verification:',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.70),
                                              fontWeight: FontWeight.w900)),
                                      Text(req.verificationReason,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.82),
                                              fontWeight: FontWeight.w700, height: 1.35)),
                                    ],
                                    if (req.supportingLinks.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('Supporting links:',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.70),
                                              fontWeight: FontWeight.w900)),
                                      Text(req.supportingLinks,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.82),
                                              fontWeight: FontWeight.w700, height: 1.35)),
                                    ],
                                  ],
                                  const SizedBox(height: 8),
                                  _kv(theme, cs, 'Request ID', req.requestId),
                                  _kv(theme, cs, 'Owner UID', req.ownerId),
                                  _kv(theme, cs, 'Provider', req.provider.isEmpty ? '\u2014' : req.provider),
                                  _kv(theme, cs, 'Receipt ID', req.receiptId.isEmpty ? '\u2014' : req.receiptId),
                                  _kv(theme, cs, 'Payment ID', req.paymentId.isEmpty ? '\u2014' : req.paymentId),
                                  _kv(
                                    theme,
                                    cs,
                                    'Submitted',
                                    req.submittedAtMs > 0
                                        ? DateTime.fromMillisecondsSinceEpoch(req.submittedAtMs)
                                            .toLocal()
                                            .toString()
                                        : '\u2014',
                                  ),
                                  if (req.resubmittedAtMs > 0)
                                    _kv(
                                      theme,
                                      cs,
                                      'Resubmitted',
                                      DateTime.fromMillisecondsSinceEpoch(req.resubmittedAtMs)
                                          .toLocal()
                                          .toString(),
                                    ),
                                  if (req.reviewedAtMs > 0)
                                    _kv(
                                      theme,
                                      cs,
                                      'Reviewed',
                                      DateTime.fromMillisecondsSinceEpoch(req.reviewedAtMs)
                                          .toLocal()
                                          .toString(),
                                    ),
                                  if (req.reviewedBy.isNotEmpty)
                                    _kv(theme, cs, 'Reviewed By', req.reviewedBy),
                                  if (req.note.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Admin note:',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.70),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      req.note,
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
                                        onPressed: req.masterLeagueId.isEmpty
                                            ? null
                                            : () => context.push('/master-leagues/${req.masterLeagueId}'),
                                        icon: const Icon(Icons.open_in_new_rounded),
                                        label: const Text('Open Master League'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: req.ownerId.isEmpty
                                            ? null
                                            : () async {
                                                await Clipboard.setData(
                                                  ClipboardData(text: req.ownerId),
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
                                      if (req.status == 'pending' || req.status == 'info_requested') ...[
                                        FilledButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewRequest(req: req, action: 'approve'),
                                          icon: const Icon(Icons.verified_rounded),
                                          label: Text(
                                            req.requestType.toLowerCase() == 'renewal'
                                                ? 'Approve Renewal'
                                                : 'Approve',
                                            style: const TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewRequest(req: req, action: 'info_requested'),
                                          icon: const Icon(Icons.help_outline_rounded),
                                          label: const Text(
                                            'Request Info',
                                            style: TextStyle(fontWeight: FontWeight.w900),
                                          ),
                                        ),
                                        FilledButton.tonalIcon(
                                          onPressed: _busy
                                              ? null
                                              : () => _reviewRequest(req: req, action: 'reject'),
                                          icon: const Icon(Icons.close_rounded),
                                          label: Text(
                                            req.requestType.toLowerCase() == 'renewal'
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

extension _EmptyDash on String {
  String ifEmptyDash() => trim().isEmpty ? '\u2014' : this;
}