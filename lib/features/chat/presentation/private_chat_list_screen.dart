// lib/features/chat/presentation/private_chat_list_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
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
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final threads = snap.data!;

            if (threads.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No conversations yet.\nPremium users can start a chat from any profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                    ),
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
                    final name = _profiles.displayNameForProfile(
                      profSnap.data,
                      fallbackUserId: otherUid,
                    );

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
                          child: const Icon(Icons.person_rounded),
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(brightness),
                          ),
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
