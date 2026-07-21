//presentation/organizer_discipline_screen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

// ---------------------------------------------------------------------------
// Breakpoints — self-contained
// ---------------------------------------------------------------------------

class _BP {
  static const double tablet  = 760;
  static const double desktop = 900;
}

// ---------------------------------------------------------------------------
// Enums + extensions
// ---------------------------------------------------------------------------

enum OrganizerDisciplineActionType {
  warning,
  pointsDeduction,
  organizerChatMute,
  organizerChatBan,
  organizerChatUnmute,
  organizerChatUnban,
}

extension OrganizerDisciplineActionTypeX
    on OrganizerDisciplineActionType {
  String get firestoreValue {
    switch (this) {
      case OrganizerDisciplineActionType.warning:
        return 'warning';
      case OrganizerDisciplineActionType.pointsDeduction:
        return 'points_deduction';
      case OrganizerDisciplineActionType.organizerChatMute:
        return 'organizer_chat_mute';
      case OrganizerDisciplineActionType.organizerChatBan:
        return 'organizer_chat_ban';
      case OrganizerDisciplineActionType.organizerChatUnmute:
        return 'organizer_chat_unmute';
      case OrganizerDisciplineActionType.organizerChatUnban:
        return 'organizer_chat_unban';
    }
  }

  String get label {
    switch (this) {
      case OrganizerDisciplineActionType.warning:
        return 'Warning';
      case OrganizerDisciplineActionType.pointsDeduction:
        return 'Deduct Points';
      case OrganizerDisciplineActionType.organizerChatMute:
        return 'Mute Organizer Chat';
      case OrganizerDisciplineActionType.organizerChatBan:
        return 'Ban Organizer Chat';
      case OrganizerDisciplineActionType.organizerChatUnmute:
        return 'Unmute Organizer Chat';
      case OrganizerDisciplineActionType.organizerChatUnban:
        return 'Unban Organizer Chat';
    }
  }

  static OrganizerDisciplineActionType fromFirestore(
      String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'warning':
        return OrganizerDisciplineActionType.warning;
      case 'points_deduction':
        return OrganizerDisciplineActionType.pointsDeduction;
      case 'organizer_chat_mute':
        return OrganizerDisciplineActionType.organizerChatMute;
      case 'organizer_chat_ban':
        return OrganizerDisciplineActionType.organizerChatBan;
      case 'organizer_chat_unmute':
        return OrganizerDisciplineActionType.organizerChatUnmute;
      case 'organizer_chat_unban':
        return OrganizerDisciplineActionType.organizerChatUnban;
      default:
        return OrganizerDisciplineActionType.warning;
    }
  }
}

// ---------------------------------------------------------------------------
// OrganizerDisciplineScreen
// ---------------------------------------------------------------------------

class OrganizerDisciplineScreen extends StatefulWidget {
  const OrganizerDisciplineScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  @override
  State<OrganizerDisciplineScreen> createState() =>
      _OrganizerDisciplineScreenState();
}

