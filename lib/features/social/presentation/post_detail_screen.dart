// lib/features/social/presentation/post_detail_screen.dart
//
// PostDetailScreen — renders a single `public_posts/{postId}` document for
// the public `/post/:postId` deep link / share target.
//
// No equivalent single-post detail screen existed in the app prior to this
// sharing system (posts were only ever seen inline inside PublicFeedScreen's
// list). This screen is intentionally self-contained: it duplicates the
// minimal like/comment logic needed to be useful as a landing page, while
// staying byte-for-byte compatible with the existing `public_posts`
// Firestore schema and security rules (see firestore.rules:
// match /public_posts/{postId} and its /likes, /comments subcollections)
// so no rules changes are required for this screen to function.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/routing/route_resolver.dart';
import '../../../core/seo/web_meta_updater.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/content_unavailable_screen.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/share_button.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _commentCtrl = TextEditingController();

  bool _liking = false;
  bool _postingComment = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  DocumentReference<Map<String, dynamic>> get _postRef =>
      _firestore.collection('public_posts').doc(widget.postId.trim());

  @override
  void dispose() {
    _commentCtrl.dispose();
    WebMetaUpdater.resetToDefault();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _watchPost() =>
      _postRef.snapshots();

  Stream<bool> _watchLiked() {
    final uid = _uid;
    if (uid.isEmpty) return Stream<bool>.value(false);
    return _postRef
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((s) => s.exists)
        .handleError((_) => false);
  }

  Stream<List<Map<String, dynamic>>> _watchComments() {
    return _postRef
        .collection('comments')
        .orderBy('createdAtMs', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
            .where((m) => m['deleted'] != true)
            .toList(growable: false))
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> _toggleLike(bool currentlyLiked) async {
    final uid = _uid;
    if (uid.isEmpty) {
      _snack('Please sign in to like posts.');
      return;
    }
    if (_liking) return;
    setState(() => _liking = true);
    try {
      final likeRef = _postRef.collection('likes').doc(uid);
      if (currentlyLiked) {
        await likeRef.delete();
        await _postRef.update({'likeCount': FieldValue.increment(-1)});
      } else {
        await likeRef.set(<String, dynamic>{
          'userId': uid,
          'likedAtMs': DateTime.now().millisecondsSinceEpoch,
        });
        await _postRef.update({'likeCount': FieldValue.increment(1)});
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _submitComment() async {
    final uid = _uid;
    if (uid.isEmpty) {
      _snack('Please sign in to comment.');
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    if (_postingComment) return;

    setState(() => _postingComment = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final commentRef = _postRef.collection('comments').doc();
      await commentRef.set(<String, dynamic>{
        'commentId': commentRef.id,
        'postId': widget.postId.trim(),
        'authorId': uid,
        'authorDisplayName': (user?.displayName ?? '').trim().isNotEmpty
            ? user!.displayName!.trim()
            : 'User',
        'authorPhotoUrl': (user?.photoURL ?? '').trim(),
        'text': text,
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'deleted': false,
      });
      await _postRef.update({'commentCount': FieldValue.increment(1)});
      _commentCtrl.clear();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  String _formatWhen(int ms) {
    if (ms <= 0) return '';
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms)
          .toLocal()
          .toString()
          .split('.')
          .first;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _watchPost(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = snap.data?.data();
        if (data == null || data['deleted'] == true) {
          return const ContentUnavailableScreen(
            message: 'This post is unavailable.',
            subtitle: 'It may have been removed by its author.',
          );
        }

        final brightness = Theme.of(context).brightness;
        final theme = Theme.of(context);

        final authorName =
            (data['authorDisplayName'] as String? ?? '').trim().isNotEmpty
                ? data['authorDisplayName'] as String
                : 'User';
        final authorPhoto = (data['authorPhotoUrl'] as String? ?? '').trim();
        final text = (data['text'] as String? ?? '').trim();
        final mediaUrl = (data['mediaUrl'] as String? ?? '').trim();
        final createdAtMs = (data['createdAtMs'] as num?)?.toInt() ?? 0;
        final likeCount = (data['likeCount'] as num?)?.toInt() ?? 0;
        final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
        final leagueName = (data['leagueName'] as String? ?? '').trim();

        WebMetaUpdater.applyEntityMeta(
          title: '$authorName on eSportlyic',
          description: text.length > 160 ? '${text.substring(0, 160)}…' : text,
          imageUrl: mediaUrl.isNotEmpty ? mediaUrl : authorPhoto,
        );

        return GlassScaffold(
          appBar: AppBar(
            title: const Text('Post'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              ShareButton(
                entity: ShareableEntity(
                  type: ShareableEntityType.post,
                  id: widget.postId.trim(),
                ),
                title: '$authorName on eSportlyic',
                description: text.length > 100 ? '${text.substring(0, 100)}…' : text,
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Glass(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(16),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                AppTheme.iconCircleBackground(brightness),
                            backgroundImage: authorPhoto.isNotEmpty
                                ? NetworkImage(authorPhoto)
                                : null,
                            child: authorPhoto.isEmpty
                                ? const Icon(Icons.person_rounded)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  authorName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryText(brightness),
                                  ),
                                ),
                                if (createdAtMs > 0)
                                  Text(
                                    _formatWhen(createdAtMs),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppTheme.secondaryText(brightness),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (leagueName.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: AppTheme.limeAccentDark.withOpacity(0.12),
                            border: Border.all(
                                color: AppTheme.limeAccentDark.withOpacity(0.28)),
                          ),
                          child: Text(
                            leagueName,
                            style: TextStyle(
                              color: AppTheme.limeAccentDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (mediaUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            mediaUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      StreamBuilder<bool>(
                        stream: _watchLiked(),
                        builder: (context, likedSnap) {
                          final liked = likedSnap.data ?? false;
                          return Row(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _liking ? null : () => _toggleLike(liked),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        liked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        color: liked
                                            ? const Color(0xFFEF4444)
                                            : AppTheme.secondaryText(brightness),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$likeCount',
                                        style: TextStyle(
                                          color: AppTheme.secondaryText(brightness),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Icon(Icons.mode_comment_outlined,
                                  size: 18, color: AppTheme.secondaryText(brightness)),
                              const SizedBox(width: 6),
                              Text(
                                '$commentCount',
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Comments',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Write a comment…',
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _postingComment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      onPressed: _postingComment ? null : _submitComment,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _watchComments(),
                  builder: (context, commentsSnap) {
                    final comments = commentsSnap.data ?? const [];
                    if (comments.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No comments yet.',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: comments.map((c) {
                        final name =
                            (c['authorDisplayName'] as String? ?? '').trim().isNotEmpty
                                ? c['authorDisplayName'] as String
                                : 'User';
                        final commentText = (c['text'] as String? ?? '').trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Glass(
                            borderRadius: 16,
                            padding: const EdgeInsets.all(12),
                            fill: AppTheme.cardColor(brightness),
                            borderColor: AppTheme.cardBorder(brightness),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: AppTheme.primaryText(brightness),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  commentText,
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
