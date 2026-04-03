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
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/leagues_repository_firebase.dart';
import '../logic/coupon_config_service.dart';
import '../logic/league_media_service.dart';
import '../logic/league_premium_upgrade_helper.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import 'screens/edit_league_rewards_screen.dart';

class LeagueCreateWizard extends ConsumerStatefulWidget {
  const LeagueCreateWizard({
    super.key,
    this.masterLeagueId = '',
    this.initialFormat,
  });

  final String masterLeagueId;
  final LeagueFormat? initialFormat;

  @override
  ConsumerState<LeagueCreateWizard> createState() => _LeagueCreateWizardState();
}

class _LeagueCreateWizardState extends ConsumerState<LeagueCreateWizard> {
  final _uuid = const Uuid();
  late final String _draftLeagueId;

  static const int _freeLeagueListLimit = 3;

  int _step = 0;

  final _name = TextEditingController();
  final _description = TextEditingController();

  final _leagueImageUrl = TextEditingController();
  final _sponsorImageUrl = TextEditingController();

  bool _uploadingLeagueImage = false;
  bool _uploadingSponsorImage = false;

  late LeagueFormat _format;
  LeaguePrivacy _privacy = LeaguePrivacy.private;

  bool _doubleRoundRobin = false;
  bool _homeAwayEnabled = false;
  bool _containsRewards = false;

  bool _submitting = false;
  League? _createdLeague;

  bool _checkingAccess = true;
  bool _hasLeagueAccess = false;
  bool _isPaidPlanUser = false;
  int _currentLeagueCardCount = 0;
  String _activePlanLabel = 'Basic';

  static const Color _premiumAmber = Color(0xFFF59E0B);

  bool get _inMasterLeagueMode => widget.masterLeagueId.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _draftLeagueId = _uuid.v4();
    _format = widget.initialFormat ?? LeagueFormat.classic;

    if (!_supportsHomeAwayMatches) {
      _homeAwayEnabled = false;
      _doubleRoundRobin = false;
    }

