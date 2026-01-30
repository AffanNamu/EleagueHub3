import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final t = Theme.of(context).textTheme;
    final themeState = ref.watch(themeControllerProvider);
    final currentLeague = ref.watch(leagueModeProvider);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    final repo = UserProfileRepository();

    return GlassScaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),

          /// USER CARD
          Glass(
            child: StreamBuilder<UserProfile?>(
              stream: uid.isEmpty ? const Stream<UserProfile?>.empty() : repo.watchByUserId(uid),
              builder: (context, snap) {
                final profile = snap.data;
                final teamName = profile?.teamName.isNotEmpty == true ? profile!.teamName : (user?.displayName ?? 'My Team');

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                      child: const Icon(Icons.person, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  teamName,
                                  style: t.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit team name',
                                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                                onPressed: uid.isEmpty
                                    ? null
                                    : () => _editTeamName(
                                          context,
                                          userId: uid,
                                          current: profile?.teamName ?? '',
                                        ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  uid.isEmpty ? 'Not signed in' : 'userId: $uid',
                                  style: t.bodySmall?.copyWith(color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy userId',
                                icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
                                onPressed: uid.isEmpty
                                    ? null
                                    : () async {
                                        await Clipboard.setData(ClipboardData(text: uid));
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('userId copied')),
                                        );
                                      },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    /// THEME TOGGLE
                    IconButton(
                      icon: Icon(
                        themeState.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                        color: Colors.cyanAccent,
                      ),
                      onPressed: () => ref.read(themeControllerProvider.notifier).toggleTheme(),
                    ),

                    /// LOGOUT
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white70),
                      onPressed: () async {
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

          const SizedBox(height: 24),

          /// LEAGUE MODE SWITCHER (APP STANDARD)
          const LeagueSwitcher(),

          const SizedBox(height: 24),

          /// STATS
          const SectionHeader('League Overview'),

          const SizedBox(height: 12),

          Glass(
            child: Row(
              children: [
                const Expanded(
                  child: _Stat(label: 'Active', value: '2'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: _Stat(label: 'Teams', value: '16'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    label: 'Format',
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

  Future<void> _editTeamName(
    BuildContext context, {
    required String userId,
    required String current,
  }) async {
    final controller = TextEditingController(text: current);
    final repo = UserProfileRepository();

    try {
      final next = await showDialog<String?>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1D37),
            title: const Text(
              'Edit Team Name',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Team name',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: const Text('Save'),
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
        const SnackBar(content: Text('Team name updated')),
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
