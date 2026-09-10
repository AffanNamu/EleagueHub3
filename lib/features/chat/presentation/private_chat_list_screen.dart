// lib/features/chat/presentation/private_chat_list_screen.dart
//
// NOTE: despite the filename/class name (kept as-is so the existing
// '/messages' route and every `PrivateChatListScreen()` reference
// elsewhere in the app keeps compiling), this is no longer just the
// private-DM inbox. It's now a unified "Messages" list combining:
//   - private 1:1 chat threads (existing behavior, unchanged),
//   - every league chatroom the user is a member of, and
//   - every organizer (master league) workspace chatroom the user
//     belongs to (as owner, member, or role holder),
// merged into one list sorted by most recent activity, each row
// showing the right name for its kind (the other person's name for a
// DM, the league's name for a league chat, the organizer workspace's
// name for an organizer chat) and a live-updating preview of the last
// message.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/data/leagues_repository_firebase.dart';
import '../../leagues/models/league.dart';
import '../../master_leagues/data/master_leagues_repository_firebase.dart';
import '../../master_leagues/domain/master_league.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../data/private_chat_repository.dart';
import '../models/private_thread.dart';

enum _RoomKind { private, league, organizer }

/// One row in the merged inbox. For [_RoomKind.private], [thread] is
/// set and everything else is resolved live via the existing
/// per-row FutureBuilder (profile lookup) exactly as before. For
/// [_RoomKind.league] / [_RoomKind.organizer], the fields here are
/// kept up to date by a per-room subscription in the State (see
/// _RoomWatch below) and rendered directly, no per-row builder needed.
class _InboxItem {
  _InboxItem.private(PrivateThread t)
      : kind = _RoomKind.private,
        id = t.id,
        thread = t,
        title = '',
        subtitle = '',
        lastActivityMs = 0;

  _InboxItem.room({
    required _RoomKind kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lastActivityMs,
  })  : kind = kind,
        thread = null;

  final _RoomKind kind;
  final String id;
  final PrivateThread? thread;
  final String title;
  final String subtitle;
  final int lastActivityMs;
}

/// Tracks one league or organizer chatroom the user belongs to: its
/// resolved display name (fetched once — room names rarely change)
/// and a live listener on that room's most recent message (so the
/// inbox actually updates the moment a new message arrives, which is
/// the whole point of this screen).
class _RoomWatch {
  _RoomWatch({required this.kind, required this.id});

  final _RoomKind kind;
  final String id;

  String name = '';
  String preview = 'No messages yet';
  int lastActivityMs = 0;
  bool nameResolved = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  void dispose() {
    _sub?.cancel();
  }
}

class PrivateChatListScreen extends StatefulWidget {
  const PrivateChatListScreen({super.key});

  @override
  State<PrivateChatListScreen> createState() => _PrivateChatListScreenState();
}

class _PrivateChatListScreenState extends State<PrivateChatListScreen> {
  final PrivateChatRepository _privateRepo = PrivateChatRepository();
  final UserProfileRepository _profiles = UserProfileRepository();
  final LeaguesRepositoryFirebase _leaguesRepo = LeaguesRepositoryFirebase();
  final MasterLeaguesRepositoryFirebase _masterLeaguesRepo =
      MasterLeaguesRepositoryFirebase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<List<PrivateThread>>? _privateSub;
  StreamSubscription<List<League>>? _leaguesSub;
  StreamSubscription<List<MasterLeague>>? _masterLeaguesSub;

  List<PrivateThread> _privateThreads = [];
  bool _privateLoaded = false;
  bool _leaguesLoaded = false;
  bool _organizerLoaded = false;
  Object? _privateError;

  final Map<String, _RoomWatch> _leagueRooms = {};
  final Map<String, _RoomWatch> _organizerRooms = {};