    _loadAccessState();
  }

  Future<void> _loadAccessState() async {
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
        _activePlanLabel = isPaid ? (activePlan?.displayName ?? 'Paid Plan') : 'Basic';
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
    final snap = await FirebaseFirestore.instance
        .collection('leagues')
        .where('organizerUid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    return snap.docs.length;
  }

  bool get _basicLimitReachedForNewLeague =>
      _hasLeagueAccess &&
      !_isPaidPlanUser &&
      _currentLeagueCardCount >= _freeLeagueListLimit;

  String get _basicLimitText =>
      'Basic users can create up to $_freeLeagueListLimit leagues/competitions total. This total is shared across normal leagues and competitions created inside Organizer or Master League workspace. Upgrade to Pro or Elite to create more.';

  Future<void> _openPlanUpgradeFlow() async {
    if (_submitting) return;

    final success = await LeaguePremiumUpgradeHelper.openUpgradeFlow(
      context,
      leagueName:
          _name.text.trim().isEmpty ? 'Organizer Plan' : _name.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      _showSnack('Plan purchase completed. Refreshing access...');
      await _loadAccessState();
      return;
    }

    _showSnack('Plan purchase cancelled.');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _leagueImageUrl.dispose();
    _sponsorImageUrl.dispose();
    super.dispose();
  }

  bool get _isLight => Theme.of(context).brightness == Brightness.light;

  Color _softPanelFill(ThemeData theme) {
    if (theme.brightness == Brightness.light) {
      return Colors.white.withOpacity(0.38);
    }
    return theme.colorScheme.onSurface.withOpacity(0.04);
  }

  Color _softPanelBorder(ThemeData theme, {Color? accent}) {
    if (theme.brightness == Brightness.light) {
      final a = accent ?? theme.colorScheme.primary;
      return Color.alphaBlend(
        a.withOpacity(0.14),
        Colors.white.withOpacity(0.70),
      );
    }
    return theme.colorScheme.onSurface.withOpacity(0.10);
  }

  List<BoxShadow>? _softPanelShadow(ThemeData theme, {Color? tint}) {
    if (theme.brightness != Brightness.light) return null;
    final c = tint ?? const Color(0xFFB4D2FF);
    return <BoxShadow>[
      BoxShadow(
        color: c.withOpacity(0.22),
        blurRadius: 28,
        offset: const Offset(0, 16),
      ),
    ];
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final msg = message.trim();
    if (msg.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _uploadImage({
    required LeagueMediaKind kind,
  }) async {
    if (_submitting) return;

    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return;
    }

    if (_basicLimitReachedForNewLeague) {
      _showSnack(_basicLimitText);
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
        _showSnack('Image not selected or upload failed. Please try again.');
        return;
      }

      setState(() {
        if (kind == LeagueMediaKind.leagueImage) {
          _leagueImageUrl.text = url;
        } else {
          _sponsorImageUrl.text = url;
        }
      });

      _showSnack(context.l10n.tr('common_done'));
    } catch (e) {
      _showSnack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
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
    final firestore = FirebaseFirestore.instance;

    for (int i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (snap.docs.isEmpty) return code;
    }

    throw StateError(
      "We couldn't create a league code right now. Please try again.",
    );
  }

  Future<bool> _validateAndNext() async {
    final l10n = context.l10n;

    if (_checkingAccess) {
      _showSnack('Checking your access. Please wait.');
      return false;
    }

    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return false;
    }

    if (_basicLimitReachedForNewLeague) {
      _showSnack(_basicLimitText);
      return false;
    }

    if (_step == 0) {
      if (_name.text.trim().isEmpty) {
        _showSnack(l10n.tr('league_create_error_name_required'));
        return false;
      }
      setState(() => _step = 1);
      return true;
    }

    if (_step == 1) {
      setState(() => _step = 2);
      return true;
    }

    return true;
  }

  void _backOrClose() {
    if (_submitting) return;
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() => _step = max(0, _step - 1));
  }

  bool get _supportsHomeAwayMatches =>
      _format == LeagueFormat.classic || _format == LeagueFormat.uclGroup;

  int get _maxTeams {
    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
        return 32;
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (authUid.isEmpty) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('league_create_appbar_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, color: cs.primary, size: 44),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to create a league.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
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

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    if (_createdLeague != null) {
      final league = _createdLeague!;
      final qrColor =
          theme.brightness == Brightness.dark ? Colors.white : Colors.black;

      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('league_create_created_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 760 : 520),
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
                          '0 / ${league.maxTeams} ${l10n.tr('league_create_teams_word')}',
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
                    Glass(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            l10n.tr('league_create_share_hint'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.75),
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_inMasterLeagueMode) ...[
                            const SizedBox(height: 10),
                            Text(
                              'This competition was created inside your Master League.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.primary.withOpacity(0.95),
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
                                  onPressed: () {
                                    if (_inMasterLeagueMode) {
                                      context.go(
                                        '/master-leagues/${widget.masterLeagueId.trim()}',
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
                                    l10n.tr('league_create_add_teams_upper'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => context.push('/leagues/${league.id}'),
                            child: Text(
                              l10n.tr(
                                'league_create_open_league_details_upper',
                              ),
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (_containsRewards) ...[
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EditLeagueRewardsScreen(
                                      leagueId: league.id,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.card_giftcard_outlined),
                              label: const Text(
                                'Manage Rewards',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
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
                  ? 1180.0
                  : (maxWidth >= 900 ? 900.0 : 560.0);

              final main = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 720 : contentMax),
                child: _buildMainCard(context),
              );

              if (!isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: main,
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMax),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: _buildSideSummary(context),
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

  Widget _buildMainCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(),
          const SizedBox(height: 14),
          if (_checkingAccess)
            _limitStatusBanner(
              text: 'Checking your access...',
              color: cs.primary,
              icon: Icons.hourglass_top_rounded,
            )
          else if (_basicLimitReachedForNewLeague)
            _limitStatusBanner(
              text: _basicLimitText,
              color: _premiumAmber,
              icon: Icons.lock_rounded,
            )
          else if (_isPaidPlanUser)
            _limitStatusBanner(
              text:
                  '$_activePlanLabel plan active. You can create more than $_freeLeagueListLimit leagues/competitions.',
              color: cs.primary,
              icon: Icons.verified_rounded,
            )
          else
            _limitStatusBanner(
              text:
                  'Basic/free access: $_currentLeagueCardCount / $_freeLeagueListLimit league/competition slots used.',
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              icon: Icons.info_outline_rounded,
            ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _stepBody(key: ValueKey<int>(_step)),
          ),
          const SizedBox(height: 16),
          _buildFooterActions(context),
        ],
      ),
    );
  }

  Widget _limitStatusBanner({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color:
            color.withOpacity(theme.brightness == Brightness.light ? 0.10 : 0.12),
        border: Border.all(color: color.withOpacity(0.28)),
        boxShadow: _softPanelShadow(theme, tint: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideSummary(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget row(IconData icon, String label, String value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.70),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color ?? cs.onSurface,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_create_summary_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          row(
            _isPaidPlanUser
                ? Icons.verified_rounded
                : Icons.layers_outlined,
            'Access',
            _isPaidPlanUser
                ? _activePlanLabel
                : 'Basic • $_currentLeagueCardCount / $_freeLeagueListLimit used',
            color: _isPaidPlanUser
                ? cs.primary
                : (_basicLimitReachedForNewLeague
                    ? _premiumAmber
                    : cs.onSurface.withOpacity(0.78)),
          ),
          if (_basicLimitReachedForNewLeague)
            row(
              Icons.lock_rounded,
              'Limit',
              'Reached',
              color: _premiumAmber,
            ),
          if (_inMasterLeagueMode)
            row(
              Icons.hub_rounded,
              'Master',
              'Inside Master League',
              color: cs.primary,
            ),
          row(
            Icons.auto_awesome,
            l10n.tr('league_create_summary_type_label'),
            _format.displayName,
          ),
          row(
            Icons.label,
            l10n.tr('league_create_summary_name_label'),
            _name.text.trim().isEmpty
                ? l10n.tr('league_create_summary_not_set')
                : _name.text.trim(),
          ),
          row(
            Icons.lock,
            l10n.tr('league_create_summary_privacy_label'),
            _privacy == LeaguePrivacy.private
                ? l10n.tr('league_create_private')
                : l10n.tr('league_create_public'),
          ),
          row(
            Icons.groups,
            l10n.tr('league_create_summary_max_teams_label'),
            '$_maxTeams',
          ),
          if (_supportsHomeAwayMatches)
            row(
              Icons.swap_horiz,
              'Home/Away',
              _homeAwayEnabled ? 'Enabled' : 'Disabled',
              color: _homeAwayEnabled
                  ? cs.primary
                  : cs.onSurface.withOpacity(0.75),
            ),
          row(
            Icons.card_giftcard_outlined,
            'Rewards',
            _containsRewards ? 'Yes' : 'No',
            color: _containsRewards
                ? cs.primary
                : cs.onSurface.withOpacity(0.75),
          ),
          row(
            Icons.verified,
            l10n.tr('league_create_summary_creation_fee_label'),
            _basicLimitReachedForNewLeague
                ? 'Upgrade required'
                : (_isPaidPlanUser
                    ? 'Included in paid plan'
                    : 'Included in Basic allowance'),
            color: _basicLimitReachedForNewLeague
                ? _premiumAmber
                : cs.primary,
          ),
          const SizedBox(height: 10),
          Text(
            _basicLimitReachedForNewLeague
                ? _basicLimitText
                : (_inMasterLeagueMode
                    ? 'This competition uses the same shared Basic creation allowance as normal leagues.'
                    : 'Normal leagues and Organizer/Master League competitions share the same Basic creation allowance.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _basicLimitReachedForNewLeague
                  ? _premiumAmber
                  : cs.onSurface.withOpacity(0.60),
              height: 1.35,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_basicLimitReachedForNewLeague) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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

  String _unlockNote(AppLocalizations l10n) {
    if (_basicLimitReachedForNewLeague) {
      return _basicLimitText;
    }
    if (_inMasterLeagueMode) {
      return 'This competition uses the same shared Basic creation allowance as normal leagues.';
    }
    return 'League creation is included while you are within your Basic or paid access.';
  }

  Widget _buildStepHeader() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final steps = <_StepMeta>[
      _StepMeta(l10n.tr('league_create_wizard_step_basics'), Icons.edit_note),
      _StepMeta(l10n.tr('league_create_wizard_step_rules'), Icons.rule),
      _StepMeta(
        l10n.tr('league_create_wizard_step_review'),
        Icons.check_circle_outline,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _inMasterLeagueMode
              ? 'Create Competition'
              : l10n.tr('league_create_header_title'),
          style: theme.textTheme.titleLarge?.copyWith(
            color: cs.onSurface,
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
            backgroundColor: cs.onSurface.withOpacity(0.08),
            color: cs.primary,
          ),
        ),
      ],
    );
  }

  Widget _stepPill({
    required String title,
    required IconData icon,
    required int index,
    required int current,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final active = index == current;
    final done = index < current;

    final Color borderColor = active
        ? cs.primary.withOpacity(0.75)
        : done
            ? cs.primary.withOpacity(0.40)
            : (_isLight
                ? Colors.white.withOpacity(0.70)
                : cs.onSurface.withOpacity(0.14));

    final Color bgColor = active
        ? cs.primary.withOpacity(0.14)
        : done
            ? cs.onSurface.withOpacity(0.06)
            : (_isLight
                ? Colors.white.withOpacity(0.30)
                : cs.onSurface.withOpacity(0.04));

    final Color iconColor = active
        ? cs.primary
        : done
            ? cs.primary.withOpacity(0.85)
            : cs.onSurface.withOpacity(0.55);

    final Color textColor = active
        ? cs.primary
        : done
            ? cs.onSurface.withOpacity(0.75)
            : cs.onSurface.withOpacity(0.55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: _softPanelShadow(theme, tint: cs.primary),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
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

  Widget _stepBody({Key? key}) {
    switch (_step) {
      case 0:
        return _stepBasics(key: key);
      case 1:
        return _stepRules(key: key);
      case 2:
        return _stepReview(key: key);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepBasics({Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locked = _submitting || _basicLimitReachedForNewLeague || _checkingAccess;

    Widget formatChip(LeagueFormat fmt, String label) {
      final selected = _format == fmt;

      final unselectedBg = theme.brightness == Brightness.light
          ? Colors.white.withOpacity(0.34)
          : cs.onSurface.withOpacity(0.06);

      return ChoiceChip(
        selected: selected,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        selectedColor: cs.primary.withOpacity(0.18),
        backgroundColor: unselectedBg,
        side: BorderSide(
          color: selected
              ? cs.primary.withOpacity(0.35)
              : (theme.brightness == Brightness.light
                  ? Colors.white.withOpacity(0.70)
                  : cs.onSurface.withOpacity(0.12)),
        ),
        labelStyle: TextStyle(
          color: selected ? cs.primary : cs.onSurface.withOpacity(0.72),
          fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
        ),
        onSelected: locked
            ? null
            : (v) {
                if (!v) return;
                setState(() {
                  _format = fmt;

                  if (!_supportsHomeAwayMatches) {
                    _homeAwayEnabled = false;
                    _doubleRoundRobin = false;
                  }
                });
              },
      );
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Basics', Icons.edit_note),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          enabled: !locked,
          decoration: const InputDecoration(
            labelText: 'League name (required)',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          enabled: !locked,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            prefixIcon: Icon(Icons.subject_outlined),
            alignLabelWithHint: true,
          ),
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Format', Icons.auto_awesome),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            formatChip(LeagueFormat.classic, 'Classic'),
            formatChip(LeagueFormat.uclGroup, 'Group'),
            formatChip(LeagueFormat.uclSwiss, 'Series'),
          ],
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

  Widget _stepRules({Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locked = _submitting || _basicLimitReachedForNewLeague || _checkingAccess;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Rules & Access', Icons.rule),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: _softPanelFill(theme),
            border: Border.all(color: _softPanelBorder(theme)),
            boxShadow: _softPanelShadow(theme),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: _privacy == LeaguePrivacy.private,
                onChanged: locked
                    ? null
                    : (v) => setState(
                          () => _privacy =
                              v ? LeaguePrivacy.private : LeaguePrivacy.public,
                        ),
                activeColor: cs.primary,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Private league',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  _privacy == LeaguePrivacy.private
                      ? 'Only members can view and join.'
                      : 'Anyone can view, join with code.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_supportsHomeAwayMatches) ...[
                Divider(color: cs.onSurface.withOpacity(0.12)),
                CheckboxListTile.adaptive(
                  value: _homeAwayEnabled,
                  onChanged: locked
                      ? null
                      : (v) {
                          final enabled = v ?? false;
                          setState(() {
                            _homeAwayEnabled = enabled;
                            _doubleRoundRobin = enabled;
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: cs.primary,
                  checkColor: Colors.white,
                  title: Text(
                    'Home and Away Matches',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    _homeAwayEnabled
                        ? 'Each team plays twice (home + away).'
                        : 'Each team plays once.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              Divider(color: cs.onSurface.withOpacity(0.12)),
              SwitchListTile.adaptive(
                value: _containsRewards,
                onChanged:
                    locked ? null : (v) => setState(() => _containsRewards = v),
                activeColor: cs.primary,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Does this league contain rewards?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  _containsRewards
                      ? 'Yes — you will be prompted to add rewards after creation.'
                      : 'No — you can add rewards later from League Admin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepReview({Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final canCreate =
        _name.text.trim().isNotEmpty &&
        !_checkingAccess &&
        _hasLeagueAccess &&
        !_basicLimitReachedForNewLeague;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Review', Icons.check_circle_outline),
        const SizedBox(height: 10),
        _infoBanner(
          icon: Icons.emoji_events_outlined,
          title: _name.text.trim().isEmpty
              ? l10n.tr('league_create_league_name_not_set')
              : _name.text.trim(),
          subtitle:
              '${_format.displayName} • $_maxTeams teams • ${_privacy == LeaguePrivacy.private ? 'Private' : 'Public'}',
        ),
        const SizedBox(height: 10),
        if (_inMasterLeagueMode)
          _confirmRow(
            Icons.hub_rounded,
            'Master League',
            'This competition will be inside your Master League',
            valueColor: cs.primary,
          ),
        if (_supportsHomeAwayMatches)
          _confirmRow(
            Icons.swap_horiz,
            'Home & away matches',
            _homeAwayEnabled ? 'Enabled' : 'Disabled',
            valueColor:
                _homeAwayEnabled ? cs.primary : cs.onSurface.withOpacity(0.75),
          ),
        _confirmRow(
          Icons.card_giftcard_outlined,
          'Rewards',
          _containsRewards ? 'Yes' : 'No',
          valueColor:
              _containsRewards ? cs.primary : cs.onSurface.withOpacity(0.75),
        ),
        const SizedBox(height: 10),
        if (_basicLimitReachedForNewLeague)
          _infoBanner(
            icon: Icons.workspace_premium_rounded,
            title: 'Upgrade required',
            subtitle: _basicLimitText,
            accent: _premiumAmber,
          )
        else
          _infoBanner(
            icon: Icons.verified_rounded,
            title: _inMasterLeagueMode
                ? (_isPaidPlanUser
                    ? 'Included in Master League / paid plan'
                    : 'Included in Master League / Basic allowance')
                : (_isPaidPlanUser
                    ? 'Included in your paid plan'
                    : 'Included in your Basic allowance'),
            subtitle: _inMasterLeagueMode
                ? 'This competition uses the same shared creation allowance as normal leagues.'
                : 'You can create this league now.',
            accent: cs.primary,
          ),
        const SizedBox(height: 12),
        if (_basicLimitReachedForNewLeague)
          FilledButton.icon(
            onPressed: _submitting ? null : _openPlanUpgradeFlow,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text(
              'Upgrade Plan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          )
        else
          FilledButton(
            onPressed: (_submitting || !canCreate) ? null : () => _create(context),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    l10n.tr('league_create_create_league_button_upper'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
      ],
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isLast = _step == 2;

    final outlineSide = BorderSide(
      color: theme.brightness == Brightness.light
          ? Colors.white.withOpacity(0.70)
          : cs.onSurface.withOpacity(0.18),
    );

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _submitting ? null : _backOrClose,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: outlineSide,
              foregroundColor: cs.onSurface.withOpacity(0.80),
            ),
            child: Text(
              (_step == 0
                      ? l10n.tr('common_cancel')
                      : l10n.tr('common_back'))
                  .toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed:
                (_submitting || isLast || _checkingAccess || _basicLimitReachedForNewLeague)
                    ? null
                    : () async {
                        await _validateAndNext();
                      },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              l10n.tr('common_next').toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
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
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.70),
              fontWeight: FontWeight.w900,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.primary.withOpacity(0.14),
            border: Border.all(color: cs.primary.withOpacity(0.35)),
            boxShadow: _softPanelShadow(theme, tint: cs.primary),
          ),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = accent ?? cs.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _softPanelFill(theme),
        border: Border.all(color: _softPanelBorder(theme, accent: a)),
        boxShadow: _softPanelShadow(theme, tint: a),
      ),
      child: Row(
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
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
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
    );
  }

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_submitting) return;

    if (_checkingAccess) {
      _showSnack('Checking your access. Please wait.');
      return;
    }

    if (!_hasLeagueAccess) {
      _showSnack('You need to sign in to create leagues.');
      return;
    }

    if (_basicLimitReachedForNewLeague) {
      await _openPlanUpgradeFlow();
      return;
    }

    if (_name.text.trim().isEmpty) {
      _showSnack(l10n.tr('league_create_error_name_required'));
      return;
    }

    setState(() => _submitting = true);

    try {
      final organizerUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (organizerUid.isEmpty) {
        throw StateError('unauthenticated');
      }

      final derivedShortId =
          UserProfile.deriveShareIdFromUid(organizerUid).trim();
      final organizerUserId =
          derivedShortId.isNotEmpty ? derivedShortId : organizerUid;

      final requestedLeagueId = _inMasterLeagueMode ? '' : _draftLeagueId;
      final now = DateTime.now().millisecondsSinceEpoch;

      final effectiveHomeAwayEnabled = _supportsHomeAwayMatches
          ? _homeAwayEnabled
          : false;

      final settings = LeagueSettings.defaultsFor(_format).copyWith(
        doubleRoundRobin: effectiveHomeAwayEnabled,
        lastPulledAtMs: 0,
      );

      _doubleRoundRobin = effectiveHomeAwayEnabled;

      final joinCode = await _generateUniqueJoinCode().timeout(
        const Duration(seconds: 12),
      );

      final pendingLeague = League(
        id: requestedLeagueId,
        name: _name.text.trim(),
        masterLeagueId: widget.masterLeagueId.trim(),
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
        region: l10n.tr('common_region_global'),
        maxTeams: _maxTeams,
        season: '2026',
        organizerUid: organizerUid,
        organizerUserId: organizerUserId,
        code: joinCode,
        qrPayloadOverride: '',
        settings: settings,
        updatedAtMs: now,
        version: 1,
      );

      final repo = LeaguesRepositoryFirebase();
      final savedLeagueId = await repo
          .saveLeague(pendingLeague)
          .timeout(const Duration(seconds: 25));

      final createdLeague = pendingLeague.copyWith(id: savedLeagueId);

      if (!mounted) return;
      setState(() {
        _createdLeague = createdLeague;
        _submitting = false;
        _currentLeagueCardCount = _currentLeagueCardCount + 1;
      });

      if (_containsRewards) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditLeagueRewardsScreen(
              leagueId: createdLeague.id,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      );
    }
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
    final cs = theme.colorScheme;

    final previewFill = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.40)
        : cs.onSurface.withOpacity(0.06);
    final previewBorder = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.72)
        : cs.onSurface.withOpacity(0.14);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final url = value.text.trim();
        final bytes = url.isEmpty ? null : _tryDecodeDataUri(url);
        final hasImage = url.isNotEmpty;

        final preview = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: previewFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: previewBorder),
            boxShadow: theme.brightness == Brightness.light
                ? <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFB4D2FF).withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                : (hasImage
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.image_outlined,
                          color: cs.onSurface.withOpacity(0.55),
                        ),
                      )
                    : Icon(
                        Icons.image_outlined,
                        color: cs.onSurface.withOpacity(0.55),
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
        final Color tickColor =
            hasImage ? cs.primary : cs.onSurface.withOpacity(0.45);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: label,
              image: true,
              child: preview,
            ),
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
                        color: cs.onSurface,
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
                              color: cs.onSurface.withOpacity(0.70),
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
                            color: cs.primary,
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
