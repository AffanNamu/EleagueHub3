// lib/features/discovery/discussions/presentation/discussions_list_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/locale/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../auth/data/user_profile_repository.dart';
import '../../../auth/models/user_profile.dart';
import '../data/discussions_repository.dart';
import '../models/discussion_thread.dart';
import 'widgets/create_discussion_sheet.dart';

class DiscussionsListScreen extends StatefulWidget {
  const DiscussionsListScreen({super.key});

  @override
  State<DiscussionsListScreen> createState() => _DiscussionsListScreenState();
}

class _DiscussionsListScreenState extends State<DiscussionsListScreen> {
  final DiscussionsRepository _repo = DiscussionsRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  Future<void> _handleCreateTap() async {
    final account = await _userRepo.fetchByUserId(_selfUid);
    final name = _userRepo.displayNameForProfile(account, fallbackUserId: _selfUid);
    if (!mounted) return;
    final result = await showCreateDiscussionSheet(
      context,
      authorDisplayName: name,
      authorPhotoUrl: account?.effectivePhotoUrl ?? '',
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(context.l10n.tr('discussions_list_posted'))),
      );
    }
  }

  String _timeAgo(AppLocalizations l10n, int ms) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return l10n.tr('discussions_list_time_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}${l10n.tr('discussions_list_time_minutes_suffix')}';
    if (diff.inHours < 24) return '${diff.inHours}${l10n.tr('discussions_list_time_hours_suffix')}';
    return '${diff.inDays}${l10n.tr('discussions_list_time_days_suffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('discussions_list_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.limeAccent,
        foregroundColor: AppTheme.darkText,
        onPressed: _handleCreateTap,
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: StreamBuilder<List<DiscussionThread>>(
          stream: _repo.watchThreads(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(
                  UserFriendlyError.toMessage(snap.error as Object),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final threads = snap.data!;
            if (threads.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.tr('discussions_list_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: threads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final thread = threads[i];
                return InkWell(
                  onTap: () => context.push('/discovery/community/discussions/${thread.threadId}'),
                  borderRadius: BorderRadius.circular(18),
                  child: Glass(
                    borderRadius: 18,
                    padding: const EdgeInsets.all(14),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.iconCircleBackground(brightness),
                              backgroundImage:
                                  thread.authorPhotoUrl.isNotEmpty ? NetworkImage(thread.authorPhotoUrl) : null,
                              child: thread.authorPhotoUrl.isEmpty ? const Icon(Icons.person_rounded, size: 14) : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                thread.authorDisplayName.isEmpty ? l10n.tr('discussions_list_author_fallback') : thread.authorDisplayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: AppTheme.secondaryText(brightness),
                                ),
                              ),
                            ),
                            Text(
                              _timeAgo(l10n, thread.lastReplyAtMs),
                              style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          thread.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppTheme.secondaryText(brightness)),
                            const SizedBox(width: 4),
                            Text(
                              '${thread.replyCount} ${thread.replyCount == 1 ? l10n.tr('discussions_list_reply_singular') : l10n.tr('discussions_list_reply_plural')}',
                              style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
