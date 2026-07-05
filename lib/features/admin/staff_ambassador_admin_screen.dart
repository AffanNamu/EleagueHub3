// lib/features/admin/staff_ambassador_admin_screen.dart
//
// SUPER-ADMIN ONLY screen for granting/revoking the purple Staff /
// Ambassador badge (Icons.shield_rounded, deep purple) to any user by
// their Firebase UID. Access is restricted at the router level to the
// hardcoded super-admin UID — see app_router.dart's redirect logic for
// the '/admin/staff-ambassadors' route.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/user_friendly_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import '../auth/data/user_profile_repository.dart';
import '../auth/models/user_profile.dart';
import '../verification/logic/badge_service.dart';

const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

class StaffAmbassadorAdminScreen extends StatefulWidget {
  const StaffAmbassadorAdminScreen({super.key});

  @override
  State<StaffAmbassadorAdminScreen> createState() =>
      _StaffAmbassadorAdminScreenState();
}

class _StaffAmbassadorAdminScreenState
    extends State<StaffAmbassadorAdminScreen> {
  final TextEditingController _uidController = TextEditingController();
  final UserProfileRepository _profileRepo = UserProfileRepository();

  bool _granting = false;
  String? _error;

  List<String> _staffUserIds = const <String>[];
  Map<String, UserProfile> _profilesById = const <String, UserProfile>{};
  bool _loadingRoster = true;
  String? _rosterError;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
        content: Text(message),
      ),
    );
  }

  Future<void> _loadRoster() async {
    setState(() {
      _loadingRoster = true;
      _rosterError = null;
    });

    try {
      final ids = await BadgeService.instance.listStaffUserIds();
      final profiles = await _profileRepo.fetchByUserIds(ids);

      if (!mounted) return;
      setState(() {
        _staffUserIds = ids;
        _profilesById = profiles;
        _loadingRoster = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRoster = false;
        _rosterError = UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        );
      });
    }
  }

  Future<void> _grantByUid() async {
    if (_granting) return;

    final rawUid = _uidController.text.trim();
    if (rawUid.isEmpty) {
      setState(() => _error = 'Please enter a user UID.');
      return;
    }
    if (!_looksLikeFirebaseUid(rawUid)) {
      setState(() => _error =
          'That doesn\'t look like a valid Firebase UID. '
          'Copy it exactly from the user\'s profile.');
      return;
    }
    if (rawUid == _superAdminUid) {
      setState(() =>
          _error = 'You are already the super admin — no badge needed.');
      return;
    }

    setState(() {
      _granting = true;
      _error = null;
    });

    try {
      // Confirm the user actually exists before granting, so we never
      // silently create a badge on a document that doesn't correspond
      // to a real account.
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(rawUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (!doc.exists) {
        setState(() {
          _granting = false;
          _error = 'No user found with that UID. Double-check it and '
              'try again.';
        });
        return;
      }

      await BadgeService.instance.adminGrantStaffBadge(rawUid);

      if (!mounted) return;
      _uidController.clear();
      _snack('Staff / Ambassador badge granted.');
      await _loadRoster();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        );
      });
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  Future<void> _revoke(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final brightness = Theme.of(ctx).brightness;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Glass(
            borderRadius: 24,
            padding: const EdgeInsets.all(18),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.remove_moderator_rounded,
                  color: Theme.of(ctx).colorScheme.error,
                  size: 34,
                ),
                const SizedBox(height: 10),
                Text(
                  'Revoke Staff / Ambassador badge?',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This user will immediately lose the purple '
                  'verification badge.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Revoke'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    try {
      await BadgeService.instance.adminRevokeStaffBadge(userId);
      if (!mounted) return;
      _snack('Badge revoked.');
      await _loadRoster();
    } catch (e) {
      if (!mounted) return;
      _snack(
        UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        ),
        error: true,
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) return;
    _uidController.text = text;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    // Defense in depth: even though the router already restricts this
    // route to the super admin, refuse to render the screen's actions
    // for anyone else who somehow lands here.
    final isAuthorized = currentUid == _superAdminUid;

    if (!isAuthorized) {
      return GlassScaffold(
        appBar: AppBar(
          title: const Text('Staff / Ambassadors'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'You don\'t have access to this screen.',
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Staff / Ambassadors'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadingRoster ? null : _loadRoster,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.all(18),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF7C3AED)
                                  .withOpacity(0.14),
                              border: Border.all(
                                color: const Color(0xFF7C3AED)
                                    .withOpacity(0.28),
                              ),
                            ),
                            child: const Icon(
                              Icons.shield_rounded,
                              color: Color(0xFF7C3AED),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Grant Staff / Ambassador Badge',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter the Firebase UID of the user you want to '
                        'make a staff member or ambassador. They\'ll get '
                        'the purple shield badge shown next to their name '
                        'app-wide.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _uidController,
                        enabled: !_granting,
                        decoration: InputDecoration(
                          labelText: 'User UID',
                          hintText: 'e.g. a0JDUelQW3TEyoXTm4ESuGi7ndq1',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'Paste',
                            icon: const Icon(Icons.paste_rounded),
                            onPressed: _granting ? null : _pasteFromClipboard,
                          ),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        onSubmitted: (_) => _grantByUid(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.colorScheme.error.withOpacity(0.25),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _granting ? null : _grantByUid,
                          icon: _granting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.shield_rounded),
                          label: Text(
                            _granting ? 'Granting...' : 'Grant Badge',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'Current Staff / Ambassadors',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                ),
                if (_loadingRoster)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_rosterError != null)
                  Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Text(
                      _rosterError!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (_staffUserIds.isEmpty)
                  Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.secondaryText(brightness),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No staff or ambassadors yet.',
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...List.generate(_staffUserIds.length, (i) {
                    final id = _staffUserIds[i];
                    final profile = _profilesById[id];
                    final displayName = profile != null &&
                            profile.displayName.trim().isNotEmpty
                        ? profile.displayName.trim()
                        : id;
                    final shareId = profile?.effectiveShareId ?? '';

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == _staffUserIds.length - 1 ? 0 : 10,
                      ),
                      child: Glass(
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
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF7C3AED)
                                    .withOpacity(0.14),
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                color: Color(0xFF7C3AED),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.primaryText(brightness),
                                    ),
                                  ),
                                  if (shareId.isNotEmpty)
                                    Text(
                                      shareId,
                                      style: TextStyle(
                                        color: AppTheme.secondaryText(
                                            brightness),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Revoke',
                              icon: Icon(
                                Icons.remove_circle_outline_rounded,
                                color: theme.colorScheme.error,
                              ),
                              onPressed: () => _revoke(id),
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
      ),
    );
  }
}