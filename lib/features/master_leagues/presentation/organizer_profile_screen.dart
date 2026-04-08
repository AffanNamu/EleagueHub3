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
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/data/league_announcements_firebase.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_announcement.dart';
import '../data/organizer_feed_firebase.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import '../domain/organizer_feed_event.dart';
import '../logic/master_leagues_providers.dart';

// ---------------------------------------------------------------------------
// Breakpoints — self-contained
// ---------------------------------------------------------------------------

class _BP {
  static const double tablet  = 760;
  static const double desktop = 900;
  static const double wide    = 1200;
}

// ---------------------------------------------------------------------------
// OrganizerProfileScreen
// ---------------------------------------------------------------------------

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
  static const int _maxBytes = 5 * 1024 * 1024;

  bool    _saving          = false;
  bool    _followBusy      = false;
  bool    _uploadingBanner = false;
  bool    _uploadingLogo   = false;
  String  _hydratedForId   = '';

  // Cached owner profile future — prevents repeated fetches on every
  // master league stream emission that would otherwise call
  // UserProfileRepository().fetchByUserId() on each rebuild.
  Future<UserProfile?>? _ownerProfileFuture;
  String                _ownerProfileCachedForId = '';

  final LeagueAnnouncementsFirebase _announcements =
      LeagueAnnouncementsFirebase();
  final OrganizerFeedFirebase _organizerFeed =
      OrganizerFeedFirebase();

  final _bannerCtrl   = TextEditingController();
  final _logoCtrl     = TextEditingController();
  final _bioCtrl      = TextEditingController();
  final _badgeCtrl    = TextEditingController();

  final _facebookCtrl  = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _xCtrl         = TextEditingController();
  final _youtubeCtrl   = TextEditingController();
  final _tiktokCtrl    = TextEditingController();

  // ── identity ───────────────────────────────────────────────────────────────

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  // ── lifecycle ──────────────────────────────────────────────────────────────

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

  // ── safe navigation ────────────────────────────────────────────────────────
  // This screen is pushed via Navigator.push(MaterialPageRoute(...)) from
  // master_league_details_screen.dart. On mobile that means Navigator.pop
  // is the correct back action.
  // The smart pop tries Navigator first, then falls back to GoRouter.

  void _safePush(String location) {
    try {
      GoRouter.of(context).push(location);
    } catch (e) {
      debugPrint('[OrganizerProfile] push($location) failed: $e');
    }
  }

  void _smartPop() {
    final nav = Navigator.of(context, rootNavigator: false);
    if (nav.canPop()) {
      nav.pop();
    } else {
      try {
        if (GoRouter.of(context).canPop()) {
          GoRouter.of(context).pop();
        } else {
          GoRouter.of(context).go('/');
        }
      } catch (_) {
        GoRouter.of(context).go('/');
      }
    }
  }

  // ── snack ──────────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final text = msg.trim();
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior:        SnackBarBehavior.floating,
        content:         Text(text),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
  }

  // ── owner profile cache ────────────────────────────────────────────────────

  Future<UserProfile?> _getOwnerProfile(String ownerId) {
    if (_ownerProfileCachedForId == ownerId &&
        _ownerProfileFuture != null) {
      return _ownerProfileFuture!;
    }
    _ownerProfileCachedForId = ownerId;
    _ownerProfileFuture =
        UserProfileRepository().fetchByUserId(ownerId);
    return _ownerProfileFuture!;
  }

  String _ownerDisplayName(UserProfile? ownerProfile) {
    if (ownerProfile != null &&
        ownerProfile.displayName.trim().isNotEmpty) {
      return ownerProfile.displayName.trim();
    }
    return 'Organizer';
  }

  // ── Cloudinary ─────────────────────────────────────────────────────────────

  String _cloudinaryOptimizedUrl(
    String url, {
    int?   width,
    int?   height,
    String crop = 'fill',
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final isCloudinary = u.contains('res.cloudinary.com') &&
        u.contains('/image/upload/');
    if (!isCloudinary) return u;
    final marker = '/image/upload/';
    final idx    = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = <String>[
      'f_auto',
      'q_auto',
      if (width  != null && width  > 0) 'w_$width',
      if (height != null && height > 0) 'h_$height',
      (crop == 'fit') ? 'c_fit' : 'c_fill',
      if (crop != 'fit') 'g_auto',
    ].join(',');

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly = first.startsWith('v') &&
        int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') ||
          first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  Future<String> _uploadToCloudinary({
    required PlatformFile picked,
    required String       folder,
    required String       publicPrefix,
  }) async {
    final cloudName = const String.fromEnvironment(
            'CLOUDINARY_CLOUD_NAME')
        .trim();
    final uploadPreset = const String.fromEnvironment(
            'CLOUDINARY_UNSIGNED_UPLOAD_PRESET')
        .trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }

    final uploadUrl = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );
    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;
    final bytes = picked.bytes;
    final path  = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart = http.MultipartFile.fromBytes(
        'file', bytes,
        filename: picked.name,
      );
    } else if (path.isNotEmpty) {
      filePart = await http.MultipartFile.fromPath(
        'file', path,
        filename: picked.name,
      );
    } else {
      throw StateError('Selected image is not accessible.');
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = uploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder']        = folder
      ..fields['public_id']     = '${publicPrefix}_$ts'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message =
            'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>)
              ? decoded['error']
              : null;
          final msg = (err is Map<String, dynamic>)
              ? (err['message']?.toString() ?? '')
              : '';
          if (msg.trim().isNotEmpty) {
            message = 'Upload failed: ${msg.trim()}';
          }
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Upload failed: invalid response.');
      }

      final secureUrl =
          (decoded['secure_url']?.toString() ?? '').trim();
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

  // ── streams ────────────────────────────────────────────────────────────────

  Stream<MasterLeague?> _watchMasterLeague(String id) {
    return FirebaseFirestore.instance
        .collection('master_leagues')
        .doc(id.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      if (!snap.exists) return null;
      return MasterLeague.fromMap(
        snap.id,
        (snap.data() ?? <String, dynamic>{})
            .cast<String, dynamic>(),
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
        map['id'] =
            (map['id'] as String?)?.trim().isNotEmpty == true
                ? map['id']
                : d.id;
        return League.fromRemoteMap(map);
      }).toList(growable: false);
      final sorted = [...list];
      sorted.sort(
          (a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return sorted;
    }).handleError((_) => <League>[]);
  }

  Stream<LeagueAnnouncement?>
      _watchPinnedWorkspaceAnnouncement(String masterLeagueId) =>
          _announcements.watchPinnedMasterLeagueAnnouncement(
              masterLeagueId);

  // ── controller hydration ───────────────────────────────────────────────────
  // Called in build path but guarded by _hydratedForId to run only once.

  void _loadControllersFrom(MasterLeague ml) {
    if (_hydratedForId == ml.id) return;
    _hydratedForId = ml.id;

    final op = ml.organizerProfile;
    _bannerCtrl.text  = op.bannerUrl;
    _logoCtrl.text    = op.logoUrl;
    _bioCtrl.text     = op.bio;
    _badgeCtrl.text   = op.badge;

    _facebookCtrl.text  = op.socialLinks['facebook'] ?? '';
    _instagramCtrl.text = op.socialLinks['instagram'] ?? '';
    _xCtrl.text         =
        op.socialLinks['x'] ?? op.socialLinks['twitter'] ?? '';
    _youtubeCtrl.text   = op.socialLinks['youtube'] ?? '';
    _tiktokCtrl.text    = op.socialLinks['tiktok'] ?? '';
  }

  // ── profile builders ───────────────────────────────────────────────────────

  OrganizerProfile _profileFromControllers() {
    final socials = <String, String>{
      'facebook':  _facebookCtrl.text.trim(),
      'instagram': _instagramCtrl.text.trim(),
      'x':         _xCtrl.text.trim(),
      'youtube':   _youtubeCtrl.text.trim(),
      'tiktok':    _tiktokCtrl.text.trim(),
    }..removeWhere((k, v) => v.trim().isEmpty);

    return OrganizerProfile(
      bannerUrl:   _bannerCtrl.text.trim(),
      logoUrl:     _logoCtrl.text.trim(),
      bio:         _bioCtrl.text.trim(),
      socialLinks: socials,
      badge:       _badgeCtrl.text.trim(),
    );
  }

  String? _validateProfile(OrganizerProfile p) {
    if (p.bannerUrl.length > 2000) return 'Banner URL is too long.';
    if (p.logoUrl.length  > 2000) return 'Logo URL is too long.';
    if (p.bio.length      > 2000) return 'Bio is too long.';
    if (p.badge.length    > 80)   return 'Badge is too long.';
    for (final e in p.socialLinks.entries) {
      if (e.key.length   > 30)   return 'Invalid social link key.';
      if (e.value.length > 2000) return 'A social link is too long.';
    }
    return null;
  }

  // ── save ───────────────────────────────────────────────────────────────────

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
    final err     = _validateProfile(profile);
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      await repo.updateOrganizerProfile(
        masterLeagueId: ml.id,
        profile:        profile,
      );
      ref.invalidate(
          masterLeagueByIdProvider(widget.masterLeagueId));
      ref.invalidate(myMasterLeaguesProvider);
      _snack('Organizer profile updated');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── image upload ───────────────────────────────────────────────────────────

  Future<void> _pickAndUploadOrganizerImage(
    MasterLeague ml, {
    required bool banner,
  }) async {
    if (!ml.isOwner(_uid)) {
      _snack('Only the owner can update organizer images.',
          error: true);
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
        _snack(
          pickResult.errorMessage ?? 'Could not pick image.',
          error: true,
        );
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
        picked:       picked,
        folder:       'eleaguehub/organizers',
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
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
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

  // ── follow ─────────────────────────────────────────────────────────────────

  Future<void> _toggleFollow(
      MasterLeague ml, bool isFollowing) async {
    if (_followBusy) return;
    if (_uid.isEmpty) {
      _snack('Please sign in to follow this organizer.',
          error: true);
      return;
    }
    if (ml.ownerId.trim() == _uid) {
      _snack(
        'You cannot follow your own organizer workspace.',
        error: true,
      );
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

  // ── verification ───────────────────────────────────────────────────────────

  Future<void> _renewVerification(MasterLeague ml) async {
    if (_uid.isEmpty) {
      _snack('Please sign in to continue.', error: true);
      return;
    }
    if (ml.ownerId.trim() != _uid) {
      _snack('Only the owner can renew verification.',
          error: true);
      return;
    }
    if (!ml.canRenewVerification) {
      _snack(
        'This organizer cannot renew verification right now.',
        error: true,
      );
      return;
    }
    if (ml.isVerificationPending &&
        ml.verificationRequestType.trim().toLowerCase() ==
            'renewal') {
      _snack('A renewal request is already pending review.',
          error: true);
      return;
    }

    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final brightness = Theme.of(ctx).brightness;
        return AlertDialog(
          backgroundColor:  AppTheme.cardColor(brightness),
          surfaceTintColor: Colors.transparent,
          title: const Text('Renew Verification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A paid renewal request will be submitted '
                'for re-review. Approval is required before '
                'expiry is extended.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines:   4,
                decoration: const InputDecoration(
                  labelText:
                      'Renewal note for admin (optional)',
                  alignLabelWithHint: true,
                  prefixIcon:
                      Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width:   double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: brightness == Brightness.dark
                      ? AppTheme.limeAccentDark
                          .withOpacity(0.10)
                      : const Color(0xFFECFCCB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: brightness == Brightness.dark
                        ? AppTheme.limeAccentDark
                            .withOpacity(0.18)
                        : const Color(0xFFD9F99D),
                  ),
                ),
                child: Text(
                  'Renewals keep organizer trust current '
                  'and require another review cycle.',
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: () =>
                  Navigator.of(ctx).pop(true),
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
      final paymentSvc =
          ref.read(masterLeaguePaymentServiceProvider);
      final repo =
          ref.read(masterLeaguesRepositoryProvider);
      final userId =
          FirebaseAuth.instance.currentUser?.uid.trim() ??
              '';

      final payment =
          await paymentSvc.payForOrganizerVerificationRenewal(
        context:          context,
        userId:           userId,
        masterLeagueId:   ml.id,
        masterLeagueName: ml.name,
      );

      if (!mounted) return;

      if (!payment.success) {
        _snack(
          payment.errorMessage ??
              'Verification renewal payment failed.',
          error: true,
        );
        return;
      }

      await repo.submitVerificationRenewalRequest(
        masterLeagueId: ml.id,
        attemptId:      payment.attemptId,
        paymentId:      payment.paymentId,
        receiptId:      payment.receiptId ?? '',
        note:           noteCtrl.text.trim(),
      );

      if (!mounted) return;
      _snack(
          'Verification renewal request submitted for review.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      noteCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startInitialVerification(
      MasterLeague ml) async {
    if (_uid.isEmpty) {
      _snack('Please sign in to continue.', error: true);
      return;
    }
    if (ml.ownerId.trim() != _uid) {
      _snack('Only the owner can request verification.',
          error: true);
      return;
    }
    if (ml.isVerifiedOrganizer) {
      _snack('This organizer is already verified.',
          error: true);
      return;
    }
    if (ml.isVerificationPending) {
      _snack(
        'A verification request is already pending review.',
        error: true,
      );
      return;
    }

    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final brightness = Theme.of(ctx).brightness;
        return AlertDialog(
          backgroundColor:  AppTheme.cardColor(brightness),
          surfaceTintColor: Colors.transparent,
          title: const Text('Get Verified'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A paid verification request will be '
                'submitted for manual review. Approval is '
                'required before the verified badge appears.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines:   4,
                decoration: const InputDecoration(
                  labelText: 'Note for admin (optional)',
                  alignLabelWithHint: true,
                  prefixIcon:
                      Icon(Icons.verified_user_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width:   double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: brightness == Brightness.dark
                      ? AppTheme.limeAccentDark
                          .withOpacity(0.10)
                      : const Color(0xFFECFCCB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: brightness == Brightness.dark
                        ? AppTheme.limeAccentDark
                            .withOpacity(0.18)
                        : const Color(0xFFD9F99D),
                  ),
                ),
                child: Text(
                  'Verification is different from your '
                  'organizer plan. It is a trust review badge '
                  'for participants.',
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: () =>
                  Navigator.of(ctx).pop(true),
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
      final paymentSvc =
          ref.read(masterLeaguePaymentServiceProvider);
      final repo =
          ref.read(masterLeaguesRepositoryProvider);
      final userId =
          FirebaseAuth.instance.currentUser?.uid.trim() ??
              '';

      final payment =
          await paymentSvc.payForOrganizerVerification(
        context:          context,
        userId:           userId,
        masterLeagueId:   ml.id,
        masterLeagueName: ml.name,
      );

      if (!mounted) return;

      if (!payment.success) {
        _snack(
          payment.errorMessage ??
              'Verification payment failed.',
          error: true,
        );
        return;
      }

      await repo.submitVerificationRequest(
        masterLeagueId: ml.id,
        attemptId:      payment.attemptId,
        paymentId:      payment.paymentId,
        receiptId:      payment.receiptId ?? '',
        note:           noteCtrl.text.trim(),
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

  // ── feed event ─────────────────────────────────────────────────────────────

  Future<void> _postProfileUpdateFeedEvent(
      MasterLeague ml) async {
    try {
      final profile =
          await UserProfileRepository().fetchByUserId(_uid);
      final actorName =
          (profile?.displayName.trim().isNotEmpty == true)
              ? profile!.displayName.trim()
              : 'Organizer';

      await _organizerFeed.addEvent(
        OrganizerFeedEvent(
          id:             '',
          masterLeagueId: ml.id,
          type:           'announcement',
          title:          'Organizer profile updated',
          message:
              'Brand profile, links, or organizer identity '
              'details were updated.',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          actorId:     _uid,
          actorName:   actorName,
          leagueId:    '',
        ),
      );
    } catch (_) {}
  }

  // ── shared UI atoms ────────────────────────────────────────────────────────

  Widget _imageBox({
    required String url,
    required double height,
    required BorderRadius radius,
    Widget? fallback,
  }) {
    final brightness = Theme.of(context).brightness;
    if (url.trim().isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            colors: brightness == Brightness.dark
                ? [
                    AppTheme.darkCard,
                    AppTheme.darkCardAlt,
                    AppTheme.navyBgSoft,
                  ]
                : [
                    const Color(0xFFECFCCB),
                    const Color(0xFFF8FAFC),
                    const Color(0xFFFFFFFF),
                  ],
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
          border: Border.all(
              color: AppTheme.cardBorder(brightness)),
        ),
        child: fallback ??
            Center(
              child: Text(
                'No image',
                style: TextStyle(
                  color:      AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        _cloudinaryOptimizedUrl(
          url.trim(),
          width:  1200,
          height: 500,
          crop:   'fill',
        ),
        height: height,
        width:  double.infinity,
        fit:    BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: Theme.of(context)
                  .colorScheme
                  .error
                  .withOpacity(0.06),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .error
                    .withOpacity(0.18),
              ),
            ),
            child: Center(
              child: Text(
                'Image failed to load',
                style: TextStyle(
                  color:      Theme.of(context).colorScheme.error,
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
    required String label,
    required String value,
  }) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color:      AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color:      AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(
    Brightness brightness, {
    required IconData icon,
    required String   label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color:  AppTheme.searchBackground(brightness),
        border: Border.all(
            color: AppTheme.searchOutline(brightness)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14,
              color: AppTheme.limeAccentDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color:      AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w800,
              fontSize:   12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String  text,
    required Color   color,
    IconData?        icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color:  color.withOpacity(0.12),
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
              color:      color,
              fontWeight: FontWeight.w900,
              fontSize:   12,
            ),
          ),
        ],
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
          size:  42,
        ),
      ),
    );
  }

  Widget _accessDenied() {
    return const Center(
      child: EmptyState(
        title:   'Sign in required',
        message: 'Please sign in to view organizer profiles.',
        icon:    Icons.lock_outline_rounded,
      ),
    );
  }

  Widget _socialEditor() {
    return Column(
      children: [
        TextField(
          controller: _facebookCtrl,
          decoration: const InputDecoration(
            labelText:  'Facebook link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _instagramCtrl,
          decoration: const InputDecoration(
            labelText:  'Instagram link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _xCtrl,
          decoration: const InputDecoration(
            labelText:  'X / Twitter link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _youtubeCtrl,
          decoration: const InputDecoration(
            labelText:  'YouTube link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tiktokCtrl,
          decoration: const InputDecoration(
            labelText:  'TikTok link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
      ],
    );
  }

  // ── Section: pinned announcement ───────────────────────────────────────────

  Widget _buildPinnedAnnouncementSection(MasterLeague ml) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return StreamBuilder<LeagueAnnouncement?>(
      stream: _watchPinnedWorkspaceAnnouncement(ml.id),
      builder: (context, snap) {
        final pinned = snap.data;
        if (pinned == null) return const SizedBox.shrink();

        return Glass(
          borderRadius: 24,
          padding:      const EdgeInsets.all(16),
          fill:         AppTheme.cardColor(brightness),
          borderColor:  AppTheme.cardBorder(brightness),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'Official Organizer Notice',
                padding: EdgeInsets.zero,
                trailing: Icon(
                  Icons.push_pin_rounded,
                  color: AppTheme.limeAccentDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pinned.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color:      AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pinned.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:      AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w700,
                  height:     1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing:    8,
                runSpacing: 8,
                children: [
                  _metaChip(
                    brightness,
                    icon: Icons.person_outline_rounded,
                    label: pinned.authorName.trim().isEmpty
                        ? 'Organizer'
                        : pinned.authorName.trim(),
                  ),
                  _metaChip(
                    brightness,
                    icon: Icons.schedule_rounded,
                    label: pinned.pinnedAtMs > 0
                        ? DateTime
                            .fromMillisecondsSinceEpoch(
                              pinned.pinnedAtMs,
                            )
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

  // ── Section: verification status ───────────────────────────────────────────

  Widget _verificationStatusCard(MasterLeague ml) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    Color  statusColor;
    String statusTitle;
    String statusBody;

    if (ml.isVerifiedOrganizer) {
      statusColor = const Color(0xFF1D9BF0);
      statusTitle = 'Verified Organizer';
      statusBody  =
          'This organizer has been manually reviewed and '
          'approved. This badge helps participants identify '
          'authentic organizers and avoid scams.';
    } else if (ml.isVerificationPending) {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = ml.lastVerificationWasRenewal
          ? 'Renewal Pending Review'
          : 'Verification Pending';
      statusBody = ml.lastVerificationWasRenewal
          ? 'A paid renewal request has been submitted '
              'and is waiting for admin review.'
          : 'A paid verification request has been submitted '
              'and is waiting for admin review.';
    } else if (ml.isVerificationRejected) {
      statusColor = Theme.of(context).colorScheme.error;
      statusTitle = 'Verification Rejected';
      statusBody  =
          'The verification request was reviewed and rejected. '
          'Please contact support or submit again later.';
    } else if (ml.verificationExpired) {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = 'Verification Expired';
      statusBody  =
          'This organizer was previously verified, but the '
          'verification period has expired and should be renewed.';
    } else {
      statusColor = AppTheme.secondaryText(brightness);
      statusTitle = 'Not Verified';
      statusBody  =
          'This organizer is not yet verified. Verified badges '
          'help participants identify trusted organizer identities.';
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

    final ownerCanRenew = ml.isOwner(_uid) &&
        ml.canRenewVerification &&
        !ml.isVerificationPending;

    return Glass(
      borderRadius: 24,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
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
              color:      statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color:      AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              height:     1.35,
            ),
          ),
          const SizedBox(height: 10),
          _metricRow(
            label: 'Verification expires',
            value: expiryLabel,
          ),
          if (ml.verificationNote.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Review note: ${ml.verificationNote.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color:      AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (ownerCanStartInitial || ownerCanRenew) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed: ownerCanStartInitial
                        ? () =>
                            _startInitialVerification(ml)
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
                      style: const TextStyle(
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Verification purchase is separate from your '
              'organizer plan. Plan controls capacity; '
              'verification adds trust review.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:      AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                height:     1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section: identity hero ─────────────────────────────────────────────────

  Widget _identityHero(
    MasterLeague ml,
    String        ownerName,
    bool          isFollowing,
    int           followersCount,
  ) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    final planColor = ml.plan == MasterLeaguePlan.elite
        ? const Color(0xFF8B5CF6)
        : (ml.plan == MasterLeaguePlan.pro
            ? const Color(0xFF22C55E)
            : AppTheme.limeAccentDark);

    final planLabel     = 'Plan: ${ml.plan.displayName}';
    final canFollow     =
        _uid.isNotEmpty && ml.ownerId.trim() != _uid;
    final ownerCanEdit  = ml.isOwner(_uid);
    final bannerUrl     = ml.organizerProfile.bannerUrl.trim();
    final logoUrl       = ml.organizerProfile.logoUrl.trim();

    return Glass(
      borderRadius: 30,
      padding:      const EdgeInsets.all(12),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: ownerCanEdit
                    ? () => _pickAndUploadOrganizerImage(
                        ml, banner: true)
                    : null,
                child: Stack(
                  children: [
                    _imageBox(
                      url:    bannerUrl,
                      height: 220,
                      radius: BorderRadius.circular(24),
                      fallback: Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(24),
                          gradient: brightness ==
                                  Brightness.dark
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF182230),
                                    Color(0xFF222E3D),
                                    Color(0xFF0F172A),
                                  ],
                                  begin: Alignment.topLeft,
                                  end:
                                      Alignment.bottomRight,
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFECFCCB),
                                    Color(0xFFF8FAFC),
                                    Color(0xFFFFFFFF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end:
                                      Alignment.bottomRight,
                                ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons
                                .photo_size_select_actual_outlined,
                            size:  48,
                            color: AppTheme.secondaryText(
                                brightness),
                          ),
                        ),
                      ),
                    ),
                    if (_uploadingBanner)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(24),
                            color: Colors.black
                                .withOpacity(0.18),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width:  26,
                              height: 26,
                              child:
                                  CircularProgressIndicator(
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
              Positioned(
                left:   20,
                bottom: -42,
                child: Stack(
                  children: [
                    InkWell(
                      onTap: ownerCanEdit
                          ? () =>
                              _pickAndUploadOrganizerImage(
                                ml, banner: false)
                          : null,
                      borderRadius:
                          BorderRadius.circular(999),
                      child: Container(
                        width:  96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context)
                              .scaffoldBackgroundColor,
                          border: Border.all(
                            color: Theme.of(context)
                                .scaffoldBackgroundColor,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(0.12),
                              blurRadius:   18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: logoUrl.isNotEmpty
                              ? Image.network(
                                  _cloudinaryOptimizedUrl(
                                    logoUrl,
                                    width:  300,
                                    height: 300,
                                    crop:   'fill',
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) =>
                                          _logoFallback(
                                              brightness),
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
                            color: Colors.black
                                .withOpacity(0.22),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width:  24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (ownerCanEdit && !_uploadingLogo)
                      Positioned(
                        right:  0,
                        bottom: 0,
                        child: Container(
                          width:  32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.limeAccent,
                            border: Border.all(
                              color: Theme.of(context)
                                  .scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size:  16,
                            color: AppTheme.darkText,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 54),
          Wrap(
            spacing:    8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      ml.name.trim().isEmpty
                          ? 'Organizer'
                          : ml.name.trim(),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(
                        fontWeight:    FontWeight.w900,
                        letterSpacing: -0.3,
                        color: AppTheme.primaryText(
                            brightness),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (ml.isVerifiedOrganizer)
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF1D9BF0),
                      size:  20,
                    )
                  else if (ml.isVerificationPending)
                    const Icon(
                      Icons.verified_outlined,
                      color: Color(0xFFF59E0B),
                      size:  20,
                    ),
                ],
              ),
              _pill(
                text:  planLabel,
                color: planColor,
                icon:  Icons.workspace_premium_rounded,
              ),
              if (ml.organizerProfile.badge
                  .trim()
                  .isNotEmpty)
                _pill(
                  text:  ml.organizerProfile.badge.trim(),
                  color: const Color(0xFFF59E0B),
                ),
              _pill(
                text: '$followersCount '
                    'follower${followersCount == 1 ? '' : 's'}',
                color: const Color(0xFF22C55E),
                icon:  Icons.favorite_border_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ownerName.isNotEmpty
                ? 'Managed by $ownerName'
                : 'Managed by Organizer',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:      AppTheme.secondaryText(brightness),
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
              color:      AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
              height:     1.35,
            ),
          ),
          if (canFollow) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed: _followBusy
                        ? null
                        : () =>
                            _toggleFollow(ml, isFollowing),
                    icon: _followBusy
                        ? const SizedBox(
                            width:  16,
                            height: 16,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.darkText,
                            ),
                          )
                        : Icon(
                            isFollowing
                                ? Icons.favorite_rounded
                                : Icons
                                    .favorite_border_rounded,
                          ),
                    label: Text(
                      isFollowing
                          ? 'Following'
                          : 'Follow Organizer',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Section: trust metrics ─────────────────────────────────────────────────

  Widget _trustMetrics(MasterLeague ml, int followersCount) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    final cards = <_TrustMetric>[
      _TrustMetric(
        icon:  Icons.workspace_premium_rounded,
        label: 'Organizer Plan',
        value: ml.plan.displayName,
        tint: ml.plan == MasterLeaguePlan.elite
            ? const Color(0xFF8B5CF6)
            : (ml.plan == MasterLeaguePlan.pro
                ? const Color(0xFF22C55E)
                : AppTheme.limeAccentDark),
      ),
      _TrustMetric(
        icon:  Icons.verified_user_outlined,
        label: 'Trust Status',
        value: ml.isVerifiedOrganizer
            ? 'Verified'
            : (ml.isVerificationPending
                ? 'Pending'
                : (ml.verificationExpired
                    ? 'Expired'
                    : 'Unverified')),
        tint: ml.isVerifiedOrganizer
            ? const Color(0xFF1D9BF0)
            : (ml.isVerificationPending
                ? const Color(0xFFF59E0B)
                : AppTheme.secondaryText(brightness)),
      ),
      _TrustMetric(
        icon:  Icons.emoji_events_outlined,
        label: 'Competitions Hosted',
        value: '${ml.analytics.totalTournamentsCreated}',
        tint:  AppTheme.limeAccentDark,
      ),
      _TrustMetric(
        icon:  Icons.groups_rounded,
        label: 'Teams Hosted',
        value: '${ml.analytics.totalParticipantsTeams}',
        tint:  const Color(0xFF22C55E),
      ),
      _TrustMetric(
        icon:  Icons.sports_score_rounded,
        label: 'Matches Managed',
        value: '${ml.analytics.totalMatches}',
        tint:  const Color(0xFF8B5CF6),
      ),
      _TrustMetric(
        icon:  Icons.favorite_border_rounded,
        label: 'Followers',
        value: '$followersCount',
        tint:  const Color(0xFFEF4444),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount:  cards.length,
      physics:    const NeverScrollableScrollPhysics(),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   2,
        mainAxisSpacing:  12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final item = cards[index];
        return Glass(
          borderRadius: 20,
          padding:      const EdgeInsets.all(14),
          fill:         AppTheme.cardColor(brightness),
          borderColor:  AppTheme.cardBorder(brightness),
          child: Row(
            children: [
              Container(
                width:  42,
                height: 42,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  item.tint.withOpacity(0.12),
                  border: Border.all(
                      color: item.tint.withOpacity(0.24)),
                ),
                child:
                    Icon(item.icon, color: item.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(
                            brightness),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(
                        color: AppTheme.secondaryText(
                            brightness),
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

  // ── Section: social links ──────────────────────────────────────────────────

  Widget _socialLinksSection(MasterLeague ml) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;
    final links      = ml.organizerProfile.socialLinks;

    Widget socialTile(String key, String value) {
      return Glass(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        fill:        AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Row(
          children: [
            Icon(Icons.link_rounded,
                color: AppTheme.limeAccentDark, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    key,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(
                      color:      AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(
                      color:      AppTheme.primaryText(brightness),
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
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Official Links',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.public_rounded,
                color: AppTheme.limeAccentDark),
          ),
          const SizedBox(height: 10),
          if (links.isEmpty)
            Text(
              'No official links published yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:      AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...links.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: socialTile(e.key, e.value),
              ),
            ),
          if (ml.isOwner(_uid)) ...[
            const SizedBox(height: 12),
            _socialEditor(),
          ],
        ],
      ),
    );
  }

  // ── Section: about ─────────────────────────────────────────────────────────

  Widget _aboutSection(MasterLeague ml) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 24,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'About Organizer',
            padding: EdgeInsets.zero,
            trailing: Icon(
              Icons.subject_outlined,
              color: AppTheme.limeAccentDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            ml.organizerProfile.bio.trim().isEmpty
                ? 'No bio yet.'
                : ml.organizerProfile.bio.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color:      AppTheme.secondaryText(brightness),
              height:     1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (ml.isOwner(_uid)) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _bioCtrl,
              maxLines:   5,
              decoration: const InputDecoration(
                labelText:        'Organizer bio',
                prefixIcon:       Icon(Icons.subject_outlined),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section: competition history ───────────────────────────────────────────

  Widget _competitionHistory(MasterLeague ml) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 24,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Competition History',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.history_rounded,
                color: AppTheme.limeAccentDark),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<League>>(
            stream: _watchCompetitions(ml.id),
            builder: (context, leaguesSnap) {
              final leagues =
                  leaguesSnap.data ?? const <League>[];
              if (leaguesSnap.connectionState ==
                      ConnectionState.waiting &&
                  leagues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                      child: CircularProgressIndicator()),
                );
              }

              if (leagues.isEmpty) {
                return Text(
                  'No competitions yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:      AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }

              return Column(
                children: leagues.take(20).map((l) {
                  return Padding(
                    padding:
                        const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () =>
                          _safePush('/leagues/${l.id}'),
                      borderRadius:
                          BorderRadius.circular(18),
                      child: Glass(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical:   12,
                        ),
                        fill:        AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Row(
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              color: AppTheme.limeAccentDark,
                              size:  18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.name,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: theme.textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                  fontWeight:
                                      FontWeight.w800,
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                ),
                              ),
                            ),
                            Text(
                              l.format.displayName,
                              style: theme.textTheme
                                  .bodySmall
                                  ?.copyWith(
                                color:
                                    AppTheme.secondaryText(
                                        brightness),
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

  // ── Section: owner actions ─────────────────────────────────────────────────

  Widget _ownerActions(MasterLeague ml) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    if (!ml.isOwner(_uid)) return const SizedBox.shrink();

    return Glass(
      borderRadius: 24,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Owner Actions',
            padding: EdgeInsets.zero,
            trailing: Icon(
              Icons.settings_suggest_outlined,
              color: AppTheme.limeAccentDark,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                  ),
                  onPressed: _saving
                      ? null
                      : () async {
                          await _save(ml);
                          await _postProfileUpdateFeedEvent(
                              ml);
                        },
                  icon: _saving
                      ? const SizedBox(
                          width:  16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color:       AppTheme.darkText,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text(
                    'Save Profile',
                    style: TextStyle(
                        fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  // Back to workspace — tries Navigator pop first
                  // (this screen is usually pushed via MaterialPageRoute),
                  // then falls back to GoRouter push as a safety net.
                  onPressed: () {
                    final nav = Navigator.of(context,
                        rootNavigator: false);
                    if (nav.canPop()) {
                      nav.pop();
                    } else {
                      _safePush(
                          '/master-leagues/${ml.id}');
                    }
                  },
                  icon: const Icon(
                      Icons.dashboard_customize_outlined),
                  label: const Text(
                    'Back to Workspace',
                    style: TextStyle(
                        fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MasterLeague?>(
      stream: _watchMasterLeague(widget.masterLeagueId),
      builder: (context, snap) {
        final ml = snap.data;

        // ── Loading ──────────────────────────────────────────────────────────
        if (snap.connectionState == ConnectionState.waiting &&
            ml == null) {
          return GlassScaffold(
            appBar: AppBar(
              title:           const Text('Organizer Trust Page'),
              backgroundColor: Colors.transparent,
              elevation:       0,
              leading: IconButton(
                icon:     const Icon(Icons.arrow_back),
                onPressed: _smartPop,
              ),
            ),
            body: const Center(
                child: CircularProgressIndicator()),
          );
        }

        // ── Not found ────────────────────────────────────────────────────────
        if (ml == null) {
          return GlassScaffold(
            appBar: AppBar(
              title:           const Text('Organizer Trust Page'),
              backgroundColor: Colors.transparent,
              elevation:       0,
              leading: IconButton(
                icon:     const Icon(Icons.arrow_back),
                onPressed: _smartPop,
              ),
            ),
            body: const Center(
              child: EmptyState(
                title:   'Not found',
                message:
                    'This Master League may have been deleted.',
                icon: Icons.badge_outlined,
              ),
            ),
          );
        }

        // ── Signed out ───────────────────────────────────────────────────────
        if (_uid.isEmpty) {
          return GlassScaffold(
            appBar: AppBar(
              title:           const Text('Organizer Trust Page'),
              backgroundColor: Colors.transparent,
              elevation:       0,
              leading: IconButton(
                icon:     const Icon(Icons.arrow_back),
                onPressed: _smartPop,
              ),
            ),
            body: _accessDenied(),
          );
        }

        _loadControllersFrom(ml);

        final followAsync =
            ref.watch(masterLeagueFollowStateProvider(ml.id));
        final followersCountAsync =
            ref.watch(masterLeagueFollowersCountProvider(ml.id));

        final isFollowing    = followAsync.valueOrNull ?? false;
        final followersCount =
            followersCountAsync.valueOrNull ?? 0;

        return FutureBuilder<UserProfile?>(
          future: _getOwnerProfile(ml.ownerId),
          builder: (context, ownerSnap) {
            final ownerName =
                _ownerDisplayName(ownerSnap.data);

            return GlassScaffold(
              appBar: AppBar(
                title: const Text('Organizer Trust Page'),
                backgroundColor: Colors.transparent,
                elevation:       0,
                leading: IconButton(
                  icon:     const Icon(Icons.arrow_back),
                  onPressed: _smartPop,
                ),
                actions: [
                  if (ml.isOwner(_uid))
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              await _save(ml);
                              await _postProfileUpdateFeedEvent(
                                  ml);
                            },
                      child: Text(
                        _saving ? 'Saving...' : 'Save',
                        style: TextStyle(
                          color: _saving
                              ? AppTheme.secondaryText(
                                  Theme.of(context)
                                      .brightness)
                              : AppTheme.limeAccentDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w         = constraints.maxWidth;
                    final isDesktop = w >= _BP.desktop;
                    final hPad =
                        w < _BP.tablet ? 16.0 : 24.0;

                    if (isDesktop) {
                      return _buildDesktopLayout(
                        ml:           ml,
                        ownerName:    ownerName,
                        isFollowing:  isFollowing,
                        followersCount: followersCount,
                        hPad:         hPad,
                      );
                    }

                    return _buildMobileLayout(
                      ml:             ml,
                      ownerName:      ownerName,
                      isFollowing:    isFollowing,
                      followersCount: followersCount,
                      hPad:           hPad,
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Desktop two-column layout ──────────────────────────────────────────────
  //
  // Left  (flex 3): Hero + Pinned notice + Trust metrics + Competition history
  // Right (flex 2): Verification + About + Social links + Owner actions

  Widget _buildDesktopLayout({
    required MasterLeague ml,
    required String        ownerName,
    required bool          isFollowing,
    required int           followersCount,
    required double        hPad,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _identityHero(ml, ownerName,
                        isFollowing, followersCount),
                    const SizedBox(height: 16),
                    _buildPinnedAnnouncementSection(ml),
                    const SizedBox(height: 16),
                    _trustMetrics(ml, followersCount),
                    const SizedBox(height: 16),
                    _competitionHistory(ml),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _verificationStatusCard(ml),
                    const SizedBox(height: 16),
                    _aboutSection(ml),
                    const SizedBox(height: 16),
                    _socialLinksSection(ml),
                    if (ml.isOwner(_uid)) ...[
                      const SizedBox(height: 16),
                      _ownerActions(ml),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mobile single-column layout ────────────────────────────────────────────

  Widget _buildMobileLayout({
    required MasterLeague ml,
    required String        ownerName,
    required bool          isFollowing,
    required int           followersCount,
    required double        hPad,
  }) {
    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
      children: [
        _identityHero(ml, ownerName, isFollowing,
            followersCount),
        const SizedBox(height: 16),
        _buildPinnedAnnouncementSection(ml),
        const SizedBox(height: 16),
        _trustMetrics(ml, followersCount),
        const SizedBox(height: 16),
        _verificationStatusCard(ml),
        const SizedBox(height: 16),
        _aboutSection(ml),
        const SizedBox(height: 16),
        _socialLinksSection(ml),
        const SizedBox(height: 16),
        _competitionHistory(ml),
        if (ml.isOwner(_uid)) ...[
          const SizedBox(height: 16),
          _ownerActions(ml),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _TrustMetric
// ---------------------------------------------------------------------------

class _TrustMetric {
  const _TrustMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String   label;
  final String   value;
  final Color    tint;
}