  @override
  void initState() {
    super.initState();

    _privateSub = _privateRepo.watchInbox().listen(
      (threads) {
        if (!mounted) return;
        setState(() {
          _privateThreads = threads;
          _privateLoaded = true;
          _privateError = null;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _privateError = e;
          _privateLoaded = true;
        });
      },
    );

    _leaguesSub = _leaguesRepo.watchLeagues().listen((leagues) {
      _syncRooms(
        kind: _RoomKind.league,
        ids: leagues.map((l) => l.id.trim()).where((id) => id.isNotEmpty),
        watchMap: _leagueRooms,
      );
      if (!mounted) return;
      setState(() => _leaguesLoaded = true);
    });

    _masterLeaguesSub = _masterLeaguesRepo.watchMyMasterLeagues().listen((mls) {
      _syncRooms(
        kind: _RoomKind.organizer,
        ids: mls.map((m) => m.id.trim()).where((id) => id.isNotEmpty),
        watchMap: _organizerRooms,
      );
      if (!mounted) return;
      setState(() => _organizerLoaded = true);
    });
  }

  @override
  void dispose() {
    _privateSub?.cancel();
    _leaguesSub?.cancel();
    _masterLeaguesSub?.cancel();
    for (final w in _leagueRooms.values) {
      w.dispose();
    }
    for (final w in _organizerRooms.values) {
      w.dispose();
    }
    super.dispose();
  }

  /// Adds a _RoomWatch (with its own live "latest message" listener)
  /// for every id newly seen in [ids], and tears down + removes any
  /// room that's no longer in [ids] (e.g. the user left that league or
  /// was removed from that organizer workspace).
  void _syncRooms({
    required _RoomKind kind,
    required Iterable<String> ids,
    required Map<String, _RoomWatch> watchMap,
  }) {
    final newIds = ids.toSet();

    final toRemove =
        watchMap.keys.where((id) => !newIds.contains(id)).toList();
    for (final id in toRemove) {
      watchMap.remove(id)?.dispose();
    }

    for (final id in newIds) {
      if (watchMap.containsKey(id)) continue;
      final watch = _RoomWatch(kind: kind, id: id);
      watchMap[id] = watch;
      _resolveRoomName(watch);
      _attachRoomListener(watch);
    }

    if (mounted) setState(() {});
  }

  Future<void> _resolveRoomName(_RoomWatch watch) async {
    try {
      final collection =
          watch.kind == _RoomKind.league ? 'leagues' : 'master_leagues';
      final snap = await _firestore
          .collection(collection)
          .doc(watch.id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      final data = snap.data() ?? const <String, dynamic>{};
      // Same field-fallback order LeagueChatScreen / OrganizerChatScreen
      // already use to resolve their own app-bar titles from this same
      // document, kept identical here so the name always matches what
      // the chat screen itself shows.
      final name = watch.kind == _RoomKind.league
          ? (data['name'] ?? data['leagueName'] ?? '').toString().trim()
          : (data['name'] ?? data['title'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        watch.name = name.isNotEmpty
            ? name
            : (watch.kind == _RoomKind.league ? 'League' : 'Organizer');
        watch.nameResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        watch.name = watch.kind == _RoomKind.league ? 'League' : 'Organizer';
        watch.nameResolved = true;
      });
    }
  }

  void _attachRoomListener(_RoomWatch watch) {
    final collection =
        watch.kind == _RoomKind.league ? 'leagues' : 'master_leagues';

    watch._sub = _firestore
        .collection(collection)
        .doc(watch.id)
        .collection('chatroom')
        .orderBy('createdAtMs', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;

      if (snap.docs.isEmpty) {
        setState(() {
          watch.preview = 'No messages yet';
          watch.lastActivityMs = 0;
        });
        return;
      }

      final data = snap.docs.first.data();
      final type = (data['type'] as String? ?? 'text').trim();
      final text = (data['text'] as String? ?? '').trim();
      final senderName = (data['senderName'] as String? ?? '').trim();
      final createdAtMs = (data['createdAtMs'] as num?)?.toInt() ?? 0;
      final deleted = data['deleted'] == true;

      String body;
      if (deleted) {
        body = 'Message deleted';
      } else {
        switch (type) {
          case 'image':
            body = '📷 Photo';
            break;
          case 'voice':
            body = '🎤 Voice message';
            break;
          default:
            body = text.isNotEmpty ? text : 'New message';
        }
      }

      setState(() {
        watch.preview =
            senderName.isNotEmpty ? '$senderName: $body' : body;
        watch.lastActivityMs = createdAtMs;
      });
    }, onError: (_) {
      // A room this user just lost access to (left the league, etc.)
      // will error here until the next _syncRooms() removal fires —
      // leave the last-known preview in place rather than clearing it.
    });
  }

