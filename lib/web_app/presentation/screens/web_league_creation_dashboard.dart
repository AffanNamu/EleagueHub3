import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/routing/home_shell_tab_controller.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../features/auth/data/user_profile_repository.dart';
import '../../../features/auth/models/user_profile.dart';
import '../../../features/leagues/data/leagues_repository_firebase.dart';
import '../../../features/leagues/logic/league_media_service.dart';
import '../../../features/leagues/logic/league_premium_upgrade_helper.dart';
import '../../../features/leagues/models/enums.dart';
import '../../../features/leagues/models/league.dart';
import '../../../features/leagues/models/league_format.dart';
import '../../../features/leagues/models/league_settings.dart';
import '../../../features/master_leagues/data/organizer_feed_firebase.dart';
import '../../../widgets/league_flip_card.dart';

enum LeagueCreationType {
  series,
  group,
  classic,
}

class WebLeagueCreationDashboard extends ConsumerStatefulWidget {
  const WebLeagueCreationDashboard({super.key});

  @override
  ConsumerState<WebLeagueCreationDashboard> createState() =>
      _WebLeagueCreationDashboardState();
}

class _WebLeagueCreationDashboardState
    extends ConsumerState<WebLeagueCreationDashboard> {
  final Uuid _uuid = const Uuid();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrganizerFeedFirebase _organizerFeed = OrganizerFeedFirebase();

  static const int _freeLeagueListLimit = 3;
  static const Color _premiumAmber = Color(0xFFF59E0B);

  late final String _draftLeagueId;

  int _step = 0;
  LeagueCreationType? _type;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _leagueImageUrl = TextEditingController();
  final TextEditingController _sponsorImageUrl = TextEditingController();

  bool _uploadingLeagueImage = false;
  bool _uploadingSponsorImage = false;

  LeaguePrivacy _privacy = LeaguePrivacy.private;
  bool _homeAwayEnabled = false;

  bool _submitting = false;
  League? _createdLeague;

  int? _selectedMaxTeams;

  bool _creatorWillParticipate = false;
  bool _extrasApplied = false;
  String _masterLeagueId = '';
  bool _containsRewards = false;

  bool _checkingAccess = true;
  bool _hasLeagueAccess = false;
  bool _isPaidPlanUser = false;
  int _currentLeagueCardCount = 0;
  String _activePlanLabel = 'Basic';

  @override
  void initState() {
    super.initState();
    _draftLeagueId = _uuid.v4();
    _loadPlanLimitState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_extrasApplied) return;
    _extrasApplied = true;

    Map<String, dynamic>? extra;
    try {
      final x = GoRouterState.of(context).extra;
      if (x is Map) extra = x.cast<String, dynamic>();
    } catch (_) {
      extra = null;
    }

    if (extra == null) return;

    final ml = (extra['masterLeagueId'] as String?)?.trim() ?? '';
    final LeagueFormat? initialFormat = extra['initialFormat'] is LeagueFormat
        ? extra['initialFormat'] as LeagueFormat
        : null;

    final String? typeString =
        (extra['type'] as String?)?.trim().toLowerCase();

    final inferredType = initialFormat != null
        ? _creationTypeFromFormat(initialFormat)
        : (typeString != null && typeString.isNotEmpty
            ? _creationTypeFromString(typeString)
            : null);

    if (!mounted) return;

    setState(() {
      _masterLeagueId = ml;
      if (inferredType != null) {
        _type = inferredType;

        final fmt = _format;
        if (fmt == LeagueFormat.uclGroup) {
          _selectedMaxTeams = 32;
        } else if (fmt == LeagueFormat.uclSwiss) {
          _selectedMaxTeams = 36;
        } else {
          _selectedMaxTeams = 20;
        }

        if (!_supportsHomeAwayMatches) {
          _homeAwayEnabled = false;
        }
        _step = 1;
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _leagueImageUrl.dispose();
    _sponsorImageUrl.dispose();
    super.dispose();
  }

  bool get _inMasterLeagueMode => _masterLeagueId.trim().isNotEmpty;

  Future<void> _loadPlanLimitState() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _checkingAccess = false;
        _hasLeagueAccess = false;
        _isPaidPlanUser = false;
        _currentLeagueCardCount = 0;
        _activePlanLabel = 'Basic';
      });
      return;
    }

    try {
      final profile = await UserProfileRepository()
          .fetchByUserId(uid)
          .timeout(const Duration(seconds: 12));

      final count = await _countCurrentLeagueCards(uid);

      final activePlan = profile?.activePlan;
      final isPaid = activePlan != null && !activePlan.isFree;

      if (!mounted) return;
      setState(() {
        _hasLeagueAccess = true;
        _isPaidPlanUser = isPaid;
        _currentLeagueCardCount = count;
        _activePlanLabel =
            isPaid ? (activePlan?.displayName ?? 'Paid Plan') : 'Basic';
        _checkingAccess = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAccess = false;
        _hasLeagueAccess = true;
        _isPaidPlanUser = false;
        _currentLeagueCardCount = 0;
        _activePlanLabel = 'Basic';
      });
    }
  }

  Future<int> _countCurrentLeagueCards(String uid) async {
    final snap = await _firestore
        .collection('leagues')
        .where('organizerUid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));

    return snap.docs.length;
  }

  bool get _freeLimitReachedForNewLeague =>
      _hasLeagueAccess &&
      !_isPaidPlanUser &&
      _currentLeagueCardCount >= _freeLeagueListLimit;

  String get _freeLimitText =>
      'Basic users can create up to $_freeLeagueListLimit leagues/competitions total. This total is shared across normal leagues and competitions created inside Organizer or Master League workspace. Upgrade to Pro or Elite to create more.';

  Future<void> _openPlanUpgradeFlow() async {
    final success = await LeaguePremiumUpgradeHelper.openUpgradeFlow(
      context,
      leagueName:
          _name.text.trim().isEmpty ? 'Organizer Plan' : _name.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      _showSnack('Plan purchase completed. Refreshing access...');
      await _loadPlanLimitState();
      return;
    }

    _showSnack('Plan purchase cancelled.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final msg = message.trim();
    if (msg.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  LeagueCreationType _creationTypeFromFormat(LeagueFormat format) {
    switch (format) {
      case LeagueFormat.uclSwiss:
        return LeagueCreationType.series;
      case LeagueFormat.uclGroup:
        return LeagueCreationType.group;
      case LeagueFormat.classic:
        return LeagueCreationType.classic;
    }
  }

  LeagueCreationType? _creationTypeFromString(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'classic') return LeagueCreationType.classic;
    if (s == 'swiss' || s == 'series') return LeagueCreationType.series;
    if (s == 'ucl' || s == 'group') return LeagueCreationType.group;
    return null;
  }

  LeagueFormat get _format {
    final type = _type;
    if (type == null) return LeagueFormat.classic;

    switch (type) {
      case LeagueCreationType.series:
        return LeagueFormat.uclSwiss;
      case LeagueCreationType.group:
        return LeagueFormat.uclGroup;
      case LeagueCreationType.classic:
        return LeagueFormat.classic;
    }
  }

  bool get _supportsHomeAwayMatches =>
      _format == LeagueFormat.classic || _format == LeagueFormat.uclGroup;

  List<int> get _allowedMaxTeams {
    switch (_format) {
      case LeagueFormat.uclGroup:
        return const [16, 32];
      case LeagueFormat.uclSwiss:
        return const [18, 36];
      case LeagueFormat.classic:
      default:
        return const [20];
    }
  }

  int get _maxTeams {
    final selected = _selectedMaxTeams;
    if (selected != null) return selected;

    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
        return 32;
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  String get _typeLabel {
    final l10n = AppLocalizations.of(context);
    final type = _type;
    if (type == null) return l10n.tr('league_create_summary_not_selected');

    switch (type) {
      case LeagueCreationType.series:
        return l10n.tr('league_create_type_series_title');
      case LeagueCreationType.group:
        return l10n.tr('league_create_type_group_title');
      case LeagueCreationType.classic:
        return l10n.tr('league_create_type_classic_title');
    }
  }

  IconData get _typeIcon {
    final type = _type;
    if (type == null) return Icons.help_outline;
    switch (type) {
      case LeagueCreationType.series:
        return Icons.auto_graph;
      case LeagueCreationType.group:
        return Icons.grid_view;
      case LeagueCreationType.classic:
        return Icons.table_chart;
    }
  }

  void _setType(LeagueCreationType t) {
    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return;
    }

    if (_freeLimitReachedForNewLeague) {
      _showSnack(_freeLimitText);
      return;
    }

    setState(() {
      _type = t;

      final fmt = _format;
      if (fmt == LeagueFormat.uclGroup) {
        _selectedMaxTeams = 32;
      } else if (fmt == LeagueFormat.uclSwiss) {
        _selectedMaxTeams = 36;
      } else {
        _selectedMaxTeams = 20;
      }

      if (!_supportsHomeAwayMatches) {
        _homeAwayEnabled = false;
      }
    });
  }

  Future<void> _uploadImage({
    required LeagueMediaKind kind,
  }) async {
    final l10n = context.l10n;
    if (_submitting) return;

    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return;
    }

    if (_freeLimitReachedForNewLeague) {
      _showSnack(_freeLimitText);
      return;
    }

    if (kind == LeagueMediaKind.leagueImage) {
      if (_uploadingLeagueImage) return;
      setState(() => _uploadingLeagueImage = true);
    } else {
      if (_uploadingSponsorImage) return;
      setState(() => _uploadingSponsorImage = true);
    }

    try {
      final service = LeagueMediaService();
      final url = await service
          .pickAndUploadImage(
            leagueId: _draftLeagueId,
            kind: kind,
          )
          .timeout(const Duration(seconds: 40));

      if (!mounted) return;

      if (url == null || url.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image not selected or upload failed.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        if (kind == LeagueMediaKind.leagueImage) {
          _leagueImageUrl.text = url;
        } else {
          _sponsorImageUrl.text = url;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('common_done')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFriendlyError.toMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingLeagueImage = false;
        _uploadingSponsorImage = false;
      });
    }
  }

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueJoinCode() async {
    for (int i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await _firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      if (snap.docs.isEmpty) return code;
    }
    throw StateError("We couldn't create a join code. Please try again.");
  }

  Future<League> _createLeagueOnline({
    required League league,
  }) async {
    await ConnectivityService.instance.requireOnline(
      timeout: const Duration(seconds: 4),
    );

    final repo = LeaguesRepositoryFirebase();
    final savedId = await repo
        .saveLeague(league)
        .timeout(const Duration(seconds: 25));

    if (_inMasterLeagueMode) {
      return league.copyWith(id: savedId);
    }

    final fresh = await repo
        .getLeagueById(savedId)
        .timeout(const Duration(seconds: 20));

    return fresh ?? league.copyWith(id: savedId);
  }

  Color _panelFill(ThemeData theme) {
    return AppTheme.cardColor(theme.brightness);
  }

  Color _panelBorder(ThemeData theme, {Color? accent}) {
    return AppTheme.cardBorder(theme.brightness);
  }

  Widget _flatPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
      ),
      child: child,
    );
  }

  Widget _softPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: child,
    );
  }

  Widget _stepChip({
    required bool active,
    required bool done,
    required String title,
    required IconData icon,
  }) {
    final brightness = Theme.of(context).brightness;

    final borderColor = active
        ? AppTheme.limeAccentDark
        : done
            ? AppTheme.limeAccentDark.withOpacity(0.40)
            : AppTheme.cardBorder(brightness);

    final bgColor = active
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : done
            ? AppTheme.searchBackground(brightness)
            : AppTheme.cardColor(brightness);

    final iconColor = active
        ? AppTheme.limeAccentDark
        : done
            ? AppTheme.limeAccentDark
            : AppTheme.secondaryText(brightness);

    final textColor = active
        ? AppTheme.limeAccentDark
        : done
            ? AppTheme.primaryText(brightness)
            : AppTheme.secondaryText(brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(BuildContext context, {Key? key}) {
    switch (_step) {
      case 0:
        return _stepLeagueType(context, key: key);
      case 1:
        return _stepLeagueDetails(context, key: key);
      case 2:
        return _stepPrivacy(context, key: key);
      case 3:
        return _stepPayment(context, key: key);
      case 4:
        return _stepConfirm(context, key: key);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepLeagueType(BuildContext context, {Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _inMasterLeagueMode
              ? 'Select the competition type for your Master League.'
              : l10n.tr('league_create_choose_type_help'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.secondaryText(brightness),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _typeCard(
          type: LeagueCreationType.series,
          title: l10n.tr('league_create_type_series_title'),
          subtitle: l10n.tr('league_create_type_series_subtitle'),
          icon: Icons.auto_graph,
        ),
        const SizedBox(height: 10),
        _typeCard(
          type: LeagueCreationType.group,
          title: l10n.tr('league_create_type_group_title'),
          subtitle: l10n.tr('league_create_type_group_subtitle'),
          icon: Icons.grid_view,
        ),
        const SizedBox(height: 10),
        _typeCard(
          type: LeagueCreationType.classic,
          title: l10n.tr('league_create_type_classic_title'),
          subtitle: l10n.tr('league_create_type_classic_subtitle'),
          icon: Icons.table_chart,
        ),
        const SizedBox(height: 14),
        if (_type != null && _allowedMaxTeams.length > 1) ...[
          _sectionTitle(
            l10n.tr('league_create_competition_size_title'),
            Icons.groups,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final n in _allowedMaxTeams)
                ChoiceChip(
                  label: Text(
                    '$n ${l10n.tr('league_create_teams_word')}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  selected: _maxTeams == n,
                  selectedColor: AppTheme.limeAccent,
                  backgroundColor: AppTheme.tabInactiveBackground(brightness),
                  side: BorderSide(
                    color: _maxTeams == n
                        ? AppTheme.limeAccentDark
                        : AppTheme.cardBorder(brightness),
                  ),
                  labelStyle: TextStyle(
                    color: _maxTeams == n
                        ? AppTheme.darkText
                        : AppTheme.tabInactiveText(brightness),
                    fontWeight:
                        _maxTeams == n ? FontWeight.w900 : FontWeight.w800,
                  ),
                  onSelected: (_freeLimitReachedForNewLeague || _checkingAccess)
                      ? null
                      : (v) {
                          if (!v) return;
                          setState(() => _selectedMaxTeams = n);
                        },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _typeCard({
    required LeagueCreationType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final selected = _type == type;

    final fill = selected
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : _panelFill(theme);

    final border = selected
        ? AppTheme.limeAccentDark
        : _panelBorder(theme);

    return InkWell(
      onTap: (_freeLimitReachedForNewLeague || _checkingAccess)
          ? null
          : () => _setType(type),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: fill,
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppTheme.iconCircleBackground(brightness),
                border: Border.all(
                  color: AppTheme.cardBorder(brightness),
                ),
              ),
              child: Icon(
                icon,
                color: selected
                    ? AppTheme.limeAccentDark
                    : AppTheme.secondaryText(brightness),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          height: 1.25,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.limeAccent
                    : AppTheme.tabInactiveBackground(brightness),
                borderRadius: BorderRadius.circular(999),
                border: selected
                    ? null
                    : Border.all(
                        color: AppTheme.cardBorder(brightness),
                      ),
              ),
              child: Text(
                selected
                    ? context.l10n.tr('common_selected')
                    : context.l10n.tr('common_select'),
                style: TextStyle(
                  color: selected
                      ? AppTheme.darkText
                      : AppTheme.tabInactiveText(brightness),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepLeagueDetails(BuildContext context, {Key? key}) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final locked = _freeLimitReachedForNewLeague || _checkingAccess;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_details_title'), Icons.edit_note),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          enabled: !locked,
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_league_name_required_label'),
            prefixIcon: const Icon(Icons.edit_note),
          ),
          onChanged: (_) {
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          enabled: !locked,
          minLines: 3,
          maxLines: 7,
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            labelText:
                l10n.tr('league_create_league_description_recommended_label'),
            alignLabelWithHint: true,
            prefixIcon: const Icon(Icons.subject),
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Images (optional)', Icons.image_outlined),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _leagueImageUrl,
          label: 'League image (optional)',
          uploading: _uploadingLeagueImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.leagueImage),
          onClear:
              locked ? () {} : () => setState(() => _leagueImageUrl.text = ''),
        ),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _sponsorImageUrl,
          label: 'Sponsor image (optional)',
          uploading: _uploadingSponsorImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.sponsorImage),
          onClear:
              locked ? () {} : () => setState(() => _sponsorImageUrl.text = ''),
        ),
      ],
    );
  }

  Widget _stepPrivacy(BuildContext context, {Key? key}) {
    final l10n = context.l10n;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_privacy_title'), Icons.lock),
        const SizedBox(height: 10),
        _privacyTile(
          value: LeaguePrivacy.public,
          title: l10n.tr('league_create_public_title'),
          subtitle: l10n.tr('league_create_public_subtitle'),
        ),
        const SizedBox(height: 10),
        _privacyTile(
          value: LeaguePrivacy.private,
          title: l10n.tr('league_create_private_title'),
          subtitle: l10n.tr('league_create_private_subtitle'),
        ),
      ],
    );
  }

  Widget _privacyTile({
    required LeaguePrivacy value,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final selected = _privacy == value;

    final fill = selected
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : _panelFill(theme);

    final border = selected
        ? AppTheme.limeAccentDark
        : _panelBorder(theme);

    return InkWell(
      onTap: (_freeLimitReachedForNewLeague || _checkingAccess)
          ? null
          : () => setState(() => _privacy = value),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: fill,
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? AppTheme.limeAccentDark
                  : AppTheme.secondaryText(brightness),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          height: 1.25,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepPayment(BuildContext context, {Key? key}) {
    if (_checkingAccess) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Creation status', Icons.verified_rounded),
          const SizedBox(height: 10),
          _infoBanner(
            icon: Icons.hourglass_top_rounded,
            title: 'Checking your access...',
            subtitle: 'Please wait before continuing.',
            accent: AppTheme.limeAccentDark,
          ),
        ],
      );
    }

    if (_freeLimitReachedForNewLeague) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Upgrade required', Icons.workspace_premium_rounded),
          const SizedBox(height: 10),
          _infoBanner(
            icon: Icons.workspace_premium_rounded,
            title: 'Basic limit reached',
            subtitle: _freeLimitText,
            accent: _premiumAmber,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: _submitting ? null : _openPlanUpgradeFlow,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text(
              'Upgrade Plan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Creation status', Icons.verified_rounded),
        const SizedBox(height: 10),
        _infoBanner(
          icon: Icons.verified_rounded,
          title: _isPaidPlanUser
              ? 'Included in your paid plan'
              : 'Included in your Basic allowance',
          subtitle: _isPaidPlanUser
              ? 'Your paid plan includes additional league and competition creation.'
              : 'Basic users can create up to $_freeLeagueListLimit leagues/competitions total across all creation flows.',
          accent: AppTheme.limeAccentDark,
        ),
      ],
    );
  }

  Widget _stepConfirm(BuildContext context, {Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final canCreate = _type != null &&
        _name.text.trim().isNotEmpty &&
        !_checkingAccess &&
        _hasLeagueAccess &&
        !_freeLimitReachedForNewLeague;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          l10n.tr('league_create_confirm_title'),
          Icons.check_circle_outline,
        ),
        const SizedBox(height: 10),
        _infoBanner(
          icon: _typeIcon,
          title: _typeLabel,
          subtitle: _name.text.trim().isEmpty
              ? l10n.tr('league_create_league_name_not_set')
              : _name.text.trim(),
        ),
        const SizedBox(height: 10),
        if (_inMasterLeagueMode)
          _confirmRow(
            Icons.hub_rounded,
            'Master League',
            'Inside Master League',
            valueColor: AppTheme.limeAccentDark,
          ),
        _confirmRow(
          Icons.lock,
          l10n.tr('league_create_confirm_privacy_label'),
          _privacy == LeaguePrivacy.private
              ? l10n.tr('league_create_private')
              : l10n.tr('league_create_public'),
        ),
        _confirmRow(
          Icons.groups,
          l10n.tr('league_create_confirm_max_teams_label'),
          '$_maxTeams',
        ),
        if (_supportsHomeAwayMatches)
          _confirmRow(
            Icons.swap_horiz,
            'Home & away matches',
            _homeAwayEnabled ? 'Enabled' : 'Disabled',
            valueColor: _homeAwayEnabled
                ? AppTheme.limeAccentDark
                : AppTheme.secondaryText(brightness),
          ),
        _confirmRow(
          Icons.card_giftcard_outlined,
          'Rewards',
          _containsRewards ? 'Enabled' : 'Disabled',
          valueColor: _containsRewards
              ? AppTheme.limeAccentDark
              : AppTheme.secondaryText(brightness),
        ),
        const SizedBox(height: 12),
        if (_freeLimitReachedForNewLeague) ...[
          _infoBanner(
            icon: Icons.workspace_premium_rounded,
            title: 'Upgrade required',
            subtitle: _freeLimitText,
            accent: _premiumAmber,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: _submitting ? null : _openPlanUpgradeFlow,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text(
              'Upgrade Plan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ] else ...[
          _infoBanner(
            icon: Icons.verified_rounded,
            title: _isPaidPlanUser
                ? 'Included in your paid plan'
                : 'Included in your Basic allowance',
            subtitle: _inMasterLeagueMode
                ? 'This competition uses the same shared creation allowance as normal leagues.'
                : 'You can create this league now.',
            accent: AppTheme.limeAccentDark,
          ),
        ],
        const SizedBox(height: 12),
        if (_supportsHomeAwayMatches) ...[
          _softPanel(
            child: CheckboxListTile.adaptive(
              value: _homeAwayEnabled,
              onChanged:
                  (_submitting || _freeLimitReachedForNewLeague || _checkingAccess)
                      ? null
                      : (v) {
                          setState(() => _homeAwayEnabled = v ?? false);
                        },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.limeAccentDark,
              checkColor: Colors.white,
              title: Text(
                'Home and Away Matches',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                _homeAwayEnabled
                    ? 'Each team plays twice (home + away).'
                    : 'Each team plays once.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _softPanel(
          child: SwitchListTile.adaptive(
            value: _creatorWillParticipate,
            onChanged:
                (_submitting || _freeLimitReachedForNewLeague || _checkingAccess)
                    ? null
                    : (v) => setState(() => _creatorWillParticipate = v),
            activeColor: AppTheme.limeAccentDark,
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.tr('league_create_creator_participate_title'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              l10n.tr('league_create_creator_participate_subtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _freeLimitReachedForNewLeague
              ? _freeLimitText
              : l10n.tr('league_create_admin_notice'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _freeLimitReachedForNewLeague
                ? _premiumAmber
                : AppTheme.secondaryText(brightness),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_submitting || !canCreate) ? null : () => _create(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.limeAccent,
            foregroundColor: AppTheme.darkText,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.darkText,
                  ),
                )
              : Text(
                  _freeLimitReachedForNewLeague
                      ? 'UPGRADE PLAN'
                      : (_inMasterLeagueMode
                          ? 'CREATE COMPETITION'
                          : l10n.tr('league_create_create_league_button_upper')),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.iconCircleBackground(brightness),
            border: Border.all(color: AppTheme.cardBorder(brightness)),
          ),
          child: Icon(icon, size: 18, color: AppTheme.limeAccentDark),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _confirmRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.limeAccentDark),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final a = accent ?? AppTheme.limeAccentDark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: a, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                  height: 1.25,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final isLast = _step == 4;
    final backLabel =
        _step == 0 ? l10n.tr('common_cancel') : l10n.tr('common_back');

    if (isLast && _createdLeague == null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () {
                      setState(() => _step = max(0, _step - 1));
                    },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: AppTheme.cardBorder(brightness),
                ),
                foregroundColor: AppTheme.primaryText(brightness),
              ),
              child: Text(
                backLabel.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      );
    }

    final nextLabel = l10n.tr('common_next');

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _submitting
                ? null
                : () {
                    if (_step == 0) {
                      context.pop();
                      return;
                    }
                    setState(() => _step--);
                  },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                color: AppTheme.cardBorder(brightness),
              ),
              foregroundColor: AppTheme.primaryText(brightness),
            ),
            child: Text(
              backLabel.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed:
                (_submitting || _checkingAccess || _freeLimitReachedForNewLeague)
                    ? null
                    : () async {
                        final ok = await _validateAndAdvance(context);
                        if (ok && mounted) setState(() => _step++);
                      },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              nextLabel.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 1040;

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) {
      return GlassScaffold(
        useBubbles: false,
        appBar: AppBar(
          title: Text(
            _inMasterLeagueMode
                ? 'Create Competition'
                : l10n.tr('league_create_appbar_title'),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _flatPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.login,
                        color: AppTheme.limeAccentDark,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to create a league.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: () => context.pop(),
                        child: const Text('Close'),
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

    if (_createdLeague != null) {
      final league = _createdLeague!;
      final qrColor =
          theme.brightness == Brightness.dark ? Colors.white : Colors.black;

      return GlassScaffold(
        useBubbles: false,
        appBar: AppBar(
          title: Text(
            _inMasterLeagueMode
                ? 'Competition Created'
                : l10n.tr('league_create_created_title'),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(18, 24, 18, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 980 : 560),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LeagueFlipCard(
                                  leagueId: league.id,
                                  leagueName: league.name,
                                  leagueCode: league.code,
                                  distribution:
                                      '${league.format.displayName} • ${league.season}',
                                  subtitle:
                                      '0 / ${league.maxTeams} ${l10n.tr('leagues_teams_word')}',
                                  onDoubleTap: () =>
                                      context.push('/leagues/${league.id}'),
                                  qrWidget: QrImageView(
                                    data: league.qrPayload,
                                    version: QrVersions.auto,
                                    gapless: true,
                                    eyeStyle: QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: qrColor,
                                    ),
                                    dataModuleStyle: QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: qrColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _flatPanel(
                                  child: Column(
                                    children: [
                                      Text(
                                        l10n.tr('league_create_share_hint'),
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                          color: AppTheme.secondaryText(brightness),
                                          height: 1.4,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_inMasterLeagueMode) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          'League created successfully inside Master League container',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: const Color(0xFF16A34A),
                                            height: 1.35,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.limeAccent,
                                                foregroundColor:
                                                    AppTheme.darkText,
                                              ),
                                              onPressed: () {
                                                if (_inMasterLeagueMode) {
                                                  context.go(
                                                    '/master-leagues/${_masterLeagueId.trim()}',
                                                  );
                                                  return;
                                                }
                                                openHomeShellTab(1);
                                                context.go('/');
                                              },
                                              child: Text(
                                                l10n.tr(
                                                    'league_create_done_upper'),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => context.push(
                                                '/leagues/add-teams',
                                                extra: {
                                                  'leagueId': league.id,
                                                  'format': league.format,
                                                },
                                              ),
                                              child: Text(
                                                l10n.tr(
                                                    'league_create_add_teams_upper'),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () =>
                                            context.push('/leagues/${league.id}'),
                                        child: Text(
                                          l10n.tr(
                                            'league_create_open_league_details_upper',
                                          ),
                                          style: TextStyle(
                                            color: AppTheme.limeAccentDark,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: _buildSummaryCard(context),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LeagueFlipCard(
                            leagueId: league.id,
                            leagueName: league.name,
                            leagueCode: league.code,
                            distribution:
                                '${league.format.displayName} • ${league.season}',
                            subtitle:
                                '0 / ${league.maxTeams} ${l10n.tr('leagues_teams_word')}',
                            onDoubleTap: () => context.push('/leagues/${league.id}'),
                            qrWidget: QrImageView(
                              data: league.qrPayload,
                              version: QrVersions.auto,
                              gapless: true,
                              eyeStyle: QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: qrColor,
                              ),
                              dataModuleStyle: QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: qrColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _flatPanel(
                            child: Column(
                              children: [
                                Text(
                                  l10n.tr('league_create_share_hint'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.secondaryText(brightness),
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppTheme.limeAccent,
                                          foregroundColor: AppTheme.darkText,
                                        ),
                                        onPressed: () {
                                          if (_inMasterLeagueMode) {
                                            context.go(
                                              '/master-leagues/${_masterLeagueId.trim()}',
                                            );
                                            return;
                                          }
                                          openHomeShellTab(1);
                                          context.go('/');
                                        },
                                        child: Text(
                                          l10n.tr('league_create_done_upper'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => context.push(
                                          '/leagues/add-teams',
                                          extra: {
                                            'leagueId': league.id,
                                            'format': league.format,
                                          },
                                        ),
                                        child: Text(
                                          l10n.tr(
                                              'league_create_add_teams_upper'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      useBubbles: false,
      appBar: AppBar(
        title: Text(
          _inMasterLeagueMode
              ? 'Create Competition'
              : l10n.tr('league_create_appbar_title'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final contentMax = maxWidth >= 1200
                  ? 1240.0
                  : (maxWidth >= 900 ? 980.0 : 620.0);

              if (!isWide) {
                return SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: Column(
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 16),
                        _buildStatusCard(context),
                        const SizedBox(height: 16),
                        _buildMainStage(context),
                        const SizedBox(height: 16),
                        _buildSummaryCard(context),
                      ],
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMax),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            _buildHeader(context),
                            const SizedBox(height: 16),
                            _buildStatusCard(context),
                            const SizedBox(height: 16),
                            _buildMainStage(context),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildSummaryCard(context),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OptionalImageField extends StatelessWidget {
  const _OptionalImageField({
    required this.controller,
    required this.label,
    required this.uploading,
    required this.onUpload,
    required this.onClear,
  });

  final TextEditingController controller;
  final String label;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback onClear;

  Uint8List? _tryDecodeDataUri(String raw) {
    final s = raw.trim();
    if (!s.startsWith('data:image')) return null;
    final idx = s.indexOf('base64,');
    if (idx < 0) return null;
    final b64 = s.substring(idx + 'base64,'.length);
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final previewFill = AppTheme.searchBackground(brightness);
    final previewBorder = AppTheme.searchOutline(brightness);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final raw = value.text.trim();
        final bytes = raw.isEmpty ? null : _tryDecodeDataUri(raw);
        final hasImage = raw.isNotEmpty;

        final preview = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: previewFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: previewBorder),
            boxShadow: AppTheme.softCardShadow(brightness),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : (hasImage
                    ? Image.network(
                        raw,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.image_outlined,
                          color: AppTheme.secondaryText(brightness),
                        ),
                      )
                    : Icon(
                        Icons.image_outlined,
                        color: AppTheme.secondaryText(brightness),
                      )),
          ),
        );

        final String statusText = uploading
            ? 'Uploading...'
            : hasImage
                ? 'Uploaded'
                : 'No image selected';

        final IconData tickIcon =
            hasImage ? Icons.check_box : Icons.check_box_outline_blank;
        final Color tickColor = hasImage
            ? AppTheme.limeAccentDark
            : AppTheme.secondaryText(brightness);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            preview,
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(tickIcon, size: 16, color: tickColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: uploading
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.limeAccentDark,
                          ),
                        )
                      : IconButton(
                          tooltip: 'Upload',
                          onPressed: onUpload,
                          icon: const Icon(Icons.cloud_upload_outlined),
                        ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    tooltip: hasImage ? 'Clear' : 'Clear (disabled)',
                    onPressed: (!uploading && hasImage) ? onClear : null,
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StepMeta {
  final String title;
  final IconData icon;

  const _StepMeta(this.title, this.icon);
}