class _OrganizerDisciplineScreenState
    extends State<OrganizerDisciplineScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool   _loadingMaster = true;
  bool   _submitting    = false;

  String      _masterLeagueName = 'Organizer Discipline';
  String      _ownerId          = '';
  final Set<String> _adminIds     = <String>{};
  final Set<String> _moderatorIds = <String>{};
  final Set<String> _memberIds    = <String>{};

  final TextEditingController _targetUserIdCtrl =
      TextEditingController();
  final TextEditingController _targetNameCtrl =
      TextEditingController();
  final TextEditingController _reasonCtrl =
      TextEditingController();
  final TextEditingController _pointsCtrl =
      TextEditingController(text: '1');

  OrganizerDisciplineActionType _actionType =
      OrganizerDisciplineActionType.warning;

  String? _errorText;

  // ── identity ───────────────────────────────────────────────────────────────

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  // ── Firestore refs ─────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>>
      get _actionsCol => _firestore
          .collection('master_leagues')
          .doc(widget.masterLeagueId)
          .collection('disciplineActions');

  CollectionReference<Map<String, dynamic>>
      get _moderationCol => _firestore
          .collection('master_leagues')
          .doc(widget.masterLeagueId)
          .collection('memberModeration');

  // ── safe navigation ────────────────────────────────────────────────────────

  void _safePop() {
    try {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/');
      }
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  // ── snack ──────────────────────────────────────────────────────────────────

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:         Text(trimmed),
        behavior:        SnackBarBehavior.floating,
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
  }

  // ── access ─────────────────────────────────────────────────────────────────

  bool _canManageDiscipline() {
    final uid = _currentUid.trim();
    if (uid.isEmpty)               return false;
    if (uid == _ownerId.trim())    return true;
    if (_adminIds.contains(uid))   return true;
    if (_moderatorIds.contains(uid)) return true;
    return false;
  }

  String _inferRoleForTarget(String uid) {
    final id = uid.trim();
    if (id.isEmpty)                return 'member';
    if (id == _ownerId.trim())     return 'owner';
    if (_adminIds.contains(id))    return 'admin';
    if (_moderatorIds.contains(id)) return 'moderator';
    if (_memberIds.contains(id))   return 'member';
    return 'external';
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadMasterLeague();
  }

  @override
  void dispose() {
    _targetUserIdCtrl.dispose();
    _targetNameCtrl.dispose();
    _reasonCtrl.dispose();
    _pointsCtrl.dispose();
    super.dispose();
  }

  // ── data load ──────────────────────────────────────────────────────────────

  Future<void> _loadMasterLeague() async {
    setState(() {
      _loadingMaster = true;
      _errorText     = null;
    });

    try {
      final snap = await _firestore
          .collection('master_leagues')
          .doc(widget.masterLeagueId)
          .get();

      final data = snap.data() ?? <String, dynamic>{};

      final ownerId = (data['ownerId'] as String? ?? '')
          .trim();
      final adminIds =
          (data['adminIds'] as List?)
                  ?.map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toSet() ??
              <String>{};
      final moderatorIds =
          (data['moderatorIds'] as List?)
                  ?.map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toSet() ??
              <String>{};
      final memberIds =
          (data['memberIds'] as List?)
                  ?.map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toSet() ??
              <String>{};

      if (!mounted) return;
      setState(() {
        _masterLeagueName =
            (data['name'] as String? ?? '').trim().isEmpty
                ? 'Organizer Discipline'
                : (data['name'] as String).trim();
        _ownerId = ownerId;
        _adminIds
          ..clear()
          ..addAll(adminIds);
        _moderatorIds
          ..clear()
          ..addAll(moderatorIds);
        _memberIds
          ..clear()
          ..addAll(memberIds);
        _loadingMaster = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMaster = false;
        _errorText     = '$e';
      });
    }
  }

  // ── user picker ────────────────────────────────────────────────────────────

  Future<void> _openUserPicker() async {
    final picked = await showModalBottomSheet<
        Map<String, String>?>(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      showDragHandle:     true,
      builder: (ctx) => _OrganizerMemberPickerSheet(
        masterLeagueId: widget.masterLeagueId,
        ownerId:        _ownerId,
        adminIds:       _adminIds,
        moderatorIds:   _moderatorIds,
        memberIds:      _memberIds,
      ),
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _targetUserIdCtrl.text = picked['userId'] ?? '';
      _targetNameCtrl.text   = picked['displayName'] ?? '';
      _errorText             = null;
    });
  }

  // ── apply discipline ───────────────────────────────────────────────────────

  Future<void> _applyDiscipline() async {
    if (_submitting) return;

    final targetUserId = _targetUserIdCtrl.text.trim();
    final targetName   = _targetNameCtrl.text.trim();
    final reason       = _reasonCtrl.text.trim();
    final points =
        int.tryParse(_pointsCtrl.text.trim()) ?? 0;

    if (targetUserId.isEmpty) {
      setState(() =>
          _errorText = 'Target user id is required.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _errorText = 'Reason is required.');
      return;
    }
    if (_actionType ==
            OrganizerDisciplineActionType.pointsDeduction &&
        points <= 0) {
      setState(() =>
          _errorText = 'Points must be greater than 0.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText  = null;
    });

    try {
      final uid = _currentUid.trim();
      final now = DateTime.now().millisecondsSinceEpoch;
      final actionRef     = _actionsCol.doc();
      final moderationRef = _moderationCol.doc(targetUserId);

      final currentModerationSnap =
          await moderationRef.get();
      final currentData =
          currentModerationSnap.data() ?? <String, dynamic>{};

      final currentPoints =
          (currentData['points'] as num?)?.toInt() ?? 0;
      final currentWarnings =
          (currentData['warnings'] as num?)?.toInt() ?? 0;
      final currentMuted  = currentData['chatMuted'] == true;
      final currentBanned = currentData['chatBanned'] == true;

      int  nextPoints   = currentPoints;
      int  nextWarnings = currentWarnings;
      bool nextMuted    = currentMuted;
      bool nextBanned   = currentBanned;
      int  pointsDelta  = 0;

      switch (_actionType) {
        case OrganizerDisciplineActionType.warning:
          nextWarnings = currentWarnings + 1;
          break;
        case OrganizerDisciplineActionType.pointsDeduction:
          pointsDelta = -points.abs();
          nextPoints  = currentPoints + pointsDelta;
          break;
        case OrganizerDisciplineActionType.organizerChatMute:
          nextMuted = true;
          break;
        case OrganizerDisciplineActionType.organizerChatBan:
          nextBanned = true;
          nextMuted  = true;
          break;
        case OrganizerDisciplineActionType.organizerChatUnmute:
          nextMuted = false;
          break;
        case OrganizerDisciplineActionType.organizerChatUnban:
          nextBanned = false;
          break;
      }

      final batch = _firestore.batch();

      batch.set(
        actionRef,
        <String, dynamic>{
          'id':             actionRef.id,
          'masterLeagueId': widget.masterLeagueId,
          'targetUserId':   targetUserId,
          'targetName':     targetName,
          'targetRole':     _inferRoleForTarget(targetUserId),
          'actionType':     _actionType.firestoreValue,
          'pointsDelta':    pointsDelta,
          'reason':         reason,
          'createdBy':      uid,
          'createdAtMs':    now,
          'active':         true,
          'reversedAtMs':   0,
          'reversedBy':     '',
          'reversalReason': '',
        },
        SetOptions(merge: true),
      );

      batch.set(
        moderationRef,
        <String, dynamic>{
          'userId':      targetUserId,
          'displayName': targetName,
          'points':      nextPoints,
          'warnings':    nextWarnings,
          'chatMuted':   nextMuted,
          'chatBanned':  nextBanned,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;

      _targetUserIdCtrl.clear();
      _targetNameCtrl.clear();
      _reasonCtrl.clear();
      _pointsCtrl.text = '1';
      setState(() {
        _actionType = OrganizerDisciplineActionType.warning;
        _submitting = false;
      });

      _snack('Discipline action applied.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText  = '$e';
      });
      _snack('$e', error: true);
    }
  }

  // ── reverse action ─────────────────────────────────────────────────────────

  Future<void> _reverseAction(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data          = doc.data();
    final reversedAtMs  =
        (data['reversedAtMs'] as num?)?.toInt() ?? 0;
    if (reversedAtMs > 0) {
      _snack('This action has already been reversed.');
      return;
    }

    final targetUserId =
        (data['targetUserId'] as String? ?? '').trim();
    if (targetUserId.isEmpty) {
      _snack('Target user missing.', error: true);
      return;
    }

    final actionType =
        OrganizerDisciplineActionTypeX.fromFirestore(
      (data['actionType'] as String? ?? '').trim(),
    );
    final pointsDelta =
        (data['pointsDelta'] as num?)?.toInt() ?? 0;

    final reasonCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:  AppTheme.cardColor(
            Theme.of(ctx).brightness),
        surfaceTintColor: Colors.transparent,
        title: const Text('Reverse Discipline Action'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Provide a reversal reason. This will update '
              'the moderation summary and mark this action '
              'as reversed.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines:   4,
              decoration: const InputDecoration(
                labelText:        'Reversal reason',
                alignLabelWithHint: true,
                prefixIcon:       Icon(Icons.undo_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      reasonCtrl.dispose();
      return;
    }

    final reversalReason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    if (reversalReason.isEmpty) {
      _snack('Reversal reason is required.', error: true);
      return;
    }

    try {
      final uid = _currentUid.trim();
      final now = DateTime.now().millisecondsSinceEpoch;
      final moderationRef =
          _moderationCol.doc(targetUserId);

      final moderationSnap = await moderationRef.get();
      final current =
          moderationSnap.data() ?? <String, dynamic>{};

      int  nextPoints   =
          (current['points'] as num?)?.toInt() ?? 0;
      int  nextWarnings =
          (current['warnings'] as num?)?.toInt() ?? 0;
      bool nextMuted    = current['chatMuted'] == true;
      bool nextBanned   = current['chatBanned'] == true;

      switch (actionType) {
        case OrganizerDisciplineActionType.warning:
          if (nextWarnings > 0) nextWarnings -= 1;
          break;
        case OrganizerDisciplineActionType.pointsDeduction:
          nextPoints = nextPoints - pointsDelta;
          break;
        case OrganizerDisciplineActionType.organizerChatMute:
          nextMuted = false;
          break;
        case OrganizerDisciplineActionType.organizerChatBan:
          nextBanned = false;
          break;
        case OrganizerDisciplineActionType.organizerChatUnmute:
          nextMuted = true;
          break;
        case OrganizerDisciplineActionType.organizerChatUnban:
          nextBanned = true;
          break;
      }

      final batch = _firestore.batch();

      batch.set(
        doc.reference,
        <String, dynamic>{
          'active':         false,
          'reversedAtMs':   now,
          'reversedBy':     uid,
          'reversalReason': reversalReason,
        },
        SetOptions(merge: true),
      );

      batch.set(
        moderationRef,
        <String, dynamic>{
          'userId':      targetUserId,
          'points':      nextPoints,
          'warnings':    nextWarnings,
          'chatMuted':   nextMuted,
          'chatBanned':  nextBanned,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      _snack('Discipline action reversed.');
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title:           const Text('Organizer Discipline'),
        backgroundColor: Colors.transparent,
        elevation:       0,
        // Explicit leading — prevents shell navigator from
        // intercepting back on web
        leading: IconButton(
          icon:     const Icon(Icons.arrow_back),
          tooltip:  'Back',
          onPressed: _safePop,
        ),
        actions: [
          IconButton(
            tooltip:  'Refresh',
            onPressed: _loadMasterLeague,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loadingMaster
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final w         = constraints.maxWidth;
                  final isDesktop = w >= _BP.desktop;
                  final hPad =
                      w < _BP.tablet ? 16.0 : 24.0;

                  if (isDesktop) {
                    return _buildDesktopLayout(
                      theme:      theme,
                      brightness: brightness,
                      hPad:       hPad,
                    );
                  }

                  return _buildMobileLayout(
                    theme:      theme,
                    brightness: brightness,
                    hPad:       hPad,
                  );
                },
              ),
      ),
    );
  }

  // ── Desktop two-column layout ──────────────────────────────────────────────
  //
  // Left  (flex 3): Header + Apply action form
  // Right (flex 2): Moderation summary + Discipline history

  Widget _buildDesktopLayout({
    required ThemeData  theme,
    required Brightness brightness,
    required double     hPad,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding:
              EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // Left: header + form
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildHeaderCard(theme, brightness),
                    if (!_canManageDiscipline()) ...[
                      const SizedBox(height: 16),
                      const EmptyState(
                        title:   'No access',
                        message:
                            'Only the master league owner, '
                            'admins, or moderators can manage '
                            'organizer discipline.',
                        icon: Icons.lock_outline_rounded,
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      _buildActionForm(theme, brightness),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Right: moderation + history (only when access granted)
              if (_canManageDiscipline())
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildModerationSummary(),
                      const SizedBox(height: 16),
                      _buildHistoryCard(theme, brightness),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mobile single-column layout ────────────────────────────────────────────

  Widget _buildMobileLayout({
    required ThemeData  theme,
    required Brightness brightness,
    required double     hPad,
  }) {
    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
      children: [
        _buildHeaderCard(theme, brightness),
        const SizedBox(height: 16),
        if (!_canManageDiscipline())
          const EmptyState(
            title:   'No access',
            message:
                'Only the master league owner, admins, or '
                'moderators can manage organizer discipline.',
            icon: Icons.lock_outline_rounded,
          )
        else ...[
          _buildActionForm(theme, brightness),
          const SizedBox(height: 16),
          _buildModerationSummary(),
          const SizedBox(height: 16),
          _buildHistoryCard(theme, brightness),
        ],
      ],
    );
  }

  // ── Header card ────────────────────────────────────────────────────────────

  Widget _buildHeaderCard(
      ThemeData theme, Brightness brightness) {
    return Glass(
      borderRadius: 28,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _masterLeagueName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Apply warnings, point deductions, and organizer '
            'chat restrictions with a required reason and '
            'audit trail.',
            style: theme.textTheme.bodySmall?.copyWith(
              color:      AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              height:     1.35,
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color:      Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Action form ────────────────────────────────────────────────────────────

  Widget _buildActionForm(
      ThemeData theme, Brightness brightness) {
    return Glass(
      borderRadius: 24,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apply Discipline Action',
            style: theme.textTheme.titleSmall?.copyWith(
              color:      AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetUserIdCtrl,
                  enabled:    !_submitting,
                  decoration: const InputDecoration(
                    labelText:  'Target user id',
                    prefixIcon:
                        Icon(Icons.person_outline_rounded),
                  ),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed:
                    _submitting ? null : _openUserPicker,
                icon: const Icon(Icons.search_rounded),
                label: const Text(
                  'Pick',
                  style:
                      TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _targetNameCtrl,
            enabled:    !_submitting,
            decoration: const InputDecoration(
              labelText:  'Target display name (optional)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _buildActionTypeSelector(),
          if (_actionType ==
              OrganizerDisciplineActionType
                  .pointsDeduction) ...[
            const SizedBox(height: 12),
            TextField(
              controller:  _pointsCtrl,
              enabled:     !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText:  'Points to deduct',
                prefixIcon:
                    Icon(Icons.exposure_neg_1_rounded),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            enabled:    !_submitting,
            maxLines:   4,
            decoration: const InputDecoration(
              labelText:        'Reason (required)',
              alignLabelWithHint: true,
              prefixIcon:       Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed:
                  _submitting ? null : _applyDiscipline,
              icon: _submitting
                  ? const SizedBox(
                      width:  18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:       AppTheme.darkText,
                      ),
                    )
                  : const Icon(Icons.gavel_rounded),
              label: Text(
                _submitting
                    ? 'Applying...'
                    : 'Apply Discipline Action',
                style: const TextStyle(
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action type selector ───────────────────────────────────────────────────
  // Reads Theme.of(context) internally — no ThemeData parameter

  Widget _buildActionTypeSelector() {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    Widget chip(OrganizerDisciplineActionType type) {
      final selected = _actionType == type;
      return ChoiceChip(
        label: Text(
          type.label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        selected:        selected,
        onSelected:      _submitting
            ? null
            : (_) => setState(() {
                  _actionType = type;
                  _errorText  = null;
                }),
        selectedColor:   AppTheme.limeAccent,
        backgroundColor:
            AppTheme.tabInactiveBackground(brightness),
        labelStyle: TextStyle(
          color: selected
              ? AppTheme.darkText
              : AppTheme.tabInactiveText(brightness),
          fontWeight:
              selected ? FontWeight.w900 : FontWeight.w800,
        ),
        side: BorderSide(
          color: selected
              ? AppTheme.limeAccentDark
              : AppTheme.cardBorder(brightness),
        ),
      );
    }

    return Wrap(
      spacing:    10,
      runSpacing: 10,
      children: OrganizerDisciplineActionType.values
          .map(chip)
          .toList(),
    );
  }

  // ── Summary tile ───────────────────────────────────────────────────────────
  // Reads Theme.of(context) internally

  Widget _summaryTile({
    required IconData icon,
    required String   title,
    required String   subtitle,
    required Color    tint,
  }) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 18,
      padding:      const EdgeInsets.all(14),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          Container(
            width:  38,
            height: 38,
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              color:  tint.withOpacity(0.12),
              border: Border.all(
                  color: tint.withOpacity(0.24)),
            ),
            child: Icon(icon, color: tint, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(
                    color: AppTheme.primaryText(
                        brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(
                    color: AppTheme.secondaryText(
                        brightness),
                    fontWeight: FontWeight.w700,
                    height:     1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Moderation summary ─────────────────────────────────────────────────────
  // Reads Theme.of(context) internally

  Widget _buildModerationSummary() {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _moderationCol
          .orderBy('updatedAtMs', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];

        if (snap.connectionState ==
                ConnectionState.waiting &&
            docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: CircularProgressIndicator()),
          );
        }

        if (docs.isEmpty) return const SizedBox.shrink();

        return Glass(
          borderRadius: 24,
          padding:      const EdgeInsets.all(16),
          fill:         AppTheme.cardColor(brightness),
          borderColor:  AppTheme.cardBorder(brightness),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Moderation Status',
                style: theme.textTheme.titleSmall?.copyWith(
                  color:      AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ...docs.map((d) {
                final m = d.data();
                final userId =
                    (m['userId'] as String? ?? '').trim();
                final displayName =
                    (m['displayName'] as String? ?? '').trim();
                final points =
                    (m['points'] as num?)?.toInt() ?? 0;
                final warnings =
                    (m['warnings'] as num?)?.toInt() ?? 0;
                final muted  = m['chatMuted'] == true;
                final banned = m['chatBanned'] == true;

                final title = displayName.isNotEmpty
                    ? '$displayName '
                        '(${userId.isEmpty ? 'unknown' : userId})'
                    : (userId.isEmpty
                        ? 'Unknown user'
                        : userId);

                final subtitle = [
                  'Points: $points',
                  'Warnings: $warnings',
                  if (muted) 'Muted',
                  if (banned) 'Banned',
                ].join(' • ');

                final tint = banned
                    ? Theme.of(context).colorScheme.error
                    : (muted
                        ? const Color(0xFFF59E0B)
                        : AppTheme.limeAccentDark);

                return Padding(
                  padding:
                      const EdgeInsets.only(bottom: 10),
                  child: _summaryTile(
                    icon: banned
                        ? Icons.block_rounded
                        : (muted
                            ? Icons.volume_off_rounded
                            : Icons.shield_outlined),
                    title:    title,
                    subtitle: subtitle,
                    tint:     tint,
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  // ── History list card ──────────────────────────────────────────────────────
  // Reads Theme.of(context) internally

  Widget _buildHistoryCard(
      ThemeData theme, Brightness brightness) {
    return Glass(
      borderRadius: 24,
      padding:      const EdgeInsets.all(16),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Discipline History',
            style: theme.textTheme.titleSmall?.copyWith(
              color:      AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _buildHistoryList(),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    final query = _actionsCol
        .orderBy('createdAtMs', descending: true)
        .limit(200);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];

        if (snap.connectionState ==
                ConnectionState.waiting &&
            docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: CircularProgressIndicator()),
          );
        }

        if (docs.isEmpty) {
          return const EmptyState(
            title:   'No discipline actions yet',
            message:
                'Warnings, point deductions, and chat '
                'sanctions will appear here.',
            icon: Icons.gavel_rounded,
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final targetUserId =
                (data['targetUserId'] as String? ?? '')
                    .trim();
            final targetName =
                (data['targetName'] as String? ?? '')
                    .trim();
            final reason =
                (data['reason'] as String? ?? '').trim();
            final actionType =
                OrganizerDisciplineActionTypeX.fromFirestore(
              (data['actionType'] as String? ?? '').trim(),
            );
            final pointsDelta =
                (data['pointsDelta'] as num?)?.toInt() ?? 0;
            final createdBy =
                (data['createdBy'] as String? ?? '').trim();
            final createdAtMs =
                (data['createdAtMs'] as num?)?.toInt() ?? 0;
            final reversedAtMs =
                (data['reversedAtMs'] as num?)?.toInt() ?? 0;
            final reversalReason =
                (data['reversalReason'] as String? ?? '')
                    .trim();

            final when = createdAtMs > 0
                ? DateTime.fromMillisecondsSinceEpoch(
                        createdAtMs)
                    .toLocal()
                    .toString()
                    .split('.')
                    .first
                : 'Unknown time';

            final title = targetName.isNotEmpty
                ? '$targetName • ${actionType.label}'
                : '${targetUserId.isEmpty ? 'Unknown user' : targetUserId}'
                    ' • ${actionType.label}';

            final subtitleParts = <String>[
              if (pointsDelta != 0) 'Points $pointsDelta',
              if (reason.isNotEmpty) reason,
              if (createdBy.isNotEmpty) 'By $createdBy',
              when,
              if (reversedAtMs > 0) 'Reversed',
            ];

            final tint = switch (actionType) {
              OrganizerDisciplineActionType.warning =>
                const Color(0xFFF59E0B),
              OrganizerDisciplineActionType.pointsDeduction =>
                Theme.of(context).colorScheme.error,
              OrganizerDisciplineActionType.organizerChatMute =>
                const Color(0xFF8B5CF6),
              OrganizerDisciplineActionType.organizerChatBan =>
                const Color(0xFFDC2626),
              OrganizerDisciplineActionType.organizerChatUnmute =>
                const Color(0xFF0EA5E9),
              OrganizerDisciplineActionType.organizerChatUnban =>
                const Color(0xFF22C55E),
            };

            final icon = switch (actionType) {
              OrganizerDisciplineActionType.warning =>
                Icons.warning_amber_rounded,
              OrganizerDisciplineActionType.pointsDeduction =>
                Icons.exposure_neg_1_rounded,
              OrganizerDisciplineActionType.organizerChatMute =>
                Icons.volume_off_rounded,
              OrganizerDisciplineActionType.organizerChatBan =>
                Icons.block_rounded,
              OrganizerDisciplineActionType.organizerChatUnmute =>
                Icons.volume_up_rounded,
              OrganizerDisciplineActionType.organizerChatUnban =>
                Icons.lock_open_rounded,
            };

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Glass(
                borderRadius: 20,
                padding:      const EdgeInsets.all(14),
                fill:         AppTheme.cardColor(brightness),
                borderColor:  AppTheme.cardBorder(brightness),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          width:  38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape:  BoxShape.circle,
                            color:
                                tint.withOpacity(0.12),
                            border: Border.all(
                                color: tint
                                    .withOpacity(0.24)),
                          ),
                          child: Icon(icon,
                              color: tint, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme
                                    .textTheme.bodyMedium
                                    ?.copyWith(
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitleParts.join(' • '),
                                style: theme.textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  color:
                                      AppTheme.secondaryText(
                                          brightness),
                                  fontWeight:
                                      FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              if (reversalReason
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Reversal reason: '
                                  '$reversalReason',
                                  style: theme.textTheme
                                      .bodySmall
                                      ?.copyWith(
                                    color:
                                        AppTheme.secondaryText(
                                            brightness),
                                    fontWeight:
                                        FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_canManageDiscipline() &&
                        reversedAtMs <= 0) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _reverseAction(d),
                          icon: const Icon(
                              Icons.undo_rounded,
                              size: 18),
                          label: const Text(
                            'Reverse',
                            style: TextStyle(
                                fontWeight:
                                    FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _OrganizerMemberPickerSheet — unchanged logic, clean structure
// ---------------------------------------------------------------------------

class _OrganizerMemberPickerSheet extends StatefulWidget {
  const _OrganizerMemberPickerSheet({
    required this.masterLeagueId,
    required this.ownerId,
    required this.adminIds,
    required this.moderatorIds,
    required this.memberIds,
  });

  final String      masterLeagueId;
  final String      ownerId;
  final Set<String> adminIds;
  final Set<String> moderatorIds;
  final Set<String> memberIds;

  @override
  State<_OrganizerMemberPickerSheet> createState() =>
      _OrganizerMemberPickerSheetState();
}

class _OrganizerMemberPickerSheetState
    extends State<_OrganizerMemberPickerSheet> {
  final FirebaseFirestore      _firestore = FirebaseFirestore.instance;
  final TextEditingController  _searchCtrl =
      TextEditingController();

  bool   _loading = true;
  String _query   = '';
  List<_PickerUser> _users = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (!mounted) return;
      setState(() =>
          _query = _searchCtrl.text.trim().toLowerCase());
    });
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _roleFor(String uid) {
    final id = uid.trim();
    if (id.isEmpty)                        return 'member';
    if (id == widget.ownerId.trim())       return 'owner';
    if (widget.adminIds.contains(id))      return 'admin';
    if (widget.moderatorIds.contains(id))  return 'moderator';
    if (widget.memberIds.contains(id))     return 'member';
    return 'external';
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);

    try {
      final uids = <String>{
        if (widget.ownerId.trim().isNotEmpty)
          widget.ownerId.trim(),
        ...widget.adminIds,
        ...widget.moderatorIds,
        ...widget.memberIds,
      }.where((e) => e.trim().isNotEmpty)
          .toList(growable: false);

      final users = <_PickerUser>[];

      const chunkSize = 10;
      for (var i = 0; i < uids.length; i += chunkSize) {
        final chunk = uids.sublist(
          i,
          (i + chunkSize > uids.length)
              ? uids.length
              : i + chunkSize,
        );

        final snap = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final d in snap.docs) {
          final data        = d.data();
          final displayName = (data['teamName'] ??
                  data['displayName'] ??
                  data['name'] ??
                  data['username'] ??
                  '')
              .toString()
              .trim();

          users.add(_PickerUser(
            userId:      d.id,
            displayName: displayName,
            role:        _roleFor(d.id),
          ));
        }
      }

      final foundIds   = users.map((e) => e.userId).toSet();
      final missingIds =
          uids.where((id) => !foundIds.contains(id));

      for (final id in missingIds) {
        users.add(_PickerUser(
          userId:      id,
          displayName: '',
          role:        _roleFor(id),
        ));
      }

      users.sort((a, b) {
        final roleOrder =
            _roleRank(a.role).compareTo(_roleRank(b.role));
        if (roleOrder != 0) return roleOrder;
        final an =
            a.displayName.isEmpty ? a.userId : a.displayName;
        final bn =
            b.displayName.isEmpty ? b.userId : b.displayName;
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _users   = users;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _users   = [];
        _loading = false;
      });
    }
  }

  int _roleRank(String role) {
    switch (role) {
      case 'owner':     return 0;
      case 'admin':     return 1;
      case 'moderator': return 2;
      case 'member':    return 3;
      default:          return 4;
    }
  }

  List<_PickerUser> _filteredUsers() {
    final q = _query.trim();
    if (q.isEmpty) return _users;

    return _users.where((u) {
      final haystack =
          '${u.userId} ${u.displayName} ${u.role}'
              .toLowerCase();
      return haystack.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;
    final filtered   = _filteredUsers();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.of(context).viewInsets.bottom,
        ).add(
            const EdgeInsets.fromLTRB(12, 12, 12, 16)),
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 620),
            child: Glass(
              borderRadius: 28,
              padding:      const EdgeInsets.all(16),
              fill:         AppTheme.cardColor(brightness),
              borderColor:
                  AppTheme.cardBorder(brightness),
              child: SizedBox(
                height:
                    MediaQuery.of(context).size.height *
                        0.78,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick User',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(
                        color: AppTheme.primaryText(
                            brightness),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText:
                            'Search by name, user id, '
                            'or role...',
                        prefixIcon:
                            Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child:
                                  CircularProgressIndicator())
                          : filtered.isEmpty
                              ? const EmptyState(
                                  title: 'No users found',
                                  message:
                                      'Try another search '
                                      'term or refresh the '
                                      'workspace members.',
                                  icon: Icons
                                      .person_search_rounded,
                                )
                              : ListView.separated(
                                  itemCount:
                                      filtered.length,
                                  separatorBuilder:
                                      (_, __) => Divider(
                                    color:
                                        AppTheme.cardBorder(
                                            brightness),
                                  ),
                                  itemBuilder:
                                      (context, index) {
                                    final u =
                                        filtered[index];
                                    final title =
                                        u.displayName
                                                .isNotEmpty
                                            ? u.displayName
                                            : u.userId;

                                    return ListTile(
                                      contentPadding:
                                          EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            AppTheme
                                                .iconCircleBackground(
                                                    brightness),
                                        child: Icon(
                                          Icons
                                              .person_outline_rounded,
                                          color: AppTheme
                                              .limeAccentDark,
                                        ),
                                      ),
                                      title: Text(
                                        title,
                                        style: theme
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                          color:
                                              AppTheme
                                                  .primaryText(
                                                      brightness),
                                          fontWeight:
                                              FontWeight
                                                  .w900,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${u.userId} • ${u.role}',
                                        style: theme
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                          color: AppTheme
                                              .secondaryText(
                                                  brightness),
                                          fontWeight:
                                              FontWeight
                                                  .w700,
                                        ),
                                      ),
                                      trailing: const Icon(
                                          Icons
                                              .chevron_right_rounded),
                                      onTap: () {
                                        Navigator.of(context)
                                            .pop(<String,
                                                String>{
                                          'userId':
                                              u.userId,
                                          'displayName':
                                              u.displayName,
                                        });
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerUser {
  const _PickerUser({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;
}
