import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/data/league_announcements_firebase.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_announcement.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';

class OrganizerProfileScreen extends ConsumerStatefulWidget {
  const OrganizerProfileScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  @override
  ConsumerState<OrganizerProfileScreen> createState() =>
      _OrganizerProfileScreenState();
}

class _OrganizerProfileScreenState
    extends ConsumerState<OrganizerProfileScreen> {
  bool _saving = false;
  bool _followBusy = false;
  String _hydratedForId = '';

  final LeagueAnnouncementsFirebase _announcements =
      LeagueAnnouncementsFirebase();

  final _bannerCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _badgeCtrl = TextEditingController();

  final _websiteCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _xCtrl = TextEditingController();
  final _discordCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _twitchCtrl = TextEditingController();
  final _tiktokCtrl = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  @override
  void dispose() {
    _bannerCtrl.dispose();
    _logoCtrl.dispose();
    _bioCtrl.dispose();
    _badgeCtrl.dispose();
    _websiteCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _xCtrl.dispose();
    _discordCtrl.dispose();
    _youtubeCtrl.dispose();
    _twitchCtrl.dispose();
    _tiktokCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final text = msg.trim();
    if (text.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Stream<MasterLeague?> _watchMasterLeague(String id) {
    return FirebaseFirestore.instance
        .collection('master_leagues')
        .doc(id.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      if (!snap.exists) return null;
      return MasterLeague.fromMap(
        snap.id,
        (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>(),
      );
    }).handleError((_) => null);
  }

  Stream<List<League>> _watchCompetitions(String masterId) {
    return FirebaseFirestore.instance
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterId.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true
            ? map['id']
            : d.id;
        return League.fromRemoteMap(map);
      }).toList(growable: false);

      final sorted = [...list];
      sorted.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return sorted;
    }).handleError((_) => <League>[]);
  }

  Stream<LeagueAnnouncement?> _watchPinnedWorkspaceAnnouncement(
      String masterLeagueId) {
    return _announcements.watchPinnedMasterLeagueAnnouncement(masterLeagueId);
  }

  void _loadControllersFrom(MasterLeague ml) {
    if (_hydratedForId == ml.id) return;
    _hydratedForId = ml.id;

    final op = ml.organizerProfile;

    _bannerCtrl.text = op.bannerUrl;
    _logoCtrl.text = op.logoUrl;
    _bioCtrl.text = op.bio;
    _badgeCtrl.text = op.badge;

    _websiteCtrl.text = op.socialLinks['website'] ?? '';
    _facebookCtrl.text = op.socialLinks['facebook'] ?? '';
    _instagramCtrl.text = op.socialLinks['instagram'] ?? '';
    _xCtrl.text = op.socialLinks['x'] ?? op.socialLinks['twitter'] ?? '';
    _discordCtrl.text = op.socialLinks['discord'] ?? '';
    _youtubeCtrl.text = op.socialLinks['youtube'] ?? '';
    _twitchCtrl.text = op.socialLinks['twitch'] ?? '';
    _tiktokCtrl.text = op.socialLinks['tiktok'] ?? '';
  }

  OrganizerProfile _profileFromControllers() {
    final socials = <String, String>{
      'website': _websiteCtrl.text.trim(),
      'facebook': _facebookCtrl.text.trim(),
      'instagram': _instagramCtrl.text.trim(),
      'x': _xCtrl.text.trim(),
      'discord': _discordCtrl.text.trim(),
      'youtube': _youtubeCtrl.text.trim(),
      'twitch': _twitchCtrl.text.trim(),
      'tiktok': _tiktokCtrl.text.trim(),
    }..removeWhere((k, v) => v.trim().isEmpty);

    return OrganizerProfile(
      bannerUrl: _bannerCtrl.text.trim(),
      logoUrl: _logoCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      socialLinks: socials,
      badge: _badgeCtrl.text.trim(),
    );
  }

  String? _validateProfile(OrganizerProfile p) {
    if (p.bannerUrl.length > 2000) return 'Banner URL is too long.';
    if (p.logoUrl.length > 2000) return 'Logo URL is too long.';
    if (p.bio.length > 2000) return 'Bio is too long.';
    if (p.badge.length > 80) return 'Badge is too long.';
    for (final e in p.socialLinks.entries) {
      if (e.key.length > 30) return 'Invalid social link key.';
      if (e.value.length > 2000) return 'A social link is too long.';
    }
    return null;
  }

  Future<void> _save(MasterLeague ml) async {
    if (_saving) return;

    if (!ml.isOwner(_uid)) {
      _snack(
        'Only the Master League owner can edit the organizer profile.',
        error: true,
      );
      return;
    }

    final profile = _profileFromControllers();
    final err = _validateProfile(profile);
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      await repo.updateOrganizerProfile(
        masterLeagueId: ml.id,
        profile: profile,
      );
      ref.invalidate(masterLeagueByIdProvider(widget.masterLeagueId));
      ref.invalidate(myMasterLeaguesProvider);
      _snack('Organizer profile updated');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleFollow(MasterLeague ml, bool isFollowing) async {
    if (_followBusy) return;
    if (_uid.isEmpty) {
      _snack('Please sign in to follow this organizer.', error: true);
      return;
    }
    if (ml.ownerId.trim() == _uid) {
      _snack('You cannot follow your own organizer workspace.', error: true);
      return;
    }

    setState(() => _followBusy = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      if (isFollowing) {
        await repo.unfollowWorkspace(ml.id);
        _snack('Unfollowed organizer workspace.');
      } else {
        await repo.followWorkspace(ml.id);
        _snack('Now following organizer workspace.');
      }
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _renewVerification(MasterLeague ml) async {
    if (_uid.isEmpty) {
      _snack('Please sign in to continue.', error: true);
      return;
    }
    if (ml.ownerId.trim() != _uid) {
      _snack('Only the owner can renew verification.', error: true);
      return;
    }
    if (!ml.canRenewVerification) {
      _snack('This organizer cannot renew verification right now.', error: true);
      return;
    }
    if (ml.isVerificationPending &&
        ml.verificationRequestType.trim().toLowerCase() == 'renewal') {
      _snack('A renewal request is already pending review.', error: true);
      return;
    }

    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Renew Verification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A paid renewal request will be submitted for re-review. Approval is required before expiry is extended.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Renewal note for admin (optional)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.18)),
                ),
                child: const Text(
                  'Renewals keep organizer trust current and require another review cycle.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Proceed to Payment'),
            ),
          ],
        );
      },
    );

    if (shouldContinue != true) {
      noteCtrl.dispose();
      return;
    }

    setState(() => _saving = true);
    try {
      final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final userId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      final payment = await paymentSvc.payForOrganizerVerificationRenewal(
        context: context,
        userId: userId,
        masterLeagueId: ml.id,
        masterLeagueName: ml.name,
      );

      if (!mounted) return;

      if (!payment.success) {
        _snack(
          payment.errorMessage ?? 'Verification renewal payment failed.',
          error: true,
        );
        return;
      }

      await repo.submitVerificationRenewalRequest(
        masterLeagueId: ml.id,
        attemptId: payment.attemptId,
        paymentId: payment.paymentId,
        receiptId: payment.receiptId ?? '',
        note: noteCtrl.text.trim(),
      );

      if (!mounted) return;
      _snack('Verification renewal request submitted for review.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      noteCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _imageBox({
    required String url,
    required double height,
    required BorderRadius radius,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (url.trim().isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: cs.onSurface.withOpacity(0.06),
          border: Border.all(color: cs.onSurface.withOpacity(0.10)),
        ),
        child: Center(
          child: Text(
            'No image',
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.60),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url.trim(),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: cs.error.withOpacity(0.06),
              border: Border.all(color: cs.error.withOpacity(0.18)),
            ),
            child: Center(
              child: Text(
                'Image failed to load',
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _metricRow({
    required ThemeData theme,
    required ColorScheme cs,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialEditor() {
    return Column(
      children: [
        TextField(
          controller: _websiteCtrl,
          decoration: const InputDecoration(
            labelText: 'Website link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _facebookCtrl,
          decoration: const InputDecoration(
            labelText: 'Facebook link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _instagramCtrl,
          decoration: const InputDecoration(
            labelText: 'Instagram link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _xCtrl,
          decoration: const InputDecoration(
            labelText: 'X / Twitter link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _discordCtrl,
          decoration: const InputDecoration(
            labelText: 'Discord link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _youtubeCtrl,
          decoration: const InputDecoration(
            labelText: 'YouTube link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _twitchCtrl,
          decoration: const InputDecoration(
            labelText: 'Twitch link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tiktokCtrl,
          decoration: const InputDecoration(
            labelText: 'TikTok link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
      ],
    );
  }

  Widget _pill({
    required String text,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessDenied() {
    return const Center(
      child: EmptyState(
        title: 'No access',
        message:
            'This page is visible only to the Master League owner, admins, and moderators.',
        icon: Icons.lock_outline_rounded,
      ),
    );
  }

  Widget _buildPinnedAnnouncementSection(
    MasterLeague ml,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return StreamBuilder<LeagueAnnouncement?>(
      stream: _watchPinnedWorkspaceAnnouncement(ml.id),
      builder: (context, snap) {
        final pinned = snap.data;
        if (pinned == null) return const SizedBox.shrink();

        return Glass(
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'Official Organizer Notice',
                padding: EdgeInsets.zero,
                trailing: Icon(Icons.push_pin_rounded, color: cs.primary),
              ),
              const SizedBox(height: 10),
              Text(
                pinned.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pinned.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.82),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metaChip(
                    cs,
                    icon: Icons.person_outline_rounded,
                    label: pinned.authorName.trim().isEmpty
                        ? 'Organizer'
                        : pinned.authorName.trim(),
                  ),
                  _metaChip(
                    cs,
                    icon: Icons.schedule_rounded,
                    label: pinned.pinnedAtMs > 0
                        ? DateTime.fromMillisecondsSinceEpoch(
                                pinned.pinnedAtMs)
                            .toLocal()
                            .toString()
                            .split('.')
                            .first
                        : 'Pinned',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metaChip(
    ColorScheme cs, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.06),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationStatusCard(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    Color statusColor;
    String statusTitle;
    String statusBody;

    if (ml.isVerifiedOrganizer) {
      statusColor = const Color(0xFF1D9BF0);
      statusTitle = 'Verified Organizer';
      statusBody =
          'This organizer has been manually reviewed and approved. This badge helps participants identify authentic organizers and avoid scams.';
    } else if (ml.isVerificationPending) {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = ml.lastVerificationWasRenewal
          ? 'Renewal Pending Review'
          : 'Verification Pending';
      statusBody = ml.lastVerificationWasRenewal
          ? 'A paid renewal request has been submitted and is waiting for admin review.'
          : 'A paid verification request has been submitted and is waiting for admin review.';
    } else if (ml.isVerificationRejected) {
      statusColor = cs.error;
      statusTitle = 'Verification Rejected';
      statusBody =
          'The verification request was reviewed and rejected. Please contact support or submit again later.';
    } else if (ml.verificationExpired) {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = 'Verification Expired';
      statusBody =
          'This organizer was previously verified, but the verification period has expired and should be renewed.';
    } else {
      statusColor = cs.onSurface.withOpacity(0.60);
      statusTitle = 'Not Verified';
      statusBody =
          'This organizer is not yet verified. Verified badges help participants identify trusted organizer identities.';
    }

    String expiryLabel = 'No expiry';
    if (ml.verificationExpiresAtMs > 0) {
      expiryLabel = DateTime.fromMillisecondsSinceEpoch(
        ml.verificationExpiresAtMs,
      ).toLocal().toString().split('.').first;
    }

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Trust & Verification',
            padding: EdgeInsets.zero,
            trailing: Icon(
              Icons.verified_user_outlined,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            statusTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.75),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _metricRow(
            theme: theme,
            cs: cs,
            label: 'Verification expires',
            value: expiryLabel,
          ),
          if (ml.verificationNote.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Review note: ${ml.verificationNote.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (ml.isOwner(_uid) && ml.canRenewVerification && !ml.isVerificationPending) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _renewVerification(ml),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Renew Verification',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _identityHero(
    MasterLeague ml,
    ThemeData theme,
    ColorScheme cs,
    String ownerName,
    bool isFollowing,
    int followersCount,
  ) {
    final trustColor = ml.isVerifiedOrganizer
        ? const Color(0xFF1D9BF0)
        : (ml.isVerificationPending
            ? const Color(0xFFF59E0B)
            : cs.onSurface.withOpacity(0.60));

    final trustLabel = ml.isVerifiedOrganizer
        ? 'Verified Organizer'
        : (ml.isVerificationPending
            ? (ml.lastVerificationWasRenewal
                ? 'Renewal Pending'
                : 'Verification Pending')
            : (ml.verificationExpired ? 'Expired' : 'Unverified'));

    final canFollow = _uid.isNotEmpty && ml.ownerId.trim() != _uid;

    return Glass(
      borderRadius: 30,
      padding: const EdgeInsets.all(18),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(0.20),
              cs.secondary.withOpacity(0.08),
              cs.onSurface.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ml.organizerProfile.bannerUrl.trim().isNotEmpty) ...[
                _imageBox(
                  url: ml.organizerProfile.bannerUrl.trim(),
                  height: 150,
                  radius: BorderRadius.circular(22),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: cs.primary.withOpacity(0.14),
                    backgroundImage: ml.organizerProfile.logoUrl.trim().isNotEmpty
                        ? NetworkImage(ml.organizerProfile.logoUrl.trim())
                        : null,
                    child: ml.organizerProfile.logoUrl.trim().isEmpty
                        ? Icon(Icons.hub_rounded, color: cs.primary, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              ml.name.trim().isEmpty ? 'Organizer' : ml.name.trim(),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                color: cs.onSurface,
                              ),
                            ),
                            _pill(
                              text: trustLabel,
                              color: trustColor,
                              icon: ml.isVerifiedOrganizer
                                  ? Icons.verified_rounded
                                  : (ml.isVerificationPending
                                      ? Icons.hourglass_top_rounded
                                      : Icons.shield_outlined),
                            ),
                            _pill(
                              text: ml.plan.displayName,
                              color: cs.primary,
                            ),
                            if (ml.organizerProfile.badge.trim().isNotEmpty)
                              _pill(
                                text: ml.organizerProfile.badge.trim(),
                                color: const Color(0xFFF59E0B),
                              ),
                            _pill(
                              text: '$followersCount follower${followersCount == 1 ? '' : 's'}',
                              color: const Color(0xFF22C55E),
                              icon: Icons.favorite_border_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ownerName.isNotEmpty
                              ? 'Managed by $ownerName'
                              : 'Managed by ${ml.ownerId}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.72),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ml.organizerProfile.bio.trim().isEmpty
                              ? 'No organizer bio yet.'
                              : ml.organizerProfile.bio.trim(),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.82),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (canFollow) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _followBusy
                            ? null
                            : () => _toggleFollow(ml, isFollowing),
                        icon: _followBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isFollowing
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                              ),
                        label: Text(
                          isFollowing ? 'Following' : 'Follow Organizer',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _trustMetrics(MasterLeague ml, ThemeData theme, ColorScheme cs, int followersCount) {
    final cards = [
      _TrustMetric(
        icon: Icons.verified_user_outlined,
        label: 'Trust Status',
        value: ml.isVerifiedOrganizer
            ? 'Verified'
            : (ml.isVerificationPending ? 'Pending' : (ml.verificationExpired ? 'Expired' : 'Unverified')),
        tint: ml.isVerifiedOrganizer
            ? const Color(0xFF1D9BF0)
            : (ml.isVerificationPending
                ? const Color(0xFFF59E0B)
                : cs.onSurface.withOpacity(0.60)),
      ),
      _TrustMetric(
        icon: Icons.emoji_events_outlined,
        label: 'Competitions Hosted',
        value: '${ml.analytics.totalTournamentsCreated}',
        tint: cs.primary,
      ),
      _TrustMetric(
        icon: Icons.groups_rounded,
        label: 'Teams Hosted',
        value: '${ml.analytics.totalParticipantsTeams}',
        tint: const Color(0xFF22C55E),
      ),
      _TrustMetric(
        icon: Icons.sports_score_rounded,
        label: 'Matches Managed',
        value: '${ml.analytics.totalMatches}',
        tint: const Color(0xFF8B5CF6),
      ),
      _TrustMetric(
        icon: Icons.favorite_border_rounded,
        label: 'Followers',
        value: '$followersCount',
        tint: const Color(0xFFEF4444),
      ),
      _TrustMetric(
        icon: Icons.security_rounded,
        label: 'Workspace Identity',
        value: ml.plan.displayName,
        tint: const Color(0xFF14B8A6),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount: cards.length,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final item = cards[index];
        return Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.tint.withOpacity(0.12),
                  border: Border.all(color: item.tint.withOpacity(0.24)),
                ),
                child: Icon(item.icon, color: item.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.62),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _socialLinksSection(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    final links = ml.organizerProfile.socialLinks;

    Widget socialTile(String key, String value) {
      return Glass(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.link_rounded, color: cs.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.62),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Official Links',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.public_rounded, color: cs.primary),
          ),
          const SizedBox(height: 10),
          if (links.isEmpty)
            Text(
              'No official links published yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...links.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: socialTile(e.key, e.value),
                )),
          if (ml.isOwner(_uid)) ...[
            const SizedBox(height: 12),
            _socialEditor(),
          ],
        ],
      ),
    );
  }

  Widget _aboutSection(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'About Organizer',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.subject_outlined, color: cs.primary),
          ),
          const SizedBox(height: 10),
          Text(
            ml.organizerProfile.bio.trim().isEmpty
                ? 'No bio yet.'
                : ml.organizerProfile.bio.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.82),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (ml.isOwner(_uid)) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _bioCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Organizer bio',
                prefixIcon: Icon(Icons.subject_outlined),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _appearanceSection(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Brand Appearance',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.palette_outlined, color: cs.primary),
          ),
          const SizedBox(height: 10),
          if (!ml.isOwner(_uid))
            Text(
              'Only the owner can edit banner, logo, and badge.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            TextField(
              controller: _badgeCtrl,
              decoration: const InputDecoration(
                labelText: 'Organizer badge (optional)',
                prefixIcon: Icon(Icons.verified_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bannerCtrl,
              decoration: const InputDecoration(
                labelText: 'Banner image URL (optional)',
                prefixIcon: Icon(Icons.image_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _logoCtrl,
              decoration: const InputDecoration(
                labelText: 'Logo image URL (optional)',
                prefixIcon: Icon(Icons.image_outlined),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _competitionHistory(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Competition History',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.history_rounded, color: cs.primary),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<League>>(
            stream: _watchCompetitions(ml.id),
            builder: (context, leaguesSnap) {
              final leagues = leaguesSnap.data ?? const <League>[];
              if (leaguesSnap.connectionState == ConnectionState.waiting &&
                  leagues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (leagues.isEmpty) {
                return Text(
                  'No competitions yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }

              return Column(
                children: leagues.take(20).map((l) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => context.push('/leagues/${l.id}'),
                      borderRadius: BorderRadius.circular(18),
                      child: Glass(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              color: cs.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              l.format.displayName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.65),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _ownerActions(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    if (!ml.isOwner(_uid)) return const SizedBox.shrink();

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Owner Actions',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.settings_suggest_outlined, color: cs.primary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(ml),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text(
                    'Save Profile',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/master-leagues/${ml.id}'),
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text(
                    'Back to Workspace',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<MasterLeague?>(
      stream: _watchMasterLeague(widget.masterLeagueId),
      builder: (context, snap) {
        final ml = snap.data;

        if (snap.connectionState == ConnectionState.waiting && ml == null) {
          return const GlassScaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (ml == null) {
          return GlassScaffold(
            appBar: AppBar(
              title: const Text('Organizer Trust Page'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: const Center(
              child: EmptyState(
                title: 'Not found',
                message: 'This Master League may have been deleted.',
                icon: Icons.badge_outlined,
              ),
            ),
          );
        }

        if (!ml.canSeeOrganizerProfile(_uid)) {
          return GlassScaffold(
            appBar: AppBar(
              title: const Text('Organizer Trust Page'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: _accessDenied(),
          );
        }

        _loadControllersFrom(ml);

        final followAsync = ref.watch(masterLeagueFollowStateProvider(ml.id));
        final followersCountAsync =
            ref.watch(masterLeagueFollowersCountProvider(ml.id));

        return FutureBuilder<UserProfile?>(
          future: UserProfileRepository().fetchByUserId(ml.ownerId),
          builder: (context, ownerSnap) {
            final ownerName = ownerSnap.data?.teamName.trim() ?? '';
            final isFollowing = followAsync.valueOrNull ?? false;
            final followersCount = followersCountAsync.valueOrNull ?? 0;

            return GlassScaffold(
              appBar: AppBar(
                title: const Text('Organizer Trust Page'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  if (ml.isOwner(_uid))
                    TextButton(
                      onPressed: _saving ? null : () => _save(ml),
                      child: Text(
                        _saving ? 'Saving...' : 'Save',
                        style: TextStyle(
                          color: _saving
                              ? cs.onSurface.withOpacity(0.55)
                              : cs.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: ListView(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
                      children: [
                        _identityHero(
                          ml,
                          theme,
                          cs,
                          ownerName,
                          isFollowing,
                          followersCount,
                        ),
                        const SizedBox(height: 16),
                        _buildPinnedAnnouncementSection(ml, theme, cs),
                        const SizedBox(height: 16),
                        _trustMetrics(ml, theme, cs, followersCount),
                        const SizedBox(height: 16),
                        _verificationStatusCard(ml, theme, cs),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _aboutSection(ml, theme, cs),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: _appearanceSection(ml, theme, cs),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _socialLinksSection(ml, theme, cs),
                        const SizedBox(height: 16),
                        _competitionHistory(ml, theme, cs),
                        const SizedBox(height: 16),
                        _ownerActions(ml, theme, cs),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TrustMetric {
  const _TrustMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;
}
