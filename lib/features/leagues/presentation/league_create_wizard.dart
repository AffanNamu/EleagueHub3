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
import '../../../core/services/rewarded_ad_manager.dart';
import '../../../core/theme/app_theme.dart';
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

// ---------------------------------------------------------------------------
// Breakpoints — self-contained so this file has no cross-file dependency
// ---------------------------------------------------------------------------

class _BP {
  static const double tablet = 760;
  static const double desktop = 900;
  static const double wide = 1200;
}

// ---------------------------------------------------------------------------
// LeagueCreateWizard
// ---------------------------------------------------------------------------

class LeagueCreateWizard extends ConsumerStatefulWidget {
  const LeagueCreateWizard({
    super.key,
    this.masterLeagueId = '',
    this.initialFormat,
  });

  final String masterLeagueId;
  final LeagueFormat? initialFormat;

  @override
  ConsumerState<LeagueCreateWizard> createState() =>
      _LeagueCreateWizardState();
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

  bool _rewardGateInProgress = false;

  static const Color _premiumAmber = Color(0xFFF59E0B);

  bool get _inMasterLeagueMode => widget.masterLeagueId.trim().isNotEmpty;

  // ── Init ───────────────────────────────────────────────────────────────────

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

  // ── Access / plan loading ──────────────────────────────────────────────────

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
        _activePlanLabel =
            isPaid ? (activePlan?.displayName ?? 'Paid Plan') : 'Basic';
        _checkingAccess = false;
      });

      // Preload rewarded ad for free/basic users to reduce latency.
      if (!isPaid) {
        final placement =
            _inMasterLeagueMode ? 'create_competition' : 'create_league';
        unawaited(RewardedAdManager.instance.preload(placement: placement));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAccess = false;
        _hasLeagueAccess = true;
        _isPaidPlanUser = false;
        _currentLeagueCardCount = 0;
        _activePlanLabel = 'Basic';
      });

      final placement =
          _inMasterLeagueMode ? 'create_competition' : 'create_league';
      unawaited(RewardedAdManager.instance.preload(placement: placement));
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
      'Basic users can create up to $_freeLeagueListLimit '
      'leagues/competitions total. This total is shared across normal '
      'leagues and competitions created inside Organizer or Master League '
      'workspace. Upgrade to Pro or Elite to create more.';

  Future<void> _openPlanUpgradeFlow() async {
    if (_submitting || _rewardGateInProgress) return;
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

  // ── Theme helpers ──────────────────────────────────────────────────────────

  Color _softPanelFill(ThemeData theme) => AppTheme.cardColor(theme.brightness);

  Color _softPanelBorder(ThemeData theme, {Color? accent}) =>
      AppTheme.cardBorder(theme.brightness);

  List<BoxShadow>? _softPanelShadow(ThemeData theme, {Color? tint}) =>
      AppTheme.softCardShadow(theme.brightness);

  void _showSnack(String message) {
    if (!mounted) return;
    final msg = message.trim();
    if (msg.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Safe navigation ────────────────────────────────────────────────────────
  // Always use GoRouter.of(context) directly — context.push / context.pop
  // extensions can fail inside Offstage or nested navigator contexts.

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

  void _safeGo(String location) {
    try {
      GoRouter.of(context).go(location);
    } catch (e) {
      debugPrint('[LeagueCreateWizard] go($location) failed: $e');
    }
  }

  void _safePush(String location, {Object? extra}) {
    try {
      GoRouter.of(context).push(location, extra: extra);
    } catch (e) {
      debugPrint('[LeagueCreateWizard] push($location) failed: $e');
    }
  }

  // ── Image upload ───────────────────────────────────────────────────────────

  Future<void> _uploadImage({required LeagueMediaKind kind}) async {
    if (_submitting || _rewardGateInProgress) return;
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
          .pickAndUploadImage(leagueId: _draftLeagueId, kind: kind)
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

  // ── Join code ──────────────────────────────────────────────────────────────

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(
        length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueJoinCode() async {
    for (int i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await FirebaseFirestore.instance
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

  // ── Step navigation ────────────────────────────────────────────────────────

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
    if (_submitting || _rewardGateInProgress) return;
    if (_step == 0) {
      _safePop();
      return;
    }
    setState(() => _step = max(0, _step - 1));
  }

  // ── League properties ──────────────────────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    // ── Not signed in ────────────────────────────────────────────────────────
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
                constraints: const BoxConstraints(maxWidth: 480),
                child: Glass(
                  padding: const EdgeInsets.all(24),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login,
                          color: AppTheme.limeAccentDark, size: 44),
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
                        onPressed: _safePop,
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

    // ── Success screen ───────────────────────────────────────────────────────
    if (_createdLeague != null) {
      return _buildSuccessScreen(context);
    }

    // ── Main wizard ──────────────────────────────────────────────────────────
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isDesktop = w >= _BP.desktop;
            final contentMax =
                w >= _BP.wide ? 1100.0 : (w >= _BP.desktop ? 900.0 : 680.0);

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: w < _BP.tablet ? 16 : 24,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMax),
                  child: isDesktop
                      ? _buildDesktopLayout(context)
                      : _buildMobileLayout(context),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Desktop: two-column ────────────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: _buildMainCard(context),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 320,
          child: _buildSideSummary(context),
        ),
      ],
    );
  }

  // ── Mobile / tablet: single column ────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    return _buildMainCard(context);
  }

  // ── Success screen ─────────────────────────────────────────────────────────

  Widget _buildSuccessScreen(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final league = _createdLeague!;
    final qrColor =
        brightness == Brightness.dark ? Colors.white : Colors.black;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_create_created_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        // No back button on success screen — user must tap Done/Open
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth >= _BP.desktop ? 32 : 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  // Cap at 640 — success is a card, not a dashboard
                  constraints: const BoxConstraints(maxWidth: 640),
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
                        onDoubleTap: () => _safePush('/leagues/${league.id}'),
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
                        padding: const EdgeInsets.all(20),
                        fill: AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            if (_inMasterLeagueMode) ...[
                              const SizedBox(height: 10),
                              Text(
                                'This competition was created inside '
                                'your Master League.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppTheme.limeAccentDark,
                                  height: 1.35,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
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
                                        _safeGo(
                                          '/master-leagues/${widget.masterLeagueId.trim()}',
                                        );
                                        return;
                                      }
                                      openHomeShellTab(1);
                                      _safeGo('/');
                                    },
                                    child: Text(
                                      l10n.tr('league_create_done_upper'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _safePush(
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
                              onPressed: () => _safePush('/leagues/${league.id}'),
                              child: Text(
                                l10n.tr('league_create_open_league_details_upper'),
                                style: TextStyle(
                                  color: AppTheme.limeAccentDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            // Rewards management
                            // Uses Navigator.push for EditLeagueRewardsScreen
                            // because that screen does not have a named route.
                            // This is acceptable — it is a modal-style editor
                            // that only appears post-creation.
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
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Main wizard card ───────────────────────────────────────────────────────

  Widget _buildMainCard(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(),
          const SizedBox(height: 14),

          // Access banner
          if (_checkingAccess)
            _limitStatusBanner(
              text: 'Checking your access...',
              color: AppTheme.limeAccentDark,
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
              text: '$_activePlanLabel plan active. You can create more '
                  'than $_freeLeagueListLimit leagues/competitions.',
              color: AppTheme.limeAccentDark,
              icon: Icons.verified_rounded,
            )
          else
            _limitStatusBanner(
              text: 'Basic/free access: $_currentLeagueCardCount / '
                  '$_freeLeagueListLimit league/competition slots used.',
              color: AppTheme.secondaryText(brightness),
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
        color: color.withOpacity(
            theme.brightness == Brightness.light ? 0.10 : 0.12),
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

  // ── Side summary (desktop only) ────────────────────────────────────────────

  Widget _buildSideSummary(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    Widget row(IconData icon, String label, String value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.limeAccentDark),
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color ?? AppTheme.primaryText(brightness),
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
      padding: const EdgeInsets.all(20),
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
          row(
            _isPaidPlanUser ? Icons.verified_rounded : Icons.layers_outlined,
            'Access',
            _isPaidPlanUser
                ? _activePlanLabel
                : 'Basic • $_currentLeagueCardCount / $_freeLeagueListLimit used',
            color: _isPaidPlanUser
                ? AppTheme.limeAccentDark
                : (_basicLimitReachedForNewLeague
                    ? _premiumAmber
                    : AppTheme.primaryText(brightness)),
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
              color: AppTheme.limeAccentDark,
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
                  ? AppTheme.limeAccentDark
                  : AppTheme.secondaryText(brightness),
            ),
          row(
            Icons.card_giftcard_outlined,
            'Rewards',
            _containsRewards ? 'Yes' : 'No',
            color: _containsRewards
                ? AppTheme.limeAccentDark
                : AppTheme.secondaryText(brightness),
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
                : AppTheme.limeAccentDark,
          ),
          const SizedBox(height: 10),
          Text(
            _basicLimitReachedForNewLeague
                ? _basicLimitText
                : (_inMasterLeagueMode
                    ? 'This competition uses the same shared Basic '
                        'creation allowance as normal leagues.'
                    : 'Normal leagues and Organizer/Master League '
                        'competitions share the same Basic allowance.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _basicLimitReachedForNewLeague
                  ? _premiumAmber
                  : AppTheme.secondaryText(brightness),
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
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                ),
                onPressed: (_submitting || _rewardGateInProgress)
                    ? null
                    : _openPlanUpgradeFlow,
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

  // ── Step header ────────────────────────────────────────────────────────────

  Widget _buildStepHeader() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final steps = <_StepMeta>[
      _StepMeta(
          l10n.tr('league_create_wizard_step_basics'), Icons.edit_note),
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
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 10),
        // Pills — LayoutBuilder prevents overflow on narrow screens
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 400) {
              return Row(
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
                    if (i != steps.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < steps.length; i++)
                  _stepPill(
                    title: steps[i].title,
                    icon: steps[i].icon,
                    index: i,
                    current: _step,
                    flex: false,
                  ),
              ],
            );
          },
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
    );
  }

  Widget _stepPill({
    required String title,
    required IconData icon,
    required int index,
    required int current,
    bool flex = true,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final active = index == current;
    final done = index < current;

    final Color borderColor = active
        ? AppTheme.limeAccentDark
        : done
            ? AppTheme.limeAccentDark.withOpacity(0.40)
            : AppTheme.cardBorder(brightness);

    final Color bgColor = active
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : done
            ? AppTheme.searchBackground(brightness)
            : AppTheme.cardColor(brightness);

    final Color iconColor = active || done
        ? AppTheme.limeAccentDark
        : AppTheme.secondaryText(brightness);

    final Color textColor = active
        ? AppTheme.limeAccentDark
        : done
            ? AppTheme.primaryText(brightness)
            : AppTheme.secondaryText(brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: _softPanelShadow(theme, tint: AppTheme.limeAccentDark),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: flex ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step body router ───────────────────────────────────────────────────────

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

  // ── Step 0: Basics ─────────────────────────────────────────────────────────

  Widget _stepBasics({Key? key}) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final locked = _submitting ||
        _rewardGateInProgress ||
        _basicLimitReachedForNewLeague ||
        _checkingAccess;

    Widget formatChip(LeagueFormat fmt, String label) {
      final selected = _format == fmt;
      return ChoiceChip(
        selected: selected,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        selectedColor: AppTheme.limeAccent,
        backgroundColor: AppTheme.tabInactiveBackground(brightness),
        side: BorderSide(
          color: selected
              ? AppTheme.limeAccentDark
              : AppTheme.cardBorder(brightness),
        ),
        labelStyle: TextStyle(
          color: selected
              ? AppTheme.darkText
              : AppTheme.tabInactiveText(brightness),
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
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w700,
          ),
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
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w600,
          ),
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
          onClear: locked ? () {} : () => setState(() => _leagueImageUrl.text = ''),
        ),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _sponsorImageUrl,
          label: 'Sponsor image (optional)',
          uploading: _uploadingSponsorImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.sponsorImage),
          onClear: locked ? () {} : () => setState(() => _sponsorImageUrl.text = ''),
        ),
      ],
    );
  }

  // ── Step 1: Rules ──────────────────────────────────────────────────────────

  Widget _stepRules({Key? key}) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final locked = _submitting ||
        _rewardGateInProgress ||
        _basicLimitReachedForNewLeague ||
        _checkingAccess;

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
                          () => _privacy = v
                              ? LeaguePrivacy.private
                              : LeaguePrivacy.public,
                        ),
                activeColor: AppTheme.limeAccentDark,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Private league',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  _privacy == LeaguePrivacy.private
                      ? 'Only members can view and join.'
                      : 'Anyone can view, join with code.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondaryText(brightness),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_supportsHomeAwayMatches) ...[
                Divider(color: AppTheme.cardBorder(brightness)),
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
              ],
              Divider(color: AppTheme.cardBorder(brightness)),
              SwitchListTile.adaptive(
                value: _containsRewards,
                onChanged: locked ? null : (v) => setState(() => _containsRewards = v),
                activeColor: AppTheme.limeAccentDark,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Does this league contain rewards?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  _containsRewards
                      ? 'Yes — you will be prompted to add rewards after creation.'
                      : 'No — you can add rewards later from League Admin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondaryText(brightness),
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

  // ── Step 2: Review ─────────────────────────────────────────────────────────

  Widget _stepReview({Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final canCreate = _name.text.trim().isNotEmpty &&
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
              '${_format.displayName} • $_maxTeams teams • '
              '${_privacy == LeaguePrivacy.private ? 'Private' : 'Public'}',
        ),
        const SizedBox(height: 10),
        if (_inMasterLeagueMode)
          _confirmRow(
            Icons.hub_rounded,
            'Master League',
            'This competition will be inside your Master League',
            valueColor: AppTheme.limeAccentDark,
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
          _containsRewards ? 'Yes' : 'No',
          valueColor: _containsRewards
              ? AppTheme.limeAccentDark
              : AppTheme.secondaryText(brightness),
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
            accent: AppTheme.limeAccentDark,
          ),
        const SizedBox(height: 12),
        if (_basicLimitReachedForNewLeague)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: (_submitting || _rewardGateInProgress)
                ? null
                : _openPlanUpgradeFlow,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text(
              'Upgrade Plan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          )
        else
          FilledButton(
            onPressed: (_submitting || _rewardGateInProgress || !canCreate)
                ? null
                : () => _create(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: (_submitting || _rewardGateInProgress)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.darkText,
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

  // ── Footer actions ─────────────────────────────────────────────────────────

  Widget _buildFooterActions(BuildContext context) {
    final l10n = context.l10n;
    final brightness = theme.brightness;

    final isLast = _step == 2;
    final outlineSide = BorderSide(color: AppTheme.cardBorder(brightness));

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: (_submitting || _rewardGateInProgress) ? null : _backOrClose,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: outlineSide,
              foregroundColor: AppTheme.primaryText(brightness),
            ),
            child: Text(
              (_step == 0 ? l10n.tr('common_cancel') : l10n.tr('common_back')).toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            // Next is disabled on last step — Review step has its own Create button.
            onPressed: (_submitting ||
                    _rewardGateInProgress ||
                    isLast ||
                    _checkingAccess ||
                    _basicLimitReachedForNewLeague)
                ? null
                : () async {
                    await _validateAndNext();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
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

  // ── Shared UI helpers ──────────────────────────────────────────────────────

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
            boxShadow: _softPanelShadow(theme, tint: AppTheme.limeAccentDark),
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

  Widget _infoBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final a = accent ?? AppTheme.limeAccentDark;

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
      ),
    );
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_submitting || _rewardGateInProgress) return;
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

    // ───────────────────────────────────────────────────────────────
    // Monetization gate:
    // Free/Basic users MUST earn a rewarded-ad reward before proceeding.
    // Paid users bypass instantly.
    // ───────────────────────────────────────────────────────────────
    if (!_isPaidPlanUser) {
      setState(() => _rewardGateInProgress = true);
      try {
        final placement =
            _inMasterLeagueMode ? 'create_competition' : 'create_league';
        final earned = await RewardedAdManager.instance.showRewardedGate(
          placement: placement,
        );

        if (!mounted) return;

        if (!earned) {
          _showSnack('Ad not completed. Creation cancelled.');
          return;
        }
      } finally {
        if (mounted) {
          setState(() => _rewardGateInProgress = false);
        }
      }
    }

    setState(() => _submitting = true);

    try {
      final organizerUid =
          (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (organizerUid.isEmpty) {
        throw StateError('unauthenticated');
      }

      final derivedShortId =
          UserProfile.deriveShareIdFromUid(organizerUid).trim();
      final organizerUserId =
          derivedShortId.isNotEmpty ? derivedShortId : organizerUid;

      final requestedLeagueId = _inMasterLeagueMode ? '' : _draftLeagueId;
      final now = DateTime.now().millisecondsSinceEpoch;

      final effectiveHomeAwayEnabled =
          _supportsHomeAwayMatches ? _homeAwayEnabled : false;

      final settings = LeagueSettings.defaultsFor(_format).copyWith(
        doubleRoundRobin: effectiveHomeAwayEnabled,
        lastPulledAtMs: 0,
      );
      _doubleRoundRobin = effectiveHomeAwayEnabled;

      final joinCode =
          await _generateUniqueJoinCode().timeout(const Duration(seconds: 12));

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

      // Open rewards editor if user opted in.
      // Uses Navigator.push because EditLeagueRewardsScreen has no
      // named route. This is intentional — it is a modal post-creation
      // step that does not need deep-link support.
      if (_containsRewards && mounted) {
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

// ---------------------------------------------------------------------------
// _OptionalImageField — unchanged from original
// ---------------------------------------------------------------------------

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
            boxShadow: AppTheme.softCardShadow(brightness),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: bytes != null
                ? Image.memory(bytes,
                    fit: BoxFit.cover, gaplessPlayback: true)
                : (hasImage
                    ? Image.network(
                        url,
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
                      ? const Padding(
                          padding: EdgeInsets.all(10),
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

// ---------------------------------------------------------------------------
// _StepMeta
// ---------------------------------------------------------------------------

class _StepMeta {
  final String title;
  final IconData icon;
  const _StepMeta(this.title, this.icon);
}
