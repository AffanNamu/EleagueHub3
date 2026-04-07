import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

    final String templateName =
        (extra['templateName'] as String?)?.trim() ?? '';
    final String templateDescription =
        (extra['templateDescription'] as String?)?.trim() ?? '';
    final String templatePrivacy =
        (extra['templatePrivacy'] as String?)?.trim().toLowerCase() ?? '';
    final bool templateHomeAwayEnabled =
        extra['templateHomeAwayEnabled'] == true;
    final bool templateContainsRewards =
        extra['templateContainsRewards'] == true;
    final int? templateMaxTeams = extra['maxTeams'] is int
        ? extra['maxTeams'] as int
        : (extra['maxTeams'] is num
            ? (extra['maxTeams'] as num).toInt()
            : null);

    LeagueCreationType? inferredType;
    if (initialFormat != null) {
      inferredType = _creationTypeFromFormat(initialFormat);
    } else if (typeString != null && typeString.isNotEmpty) {
      inferredType = _creationTypeFromString(typeString);
    }

    if (!mounted) return;

    setState(() {
      _masterLeagueId = ml;

      if (templateName.isNotEmpty) {
        _name.text = templateName;
      }
      if (templateDescription.isNotEmpty) {
        _description.text = templateDescription;
      }
      if (templatePrivacy == 'public') {
        _privacy = LeaguePrivacy.public;
      } else if (templatePrivacy == 'private') {
        _privacy = LeaguePrivacy.private;
      }

      _containsRewards = templateContainsRewards;

      if (inferredType != null) {
        _type = inferredType;

        final fmt = _format;

        if (templateMaxTeams != null &&
            _allowedMaxTeams.contains(templateMaxTeams)) {
          _selectedMaxTeams = templateMaxTeams;
        } else if (fmt == LeagueFormat.uclGroup) {
          _selectedMaxTeams = 32;
        } else if (fmt == LeagueFormat.uclSwiss) {
          _selectedMaxTeams = 36;
        } else {
          _selectedMaxTeams = 20;
        }

        if (_supportsHomeAwayMatches) {
          _homeAwayEnabled = templateHomeAwayEnabled;
        } else {
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

  List<BoxShadow>? _panelShadow(ThemeData theme, {Color? tint}) {
    return AppTheme.softCardShadow(theme.brightness);
  }

  Future<bool> _validateAndAdvance(BuildContext context) async {
    final l10n = context.l10n;

    if (_checkingAccess) {
      _showSnack('Checking your access. Please wait.');
      return false;
    }

    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return false;
    }

    if (_freeLimitReachedForNewLeague) {
      _showSnack(_freeLimitText);
      return false;
    }

    if (_step == 0) {
      if (_type == null) {
        _showSnack(l10n.tr('league_create_error_select_type'));
        return false;
      }
      return true;
    }

    if (_step == 1) {
      if (_name.text.trim().isEmpty) {
        _showSnack(l10n.tr('league_create_error_name_required'));
        return false;
      }
      return true;
    }

    return true;
  }

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_checkingAccess) {
      _showSnack('Checking your access. Please wait.');
      return;
    }

    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return;
    }

    if (_freeLimitReachedForNewLeague) {
      await _openPlanUpgradeFlow();
      return;
    }

    if (_type == null) {
      _showSnack(l10n.tr('league_create_error_select_type'));
      return;
    }

    if (_name.text.trim().isEmpty) {
      _showSnack(l10n.tr('league_create_error_name_required'));
      return;
    }

    if (!_allowedMaxTeams.contains(_maxTeams)) {
      _showSnack(l10n.tr('league_create_error_invalid_team_count'));
      return;
    }

    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final organizerAuthUid =
          (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (organizerAuthUid.isEmpty) {
        if (mounted) context.go('/login');
        throw FirebaseAuthException(code: 'unauthenticated');
      }

      final derivedShareId =
          UserProfile.deriveShareIdFromUid(organizerAuthUid).trim();
      final organizerUserId =
          derivedShareId.isNotEmpty ? derivedShareId : organizerAuthUid;

      if (_creatorWillParticipate) {
        final profile = await UserProfileRepository()
            .fetchByUserId(organizerAuthUid)
            .timeout(const Duration(seconds: 12));
        final name = profile?.teamName.trim() ?? '';
        if (name.isEmpty) {
          throw StateError(
            l10n.tr('league_create_error_profile_team_name_missing'),
          );
        }
      }

      final effectiveHomeAwayEnabled =
          _supportsHomeAwayMatches ? _homeAwayEnabled : false;

      final now = DateTime.now().millisecondsSinceEpoch;

      final baseDefaults = LeagueSettings.defaultsFor(_format);
      final settings = baseDefaults.copyWith(
        doubleRoundRobin: _supportsHomeAwayMatches
            ? effectiveHomeAwayEnabled
            : baseDefaults.doubleRoundRobin,
        lastPulledAtMs: 0,
      );

      final joinCode = await _generateUniqueJoinCode().timeout(
        const Duration(seconds: 12),
      );

      final requestedLeagueId = _inMasterLeagueMode ? '' : _draftLeagueId;

      final league = League(
        id: requestedLeagueId,
        name: _name.text.trim(),
        masterLeagueId: _masterLeagueId.trim(),
        description: _description.text.trim(),
        leagueImageUrl: _leagueImageUrl.text.trim(),
        sponsorImageUrl: _sponsorImageUrl.text.trim(),
        viewerCapacity: 0,
        couponsEnabled: false,
        couponDiscountPercent: 0,
        couponCount: 0,
        homeAwayEnabled: effectiveHomeAwayEnabled,
        format: _format,
        privacy: _privacy,
        region: 'Global',
        maxTeams: _maxTeams,
        season: '2026',
        organizerUid: organizerAuthUid,
        organizerUserId: organizerUserId,
        code: joinCode,
        qrPayloadOverride: '',
        settings: settings,
        updatedAtMs: now,
        version: 1,
      );

      final created = await _createLeagueOnline(
        league: league,
      ).timeout(const Duration(seconds: 35));

      if (_inMasterLeagueMode) {
        try {
          final ownerProfile =
              await UserProfileRepository().fetchByUserId(organizerAuthUid);
          final actorName = ownerProfile?.teamName.trim().isNotEmpty == true
              ? ownerProfile!.teamName.trim()
              : 'Organizer';

          await _organizerFeed.addCompetitionCreatedEvent(
            masterLeagueId: _masterLeagueId.trim(),
            leagueId: created.id,
            actorId: organizerAuthUid,
            actorName: actorName,
            competitionName: created.name,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _createdLeague = created;
        _submitting = false;
        _currentLeagueCardCount = _currentLeagueCardCount + 1;
      });

      if (_inMasterLeagueMode) {
        debugPrint('League created successfully inside Master League container');
        if (!mounted) return;
        _showSnack('League created successfully inside Master League container');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      final msg = UserFriendlyError.toMessage(
        e is Object ? e : Exception('unknown'),
      );
      _showSnack(
        '${l10n.tr('league_create_error_failed_to_create_prefix')}: $msg',
      );
    }
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final steps = <_StepMeta>[
      _StepMeta(l10n.tr('league_create_step_type'), Icons.auto_awesome),
      _StepMeta(l10n.tr('league_create_step_details'), Icons.edit_note),
      _StepMeta(l10n.tr('league_create_step_privacy'), Icons.lock),
      _StepMeta(
        l10n.tr('league_create_step_payment'),
        Icons.payments_outlined,
      ),
      _StepMeta(
        l10n.tr('league_create_step_confirm'),
        Icons.check_circle_outline,
      ),
    ];

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_inMasterLeagueMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: brightness == Brightness.dark
                    ? AppTheme.limeAccentDark.withOpacity(0.10)
                    : const Color(0xFFECFCCB),
                border: Border.all(color: AppTheme.cardBorder(brightness)),
                boxShadow: _panelShadow(theme, tint: AppTheme.limeAccentDark),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.hub_rounded,
                    color: AppTheme.limeAccentDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Creating inside Master League',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.limeAccentDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_inMasterLeagueMode) const SizedBox(height: 12),
          Text(
            _inMasterLeagueMode
                ? 'Create Competition'
                : l10n.tr('league_create_header_title'),
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: _stepPill(
                    title: steps[i].title,
                    icon: steps[i].icon,
                    index: i,
                    current: _step,
                  ),
                ),
                if (i != steps.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_step + 1) / steps.length,
              minHeight: 8,
              backgroundColor: AppTheme.searchOutline(brightness),
              color: AppTheme.limeAccentDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: _checkingAccess
          ? _infoBanner(
              icon: Icons.hourglass_top_rounded,
              title: 'Checking your access...',
              subtitle:
                  'Please wait while we load your Basic or paid entitlement.',
              accent: AppTheme.limeAccentDark,
            )
          : _freeLimitReachedForNewLeague
              ? _infoBanner(
                  icon: Icons.lock_rounded,
                  title: 'Basic limit reached',
                  subtitle: _freeLimitText,
                  accent: _premiumAmber,
                )
              : _isPaidPlanUser
                  ? _infoBanner(
                      icon: Icons.verified_rounded,
                      title: 'Paid plan active',
                      subtitle:
                          '$_activePlanLabel plan active. You can create more leagues and competitions.',
                      accent: AppTheme.limeAccentDark,
                    )
                  : _infoBanner(
                      icon: Icons.layers_outlined,
                      title: 'Basic/free access active',
                      subtitle:
                          'You have used $_currentLeagueCardCount / $_freeLeagueListLimit free league/competition slots.',
                      accent: AppTheme.limeAccentDark,
                    ),
    );
  }

  Widget _buildMainStage(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _stepBody(context, key: ValueKey<int>(_step)),
          ),
          const SizedBox(height: 16),
          _buildFooterActions(context),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_create_summary_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            _isPaidPlanUser
                ? Icons.verified_rounded
                : Icons.layers_outlined,
            'Access',
            _isPaidPlanUser
                ? _activePlanLabel
                : 'Basic • $_currentLeagueCardCount / $_freeLeagueListLimit used',
            valueColor: _isPaidPlanUser
                ? AppTheme.limeAccentDark
                : (_freeLimitReachedForNewLeague
                    ? _premiumAmber
                    : AppTheme.primaryText(brightness)),
          ),
          if (_freeLimitReachedForNewLeague)
            _summaryRow(
              Icons.lock_rounded,
              'Limit',
              'Reached',
              valueColor: _premiumAmber,
            ),
          if (_inMasterLeagueMode)
            _summaryRow(
              Icons.hub_rounded,
              'Master',
              'Inside Master League',
              valueColor: AppTheme.limeAccentDark,
            ),
          _summaryRow(
            Icons.auto_awesome,
            l10n.tr('league_create_summary_type_label'),
            _typeLabel,
          ),
          _summaryRow(
            Icons.label,
            l10n.tr('league_create_summary_name_label'),
            _name.text.trim().isEmpty
                ? l10n.tr('league_create_summary_not_set')
                : _name.text.trim(),
          ),
          _summaryRow(
            Icons.lock,
            l10n.tr('league_create_summary_privacy_label'),
            _privacy == LeaguePrivacy.private
                ? l10n.tr('league_create_private')
                : l10n.tr('league_create_public'),
          ),
          _summaryRow(
            Icons.groups,
            l10n.tr('league_create_summary_max_teams_label'),
            '$_maxTeams',
          ),
          if (_supportsHomeAwayMatches)
            _summaryRow(
              Icons.swap_horiz,
              'Home/Away',
              _homeAwayEnabled ? 'Enabled' : 'Disabled',
              valueColor: _homeAwayEnabled
                  ? AppTheme.limeAccentDark
                  : AppTheme.secondaryText(brightness),
            ),
          _summaryRow(
            Icons.card_giftcard_outlined,
            'Rewards',
            _containsRewards ? 'Yes' : 'No',
            valueColor: _containsRewards
                ? AppTheme.limeAccentDark
                : AppTheme.secondaryText(brightness),
          ),
          _summaryRow(
            Icons.verified,
            l10n.tr('league_create_summary_creation_fee_label'),
            _freeLimitReachedForNewLeague
                ? 'Upgrade required'
                : (_isPaidPlanUser
                    ? 'Included in paid plan'
                    : 'Included in Basic allowance'),
            valueColor: _freeLimitReachedForNewLeague
                ? _premiumAmber
                : AppTheme.limeAccentDark,
          ),
          const SizedBox(height: 10),
          Text(
            _freeLimitReachedForNewLeague
                ? _freeLimitText
                : (_inMasterLeagueMode
                    ? 'This competition will use the same shared Basic creation allowance as normal leagues.'
                    : 'Normal leagues and Organizer/Master League competitions share the same Basic creation allowance.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _freeLimitReachedForNewLeague
                  ? _premiumAmber
                  : AppTheme.secondaryText(brightness),
              height: 1.35,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_freeLimitReachedForNewLeague) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
            ),
          ],
        ],
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
