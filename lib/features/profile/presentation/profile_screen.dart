import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/routing/league_mode_provider.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/league_switcher.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final t = Theme.of(context).textTheme;
    final themeState = ref.watch(themeControllerProvider);
    final currentLeague = ref.watch(leagueModeProvider);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    final repo = UserProfileRepository();

    return GlassScaffold(
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
        children: [
          const SizedBox(height: 56),
          Text(
            l10n.tr('profile_title'),
            style: t.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.tr('profile_subtitle'),
            style: t.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),

          /// USER CARD
          Glass(
            padding: const EdgeInsets.all(14),
            child: StreamBuilder<UserProfile?>(
              stream: uid.isEmpty ? const Stream<UserProfile?>.empty() : repo.watchByUserId(uid),
              builder: (context, snap) {
                final profile = snap.data;

                final teamName = (profile != null && profile.teamName.trim().isNotEmpty)
                    ? profile.teamName.trim()
                    : (user?.displayName ?? l10n.tr('profile_team_placeholder'));

                final shortUserId = (profile != null)
                    ? profile.effectiveShareId
                    : (uid.isEmpty ? '' : UserProfile.deriveShareIdFromUid(uid));

                return Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.85),
                        child: const Icon(Icons.person, color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Text(
                                    teamName,
                                    key: ValueKey(teamName),
                                    style: t.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.tr('profile_edit_team_name_tooltip'),
                                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                                onPressed: uid.isEmpty
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        _editTeamName(
                                          context,
                                          userId: uid,
                                          current: profile?.teamName ?? '',
                                        );
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  uid.isEmpty ? l10n.tr('profile_not_signed_in') : '${l10n.tr('profile_userid_prefix')} $shortUserId',
                                  style: t.bodySmall?.copyWith(color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.tr('profile_copy_userid_tooltip'),
                                icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
                                onPressed: uid.isEmpty
                                    ? null
                                    : () async {
                                        HapticFeedback.lightImpact();
                                        await Clipboard.setData(ClipboardData(text: shortUserId));
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(l10n.tr('profile_userid_copied'))),
                                        );
                                      },
                              ),
                            ],
                          ),
                          if (uid.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${l10n.tr('profile_internal_uid_debug_prefix')} ${uid.length > 10 ? '${uid.substring(0, 10)}…' : uid}',
                              style: t.bodySmall?.copyWith(color: Colors.white38, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    /// THEME TOGGLE
                    IconButton(
                      tooltip: l10n.tr('profile_toggle_theme_tooltip'),
                      icon: Icon(
                        themeState.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                        color: Colors.cyanAccent,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        ref.read(themeControllerProvider.notifier).toggleTheme();
                      },
                    ),

                    /// LOGOUT (WITH GLASS WARNING)
                    IconButton(
                      tooltip: l10n.tr('profile_logout_tooltip'),
                      icon: const Icon(Icons.logout, color: Colors.white70),
                      onPressed: () async {
                        final ok = await _confirmLogout(context);
                        if (!ok) return;

                        // --- DO NOT CHANGE LOGIC BELOW ---
                        final prefs = ref.read(prefsServiceProvider);
                        await AuthService().signOut();
                        await prefs.clearCurrentUserId();
                        if (!context.mounted) return;
                        context.go('/login');
                      },
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 22),

          /// LEAGUE MODE SWITCHER (APP STANDARD)
          const LeagueSwitcher(),

          const SizedBox(height: 22),

          /// STATS
          SectionHeader(l10n.tr('profile_section_league_overview')),
          const SizedBox(height: 12),

          Glass(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: _Stat(label: l10n.tr('profile_stat_active'), value: '2')),
                const SizedBox(width: 12),
                Expanded(child: _Stat(label: l10n.tr('profile_stat_teams'), value: '16')),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    label: l10n.tr('profile_stat_format'),
                    value: currentLeague.name.toUpperCase().replaceAll('CLASSIC', 'CL').replaceAll('SWISS', 'SW'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final l10n = context.l10n;
    final t = Theme.of(context).textTheme;

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Glass(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withOpacity(0.35)),
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.tr('profile_logout_dialog_title'),
                          style: t.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tr('profile_close_tooltip'),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.tr('profile_logout_dialog_message'),
                      style: t.bodyMedium?.copyWith(color: Colors.white70, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.18)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(l10n.tr('common_cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(l10n.tr('profile_logout_button')),
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

    return res ?? false;
  }

  Future<void> _editTeamName(
    BuildContext context, {
    required String userId,
    required String current,
  }) async {
    final l10n = context.l10n;

    final controller = TextEditingController(text: current);
    final repo = UserProfileRepository();

    try {
      final next = await showDialog<String?>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1D37),
            title: Text(
              l10n.tr('profile_edit_team_dialog_title'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: l10n.tr('profile_team_name_hint'),
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(
                  l10n.tr('common_cancel'),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: Text(l10n.tr('common_save')),
              ),
            ],
          );
        },
      );

      if (next == null) return;
      if (next.isEmpty) return;

      await repo.updateTeamName(userId: userId, teamName: next);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('profile_team_name_updated'))),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Glass(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: t.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: t.bodySmall?.copyWith(color: Colors.white60),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
