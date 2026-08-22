//lib/features/profile/presentation/public_team_profile_screen.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../chat/data/private_chat_repository.dart';
import '../../chat/presentation/widgets/private_message_button.dart';
import '../../master_leagues/domain/master_league_plan.dart';
import '../../moderation/data/report_repository.dart';
import '../../moderation/models/user_report.dart';
import '../../status/data/status_repository.dart';
import '../../status/presentation/widgets/create_status_sheet.dart';
import '../data/team_profile_repository.dart';
import '../models/game_id.dart';
import '../models/recent_match.dart';
import '../models/squad.dart';
import '../models/team_profile.dart';
import '../models/trophy.dart';
import '../models/user_stats.dart';
import 'widgets/squad_pitch_view.dart';

// --- SECTION: Main Screen Widget ---
class PublicTeamProfileScreen extends StatefulWidget {
  const PublicTeamProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<PublicTeamProfileScreen> createState() => _PublicTeamProfileScreenState();
}

// --- SECTION: Main Screen State ---
class _PublicTeamProfileScreenState extends State<PublicTeamProfileScreen> {
  static const int _maxBannerBytes = 5 * 1024 * 1024;

  final TeamProfileRepository _teamRepo = TeamProfileRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();
  final PrivateChatRepository _chatRepo = PrivateChatRepository();

  bool _following = false;
  bool _followBusy = false;
  bool _blocked = false;
  bool _chatBusy = false;

  // Feature 1 — Profile Background / Cover Image.
  bool _uploadingBanner = false;

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  bool get _isOwner => _selfUid.isNotEmpty && _selfUid == widget.userId.trim();

  @override
  void initState() {
    super.initState();
    _loadFollowAndBlockState();
  }

  Future<void> _loadFollowAndBlockState() async {
    if (_isOwner) return;
    final following = await _teamRepo.isFollowing(widget.userId);
    final blocked = await _teamRepo.isBlocked(widget.userId);
    if (!mounted) return;
    setState(() {
      _following = following;
      _blocked = blocked;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(trimmed)),
    );
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      if (_following) {
        await _teamRepo.unfollow(widget.userId);
      } else {
        await _teamRepo.follow(widget.userId);
      }
      if (!mounted) return;
      setState(() => _following = !_following);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _handleAppBarChatTap(String displayName) async {
    if (_chatBusy) return;
    setState(() => _chatBusy = true);
    try {
      final thread = await _chatRepo.startOrGetThread(widget.userId);
      if (!mounted) return;
      context.push(
        '/chat/${thread.id}',
        extra: {'otherUserId': widget.userId, 'otherName': displayName},
      );
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }

  Future<void> _copyProfileLink() async {
    final link = 'https://esportlyic.com/profile/${widget.userId.trim()}';
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Profile link copied.');
  }

  Future<void> _copyTeamId(String shareId) async {
    if (shareId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: shareId));
    _snack('Copied: $shareId');
  }

  Future<void> _confirmBlock() async {
    final brightness = Theme.of(context).brightness;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        title: Text(_blocked ? 'Unblock user?' : 'Block user?'),
        content: Text(
          _blocked
              ? 'They will be able to see your profile and interact with you again.'
              : 'You will no longer see their content, and they will not be able to message you.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_blocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      if (_blocked) {
        await _teamRepo.unblockUser(widget.userId);
      } else {
        await _teamRepo.blockUser(widget.userId);
      }
      if (!mounted) return;
      setState(() => _blocked = !_blocked);
      _snack(_blocked ? 'User blocked.' : 'User unblocked.');
    } catch (e) {
      _snack(e.toString());
    }
  }

