import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../features/auth/data/user_profile_repository.dart';
import '../../../features/auth/models/user_profile.dart';
import '../../../features/leagues/data/league_announcements_firebase.dart';
import '../../../features/leagues/models/league.dart';
import '../../../features/leagues/models/league_announcement.dart';
import '../../../features/master_leagues/data/organizer_feed_firebase.dart';
import '../../../features/master_leagues/domain/master_league.dart';
import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../../features/master_leagues/domain/organizer_feed_event.dart';
import '../../../features/master_leagues/logic/master_leagues_providers.dart';

class WebOrganizerProfileScreen extends ConsumerStatefulWidget {
  const WebOrganizerProfileScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  @override
  ConsumerState<WebOrganizerProfileScreen> createState() =>
      _WebOrganizerProfileScreenState();
}

class _WebOrganizerProfileScreenState
    extends ConsumerState<WebOrganizerProfileScreen> {
  static const int _maxBytes = 5 * 1024 * 1024;

  bool _saving = false;
  bool _followBusy = false;
  bool _uploadingBanner = false;
  bool _uploadingLogo = false;
  String _hydratedForId = '';

  final LeagueAnnouncementsFirebase _announcements =
      LeagueAnnouncementsFirebase();
  final OrganizerFeedFirebase _organizerFeed = OrganizerFeedFirebase();

  final _bannerCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _badgeCtrl = TextEditingController();

  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _xCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _tiktokCtrl = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  @override
  void dispose() {
    _bannerCtrl.dispose();
    _logoCtrl.dispose();
    _bioCtrl.dispose();
    _badgeCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _xCtrl.dispose();
    _youtubeCtrl.dispose();
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

  String _cloudinaryOptimizedUrl(
    String url, {
    int? width,
    int? height,
    String crop = 'fill',
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final isCloudinary =
        u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;
    const marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = <String>[
      'f_auto',
      'q_auto',
      if (width != null && width > 0) 'w_$width',
      if (height != null && height > 0) 'h_$height',
      (crop == 'fit') ? 'c_fit' : 'c_fill',
      if (crop != 'fit') 'g_auto',
    ].join(',');

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly =
        first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  Future<String> _uploadToCloudinary({
    required PlatformFile picked,
    required String folder,
    required String publicPrefix,
  }) async {
    final cloudName =
        const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
    final uploadPreset =
        const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET')
            .trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }

    final uploadUrl =
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;
    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart =
          http.MultipartFile.fromBytes('file', bytes, filename: picked.name);
    } else if (path.isNotEmpty) {
      filePart = await http.MultipartFile.fromPath(
        'file',
        path,
        filename: picked.name,
      );
    } else {
      throw StateError('Selected image is not accessible.');
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = uploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = folder
      ..fields['public_id'] = '${publicPrefix}_$ts'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>)
              ? (err['message']?.toString() ?? '')
              : '';
          if (msg.trim().isNotEmpty) message = 'Upload failed: ${msg.trim()}';
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Upload failed: invalid response.');
      }

      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      if (secureUrl.isEmpty) {
        throw StateError('Upload failed: secure_url missing.');
      }

      return secureUrl;
    } on TimeoutException {
      throw StateError('Upload timed out. Please try again.');
    } finally {
      client.close();
    }
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
    String masterLeagueId,
  ) {
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
    _facebookCtrl.text = op.socialLinks['facebook'] ?? '';
    _instagramCtrl.text = op.socialLinks['instagram'] ?? '';
    _xCtrl.text = op.socialLinks['x'] ?? op.socialLinks['twitter'] ?? '';
    _youtubeCtrl.text = op.socialLinks['youtube'] ?? '';
    _tiktokCtrl.text = op.socialLinks['tiktok'] ?? '';
  }

  OrganizerProfile _profileFromControllers() {
    final socials = <String, String>{
      'facebook': _facebookCtrl.text.trim(),
      'instagram': _instagramCtrl.text.trim(),
      'x': _xCtrl.text.trim(),
      'youtube': _youtubeCtrl.text.trim(),
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

  Future<void> _pickAndUploadOrganizerImage(
    MasterLeague ml, {
    required bool banner,
  }) async {
    if (!ml.isOwner(_uid)) {
      _snack('Only the owner can update organizer images.', error: true);
      return;
    }
    if (banner ? _uploadingBanner : _uploadingLogo) return;

    setState(() {
      if (banner) {
        _uploadingBanner = true;
      } else {
        _uploadingLogo = true;
      }
    });

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 6));

      final pickResult = await SafeImagePicker.pickImage();
      if (pickResult.wasCancelled) return;

      if (!pickResult.isSuccess) {
        _snack(pickResult.errorMessage ?? 'Could not pick image.', error: true);
        return;
      }

      final picked = pickResult.file!;
      if (picked.size > _maxBytes) {
        _snack(
          'Image too large. Please select an image under 5 MB.',
          error: true,
        );
        return;
      }

      final secureUrl = await _uploadToCloudinary(
        picked: picked,
        folder: 'eleaguehub/organizers',
        publicPrefix: banner
            ? 'organizer_banner_${ml.id}'
            : 'organizer_logo_${ml.id}',
      );

      if (banner) {
        _bannerCtrl.text = secureUrl;
      } else {
        _logoCtrl.text = secureUrl;
      }

      await _save(ml);
      await _postProfileUpdateFeedEvent(ml);
    } catch (e) {
      _snack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
        error: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        if (banner) {
          _uploadingBanner = false;
        } else {
          _uploadingLogo = false;
        }
      });
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
        final brightness = Theme.of(ctx).brightness;
        return AlertDialog(
          backgroundColor: AppTheme.cardColor(brightness),
          surfaceTintColor: Colors.transparent,
          title: const Text('Renew Verification'),
          content: SizedBox(
            width: 520,
            child: Column(
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
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

  Future<void> _startInitialVerification(MasterLeague ml) async {
    if (_uid.isEmpty) {
      _snack('Please sign in to continue.', error: true);
      return;
    }
    if (ml.ownerId.trim() != _uid) {
      _snack('Only the owner can request verification.', error: true);
      return;
    }
    if (ml.isVerifiedOrganizer) {
      _snack('This organizer is already verified.', error: true);
      return;
    }
    if (ml.isVerificationPending) {
      _snack('A verification request is already pending review.', error: true);
      return;
    }

    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final brightness = Theme.of(ctx).brightness;
        return AlertDialog(
          backgroundColor: AppTheme.cardColor(brightness),
          surfaceTintColor: Colors.transparent,
          title: const Text('Get Verified'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'A paid verification request will be submitted for manual review. Approval is required before the verified badge appears.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note for admin (optional)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
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

      final payment = await paymentSvc.payForOrganizerVerification(
        context: context,
        userId: userId,
        masterLeagueId: ml.id,
        masterLeagueName: ml.name,
      );

      if (!mounted) return;

      if (!payment.success) {
        _snack(
          payment.errorMessage ?? 'Verification payment failed.',
          error: true,
        );
        return;
      }

      await repo.submitVerificationRequest(
        masterLeagueId: ml.id,
        attemptId: payment.attemptId,
        paymentId: payment.paymentId,
        receiptId: payment.receiptId ?? '',
        note: noteCtrl.text.trim(),
      );

      if (!mounted) return;
      _snack('Verification request submitted for review.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      noteCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _postProfileUpdateFeedEvent(MasterLeague ml) async {
    try {
      final profile = await UserProfileRepository().fetchByUserId(_uid);
      final actorName = (profile?.displayName.trim().isNotEmpty == true)
          ? profile!.displayName.trim()
          : 'Organizer';

      await _organizerFeed.addEvent(
        OrganizerFeedEvent(
          id: '',
          masterLeagueId: ml.id,
          type: 'announcement',
          title: 'Organizer profile updated',
          message:
              'Brand profile, links, or organizer identity details were updated.',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          actorId: _uid,
          actorName: actorName,
          leagueId: '',
        ),
      );
    } catch (_) {}
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
      ),
      child: child,
    );
  }

  Widget _softPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(
    String title, {
    IconData? icon,
    Widget? trailing,
  }) {
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppTheme.limeAccentDark, size: 20),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _accessDenied() {
    return const Center(
      child: EmptyState(
        title: 'Sign in required',
        message: 'Please sign in to view organizer profiles.',
        icon: Icons.lock_outline_rounded,
      ),
    );
  }

  Widget _logoFallback(Brightness brightness) {
    return Container(
      color: AppTheme.iconCircleBackground(brightness),
      child: Center(
        child: Icon(
          Icons.hub_rounded,
          color: AppTheme.limeAccentDark,
          size: 42,
        ),
      ),
    );
  }

  Widget _buildHero(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
    String ownerName,
    bool isFollowing,
    int followersCount,
  ) {
    final planColor = ml.plan == MasterLeaguePlan.elite
        ? const Color(0xFF8B5CF6)
        : (ml.plan == MasterLeaguePlan.pro
            ? const Color(0xFF22C55E)
            : AppTheme.limeAccentDark);

    final canFollow = _uid.isNotEmpty && ml.ownerId.trim() != _uid;
    final ownerCanEdit = ml.isOwner(_uid);
    final bannerUrl = ml.organizerProfile.bannerUrl.trim();
    final logoUrl = ml.organizerProfile.logoUrl.trim();

    return _panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: ownerCanEdit
                    ? () => _pickAndUploadOrganizerImage(ml, banner: true)
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      Container(
                        height: 260,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.searchBackground(brightness),
                        ),
                        child: bannerUrl.isEmpty
                            ? Center(
                                child: Icon(
                                  Icons.photo_size_select_actual_outlined,
                                  size: 48,
                                  color: AppTheme.secondaryText(brightness),
                                ),
                              )
                            : Image.network(
                                _cloudinaryOptimizedUrl(
                                  bannerUrl,
                                  width: 1400,
                                  height: 620,
                                  crop: 'fill',
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    'Banner unavailable',
                                    style: TextStyle(
                                      color: AppTheme.secondaryText(brightness),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (_uploadingBanner)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.20),
                            child: const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 22,
                bottom: -46,
                child: Stack(
                  children: [
                    InkWell(
                      onTap: ownerCanEdit
                          ? () => _pickAndUploadOrganizerImage(
                                ml,
                                banner: false,
                              )
                          : null,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 98,
                        height: 98,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.scaffoldBackgroundColor,
                        ),
                        child: ClipOval(
                          child: logoUrl.isNotEmpty
                              ? Image.network(
                                  _cloudinaryOptimizedUrl(
                                    logoUrl,
                                    width: 320,
                                    height: 320,
                                    crop: 'fill',
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _logoFallback(brightness),
                                )
                              : _logoFallback(brightness),
                        ),
                      ),
                    ),
                    if (_uploadingLogo)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.22),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 58),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Text(
                          ml.name.trim().isEmpty ? 'Organizer' : ml.name.trim(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        if (ml.isVerifiedOrganizer)
                          const Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF1D9BF0),
                            size: 22,
                          )
                        else if (ml.isVerificationPending)
                          const Icon(
                            Icons.verified_outlined,
                            color: Color(0xFFF59E0B),
                            size: 22,
                          ),
                        _metaPill(
                          text: 'Plan: ${ml.plan.displayName}',
                          color: planColor,
                          icon: Icons.workspace_premium_rounded,
                        ),
                        if (ml.organizerProfile.badge.trim().isNotEmpty)
                          _metaPill(
                            text: ml.organizerProfile.badge.trim(),
                            color: const Color(0xFFF59E0B),
                          ),
                        _metaPill(
                          text: '$followersCount follower${followersCount == 1 ? '' : 's'}',
                          color: const Color(0xFF22C55E),
                          icon: Icons.favorite_border_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ownerName.isNotEmpty
                          ? 'Managed by $ownerName'
                          : 'Managed by Organizer',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ml.organizerProfile.bio.trim().isEmpty
                          ? 'No organizer bio yet.'
                          : ml.organizerProfile.bio.trim(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (canFollow) ...[
                const SizedBox(width: 18),
                SizedBox(
                  width: 220,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed:
                        _followBusy ? null : () => _toggleFollow(ml, isFollowing),
                    icon: _followBusy
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.darkText,
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaPill({
    required String text,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedAnnouncementSection(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
  ) {
    return StreamBuilder<LeagueAnnouncement?>(
      stream: _watchPinnedWorkspaceAnnouncement(ml.id),
      builder: (context, snap) {
        final pinned = snap.data;
        if (pinned == null) return const SizedBox.shrink();

        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                'Official Organizer Notice',
                icon: Icons.push_pin_rounded,
              ),
              const SizedBox(height: 12),
              Text(
                pinned.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pinned.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metaPill(
                    text: pinned.authorName.trim().isEmpty
                        ? 'Organizer'
                        : pinned.authorName.trim(),
                    color: AppTheme.limeAccentDark,
                    icon: Icons.person_outline_rounded,
                  ),
                  _metaPill(
                    text: pinned.pinnedAtMs > 0
                        ? DateTime.fromMillisecondsSinceEpoch(
                                pinned.pinnedAtMs,
                              )
                            .toLocal()
                            .toString()
                            .split('.')
                            .first
                        : 'Pinned',
                    color: const Color(0xFF8B5CF6),
                    icon: Icons.schedule_rounded,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tint,
  }) {
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);
    return _softPanel(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withOpacity(0.12),
            ),
            child: Icon(icon, color: tint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondaryText(brightness),
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

  Widget _trustMetrics(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
    int followersCount,
  ) {
    final cards = [
      _TrustMetric(
        icon: Icons.workspace_premium_rounded,
        label: 'Organizer Plan',
        value: ml.plan.displayName,
        tint: ml.plan == MasterLeaguePlan.elite
            ? const Color(0xFF8B5CF6)
            : (ml.plan == MasterLeaguePlan.pro
                ? const Color(0xFF22C55E)
                : AppTheme.limeAccentDark),
      ),
      _TrustMetric(
        icon: Icons.verified_user_outlined,
        label: 'Trust Status',
        value: ml.isVerifiedOrganizer
            ? 'Verified'
            : (ml.isVerificationPending
                ? 'Pending'
                : (ml.verificationExpired ? 'Expired' : 'Unverified')),
        tint: ml.isVerifiedOrganizer
            ? const Color(0xFF1D9BF0)
            : (ml.isVerificationPending
                ? const Color(0xFFF59E0B)
                : AppTheme.secondaryText(brightness)),
      ),
      _TrustMetric(
        icon: Icons.emoji_events_outlined,
        label: 'Competitions Hosted',
        value: '${ml.analytics.totalTournamentsCreated}',
        tint: AppTheme.limeAccentDark,
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
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount: cards.length,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final item = cards[index];
        return _metricCard(
          icon: item.icon,
          label: item.label,
          value: item.value,
          tint: item.tint,
        );
      },
    );
  }

  Widget _verificationStatusCard(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
  ) {
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
      statusColor = Theme.of(context).colorScheme.error;
      statusTitle = 'Verification Rejected';
      statusBody =
          'The verification request was reviewed and rejected. Please contact support or submit again later.';
    } else if (ml.verificationExpired) {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = 'Verification Expired';
      statusBody =
          'This organizer was previously verified, but the verification period has expired and should be renewed.';
    } else {
      statusColor = AppTheme.secondaryText(brightness);
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

    final ownerCanStartInitial = ml.isOwner(_uid) &&
        !ml.isVerifiedOrganizer &&
        !ml.isVerificationPending &&
        !ml.verificationExpired;

    final ownerCanRenew =
        ml.isOwner(_uid) && ml.canRenewVerification && !ml.isVerificationPending;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Trust & Verification',
            icon: Icons.verified_user_outlined,
          ),
          const SizedBox(height: 14),
          Text(
            statusTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _detailRow(
            label: 'Verification expires',
            value: expiryLabel,
          ),
          if (ml.verificationNote.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Review note: ${ml.verificationNote.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (ownerCanStartInitial || ownerCanRenew) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 280,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                ),
                onPressed: ownerCanStartInitial
                    ? () => _startInitialVerification(ml)
                    : () => _renewVerification(ml),
                icon: Icon(
                  ownerCanStartInitial
                      ? Icons.verified_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(
                  ownerCanStartInitial
                      ? 'Get Verified'
                      : 'Renew Verification',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Verification purchase is separate from your organizer plan. Plan controls capacity; verification adds trust review.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow({
    required String label,
    required String value,
  }) {
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _socialEditor() {
    return Column(
      children: [
        TextField(
          controller: _facebookCtrl,
          decoration: const InputDecoration(
            labelText: 'Facebook link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instagramCtrl,
          decoration: const InputDecoration(
            labelText: 'Instagram link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _xCtrl,
          decoration: const InputDecoration(
            labelText: 'X / Twitter link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _youtubeCtrl,
          decoration: const InputDecoration(
            labelText: 'YouTube link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
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

  Widget _socialLinksSection(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
  ) {
    final links = ml.organizerProfile.socialLinks;

    Widget socialTile(String key, String value) {
      return _softPanel(
        child: Row(
          children: [
            Icon(Icons.link_rounded, color: AppTheme.limeAccentDark, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.primaryText(brightness),
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

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Official Links', icon: Icons.public_rounded),
          const SizedBox(height: 14),
          if (links.isEmpty)
            Text(
              'No official links published yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...links.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: socialTile(e.key, e.value),
              ),
            ),
          if (ml.isOwner(_uid)) ...[
            const SizedBox(height: 16),
            _socialEditor(),
          ],
        ],
      ),
    );
  }

  Widget _aboutSection(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
  ) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('About Organizer', icon: Icons.subject_outlined),
          const SizedBox(height: 14),
          Text(
            ml.organizerProfile.bio.trim().isEmpty
                ? 'No bio yet.'
                : ml.organizerProfile.bio.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (ml.isOwner(_uid)) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _bioCtrl,
              maxLines: 6,
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

  Widget _competitionHistory(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
  ) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Competition History', icon: Icons.history_rounded),
          const SizedBox(height: 14),
          StreamBuilder<List<League>>(
            stream: _watchCompetitions(ml.id),
            builder: (context, leaguesSnap) {
              final leagues = leaguesSnap.data ?? const <League>[];
              if (leaguesSnap.connectionState == ConnectionState.waiting &&
                  leagues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (leagues.isEmpty) {
                return Text(
                  'No competitions yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondaryText(brightness),
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
                      child: _softPanel(
                        child: Row(
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              color: AppTheme.limeAccentDark,
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
                                  color: AppTheme.primaryText(brightness),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l.format.displayName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondaryText(brightness),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppTheme.secondaryText(brightness),
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

  Widget _ownerActions(
    MasterLeague ml,
    ThemeData theme,
    Brightness brightness,
  ) {
    if (!ml.isOwner(_uid)) return const SizedBox.shrink();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Owner Actions', icon: Icons.settings_suggest_outlined),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                  ),
                  onPressed: _saving
                      ? null
                      : () async {
                          await _save(ml);
                          await _postProfileUpdateFeedEvent(ml);
                        },
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.darkText,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text(
                    'Save Profile',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
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

  String _ownerDisplayName(UserProfile? ownerProfile) {
    if (ownerProfile != null && ownerProfile.displayName.trim().isNotEmpty) {
      return ownerProfile.displayName.trim();
    }
    return 'Organizer';
  }

  Widget _shell({
    required Widget child,
    required String title,
    List<Widget>? actions,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 72,
              margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: AppTheme.cardColor(brightness),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.cardBorder(brightness)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.pop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.searchBackground(brightness),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.searchOutline(brightness),
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                        letterSpacing: -0.35,
                      ),
                    ),
                  ),
                  ...?actions,
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return StreamBuilder<MasterLeague?>(
      stream: _watchMasterLeague(widget.masterLeagueId),
      builder: (context, snap) {
        final ml = snap.data;

        if (snap.connectionState == ConnectionState.waiting && ml == null) {
          return _shell(
            title: 'Organizer Trust Page',
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (ml == null) {
          return _shell(
            title: 'Organizer Trust Page',
            child: const Center(
              child: EmptyState(
                title: 'Not found',
                message: 'This Master League may have been deleted.',
                icon: Icons.badge_outlined,
              ),
            ),
          );
        }

        if (_uid.isEmpty) {
          return _shell(
            title: 'Organizer Trust Page',
            child: _accessDenied(),
          );
        }

        _loadControllersFrom(ml);

        final followAsync = ref.watch(masterLeagueFollowStateProvider(ml.id));
        final followersCountAsync =
            ref.watch(masterLeagueFollowersCountProvider(ml.id));

        return FutureBuilder<UserProfile?>(
          future: UserProfileRepository().fetchByUserId(ml.ownerId),
          builder: (context, ownerSnap) {
            final ownerProfile = ownerSnap.data;
            final ownerName = _ownerDisplayName(ownerProfile);
            final isFollowing = followAsync.valueOrNull ?? false;
            final followersCount = followersCountAsync.valueOrNull ?? 0;

            return _shell(
              title: 'Organizer Trust Page',
              actions: [
                if (ml.isOwner(_uid))
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed: _saving
                        ? null
                        : () async {
                            await _save(ml);
                            await _postProfileUpdateFeedEvent(ml);
                          },
                    child: Text(
                      _saving ? 'Saving...' : 'Save',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1360),
                    child: Column(
                      children: [
                        _buildHero(
                          ml,
                          theme,
                          brightness,
                          ownerName,
                          isFollowing,
                          followersCount,
                        ),
                        const SizedBox(height: 16),
                        _buildPinnedAnnouncementSection(ml, theme, brightness),
                        const SizedBox(height: 16),
                        _trustMetrics(ml, theme, brightness, followersCount),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Column(
                                children: [
                                  _verificationStatusCard(ml, theme, brightness),
                                  const SizedBox(height: 16),
                                  _aboutSection(ml, theme, brightness),
                                  const SizedBox(height: 16),
                                  _competitionHistory(ml, theme, brightness),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  _socialLinksSection(ml, theme, brightness),
                                  const SizedBox(height: 16),
                                  _ownerActions(ml, theme, brightness),
                                ],
                              ),
                            ),
                          ],
                        ),
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
