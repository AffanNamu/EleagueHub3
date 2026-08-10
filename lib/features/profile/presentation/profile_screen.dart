//profile_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/services/app_admins_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../admin/pricing_quick_editor_sheet.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/domain/username_utils.dart';
import '../../auth/models/user_profile.dart';
import '../../chat/presentation/global_chat_admin_requests_screen.dart';
import '../../legal/affiliate_disclosure_screen.dart';
import '../../legal/contact_screen.dart';
import '../../legal/privacy_policy_screen.dart';
import '../../legal/terms_of_service_screen.dart';
import '../../leagues/logic/coupon_config_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const int _maxBytes = 5 * 1024 * 1024;
  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  bool _uploadingAvatar = false;

  // Guards ensureUsernameIfMissing() so it only fires once per screen
  // instance even though the profile StreamBuilder rebuilds on every
  // snapshot (e.g. when other fields like avatar/plan change).
  bool _usernameEnsureTriggered = false;

  String _couponLeagueSubtitle({
    required bool enabled,
    required int discountPercent,
  }) {
    if (!enabled) return 'Not enabled';
    return 'Discount $discountPercent%';
  }

  void _snack(BuildContext context, String msg) {
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        content: Text(trimmed),
      ),
    );
  }

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(
    String url, {
    int? width,
    int? height,
    String crop = 'fill',
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final isCloudinary = u.contains('res.cloudinary.com') &&
        u.contains('/image/upload/');
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
    final isVersionOnly = first.startsWith('v') &&
        int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) {
        return u;
      }
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  Future<String> _uploadToCloudinary({
    required PlatformFile picked,
  }) async {
    final cloudName =
        const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
    final uploadPreset = const String.fromEnvironment(
      'CLOUDINARY_UNSIGNED_UPLOAD_PRESET',
    ).trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }

    final uploadUrl = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );
    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;

    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: picked.name,
      );
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
      ..fields['folder'] = 'eleaguehub/users'
      ..fields['public_id'] = 'user_avatar_$ts'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
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

  Future<void> _pickAndUploadAvatar(BuildContext context) async {
    if (_uploadingAvatar) return;
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (context.mounted) context.go('/login');
      return;
    }

    setState(() => _uploadingAvatar = true);

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 6));

      final pickResult = await SafeImagePicker.pickImage();

      if (pickResult.wasCancelled) return;

      if (!pickResult.isSuccess) {
        if (!context.mounted) return;
        _snack(
          context,
          pickResult.errorMessage ?? 'Could not pick image.',
        );
        return;
      }

      final picked = pickResult.file!;

      if (picked.size > _maxBytes) {
        if (!context.mounted) return;
        _snack(
          context,
          'Image too large. Please select an image under 5 MB.',
        );
        return;
      }

      final secureUrl = await _uploadToCloudinary(picked: picked);

      final now = DateTime.now().millisecondsSinceEpoch;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
        <String, dynamic>{
          'photoUrl': secureUrl,
          'profileImageUrl': secureUrl,
          'teamImageUrl': secureUrl,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));

      try {
        await FirebaseAuth.instance.currentUser
            ?.updatePhotoURL(secureUrl);
      } catch (_) {}

      if (!context.mounted) return;
      _snack(context, context.l10n.tr('common_done'));
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      _snack(context, UserFriendlyError.toMessage(e));
    } catch (e) {
      if (!context.mounted) return;
      _snack(
        context,
        UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _clearAvatar(BuildContext context) async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (context.mounted) context.go('/login');
      return;
    }

    final brightness = Theme.of(context).brightness;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Glass(
            borderRadius: 26,
            padding: const EdgeInsets.all(18),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Theme.of(ctx)
                              .colorScheme
                              .error
                              .withOpacity(0.10),
                          border: Border.all(
                            color: Theme.of(ctx)
                                .colorScheme
                                .error
                                .withOpacity(0.25),
                          ),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Theme.of(ctx).colorScheme.error,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Remove photo?',
                          style: Theme.of(ctx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color:
                                    AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(false),
                        icon: Icon(
                          Icons.close,
                          color:
                              AppTheme.secondaryText(brightness),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'This will remove your profile/team photo.',
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(ctx).colorScheme.error,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              Navigator.of(ctx).pop(true),
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirm != true) return;

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 6));

      final now = DateTime.now().millisecondsSinceEpoch;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
        <String, dynamic>{
          'photoUrl': '',
          'profileImageUrl': '',
          'teamImageUrl': '',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));

      try {
        await FirebaseAuth.instance.currentUser
            ?.updatePhotoURL(null);
      } catch (_) {}

      if (!context.mounted) return;
      _snack(context, 'Removed.');
    } catch (e) {
      if (!context.mounted) return;
      _snack(
        context,
        UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        ),
      );
    }
  }

  Future<void> _showCouponConfigSheet(
    BuildContext context, {
    required String leagueId,
    required String leagueName,
  }) async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (context.mounted) context.go('/login');
      return;
    }

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
    } catch (e) {
      if (context.mounted) {
        _snack(
          context,
          UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown'),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final brightness = theme.brightness;

        final cfgStream =
            CouponConfigService().watchConfig(leagueId);
        final redemptionsQuery = FirebaseFirestore.instance
            .collection('leagues')
            .doc(leagueId)
            .collection('couponRedemptions')
            .orderBy('paidAtMs', descending: true)
            .limit(150);

        String money(double v) {
          final r = double.parse(v.toStringAsFixed(2));
          final i = r.toInt();
          if ((r - i).abs() < 0.000001) return '$i';
          return r.toStringAsFixed(2);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Glass(
                  borderRadius: 28,
                  padding: EdgeInsets.zero,
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin:
                              const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBorder(brightness),
                            borderRadius:
                                BorderRadius.circular(2),
                          ),
                        ),
                        Text(
                          'Coupons',
                          style:
                              theme.textTheme.titleMedium?.copyWith(
                            color:
                                AppTheme.primaryText(brightness),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          leagueName,
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                            color:
                                AppTheme.secondaryText(brightness),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<CouponConfig?>(
                          stream: cfgStream,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              final msg =
                                  UserFriendlyError.toMessage(
                                snap.error as Object,
                              );
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  msg,
                                  style: theme
                                      .textTheme.bodyMedium
                                      ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }

                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Center(
                                  child:
                                      CircularProgressIndicator(
                                    color:
                                        AppTheme.limeAccentDark,
                                  ),
                                ),
                              );
                            }

                            final cfg = snap.data;
                            if (cfg == null) {
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      'No coupon configuration yet.',
                                      textAlign: TextAlign.center,
                                      style: theme
                                          .textTheme.bodySmall
                                          ?.copyWith(
                                        color:
                                            AppTheme.secondaryText(
                                          brightness,
                                        ),
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child:
                                            OutlinedButton.icon(
                                          onPressed: () =>
                                              Navigator.of(ctx)
                                                  .pop(),
                                          icon: const Icon(
                                              Icons.close),
                                          label: const Text(
                                              'Close'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          style:
                                              FilledButton.styleFrom(
                                            backgroundColor:
                                                AppTheme.limeAccent,
                                            foregroundColor:
                                                AppTheme.darkText,
                                          ),
                                          onPressed: () {
                                            Navigator.of(ctx).pop();
                                            GoRouter.of(context)
                                                .push(
                                              '/leagues/$leagueId/upgrade/payment',
                                              extra: {
                                                'leagueId':
                                                    leagueId,
                                                'leagueName':
                                                    leagueName,
                                                'addonsOnly': true,
                                                'existingCouponsEnabled':
                                                    false,
                                                'existingCouponCount':
                                                    0,
                                                'existingCouponDiscountPercent':
                                                    0,
                                              },
                                            );
                                          },
                                          icon: const Icon(
                                            Icons
                                                .add_shopping_cart,
                                          ),
                                          label: const Text(
                                              'Buy / enable'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }

                            final redeemed = cfg.qtyRedeemed;
                            final usersPay =
                                (100 - cfg.discountPercent)
                                    .clamp(0, 100);

                            return Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _kv(context, 'Currency',
                                    cfg.currency),
                                _kv(
                                  context,
                                  'Unit price',
                                  '${money(cfg.unitPrice)} ${cfg.currency}',
                                ),
                                _kv(
                                  context,
                                  'Effective unit',
                                  '${money(cfg.effectiveUnit)} ${cfg.currency}',
                                ),
                                _kv(
                                  context,
                                  'Threshold',
                                  cfg.threshold == null
                                      ? '—'
                                      : '${money(cfg.threshold!)} ${cfg.currency}',
                                ),
                                _kv(
                                  context,
                                  'Threshold discount',
                                  '${money(cfg.thresholdDiscountPercent)}%',
                                ),
                                Divider(
                                    color: AppTheme.cardBorder(
                                        brightness)),
                                _kv(
                                  context,
                                  'Discount',
                                  '${cfg.discountPercent}%',
                                ),
                                _kv(context, 'Users pay',
                                    '$usersPay%'),
                                Divider(
                                    color: AppTheme.cardBorder(
                                        brightness)),
                                _kv(context, 'Purchased',
                                    '${cfg.qtyTotal}'),
                                _kv(context, 'Remaining',
                                    '${cfg.qtyRemaining}'),
                                _kv(context, 'Redeemed',
                                    '$redeemed'),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            Navigator.of(ctx)
                                                .pop(),
                                        icon:
                                            const Icon(Icons.close),
                                        label:
                                            const Text('Close'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        style:
                                            FilledButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.limeAccent,
                                          foregroundColor:
                                              AppTheme.darkText,
                                        ),
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          GoRouter.of(context)
                                              .push(
                                            '/leagues/$leagueId/upgrade/payment',
                                            extra: {
                                              'leagueId': leagueId,
                                              'leagueName':
                                                  leagueName,
                                              'addonsOnly': true,
                                              'existingCouponsEnabled':
                                                  true,
                                              'existingCouponCount':
                                                  cfg.qtyTotal,
                                              'existingCouponDiscountPercent':
                                                  cfg.discountPercent,
                                            },
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.add_shopping_cart,
                                        ),
                                        label:
                                            const Text('Buy more'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Recent redemptions',
                                  style: theme
                                      .textTheme.bodyMedium
                                      ?.copyWith(
                                    color: AppTheme.primaryText(
                                        brightness),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(
                                    maxHeight: 320,
                                  ),
                                  child: StreamBuilder<
                                      QuerySnapshot<
                                          Map<String, dynamic>>>(
                                    stream: redemptionsQuery
                                        .snapshots(),
                                    builder: (context, rs) {
                                      if (rs.hasError) {
                                        return Center(
                                          child: Text(
                                            UserFriendlyError
                                                .toMessage(
                                              rs.error as Object,
                                            ),
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                              fontWeight:
                                                  FontWeight.w700,
                                            ),
                                            textAlign:
                                                TextAlign.center,
                                          ),
                                        );
                                      }
                                      if (!rs.hasData) {
                                        return Center(
                                          child:
                                              CircularProgressIndicator(
                                            color: AppTheme
                                                .limeAccentDark,
                                          ),
                                        );
                                      }
                                      final docs =
                                          rs.data!.docs;
                                      if (docs.isEmpty) {
                                        return Center(
                                          child: Text(
                                            'No redemptions yet.',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color:
                                                  AppTheme.secondaryText(
                                                brightness,
                                              ),
                                              fontWeight:
                                                  FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }
                                      return ListView.separated(
                                        itemCount: docs.length,
                                        separatorBuilder:
                                            (_, __) => Divider(
                                          color:
                                              AppTheme.cardBorder(
                                                  brightness),
                                        ),
                                        itemBuilder:
                                            (context, i) {
                                          final d =
                                              docs[i].data();
                                          final status =
                                              (d['status']
                                                      as String?) ??
                                                  'pending';
                                          final paidAtMs =
                                              (d['paidAtMs']
                                                          as num?)
                                                      ?.toInt() ??
                                                  0;
                                          final provider =
                                              (d['provider']
                                                      as String?) ??
                                                  '';
                                          final expected =
                                              (d['expectedAmount']
                                                          as num?)
                                                      ?.toDouble() ??
                                                  0.0;
                                          final currency =
                                              (d['currency']
                                                      as String?) ??
                                                  cfg.currency;
                                          final isPaid =
                                              status == 'paid';
                                          final when = paidAtMs > 0
                                              ? DateTime
                                                      .fromMillisecondsSinceEpoch(
                                                          paidAtMs)
                                                  .toLocal()
                                                  .toString()
                                              : '—';
                                          final shortUserId =
                                              ((d['shareId']
                                                              as String?) ??
                                                          '')
                                                      .trim()
                                                      .isNotEmpty
                                                  ? (d['shareId']
                                                          as String)
                                                      .trim()
                                                  : UserProfile
                                                      .deriveShareIdFromUid(
                                                      (d['userId']
                                                              as String?) ??
                                                          '',
                                                    );

                                          return ListTile(
                                            dense: true,
                                            contentPadding:
                                                EdgeInsets.zero,
                                            leading: Icon(
                                              isPaid
                                                  ? Icons.verified
                                                  : Icons.pending,
                                              color: isPaid
                                                  ? const Color(
                                                      0xFF22C55E)
                                                  : AppTheme
                                                      .limeAccentDark,
                                              size: 20,
                                            ),
                                            title: Text(
                                              shortUserId.isEmpty
                                                  ? '(unknown user)'
                                                  : shortUserId,
                                              style: theme.textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                color: AppTheme
                                                    .primaryText(
                                                  brightness,
                                                ),
                                                fontWeight:
                                                    FontWeight.w900,
                                              ),
                                            ),
                                            subtitle: Text(
                                              isPaid
                                                  ? 'Paid • $provider • $when'
                                                  : 'Pending • ${money(expected)} $currency',
                                              style: theme.textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                color: AppTheme
                                                    .secondaryText(
                                                  brightness,
                                                ),
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                            trailing: IconButton(
                                              tooltip:
                                                  'Copy short id',
                                              icon: Icon(
                                                Icons.copy,
                                                color: AppTheme
                                                    .secondaryText(
                                                  brightness,
                                                ),
                                                size: 18,
                                              ),
                                              onPressed:
                                                  shortUserId.isEmpty
                                                      ? null
                                                      : () async {
                                                          await Clipboard
                                                              .setData(
                                                            ClipboardData(
                                                              text:
                                                                  shortUserId,
                                                            ),
                                                          );
                                                          if (!context
                                                              .mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger
                                                              .of(context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                              content:
                                                                  Text(
                                                                'Copied: $shortUserId',
                                                              ),
                                                            ),
                                                          );
                                                        },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDesktopScanner(BuildContext context) async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (context.mounted) context.go('/login');
      return;
    }

    if (kIsWeb) {
      if (!context.mounted) return;
      _snack(
        context,
        'Need to link your desktop? Visit esportlyic.web.app on '
        'your computer and scan the displayed QR code.',
      );
      return;
    }

    if (!context.mounted) return;
    context.push('/leagues/join-scanner');
  }

  String _readProfileImageUrl(
    UserProfile? profile,
    User? authUser,
  ) {
    String url = '';
    try {
      final dyn = profile as dynamic;
      final v1 = (dyn.photoUrl as String?) ?? '';
      if (v1.trim().isNotEmpty) url = v1.trim();
    } catch (_) {}
    if (url.isEmpty) {
      try {
        final dyn = profile as dynamic;
        final v2 = (dyn.profileImageUrl as String?) ?? '';
        if (v2.trim().isNotEmpty) url = v2.trim();
      } catch (_) {}
    }
    if (url.isEmpty) {
      try {
        final dyn = profile as dynamic;
        final v3 = (dyn.teamImageUrl as String?) ?? '';
        if (v3.trim().isNotEmpty) url = v3.trim();
      } catch (_) {}
    }
    if (url.isEmpty) {
      url = (authUser?.photoURL ?? '').trim();
    }
    return url;
  }

  // ── Badge display ─────────────────────────────────────────────────────────

  Widget _verificationBadge(
    BuildContext context,
    UserProfile? profile,
  ) {
    if (profile == null) return const SizedBox.shrink();

    final badges = profile.verificationBadges;
    final icons = <Widget>[];

    // 1. Staff / Ambassador badge
    if (badges.isStaffActive) {
      icons.add(
        const Tooltip(
          message: 'Staff / Ambassador',
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.shield_rounded,
              size: 18,
              color: Color(0xFF7C3AED), // deep purple
            ),
          ),
        ),
      );
    }

    // 2. Gold Organizer badge
    if (badges.isOrganizerActive) {
      icons.add(
        const Tooltip(
          message: 'Official Tournament Organizer',
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.verified_rounded,
              size: 18,
              color: Color(0xFFFFB300), // amber / gold
            ),
          ),
        ),
      );
    }

    // 3. Green verified badge (from new badge system)
    if (badges.isGreenActive) {
      icons.add(
        const Tooltip(
          message: 'Verified User',
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.verified_rounded,
              size: 18,
              color: Color(0xFF00C853), // app green accent
            ),
          ),
        ),
      );
    } else if (!badges.isGreenActive &&
        badges.greenSource == null) {
      // 4. Legacy isVerified fallback
      if (profile.verifiedActive) {
        icons.add(
          const Tooltip(
            message: 'Verified account',
            child: Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.verified_rounded,
                size: 18,
                color: Color(0xFF1D9BF0), // legacy blue
              ),
            ),
          ),
        );
      } else if (profile.verificationPending) {
        // 5. Pending verification
        icons.add(
          const Tooltip(
            message: 'Verification pending',
            child: Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.verified_outlined,
                size: 18,
                color: Color(0xFFF59E0B), // amber
              ),
            ),
          ),
        );
      }
    }

    if (icons.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons,
    );
  }

  @override
  Widget build(BuildContext context) {
    unawaited(ConnectivityService.instance.initialize());

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final brightness = theme.brightness;

    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();

    final isSuperAdmin = uid == _superAdminUid;

    if (uid.isNotEmpty) {
      AppAdminsService.instance.ensureStarted();
    }

    final themeState = ref.watch(themeControllerProvider);

    final isPricingAdmin =
        AppAdminsService.instance.isPricingAdminUid(uid);

    final repo = UserProfileRepository();

    final muted = AppTheme.secondaryText(brightness);
    final faint = AppTheme.cardBorder(brightness);

    return GlassScaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(
                16,
                12,
                16,
                110,
              ),
              children: [
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 28,
                  padding: const EdgeInsets.all(18),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: StreamBuilder<UserProfile?>(
                    stream: uid.isEmpty
                        ? const Stream<UserProfile?>.empty()
                        : repo.watchByUserId(uid),
                    builder: (context, snap) {
                      final profile = snap.data;

                      final teamName = (profile != null &&
                              profile.teamName.trim().isNotEmpty)
                          ? profile.teamName.trim()
                          : (user?.displayName ??
                              l10n.tr(
                                  'profile_team_placeholder'));

                      final shortUserId = (profile != null)
                          ? profile.effectiveShareId
                          : (uid.isEmpty
                              ? ''
                              : UserProfile
                                  .deriveShareIdFromUid(uid));

                      // ── Username system: display + lazy assignment ──
                      final usernameLower =
                          profile?.usernameLower.trim() ?? '';
                      final usernameDisplayValue = usernameLower.isEmpty
                          ? ''
                          : UsernameUtils.toDisplay(usernameLower);

                      if (uid.isNotEmpty &&
                          profile != null &&
                          usernameLower.isEmpty &&
                          !_usernameEnsureTriggered) {
                        _usernameEnsureTriggered = true;
                        unawaited(repo.ensureUsernameIfMissing());
                      }
                      // ─────────────────────────────────────────────────

                      final rawAvatarUrl =
                          _readProfileImageUrl(profile, user);
                      final avatarUrl =
                          rawAvatarUrl.isNotEmpty &&
                                  _looksLikeHttpUrl(rawAvatarUrl)
                              ? _cloudinaryOptimizedUrl(
                                  rawAvatarUrl,
                                  width: 256,
                                  height: 256,
                                  crop: 'fill',
                                )
                              : rawAvatarUrl;

                      return Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow:
                                      AppTheme.fabGlow(brightness),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    InkWell(
                                      borderRadius:
                                          BorderRadius.circular(
                                              999),
                                      onTap: uid.isEmpty
                                          ? null
                                          : () =>
                                              _pickAndUploadAvatar(
                                                  context),
                                      onLongPress: uid.isEmpty
                                          ? null
                                          : () =>
                                              _clearAvatar(context),
                                      child: CircleAvatar(
                                        radius: 34,
                                        backgroundColor: AppTheme
                                            .iconCircleBackground(
                                                brightness),
                                        child: ClipOval(
                                          child: SizedBox(
                                            width: 68,
                                            height: 68,
                                            child: (avatarUrl
                                                        .trim()
                                                        .isNotEmpty &&
                                                    _looksLikeHttpUrl(
                                                        avatarUrl))
                                                ? Image.network(
                                                    avatarUrl,
                                                    fit: BoxFit
                                                        .cover,
                                                    gaplessPlayback:
                                                        true,
                                                    filterQuality:
                                                        FilterQuality
                                                            .low,
                                                    errorBuilder:
                                                        (_, __, ___) =>
                                                            const Icon(
                                                      Icons.person,
                                                      color: AppTheme
                                                          .darkText,
                                                      size: 30,
                                                    ),
                                                    loadingBuilder:
                                                        (context,
                                                            child,
                                                            event) {
                                                      if (event ==
                                                          null) {
                                                        return child;
                                                      }
                                                      return const Icon(
                                                        Icons.person,
                                                        color: AppTheme
                                                            .darkText,
                                                        size: 30,
                                                      );
                                                    },
                                                  )
                                                : const Icon(
                                                    Icons.person,
                                                    color: AppTheme
                                                        .darkText,
                                                    size: 30,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_uploadingAvatar)
                                      const Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color:
                                                Color(0x66000000),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: AnimatedSwitcher(
                                            duration:
                                                const Duration(
                                              milliseconds: 200,
                                            ),
                                            child: Row(
                                              key: ValueKey(
                                                '${teamName}_'
                                                '${profile?.isVerified}_'
                                                '${profile?.verificationStatus}_'
                                                '${profile?.verificationBadges.isGreenActive}_'
                                                '${profile?.verificationBadges.isOrganizerActive}_'
                                                '${profile?.verificationBadges.isStaffActive}',
                                              ),
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    teamName,
                                                    style: t.titleLarge
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight
                                                              .w900,
                                                      fontSize: 20,
                                                      letterSpacing:
                                                          -0.3,
                                                      color: AppTheme
                                                          .primaryText(
                                                        brightness,
                                                      ),
                                                    ),
                                                    overflow:
                                                        TextOverflow
                                                            .ellipsis,
                                                  ),
                                                ),
                                                _verificationBadge(
                                                  context,
                                                  profile,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: l10n.tr(
                                            'profile_edit_team_name_tooltip',
                                          ),
                                          icon: Icon(
                                            Icons.edit_rounded,
                                            color: muted,
                                            size: 18,
                                          ),
                                          onPressed: uid.isEmpty
                                              ? null
                                              : () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  _editTeamName(
                                                    context,
                                                    userId: uid,
                                                    current: profile
                                                            ?.teamName ??
                                                        '',
                                                  );
                                                },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // ── Username row ─────────────────────
                                    Row(
                                      children: [
                                        Icon(
                                          Icons
                                              .alternate_email_rounded,
                                          size: 13,
                                          color: muted,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            uid.isEmpty
                                                ? ''
                                                : (usernameDisplayValue
                                                        .isEmpty
                                                    ? 'Setting up username…'
                                                    : usernameDisplayValue),
                                            style: TextStyle(
                                              color: muted,
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (uid.isNotEmpty)
                                          InkWell(
                                            borderRadius:
                                                BorderRadius
                                                    .circular(10),
                                            onTap: () {
                                              HapticFeedback
                                                  .selectionClick();
                                              _editUsername(
                                                context,
                                                userId: uid,
                                                current: usernameLower,
                                              );
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets
                                                      .all(6),
                                              child: Icon(
                                                Icons.edit_rounded,
                                                size: 14,
                                                color: muted,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    // ─────────────────────────────────────
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.tag_rounded,
                                          size: 13,
                                          color: muted,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            uid.isEmpty
                                                ? l10n.tr(
                                                    'profile_not_signed_in',
                                                  )
                                                : shortUserId,
                                            style: TextStyle(
                                              color: muted,
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                        InkWell(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10),
                                          onTap: uid.isEmpty
                                              ? null
                                              : () async {
                                                  HapticFeedback
                                                      .lightImpact();
                                                  await Clipboard
                                                      .setData(
                                                    ClipboardData(
                                                      text:
                                                          shortUserId,
                                                    ),
                                                  );
                                                  if (!context
                                                      .mounted) {
                                                    return;
                                                  }
                                                  _snack(
                                                    context,
                                                    l10n.tr(
                                                      'profile_userid_copied',
                                                    ),
                                                  );
                                                },
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.all(
                                                    6),
                                            child: Icon(
                                              Icons.copy_rounded,
                                              size: 16,
                                              color: muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(
                            color: AppTheme.cardBorder(brightness),
                            height: 1,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _ProfileActionChip(
                                  icon: Icons.person_search_rounded,
                                  label: 'Public View',
                                  onTap: () {
                                    if (uid.isEmpty) return;
                                    HapticFeedback.selectionClick();
                                    context.push('/profile/$uid');
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ProfileActionChip(
                                  icon: Icons.groups_rounded,
                                  label: 'My Squad',
                                  onTap: () {
                                    if (uid.isEmpty) return;
                                    HapticFeedback.selectionClick();
                                    context.push('/profile/$uid/squad');
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ProfileActionChip(
                                  icon: Icons.settings_rounded,
                                  label: 'Settings',
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    context.push('/profile/settings');
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                const SectionHeader('Desktop Web'),
                const SizedBox(height: 12),
                Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(6),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: _DesktopWebRow(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Link Desktop Web',
                    subtitle:
                        'Open the mobile QR scanner to pair with '
                        'eSportlyic Web at esportlyic.web.app.',
                    onTap: () => _openDesktopScanner(context),
                  ),
                ),
                const SizedBox(height: 18),
                const SectionHeader('Coupons'),
                const SizedBox(height: 12),
                if (uid.isEmpty)
                  Glass(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(18),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          color:
                              AppTheme.secondaryText(brightness),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sign in to view your coupons.',
                            style: TextStyle(
                              color:
                                  AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Glass(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(14),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: StreamBuilder<
                        QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('leagues')
                          .where('organizerUid', isEqualTo: uid)
                          .limit(25)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Text(
                            UserFriendlyError.toMessage(
                                snap.error as Object),
                            style: t.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }

                        if (!snap.hasData) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.limeAccentDark,
                            ),
                          );
                        }

                        final leagues = snap.data!.docs
                            .map((d) => <String, dynamic>{
                                  ...d.data(),
                                  'id': d.id,
                                })
                            .where((m) {
                              final enabled =
                                  (m['couponsEnabled'] == true ||
                                      m['couponsEnabled'] == 1);
                              if (!enabled) return false;
                              final dp =
                                  (m['couponDiscountPercent']
                                          as num?)
                                      ?.toInt() ??
                                      0;
                              return dp >= 0;
                            })
                            .toList();

                        if (leagues.isEmpty) {
                          return Row(
                            children: [
                              Icon(
                                Icons
                                    .confirmation_number_outlined,
                                color: AppTheme.secondaryText(
                                    brightness),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No coupons found. Enable coupons '
                                  'during league creation payment.',
                                  style: TextStyle(
                                    color:
                                        AppTheme.secondaryText(
                                            brightness),
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            for (final m in leagues) ...[
                              _OrganizerLeagueCouponsTile(
                                leagueName: (m['name']
                                        as String?) ??
                                    'League',
                                subtitle: _couponLeagueSubtitle(
                                  enabled: true,
                                  discountPercent:
                                      ((m['couponDiscountPercent']
                                                  as num?)
                                              ?.toInt() ??
                                          0),
                                ),
                                onView: () =>
                                    _showCouponConfigSheet(
                                  context,
                                  leagueId: (m['id']
                                          as String?) ??
                                      '',
                                  leagueName: (m['name']
                                          as String?) ??
                                      'League',
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 18),
                const SectionHeader('Legal'),
                const SizedBox(height: 12),
                Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(6),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    children: [
                      _LegalNavRow(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy Policy',
                        subtitle:
                            'How we collect, use, and protect '
                            'information.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const PrivacyPolicyScreen(),
                          ),
                        ),
                      ),
                      Divider(
                        color: AppTheme.cardBorder(brightness),
                        height: 1,
                      ),
                      _LegalNavRow(
                        icon: Icons.article_outlined,
                        title: 'Terms of Service',
                        subtitle:
                            'Rules and conditions for using the app.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const TermsOfServiceScreen(),
                          ),
                        ),
                      ),
                      Divider(
                        color: AppTheme.cardBorder(brightness),
                        height: 1,
                      ),
                      _LegalNavRow(
                        icon: Icons.support_agent_outlined,
                        title: 'Contact',
                        subtitle:
                            'Get help or report an issue.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ContactScreen(),
                          ),
                        ),
                      ),
                      Divider(
                        color: AppTheme.cardBorder(brightness),
                        height: 1,
                      ),
                      _LegalNavRow(
                        icon: Icons.link_outlined,
                        title: 'Affiliate Disclosure',
                        subtitle:
                            'How affiliate links work in the '
                            'marketplace.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const AffiliateDisclosureScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (isPricingAdmin || isSuperAdmin) ...[
                  const SectionHeader('Admin'),
                  const SizedBox(height: 12),
                  Glass(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(6),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Column(
                      children: [
                        // Super admin: the ONLY capability kept in this
                        // screen is approving Global Chat access
                        // requests. Everything else that used to live
                        // here — Rewards Fulfillment, Marketplace
                        // Upload, Staff/Ambassadors — has been removed
                        // per request.
                        if (isSuperAdmin) ...[
                          _AdminRow(
                            icon: Icons.forum_rounded,
                            title: 'Global Chat Requests',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const GlobalChatAdminRequestsScreen(),
                              ),
                            ),
                          ),
                          if (isPricingAdmin)
                            Divider(
                              color:
                                  AppTheme.cardBorder(brightness),
                              height: 1,
                            ),
                        ],
                        if (isPricingAdmin) ...[
                          _AdminRow(
                            icon: Icons.price_change_rounded,
                            title: 'Pricing (Quick Editor)',
                            onTap: () =>
                                showPricingQuickEditorSheet(
                                    context),
                          ),
                          Divider(
                            color: AppTheme.cardBorder(brightness),
                            height: 1,
                          ),
                          _AdminRow(
                            icon: Icons
                                .admin_panel_settings_rounded,
                            title: 'Pricing Admin',
                            onTap: () => GoRouter.of(context)
                                .push('/admin/pricing'),
                          ),
                          Divider(
                            color: AppTheme.cardBorder(brightness),
                            height: 1,
                          ),
                          _AdminRow(
                            icon: Icons.group_add_rounded,
                            title: 'Manage Pricing Admins',
                            onTap: () => GoRouter.of(context)
                                .push('/admin/pricing-admins'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Divider(color: faint)),
                    const SizedBox(width: 12),
                    Text(
                      'Profile',
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Divider(color: faint)),
                  ],
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTeamName(
    BuildContext context, {
    required String userId,
    required String current,
  }) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: current);
    final repo = UserProfileRepository();
    final brightness = Theme.of(context).brightness;

    try {
      final next = await showDialog<String?>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: Glass(
              borderRadius: 26,
              padding: const EdgeInsets.all(18),
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(14),
                            color: AppTheme.iconCircleBackground(
                                brightness),
                            border: Border.all(
                              color:
                                  AppTheme.cardBorder(brightness),
                            ),
                          ),
                          child: Icon(
                            Icons.edit_rounded,
                            color: AppTheme.limeAccentDark,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.tr(
                              'profile_edit_team_dialog_title',
                            ),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(
                              color: AppTheme.primaryText(
                                  brightness),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(null),
                          icon: Icon(
                            Icons.close,
                            color: AppTheme.secondaryText(
                                brightness),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.tr(
                            'profile_team_name_hint'),
                        hintStyle: TextStyle(
                          color: AppTheme.secondaryText(
                              brightness),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(null),
                            child: Text(
                                l10n.tr('common_cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  AppTheme.limeAccent,
                              foregroundColor:
                                  AppTheme.darkText,
                            ),
                            onPressed: () =>
                                Navigator.of(ctx).pop(
                                    controller.text.trim()),
                            child:
                                Text(l10n.tr('common_save')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (next == null) return;
      final cleaned = next.trim();
      if (cleaned.isEmpty) return;

      try {
        await ConnectivityService.instance
            .requireOnline(timeout: const Duration(seconds: 4));
        await repo.updateTeamName(
            userId: userId, teamName: cleaned);
      } catch (e) {
        if (context.mounted) {
          _snack(
            context,
            UserFriendlyError.toMessage(
              e is Object ? e : Exception('unknown'),
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              l10n.tr('profile_team_name_updated')),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  // ── Username editing dialog ────────────────────────────────────────────
  //
  // Mirrors _editTeamName's dialog shell exactly (same Glass/Dialog
  // chrome, same button row) but adds live debounced availability
  // checking via UserProfileRepository.isUsernameAvailable(), and saves
  // through the transactional UserProfileRepository.updateUsername().
  Future<void> _editUsername(
    BuildContext context, {
    required String userId,
    required String current,
  }) async {
    final repo = UserProfileRepository();
    final brightness = Theme.of(context).brightness;
    final controller = TextEditingController(text: current);

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);

          // Local state for this dialog only.
          _UsernameCheckState checkState = current.trim().isEmpty
              ? _UsernameCheckState.idle
              : _UsernameCheckState.idle;
          String? errorText;
          Timer? debounce;
          bool saving = false;

          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              void scheduleCheck(String raw) {
                debounce?.cancel();
                final candidate = raw.trim().toLowerCase();

                if (candidate == current.trim().toLowerCase()) {
                  setDialogState(() {
                    checkState = _UsernameCheckState.idle;
                    errorText = null;
                  });
                  return;
                }

                if (!UsernameUtils.isValidFormat(candidate)) {
                  setDialogState(() {
                    checkState = _UsernameCheckState.invalid;
                    errorText =
                        '${UsernameUtils.minLength}-${UsernameUtils.maxLength} '
                        'characters: lowercase letters, numbers, and _ only.';
                  });
                  return;
                }

                if (UsernameUtils.isReserved(candidate)) {
                  setDialogState(() {
                    checkState = _UsernameCheckState.taken;
                    errorText = 'That username is reserved.';
                  });
                  return;
                }

                setDialogState(() {
                  checkState = _UsernameCheckState.checking;
                  errorText = null;
                });

                debounce = Timer(
                  const Duration(milliseconds: 450),
                  () async {
                    try {
                      final available = await repo.isUsernameAvailable(
                        candidate,
                        forUserId: userId,
                      );
                      if (!ctx.mounted) return;
                      setDialogState(() {
                        checkState = available
                            ? _UsernameCheckState.available
                            : _UsernameCheckState.taken;
                        errorText =
                            available ? null : 'Username already taken.';
                      });
                    } catch (e) {
                      if (!ctx.mounted) return;
                      setDialogState(() {
                        checkState = _UsernameCheckState.error;
                        errorText = UserFriendlyError.toMessage(
                          e is Object ? e : Exception('unknown'),
                        );
                      });
                    }
                  },
                );
              }

              Widget statusLine() {
                switch (checkState) {
                  case _UsernameCheckState.checking:
                    return Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.limeAccentDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Checking availability…',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  case _UsernameCheckState.available:
                    return Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Username available',
                          style: TextStyle(
                            color: Color(0xFF22C55E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    );
                  case _UsernameCheckState.taken:
                  case _UsernameCheckState.invalid:
                  case _UsernameCheckState.error:
                    return Row(
                      children: [
                        Icon(
                          Icons.cancel_rounded,
                          size: 14,
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            errorText ?? 'Unavailable.',
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    );
                  case _UsernameCheckState.idle:
                    return const SizedBox.shrink();
                }
              }

              final canSave = !saving &&
                  (checkState == _UsernameCheckState.available ||
                      checkState == _UsernameCheckState.idle);

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.all(18),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: AppTheme.iconCircleBackground(
                                    brightness),
                                border: Border.all(
                                  color: AppTheme.cardBorder(brightness),
                                ),
                              ),
                              child: Icon(
                                Icons.alternate_email_rounded,
                                color: AppTheme.limeAccentDark,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Edit Username',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(ctx).pop(false),
                              icon: Icon(
                                Icons.close,
                                color: AppTheme.secondaryText(brightness),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !saving,
                          style: TextStyle(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            prefixText: '@',
                            hintText: 'yourusername',
                            hintStyle: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                            ),
                          ),
                          onChanged: scheduleCheck,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: statusLine(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.limeAccent,
                                  foregroundColor: AppTheme.darkText,
                                ),
                                onPressed: !canSave
                                    ? null
                                    : () async {
                                        final value =
                                            controller.text.trim().toLowerCase();
                                        if (value.isEmpty ||
                                            value == current.trim()) {
                                          Navigator.of(ctx).pop(false);
                                          return;
                                        }

                                        setDialogState(() => saving = true);
                                        try {
                                          await repo.updateUsername(value);
                                          if (!ctx.mounted) return;
                                          Navigator.of(ctx).pop(true);
                                        } catch (e) {
                                          setDialogState(() {
                                            saving = false;
                                            checkState =
                                                _UsernameCheckState.taken;
                                            errorText =
                                                UserFriendlyError.toMessage(
                                              e is Object
                                                  ? e
                                                  : Exception('unknown'),
                                            );
                                          });
                                        }
                                      },
                                child: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.darkText,
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                            ),
                          ],
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

      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username updated.')),
        );
      }
    } finally {
      controller.dispose();
    }
  }
}

/// Local-only state enum for the username-availability indicator inside
/// the edit dialog. Not persisted or shared elsewhere.
enum _UsernameCheckState { idle, checking, available, taken, invalid, error }

// ── Supporting widgets ────────────────────────────────────────────────────────

class _ProfileActionChip extends StatelessWidget {
  const _ProfileActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final color = isDestructive
        ? const Color(0xFFE53935)
        : AppTheme.limeAccentDark;
    final bg = isDestructive
        ? color.withOpacity(0.10)
        : AppTheme.searchBackground(brightness);
    final border = isDestructive
        ? color.withOpacity(0.20)
        : AppTheme.searchOutline(brightness);
    final fg =
        isDestructive ? color : AppTheme.limeAccentDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopWebRow extends StatelessWidget {
  const _DesktopWebRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isRtl =
        Directionality.of(context) == TextDirection.rtl;
    final chevron = isRtl
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppTheme.iconCircleBackground(brightness),
              ),
              child: Icon(
                icon,
                color: AppTheme.limeAccentDark,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(
                              brightness),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color:
                          AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              chevron,
              color: AppTheme.secondaryText(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalNavRow extends StatelessWidget {
  const _LegalNavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isRtl =
        Directionality.of(context) == TextDirection.rtl;
    final chevron = isRtl
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppTheme.iconCircleBackground(brightness),
              ),
              child: Icon(
                icon,
                color: AppTheme.limeAccentDark,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(
                              brightness),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color:
                          AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              chevron,
              color: AppTheme.secondaryText(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isRtl =
        Directionality.of(context) == TextDirection.rtl;
    final chevron = isRtl
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppTheme.iconCircleBackground(brightness),
              ),
              child: Icon(
                icon,
                color: AppTheme.limeAccentDark,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                      fontWeight: FontWeight.w900,
                      color:
                          AppTheme.primaryText(brightness),
                    ),
              ),
            ),
            Icon(
              chevron,
              color: AppTheme.secondaryText(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrganizerLeagueCouponsTile extends StatelessWidget {
  const _OrganizerLeagueCouponsTile({
    required this.leagueName,
    required this.subtitle,
    required this.onView,
  });

  final String leagueName;
  final String subtitle;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Glass(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.iconCircleBackground(brightness),
            ),
            child: Icon(
              Icons.confirmation_number_rounded,
              color: AppTheme.limeAccentDark,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leagueName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                        fontWeight: FontWeight.w900,
                        color:
                            AppTheme.primaryText(brightness),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: onView,
            child: const Text('View'),
          ),
        ],
      ),
    );
  }
}