  // --- SECTION: Report Sheet ---
  void _showReportSheet() {
    final ReportRepository reportRepo = ReportRepository();
    final reasons = [
      UserReportReason.spam,
      UserReportReason.harassment,
      UserReportReason.impersonation,
      UserReportReason.cheating,
      UserReportReason.other,
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String? selectedReason;
        final detailsController = TextEditingController();
        bool submitting = false;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Report user', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: reasons
                            .map((r) => ChoiceChip(
                                  label: Text(UserReportReason.label(r)),
                                  selected: selectedReason == r,
                                  onSelected: (_) => setSheetState(() => selectedReason = r),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: detailsController,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: const InputDecoration(hintText: 'Additional details (optional)'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (selectedReason == null || submitting)
                              ? null
                              : () async {
                                  setSheetState(() => submitting = true);
                                  try {
                                    await reportRepo.submitReport(
                                      targetUserId: widget.userId,
                                      reason: selectedReason!,
                                      details: detailsController.text,
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.of(ctx).pop();
                                    _snack('Report submitted. Thank you.');
                                  } catch (e) {
                                    setSheetState(() => submitting = false);
                                    if (!ctx.mounted) return;
                                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                                  }
                                },
                          child: submitting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Submit Report'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- SECTION: More Actions Sheet ---
  void _showMoreActions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share profile'),
              onTap: () {
                Navigator.of(ctx).pop();
                _copyProfileLink();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showReportSheet();
              },
            ),
            ListTile(
              leading: Icon(_blocked ? Icons.lock_open_rounded : Icons.block_rounded),
              title: Text(_blocked ? 'Unblock' : 'Block'),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmBlock();
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- SECTION: Feature 1 — Profile Background / Cover Image ---

  String _cloudinaryOptimizedUrl(
    String url, {
    int? width,
    int? height,
    String crop = 'fill',
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final isCloudinary = u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;
    final marker = '/image/upload/';
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
    final isVersionOnly = first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  Future<String> _uploadBannerToCloudinary({required PlatformFile picked}) async {
    final cloudName = const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
    final uploadPreset =
        const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET').trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }

    final uploadUrl = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;
    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart = http.MultipartFile.fromBytes('file', bytes, filename: picked.name);
    } else if (path.isNotEmpty) {
      filePart = await http.MultipartFile.fromPath('file', path, filename: picked.name);
    } else {
      throw StateError('Selected image is not accessible.');
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = uploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = 'eleaguehub/banners'
      ..fields['public_id'] = 'team_banner_$ts'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed = await client.send(req).timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>) ? (err['message']?.toString() ?? '') : '';
          if (msg.trim().isNotEmpty) message = 'Upload failed: ${msg.trim()}';
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Upload failed: invalid response.');
      }

      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      if (secureUrl.isEmpty) throw StateError('Upload failed: secure_url missing.');

      return secureUrl;
    } finally {
      client.close();
    }
  }

  Future<void> _pickAndUploadBanner() async {
    if (_uploadingBanner) return;
    if (!_isOwner) return;

    setState(() => _uploadingBanner = true);

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));

      final pickResult = await SafeImagePicker.pickImage();
      if (pickResult.wasCancelled) return;

      if (!pickResult.isSuccess) {
        _snack(pickResult.errorMessage ?? 'Could not pick image.');
        return;
      }

      final picked = pickResult.file!;
      if (picked.size > _maxBannerBytes) {
        _snack('Image too large. Please select an image under 5 MB.');
        return;
      }

      final secureUrl = await _uploadBannerToCloudinary(picked: picked);
      await _teamRepo.updateBannerImage(bannerImageUrl: secureUrl);

      if (!mounted) return;
      _snack('Cover photo updated.');
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  Future<void> _confirmRemoveBanner() async {
    final brightness = Theme.of(context).brightness;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        title: const Text('Remove cover photo?'),
        content: const Text('Your profile will show the default background instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _uploadingBanner = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));
      await _teamRepo.updateBannerImage(bannerImageUrl: '');
      if (!mounted) return;
      _snack('Cover photo removed.');
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  void _showBannerEditSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_back_rounded),
              title: const Text('Change cover photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndUploadBanner();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove cover photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmRemoveBanner();
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- SECTION: Feature 2 — Status ---

  Future<void> _handleAvatarTap({
    required bool hasActiveStatus,
    required bool eligibleForStatus,
  }) async {
    if (hasActiveStatus) {
      context.push('/status/${widget.userId.trim()}');
      return;
    }
    if (_isOwner && eligibleForStatus) {
      await showCreateStatusSheet(context);
    }
  }

  // --- SECTION: Build Method ---
  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isOwner) ...[
            _chatBusy
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    tooltip: 'Message',
                    onPressed: () => _handleAppBarChatTap('User'),
                  ),
            _followBusy
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: Icon(
                      _following ? Icons.check_circle_rounded : Icons.person_add_alt_1_rounded,
                      color: _following ? AppTheme.limeAccent : null,
                    ),
                    tooltip: _following ? 'Unfollow' : 'Follow',
                    onPressed: _toggleFollow,
                  ),
          ],
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onPressed: _showMoreActions,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: FutureBuilder<UserProfile?>(
          future: _userRepo.fetchByUserId(widget.userId),
          builder: (context, accountSnap) {
            if (!accountSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final account = accountSnap.data;
            final displayName = _userRepo.displayNameForProfile(account, fallbackUserId: widget.userId);
            final eligibleForStatus = account != null &&
                (account.activePlan == MasterLeaguePlan.pro ||
                    account.activePlan == MasterLeaguePlan.elite);

            return StreamBuilder<TeamProfile>(
              stream: _teamRepo.watchTeamProfile(widget.userId),
              builder: (context, teamSnap) {
                final teamProfile = teamSnap.data ?? TeamProfile.empty(widget.userId);

                return StreamBuilder<bool>(
                  stream: StatusRepository().watchHasActiveStatus(widget.userId),
                  builder: (context, statusSnap) {
                    final hasActiveStatus = statusSnap.data ?? false;

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 40),
                      children: [
                        _CoverAndHeader(
                          teamProfile: teamProfile,
                          account: account,
                          displayName: displayName,
                          onCopyTeamId: () => _copyTeamId(account?.effectiveShareId ?? ''),
                          isOwner: _isOwner,
                          uploadingBanner: _uploadingBanner,
                          bannerUrlOptimizer: (u) => _cloudinaryOptimizedUrl(u, width: 800, crop: 'fill'),
                          onEditBanner: _showBannerEditSheet,
                          hasActiveStatus: hasActiveStatus,
                          eligibleForStatus: eligibleForStatus,
                          onAvatarTap: () => _handleAvatarTap(
                            hasActiveStatus: hasActiveStatus,
                            eligibleForStatus: eligibleForStatus,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!_isOwner)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: PrivateMessageButton(
                              key: ValueKey('msg_btn_$_blocked'),
                              targetUserId: widget.userId,
                              targetDisplayName: displayName,
                              onUpgradeTap: () => context.push('/settings'),
                            ),
                          ),
                        const SizedBox(height: 20),
                        _StatsSection(userId: widget.userId, repo: _teamRepo),
                        const SizedBox(height: 20),
                        _SectionLabel('Squad'),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _SquadPreview(userId: widget.userId, repo: _teamRepo),
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel('Trophy Cabinet'),
                        const SizedBox(height: 10),
                        _TrophyShelf(userId: widget.userId, repo: _teamRepo),
                        const SizedBox(height: 20),
                        _SectionLabel('Recent Matches'),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _RecentMatchesList(userId: widget.userId, repo: _teamRepo),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// --- SECTION: Section Label Widget ---
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }
}

// --- SECTION: Cover and Header Widget ---
class _CoverAndHeader extends StatelessWidget {
  const _CoverAndHeader({
    required this.teamProfile,
    required this.account,
    required this.displayName,
    required this.onCopyTeamId,
    required this.isOwner,
    required this.uploadingBanner,
    required this.bannerUrlOptimizer,
    required this.onEditBanner,
    required this.hasActiveStatus,
    required this.eligibleForStatus,
    required this.onAvatarTap,
  });

  final TeamProfile teamProfile;
  final UserProfile? account;
  final String displayName;
  final VoidCallback onCopyTeamId;
  final bool isOwner;
  final bool uploadingBanner;
  final String Function(String url) bannerUrlOptimizer;
  final VoidCallback onEditBanner;
  final bool hasActiveStatus;
  final bool eligibleForStatus;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final avatarUrl = account?.effectivePhotoUrl ?? '';
    final rawBannerUrl = teamProfile.bannerImageUrl.trim();
    final bannerUrl = rawBannerUrl.isNotEmpty ? bannerUrlOptimizer(rawBannerUrl) : '';

    // Feature 2 — Status: an avatar with an active status gets a
    // visually distinct lime ring; tapping it opens the viewer.
    // Owners who are Pro/Elite but have no active status yet can tap
    // the avatar to post one instead (see onAvatarTap).
    final bool avatarIsTappable = hasActiveStatus || (isOwner && eligibleForStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.cardColor(brightness),
                image: bannerUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(bannerUrl),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
                gradient: bannerUrl.isEmpty
                    ? LinearGradient(
                        colors: [
                          AppTheme.limeAccentDark.withOpacity(0.35),
                          AppTheme.cardColor(brightness),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
              ),
              child: uploadingBanner
                  ? Container(
                      color: Colors.black.withOpacity(0.35),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            if (isOwner)
              Positioned(
                right: 12,
                top: 12,
                child: Material(
                  color: Colors.black.withOpacity(0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: uploadingBanner ? null : onEditBanner,
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(
                        Icons.edit_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              bottom: -36,
              child: GestureDetector(
                onTap: avatarIsTappable ? onAvatarTap : null,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasActiveStatus
                          ? AppTheme.limeAccent
                          : AppTheme.cardColor(brightness),
                      width: hasActiveStatus ? 3 : 4,
                    ),
                    color: AppTheme.iconCircleBackground(brightness),
                    image: avatarUrl.isNotEmpty
                        ? DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover)
                        : null,
                  ),
                  child: Stack(
                    children: [
                      if (avatarUrl.isEmpty)
                        const Center(child: Icon(Icons.person_rounded, size: 36)),
                      if (isOwner && eligibleForStatus && !hasActiveStatus)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.limeAccent,
                              border: Border.all(color: AppTheme.cardColor(brightness), width: 2),
                            ),
                            child: const Icon(Icons.add_rounded, size: 12, color: AppTheme.darkText),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 44),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: AppTheme.primaryText(brightness),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (account?.verifiedActive == true) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF1D9BF0)),
                  ],
                  if (account?.isOrganizerVerified == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded, size: 18, color: Color(0xFFFFB300)),
                  ],
                  if (account?.isStaffVerified == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.shield_rounded, size: 18, color: Color(0xFF7C3AED)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.sports_soccer_rounded, size: 13, color: AppTheme.secondaryText(brightness)),
                  const SizedBox(width: 4),
                  Text(
                    GameId.label(teamProfile.game),
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onCopyTeamId,
                    child: Row(
                      children: [
                        Icon(Icons.tag_rounded, size: 13, color: AppTheme.secondaryText(brightness)),
                        const SizedBox(width: 2),
                        Text(
                          account?.effectiveShareId ?? '',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (teamProfile.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  teamProfile.bio,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// --- SECTION: Stats Section ---
class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.userId, required this.repo});
  final String userId;
  final TeamProfileRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserStats>(
      stream: repo.watchStats(userId),
      builder: (context, snap) {
        final stats = snap.data ?? UserStats.empty();
        final cards = <(String, String)>[
          ('Followers', '${stats.followersCount}'),
          ('Following', '${stats.followingCount}'),
          ('Competitions', '${stats.competitionsJoined}'),
          ('Trophies', '${stats.trophies}'),
          ('Matches', '${stats.matchesPlayed}'),
          ('Wins', '${stats.wins}'),
          ('Draws', '${stats.draws}'),
          ('Losses', '${stats.losses}'),
          ('Goals', '${stats.goalsScored}'),
          ('Conceded', '${stats.goalsConceded}'),
          ('Win %', '${stats.winPercentage.toStringAsFixed(0)}%'),
        ];

        return SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final (label, value) = cards[i];
              return _StatCard(label: label, value: value);
            },
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: AppTheme.secondaryText(brightness),
            ),
          ),
        ],
      ),
    );
  }
}

// --- SECTION: Squad Preview ---
class _SquadPreview extends StatelessWidget {
  const _SquadPreview({required this.userId, required this.repo});
  final String userId;
  final TeamProfileRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: repo.fetchSquadGameIds(userId),
      builder: (context, gamesSnap) {
        final games = gamesSnap.data ?? const [GameId.localFootball];
        final firstGame = games.isEmpty ? GameId.localFootball : games.first;

        return StreamBuilder<Squad>(
          stream: repo.watchSquad(userId: userId, gameId: firstGame),
          builder: (context, squadSnap) {
            final squad = squadSnap.data ?? Squad.empty(firstGame);

            return GestureDetector(
              onTap: () => context.push('/profile/$userId/squad'),
              child: AbsorbPointer(
                child: SquadPitchView(squad: squad, isEditable: false),
              ),
            );
          },
        );
      },
    );
  }
}

// --- SECTION: Trophy Shelf ---
class _TrophyShelf extends StatelessWidget {
  const _TrophyShelf({required this.userId, required this.repo});
  final String userId;
  final TeamProfileRepository repo;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return StreamBuilder<List<Trophy>>(
      stream: repo.watchTrophies(userId),
      builder: (context, snap) {
        final trophies = snap.data ?? const [];
        if (trophies.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No trophies yet.',
              style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
            ),
          );
        }

        return SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: trophies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final t = trophies[i];
              final isWinner = t.position == 1;
              return Glass(
                borderRadius: 16,
                padding: const EdgeInsets.all(12),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isWinner ? Icons.emoji_events_rounded : Icons.workspace_premium_rounded,
                        color: isWinner ? const Color(0xFFFFD54F) : const Color(0xFFB0BEC5),
                        size: 26,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.leagueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      Text(
                        isWinner ? 'Champion' : '#${t.position} place',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: AppTheme.secondaryText(brightness),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// --- SECTION: Recent Matches List ---
class _RecentMatchesList extends StatelessWidget {
  const _RecentMatchesList({required this.userId, required this.repo});
  final String userId;
  final TeamProfileRepository repo;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return StreamBuilder<List<RecentMatch>>(
      stream: repo.watchRecentMatches(userId),
      builder: (context, snap) {
        final matches = snap.data ?? const [];
        if (matches.isEmpty) {
          return Text(
            'No matches played yet.',
            style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
          );
        }

        return Column(
          children: matches
              .map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Glass(
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      fill: AppTheme.cardColor(brightness),
                      borderColor: AppTheme.cardBorder(brightness),
                      child: Row(
                        children: [
                          _ResultBadge(result: m.result),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'vs ${m.opponentName}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: AppTheme.primaryText(brightness),
                                  ),
                                ),
                                Text(
                                  m.leagueName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                    color: AppTheme.secondaryText(brightness),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${m.goalsFor} - ${m.goalsAgainst}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppTheme.primaryText(brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

// --- SECTION: Result Badge ---
class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.result});
  final MatchResult result;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String letter;
    switch (result) {
      case MatchResult.win:
        color = const Color(0xFF22C55E);
        letter = 'W';
        break;
      case MatchResult.draw:
        color = const Color(0xFFF59E0B);
        letter = 'D';
        break;
      case MatchResult.loss:
        color = const Color(0xFFE53935);
        letter = 'L';
        break;
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.15)),
      child: Center(
        child: Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
      ),
    );
  }
}