  List<_InboxItem> _mergedItems() {
    final items = <_InboxItem>[
      ..._privateThreads.map(_InboxItem.private),
      for (final w in _leagueRooms.values)
        _InboxItem.room(
          kind: _RoomKind.league,
          id: w.id,
          title: w.nameResolved ? w.name : 'League',
          subtitle: w.preview,
          lastActivityMs: w.lastActivityMs,
        ),
      for (final w in _organizerRooms.values)
        _InboxItem.room(
          kind: _RoomKind.organizer,
          id: w.id,
          title: w.nameResolved ? w.name : 'Organizer',
          subtitle: w.preview,
          lastActivityMs: w.lastActivityMs,
        ),
    ];

    items.sort((a, b) {
      final at = a.kind == _RoomKind.private
          ? (a.thread?.lastMessageAtMs ?? 0)
          : a.lastActivityMs;
      final bt = b.kind == _RoomKind.private
          ? (b.thread?.lastMessageAtMs ?? 0)
          : b.lastActivityMs;
      return bt.compareTo(at);
    });

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selfUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    final allLoaded = _privateLoaded && _leaguesLoaded && _organizerLoaded;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Builder(builder: (context) {
          if (!allLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_privateError != null &&
              _privateThreads.isEmpty &&
              _leagueRooms.isEmpty &&
              _organizerRooms.isEmpty) {
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

          final items = _mergedItems();

          if (items.isEmpty) {
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
                      'No conversations yet.\nMessages from your leagues, '
                      'organizer workspaces, and direct chats will show up '
                      'here.',
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
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = items[i];
              if (item.kind == _RoomKind.private) {
                return _PrivateRow(
                  thread: item.thread!,
                  selfUid: selfUid,
                  profiles: _profiles,
                );
              }
              return _RoomRow(item: item);
            },
          );
        }),
      ),
    );
  }
}

class _PrivateRow extends StatelessWidget {
  const _PrivateRow({
    required this.thread,
    required this.selfUid,
    required this.profiles,
  });

  final PrivateThread thread;
  final String selfUid;
  final UserProfileRepository profiles;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final otherUid = thread.otherParticipant(selfUid);

    return FutureBuilder<UserProfile?>(
      future: profiles.fetchByUserId(otherUid),
      builder: (context, profSnap) {
        final profile = profSnap.data;
        final name = profiles.displayNameForProfile(
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppTheme.iconCircleBackground(brightness),
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
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
                VerificationBadgeWidget(userId: otherUid, size: 15),
              ],
            ),
            subtitle: Text(
              thread.lastMessage.isEmpty ? 'Say hello 👋' : thread.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.secondaryText(brightness)),
            ),
            onTap: () => context.push(
              '/chat/${thread.id}',
              extra: {'otherUserId': otherUid, 'otherName': name},
            ),
          ),
        );
      },
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.item});

  final _InboxItem item;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLeague = item.kind == _RoomKind.league;

    return Glass(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.iconCircleBackground(brightness),
          child: Icon(
            isLeague ? Icons.emoji_events_rounded : Icons.workspaces_rounded,
          ),
        ),
        title: Text(
          item.title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.primaryText(brightness),
          ),
        ),
        subtitle: Text(
          item.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppTheme.secondaryText(brightness)),
        ),
        trailing: Icon(
          isLeague ? Icons.forum_rounded : Icons.groups_rounded,
          size: 18,
          color: AppTheme.secondaryText(brightness),
        ),
        onTap: () => context.push(
          isLeague
              ? '/leagues/${item.id}/chat'
              : '/master-leagues/${item.id}/chat',
        ),
      ),
    );
  }
}
