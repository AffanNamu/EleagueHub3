import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/services/supabase_edge_notifications_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/pinned_message_bar.dart';

class LeagueChatScreen extends StatefulWidget {
  final String leagueId;
  final String? organizerUid;

  const LeagueChatScreen({
    super.key,
    required this.leagueId,
    this.organizerUid,
  });

  @override
  State<LeagueChatScreen> createState() => _LeagueChatScreenState();
}

class _LeagueChatScreenState extends State<LeagueChatScreen> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Map<String, ChatMessage> _msgById = <String, ChatMessage>{};

  final ValueNotifier<String?> _selectedMessageId = ValueNotifier<String?>(null);
  final ValueNotifier<ChatMessage?> _replyTo = ValueNotifier<ChatMessage?>(null);

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  bool _leagueOwnerOrOrganizer = false;
  bool _leaguePermsResolved = false;

  String _leagueName = 'League';
  bool _leagueNameResolved = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVoiceSending = false;
  bool _recordingPermissionDenied = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  String? _playingMessageId;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  final Map<String, _CachedIdentity> _identityCache = <String, _CachedIdentity>{};
  final Set<String> _identityLoading = <String>{};

  bool _spaceActionBusy = false;

  bool _organizerChatMuted = false;
  bool _organizerChatBanned = false;
  bool _globalChatMuted = false;
  bool _globalChatBanned = false;
  bool _moderationResolved = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  bool get _isSuperAdmin => _user.uid.trim() == _superAdminUid;

  bool get _isSelecting => (_selectedMessageId.value ?? '').trim().isNotEmpty;

  bool get _isOrganizerFromParam =>
      widget.organizerUid != null &&
      widget.organizerUid!.trim().isNotEmpty &&
      widget.organizerUid!.trim() == _user.uid.trim();

  bool get _canModerateLeague =>
      _isSuperAdmin || _isOrganizerFromParam || (_leaguePermsResolved && _leagueOwnerOrOrganizer);

  bool get _chatBlocked =>
      (_organizerChatBanned || _globalChatBanned) && !_canModerateLeague;

  bool get _chatReadOnly =>
      (_organizerChatMuted || _globalChatMuted) && !_canModerateLeague;

  DocumentReference<Map<String, dynamic>> get _spaceDoc => FirebaseFirestore.instance
      .collection('leagues')
      .doc(widget.leagueId)
      .collection('space')
      .doc('current');

  CollectionReference<Map<String, dynamic>> get _spaceSpeakersCol =>
      _spaceDoc.collection('speakers');

  DocumentReference<Map<String, dynamic>> get _globalModerationDoc =>
      FirebaseFirestore.instance
          .collection('app')
          .doc('chatModeration')
          .collection('users')
          .doc(_user.uid.trim());

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
    _resolveLeaguePermissions();
    _resolveLeagueName();
    _wirePlayer();
    _watchModerationState();

    PushMessagingService.instance.subscribeToLeagueTopic(widget.leagueId);
    PushMessagingService.instance.setActiveLeagueChat(widget.leagueId);
  }

  void _watchModerationState() {
    _globalModerationDoc.snapshots(includeMetadataChanges: true).listen((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _globalChatMuted = data['allChatMuted'] == true;
        _globalChatBanned = data['allChatBanned'] == true;
        _moderationResolved = true;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _globalChatMuted = false;
        _globalChatBanned = false;
        _moderationResolved = true;
      });
    });

    FirebaseFirestore.instance.collection('leagues').doc(widget.leagueId).get().then((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      final masterLeagueId = (data['masterLeagueId'] ?? '').toString().trim();
      if (masterLeagueId.isEmpty) return;

      FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(masterLeagueId)
          .collection('memberModeration')
          .doc(_user.uid.trim())
          .snapshots(includeMetadataChanges: true)
          .listen((msnap) {
        final m = msnap.data() ?? <String, dynamic>{};
        if (!mounted) return;
        setState(() {
          _organizerChatMuted = m['chatMuted'] == true;
          _organizerChatBanned = m['chatBanned'] == true;
          _moderationResolved = true;
        });
      }, onError: (_) {
        if (!mounted) return;
        setState(() {
          _organizerChatMuted = false;
          _organizerChatBanned = false;
          _moderationResolved = true;
        });
      });
    }).catchError((_) {});
  }

  Future<void> _resolveLeagueName() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('leagues').doc(widget.leagueId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final name = (data['name'] ?? data['leagueName'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _leagueName = name.isNotEmpty ? name : 'League';
        _leagueNameResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leagueName = 'League';
        _leagueNameResolved = true;
      });
    }
  }

  Future<void> _resolveLeaguePermissions() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('leagues').doc(widget.leagueId).get();
      final data = snap.data() ?? <String, dynamic>{};

      bool isOwnerOrOrganizer = false;
      final uid = _user.uid.trim();

      final organizerUid = (data['organizerUid'] as String? ?? '').trim();
      final ownerUid = (data['ownerUid'] as String? ?? '').trim();
      final organizerUserId = (data['organizerUserId'] as String? ?? '').trim();
      final ownerId = (data['ownerId'] as String? ?? '').trim();

      if (organizerUid == uid || ownerUid == uid || organizerUserId == uid || ownerId == uid) {
        isOwnerOrOrganizer = true;
      }

      if (!mounted) return;
      setState(() {
        _leagueOwnerOrOrganizer = isOwnerOrOrganizer;
        _leaguePermsResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leagueOwnerOrOrganizer = false;
        _leaguePermsResolved = true;
      });
    }
  }

  void _wirePlayer() {
    _posSub = _player.positionStream.listen((v) {
      if (!mounted) return;
      setState(() => _pos = v);
    });
    _durSub = _player.durationStream.listen((v) {
      if (!mounted) return;
      setState(() => _dur = v ?? Duration.zero);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final isPlaying = s.playing && s.processingState != ProcessingState.completed;
      setState(() {
        _playing = isPlaying;
        if (s.processingState == ProcessingState.completed) {
          _pos = Duration.zero;
          _playing = false;
        }
      });
    });
  }

  Future<void> _resolveIdentity() async {
    try {
      final result = await _repo.resolveSenderIdentity(
        uid: _user.uid,
        fallbackName: _fallbackName(),
        fallbackPhoto: _fallbackPhoto(),
      );
      if (!mounted) return;
      setState(() {
        _resolvedName = result.name;
        _resolvedPhoto = result.photo;
        _identityResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvedName = _fallbackName();
        _resolvedPhoto = _fallbackPhoto();
        _identityResolved = true;
      });
    }
  }

  String _fallbackName() {
    final dn = (_user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = (_user.email ?? '').trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Player';
  }

  String _fallbackPhoto() => (_user.photoURL ?? '').trim();

  String _senderName() {
    if (_identityResolved && _resolvedName.isNotEmpty) return _resolvedName;
    return _fallbackName();
  }

  String _senderPhoto() {
    if (_identityResolved && _resolvedPhoto.isNotEmpty) return _resolvedPhoto;
    return _fallbackPhoto();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? cs.error : null,
        content: Text(msg),
      ),
    );
  }

  void _toastErr(Object e) =>
      _toast(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')), error: true);


  bool _canDeleteMessage(ChatMessage msg) {
    if (_canModerateLeague) return true;
    return _user.uid.trim() == msg.senderId.trim();
  }

  bool _canPinMessage(ChatMessage msg) {
    return _canModerateLeague;
  }

  String _previewForOutgoing({
    required String type,
    required String text,
    required String imageUrl,
    required String voiceUrl,
  }) {
    final t = type.trim();
    if (t == ChatMessageType.voice || voiceUrl.trim().isNotEmpty) return 'Voice message';
    if (t == ChatMessageType.image || imageUrl.trim().isNotEmpty) return 'Photo';
    if (t == ChatMessageType.code) return 'Code snippet';
    final msg = text.trim();
    if (msg.isEmpty) return 'New message';
    return msg.length > 140 ? '${msg.substring(0, 140)}…' : msg;
  }

  String _newMessageId() => FirebaseFirestore.instance.collection('_ids').doc().id;

  Future<void> _notifyPush({
    required String messageId,
    required String preview,
  }) async {
    await SupabaseEdgeNotificationsService.instance.notifyLeagueChatMessage(
      leagueId: widget.leagueId,
      leagueName: _leagueNameResolved ? _leagueName : 'League',
      messageId: messageId,
      senderId: _user.uid.trim(),
      senderName: _senderName().trim(),
      preview: preview.trim(),
    );
  }

  String _shortUid(String uid) {
    final s = uid.trim();
    if (s.length <= 10) return s;
    return '${s.substring(0, 6)}…${s.substring(s.length - 4)}';
  }

  void _ensureIdentityLoadedForUid(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return;
    if (_identityCache.containsKey(id)) return;
    if (_identityLoading.contains(id)) return;
    _identityLoading.add(id);

    () async {
      try {
        final r = await _repo.resolveSenderIdentity(
          uid: id,
          fallbackName: _shortUid(id),
          fallbackPhoto: '',
        );
        if (!mounted) return;
        setState(() {
          _identityCache[id] = _CachedIdentity(name: (r.name).trim(), photo: (r.photo).trim());
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _identityCache[id] = _CachedIdentity(name: _shortUid(id), photo: '');
        });
      } finally {
        _identityLoading.remove(id);
      }
    }();
  }

  String _displayNameForUid(String uid) {
    final cached = _identityCache[uid.trim()];
    final n = (cached?.name ?? '').trim();
    if (n.isNotEmpty) return n;
    return _shortUid(uid);
  }

  bool _spaceIsLiveFrom(Map<String, dynamic> data) {
    final v = data['isLive'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.trim().toLowerCase() == 'true';
    return false;
  }

  String _spaceTitleFrom(Map<String, dynamic> data) {
    final t = (data['title'] ?? data['name'] ?? data['spaceName'] ?? '').toString().trim();
    return t.isNotEmpty ? t : 'League Space';
  }

  String _spaceHostUidFrom(Map<String, dynamic> data) {
    return (data['hostUserId'] ?? data['hostUid'] ?? data['hostId'] ?? '').toString().trim();
  }

  int? _spaceParticipantsFrom(Map<String, dynamic> data) {
    final keys = <String>[
      'participants',
      'participantsCount',
      'participantCount',
      'numParticipants',
      'listeners',
      'listenersCount',
      'listenerCount',
      'memberCount',
    ];
    for (final k in keys) {
      final v = data[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<void> _openSpaceRoom() async {
    if (!mounted) return;
    context.push('/leagues/${widget.leagueId}/space');
  }

  Future<void> _startSpaceFromBanner({required String title}) async {
    if (_spaceActionBusy) return;
    if (!_canModerateLeague) {
      _toast('You do not have permission to start a space.', error: true);
      return;
    }

    setState(() => _spaceActionBusy = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;

      await _spaceDoc
          .set(
        {
          'leagueId': widget.leagueId,
          'hostUserId': _user.uid.trim(),
          'title': title.trim().isNotEmpty ? title.trim() : 'League Space',
          'isLive': true,
          'startedAtMs': now,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _toastErr(e);
    } finally {
      if (!mounted) return;
      setState(() => _spaceActionBusy = false);
    }
  }

  Future<void> _endSpaceFromBanner() async {
    if (_spaceActionBusy) return;
    if (!_canModerateLeague) {
      _toast('You do not have permission to end a space.', error: true);
      return;
    }

    setState(() => _spaceActionBusy = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;

      await _spaceDoc
          .set(
        {
          'isLive': false,
          'endedAtMs': now,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _toastErr(e);
    } finally {
      if (!mounted) return;
      setState(() => _spaceActionBusy = false);
    }
  }

  Widget _buildSpaceBanner(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _spaceDoc.snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        final exists = snap.data?.exists == true;
        final data = snap.data?.data() ?? <String, dynamic>{};

        final isLive = exists ? _spaceIsLiveFrom(data) : false;
        final title = exists ? _spaceTitleFrom(data) : 'League Space';
        final hostUid = exists ? _spaceHostUidFrom(data) : '';
        final isHost = hostUid.isNotEmpty && hostUid == _user.uid.trim();

        if (hostUid.isNotEmpty) _ensureIdentityLoadedForUid(hostUid);

        final hostName = hostUid.isNotEmpty ? _displayNameForUid(hostUid) : 'Host';

        final showStart = !isLive && _canModerateLeague;
        final showJoin = isLive && !isHost;

        final cardKey = ValueKey<String>(
          'space_${exists ? 'exists' : 'none'}_${isLive ? 'live' : 'off'}_${isHost ? 'host' : 'member'}',
        );

        final actionLabel = showJoin
            ? 'Join'
            : (showStart ? 'Start' : (isLive ? 'Open' : 'Off'));

        final actionEnabled = !_spaceActionBusy && (showJoin || showStart || isLive);

        final actionColor = showStart || showJoin || isLive
            ? cs.primary
            : theme.colorScheme.onSurface.withOpacity(0.35);

        final actionBg = actionColor.withOpacity(0.14);

        final banner = Glass(
          key: cardKey,
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(
                    color: (isLive ? cs.primary : Colors.white.withOpacity(0.22)).withOpacity(0.45),
                  ),
                ),
                child: Icon(
                  isLive ? Icons.graphic_eq_rounded : Icons.spatial_audio_off_rounded,
                  color: isLive ? cs.primary : Colors.white.withOpacity(0.55),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SpaceLivePill(isLive: isLive),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Host: $hostName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.62),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _SpaceParticipantsLabel(
                          isLive: isLive,
                          explicitCount: exists ? _spaceParticipantsFrom(data) : null,
                          speakersCol: _spaceSpeakersCol,
                          hostUid: hostUid,
                        ),
                      ],
                    ),
                    if (isHost && isLive) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: hostUid.trim().isEmpty
                                ? const Stream.empty()
                                : _spaceSpeakersCol.doc(hostUid.trim()).snapshots(includeMetadataChanges: true),
                            builder: (context, speakerSnap) {
                              final muted = speakerSnap.data?.data()?['muted'] == true;
                              final label = muted ? 'Mic off' : 'Mic on';
                              final icon = muted ? Icons.mic_off_rounded : Icons.mic_rounded;
                              final color = muted ? cs.error : cs.primary;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: color.withOpacity(0.10),
                                  border: Border.all(color: color.withOpacity(0.20)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 14, color: color),
                                    const SizedBox(width: 6),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: _spaceActionBusy ? null : _endSpaceFromBanner,
                            style: TextButton.styleFrom(
                              foregroundColor: cs.error,
                              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                            child: const Text('End'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: !actionEnabled
                      ? null
                      : () async {
                          if (showStart) {
                            await _startSpaceFromBanner(title: title);
                            return;
                          }
                          await _openSpaceRoom();
                        },
                  borderRadius: BorderRadius.circular(999),
                  child: Ink(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: actionBg,
                      border: Border.all(color: actionColor.withOpacity(0.22)),
                    ),
                    child: Center(
                      child: _spaceActionBusy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: actionColor),
                            )
                          : Text(
                              actionLabel,
                              style: TextStyle(
                                color: actionColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: banner,
          ),
        );
      },
    );
  }

  Future<void> _sendText() async {
    if (_chatBlocked) {
      _toast('You are banned from chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in chat.', error: true);
      return;
    }
    if (_isSelecting) return;

    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      await _repo.sendLeagueMessage(
        leagueId: widget.leagueId,
        messageIdOverride: messageId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: _codeMode ? ChatMessageType.code : ChatMessageType.text,
        text: raw,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.text,
        text: raw,
        imageUrl: '',
        voiceUrl: '',
      );
      _notifyPush(messageId: messageId, preview: preview);

      _textCtrl.clear();
      _replyTo.value = null;

      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_chatBlocked) {
      _toast('You are banned from chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in chat.', error: true);
      return;
    }
    if (_sending || _isSelecting) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final pick = await SafeImagePicker.pickImage();
      if (pick.wasCancelled) {
        if (mounted) setState(() => _sending = false);
        return;
      }
      if (!pick.isSuccess) {
        if (mounted) setState(() => _sending = false);
        _toast((pick.errorMessage ?? 'Could not pick image.').trim(), error: true);
        return;
      }

      final file = pick.file!;
      final url = await _repo.uploadLeagueChatImage(
        leagueId: widget.leagueId,
        file: file,
      );

      final caption = _textCtrl.text.trim();

      await _repo.sendLeagueMessage(
        leagueId: widget.leagueId,
        messageIdOverride: messageId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.image,
        text: caption,
        imageUrl: url,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.image,
        text: caption,
        imageUrl: url,
        voiceUrl: '',
      );
      _notifyPush(messageId: messageId, preview: preview);

      _textCtrl.clear();
      _replyTo.value = null;

      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _startRecording() async {
    if (_chatBlocked) {
      _toast('You are banned from chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in chat.', error: true);
      return;
    }
    if (_sending || _isVoiceSending || _isRecording || _isSelecting) return;

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        if (!mounted) return;
        setState(() => _recordingPermissionDenied = true);
        _toast('Microphone permission denied', error: true);
        return;
      }
      if (!mounted) return;
      setState(() => _recordingPermissionDenied = false);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final tmp = Directory.systemTemp.path;
      final outPath = p.join(tmp, 'chat_voice_${widget.leagueId}_$nowMs.m4a');

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: outPath,
      );

      _recordingTicker?.cancel();
      _recordingStartedAt = DateTime.now();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() {});
      });

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = outPath;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTicker?.cancel();
      _recordingTicker = null;
      _recordingStartedAt = null;

      if (_isRecording) {
        await _recorder.stop();
      }

      final path = _recordingPath;
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _sendRecording() async {
    if (_chatBlocked) {
      _toast('You are banned from chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in chat.', error: true);
      return;
    }
    if (_isVoiceSending || !_isRecording || _isSelecting) return;

    final path = (_recordingPath ?? '').trim();
    if (path.isEmpty) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _isVoiceSending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final stoppedPath = (await _recorder.stop())?.trim();
      final finalPath = (stoppedPath?.isNotEmpty == true ? stoppedPath! : path);

      _recordingTicker?.cancel();
      _recordingTicker = null;

      final file = File(finalPath);
      if (!await file.exists()) throw StateError('Recording not found. Try again.');

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final voiceUrl = await _repo.uploadLeagueChatVoice(
        leagueId: widget.leagueId,
        file: PlatformFile(
          name: '$nowMs.m4a',
          path: finalPath,
          size: await file.length(),
        ),
      );

      final caption = _textCtrl.text.trim();

      await _repo.sendLeagueMessage(
        leagueId: widget.leagueId,
        messageIdOverride: messageId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.voice,
        text: caption,
        voiceUrl: voiceUrl,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.voice,
        text: caption,
        imageUrl: '',
        voiceUrl: voiceUrl,
      );
      _notifyPush(messageId: messageId, preview: preview);

      _textCtrl.clear();
      _replyTo.value = null;

      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingStartedAt = null;
        _isVoiceSending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVoiceSending = false);
      _toastErr(e);
    }
  }

  String _recordingElapsed() {
    final started = _recordingStartedAt;
    if (!_isRecording || started == null) return '00:00';
    final d = DateTime.now().difference(started);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  double _progressFor(String messageId) {
    if (_playingMessageId != messageId) return 0.0;
    if (_dur.inMilliseconds <= 0) return 0.0;
    return (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
  }

  String _posLabelFor(String messageId) {
    if (_playingMessageId != messageId) return '00:00';
    return _fmt(_pos);
  }

  String _durLabelFor(String messageId) {
    if (_playingMessageId != messageId) return '00:00';
    return _fmt(_dur);
  }

  bool _isPlayingFor(String messageId) {
    return _playingMessageId == messageId && _playing;
  }

  Future<void> _toggleVoice(ChatMessage msg) async {
    final url = msg.voiceUrl.trim();
    if (url.isEmpty) return;

    try {
      if (_playingMessageId == msg.messageId) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }

      await _player.stop();
      setState(() {
        _playingMessageId = msg.messageId;
        _pos = Duration.zero;
        _dur = Duration.zero;
      });

      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _softDeleteSelected(ChatMessage msg) async {
    if (!_canDeleteMessage(msg)) {
      _toast('You can only delete your own messages.', error: true);
      return;
    }
    if (msg.deleted) {
      _toast('Already deleted');
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _repo.softDeleteLeagueMessage(
        leagueId: widget.leagueId,
        messageId: msg.messageId,
        deletedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast('Message deleted');
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _pinSelected(ChatMessage msg) async {
    if (!_canPinMessage(msg)) {
      _toast('You do not have permission to pin messages.', error: true);
      return;
    }
    if (msg.deleted) {
      _toast('Cannot pin a deleted message.', error: true);
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _repo.pinLeagueMessage(
        leagueId: widget.leagueId,
        messageId: msg.messageId,
        pinnedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast('Pinned');
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _copySelected(ChatMessage msg) async {
    if (msg.deleted) {
      _toast('Nothing to copy', error: true);
      _selectedMessageId.value = null;
      return;
    }

    final txt = msg.text.trim().isNotEmpty
        ? msg.text.trim()
        : (msg.type == ChatMessageType.image
            ? msg.imageUrl.trim()
            : (msg.type == ChatMessageType.voice ? msg.voiceUrl.trim() : ''));

    if (txt.isEmpty) {
      _toast('Nothing to copy', error: true);
      _selectedMessageId.value = null;
      return;
    }

    await Clipboard.setData(ClipboardData(text: txt));
    _toast('Copied');
    _selectedMessageId.value = null;
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      _toast('Message not loaded yet');
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  Widget _buildRecordingBar(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.mic, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Recording… ${_recordingElapsed()}',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _isVoiceSending ? null : _cancelRecording,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _isVoiceSending ? null : _sendRecording,
              child: _isVoiceSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder<String?>(
        valueListenable: _selectedMessageId,
        builder: (context, selectedId, _) {
          final selecting = (selectedId ?? '').trim().isNotEmpty;

          if (!selecting) {
            return AppBar(
              title: const Text('League Chat'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            );
          }

          final selectedMsg = (selectedId != null) ? _msgById[selectedId] : null;

          return AppBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              onPressed: () => _selectedMessageId.value = null,
              icon: const Icon(Icons.close_rounded),
            ),
            title: const Text('1 selected'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Copy',
                onPressed: selectedMsg == null ? null : () => _copySelected(selectedMsg),
                icon: const Icon(Icons.copy_rounded),
              ),
              if (selectedMsg != null && _canDeleteMessage(selectedMsg))
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _softDeleteSelected(selectedMsg),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              if (selectedMsg != null && _canPinMessage(selectedMsg))
                IconButton(
                  tooltip: 'Pin',
                  onPressed: () => _pinSelected(selectedMsg),
                  icon: const Icon(Icons.push_pin_outlined),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _moderationBanner(BuildContext context) {
    final theme = Theme.of(context);

    if (_moderationResolved && _chatBlocked) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.block_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You are banned from chat. You can no longer send messages here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_moderationResolved && _chatReadOnly) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.volume_off_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You are muted in chat. You can read messages but cannot send new ones.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFF59E0B),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    PushMessagingService.instance.setActiveLeagueChat(null);
    _recordingTicker?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    _scrollCtrl.dispose();
    _selectedMessageId.dispose();
    _replyTo.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double topBodyOffset = kToolbarHeight;

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient(theme.brightness),
      ),
      child: WillPopScope(
        onWillPop: () async {
          if (_isSelecting) {
            _selectedMessageId.value = null;
            return false;
          }
          return true;
        },
        child: GlassScaffold(
          appBar: _buildAppBar(),
          body: SafeArea(
            top: true,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: topBodyOffset),
              child: Column(
                children: [
                  _buildSpaceBanner(context),
                  _moderationBanner(context),
                  StreamBuilder<ChatMessage?>(
                    stream: _repo.leaguePinnedMessageStream(widget.leagueId),
                    builder: (context, snap) {
                      final pinned = snap.data;
                      if (pinned == null) return const SizedBox.shrink();
                      return PinnedMessageBar(
                        message: pinned,
                        onTap: () => _scrollToMessage(pinned.messageId),
                      );
                    },
                  ),
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: _repo.leagueChatStream(widget.leagueId),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          final msg = UserFriendlyError.toMessage(
                            snap.error is Object ? snap.error! : Exception('unknown'),
                          );

                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Glass(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_outline, color: theme.colorScheme.primary, size: 34),
                                    const SizedBox(height: 10),
                                    Text(
                                      msg,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton(
                                      onPressed: () => Navigator.of(context).maybePop(),
                                      child: const Text('Back'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final msgs = snap.data ?? const <ChatMessage>[];
                        if (msgs.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }

                        _msgById = {for (final m in msgs) m.messageId: m};

                        final ids = msgs.map((e) => e.messageId).toSet();
                        _messageKeys.removeWhere((k, _) => !ids.contains(k));

                        return ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final m = msgs[i];
                            final isMe = m.senderId.trim() == _user.uid.trim();
                            final key = _messageKeys.putIfAbsent(m.messageId, () => GlobalKey());

                            return ValueListenableBuilder<String?>(
                              valueListenable: _selectedMessageId,
                              builder: (context, selectedId, _) {
                                final selecting = (selectedId ?? '').trim().isNotEmpty;

                                return KeyedSubtree(
                                  key: key,
                                  child: ChatBubble(
                                    message: m,
                                    isMe: isMe,
                                    selected: selectedId == m.messageId,
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      _replyTo.value = null;
                                      _selectedMessageId.value = m.messageId;
                                    },
                                    onTap: () {
                                      if (!selecting) return;
                                      _selectedMessageId.value = (selectedId == m.messageId) ? null : m.messageId;
                                    },
                                    onSwipeReply: selecting ? null : () => _replyTo.value = m,
                                    onPlayVoice: (m.type == ChatMessageType.voice && !selecting) ? () => _toggleVoice(m) : null,
                                    isVoicePlaying: _isPlayingFor(m.messageId),
                                    voiceProgress: _progressFor(m.messageId),
                                    voicePositionLabel: _posLabelFor(m.messageId),
                                    voiceDurationLabel: _durLabelFor(m.messageId),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_isRecording) _buildRecordingBar(context),
                  if (!_chatBlocked)
                    AnimatedBuilder(
                      animation: Listenable.merge([_selectedMessageId, _replyTo]),
                      builder: (context, _) {
                        final selecting = (_selectedMessageId.value ?? '').trim().isNotEmpty;
                        final reply = _replyTo.value;

                        return ChatInputBar(
                          controller: _textCtrl,
                          isSending: _sending,
                          codeMode: _codeMode,
                          onToggleCodeMode: () => setState(() => _codeMode = !_codeMode),
                          enabled: !_isRecording && !selecting && !_chatReadOnly && !_chatBlocked,
                          onPickImage: () {
                            if (_chatReadOnly || _chatBlocked) return;
                            _pickAndSendImage();
                          },
                          onSend: () {
                            if (_chatReadOnly || _chatBlocked) return;
                            _sendText();
                          },
                          onRecordVoice: (_sending || _isVoiceSending || _isRecording || selecting || _chatReadOnly)
                              ? null
                              : _startRecording,
                          voiceTooltip: _recordingPermissionDenied ? 'Microphone permission required' : 'Record voice',
                          replySenderName: reply?.displaySenderName,
                          replyPreview: reply?.replyPreview(),
                          onCancelReply: () => _replyTo.value = null,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CachedIdentity {
  final String name;
  final String photo;
  const _CachedIdentity({required this.name, required this.photo});
}

class _SpaceLivePill extends StatelessWidget {
  const _SpaceLivePill({required this.isLive});
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isLive ? cs.error : Colors.white.withOpacity(0.55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            const _PulseDot(),
            const SizedBox(width: 6),
          ],
          Text(
            isLive ? 'LIVE' : 'OFF',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final opacity = 0.55 + (t * 0.45);
        final size = 6.0 + (t * 2.0);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.error,
            ),
          ),
        );
      },
    );
  }
}

class _SpaceParticipantsLabel extends StatelessWidget {
  const _SpaceParticipantsLabel({
    required this.isLive,
    required this.explicitCount,
    required this.speakersCol,
    required this.hostUid,
  });

  final bool isLive;
  final int? explicitCount;
  final CollectionReference<Map<String, dynamic>> speakersCol;
  final String hostUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isLive) {
      return Text(
        '0 participants',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.55),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      );
    }

    if (explicitCount != null) {
      final n = explicitCount!;
      return Text(
        '$n participants',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.62),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: speakersCol.snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];

        final host = hostUid.trim();
        final hostInSpeakers = host.isNotEmpty && docs.any((d) => d.id.trim() == host);
        final total = docs.length + (host.isNotEmpty && !hostInSpeakers ? 1 : 0);

        return Text(
          '$total participants',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.62),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        );
      },
    );
  }
}
