// lib/features/chat/presentation/private_chat_list_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../data/private_chat_repository.dart';
import '../models/private_thread.dart';

class PrivateChatListScreen extends StatefulWidget {
  const PrivateChatListScreen({super.key});

  @override
  State<PrivateChatListScreen> createState() => _PrivateChatListScreenState();
}

class _PrivateChatListScreenState extends State<PrivateChatListScreen> {
  final PrivateChatRepository _repo = PrivateChatRepository();
  final UserProfileRepository _profiles = UserProfileRepository();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selfUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<List<PrivateThread>>(
          stream: _repo.watchInbox(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData &&
                !snap.hasError) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "We couldn't load your messages.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final threads = snap.data ?? const <PrivateThread>[];

            if (threads.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 48,
                        color: AppTheme.secondaryText(brightness),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No conversations yet.\nPremium users can start a chat from any profile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: () => context.push('/search'),
                        icon: const Icon(Icons.person_search_rounded),
                        label: const Text(
                          'Find People to Chat',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: threads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final thread = threads[i];
                final otherUid = thread.otherParticipant(selfUid);

                return FutureBuilder<UserProfile?>(
                  future: _profiles.fetchByUserId(otherUid),
                  builder: (context, profSnap) {
                    final profile = profSnap.data;
                    final name = _profiles.displayNameForProfile(
                      profile,
                      fallbackUserId: otherUid,
                    );
                    final avatarUrl = profile?.effectivePhotoUrl ?? '';

                    return Glass(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      fill: AppTheme.cardColor(brightness),
                      borderColor: AppTheme.cardBorder(brightness),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppTheme.iconCircleBackground(brightness),
                          backgroundImage: avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl.isEmpty
                              ? const Icon(Icons.person_rounded)
                              : null,
                        ),
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryText(brightness),
                                ),
                              ),
                            ),
                            // Verification badge — renders nothing if the
                            // user does not hold an active badge.
                            VerificationBadgeWidget(
                              userId: otherUid,
                              size: 15,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          thread.lastMessage.isEmpty
                              ? 'Say hello 👋'
                              : thread.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.secondaryText(brightness)),
                        ),
                        onTap: () => context.push(
                          '/chat/${thread.id}',
                          extra: {'otherUserId': otherUid, 'otherName': name},
                        ),
                      ),
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
