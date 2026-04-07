import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../../../features/auth/data/user_profile_repository.dart';
import '../../../features/leagues/data/leagues_repository_firebase.dart';
import '../../../features/leagues/logic/league_media_service.dart';
import '../../../features/leagues/logic/league_premium_upgrade_helper.dart';
import '../../../features/leagues/models/enums.dart';
import '../../../features/leagues/models/league.dart';
import '../../../features/leagues/models/league_format.dart';
import '../../../features/leagues/models/league_settings.dart';

class WebLeagueCreateWizard extends ConsumerStatefulWidget {
  const WebLeagueCreateWizard({
    super.key,
    this.masterLeagueId = '',
    this.initialFormat,
  });

  final String masterLeagueId;
  final LeagueFormat? initialFormat;

  @override
  ConsumerState<WebLeagueCreateWizard> createState() =>
      _WebLeagueCreateWizardState();
}

class _WebLeagueCreateWizardState extends ConsumerState<WebLeagueCreateWizard> {
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
    } else {
      _showSnack('Plan purchase cancelled.');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _leagueImageUrl.dispose();
    _sponsorImageUrl.dispose();
    super.dispose();
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

  Future<void> _uploadImage({required LeagueMediaKind kind}) async {
    if (_submitting ||
        !_hasLeagueAccess ||
        _basicLimitReachedForNewLeague) return;

    if (kind == LeagueMediaKind.leagueImage) {
      setState(() => _uploadingLeagueImage = true);
    } else {
      setState(() => _uploadingSponsorImage = true);
    }

    try {
      final service = LeagueMediaService();
      final url = await service
          .pickAndUploadImage(leagueId: _draftLeagueId, kind: kind)
          .timeout(const Duration(seconds: 40));

      if (!mounted) return;
      if (url == null || url.trim().isEmpty) throw Exception('Upload failed');

      setState(() {
        if (kind == LeagueMediaKind.leagueImage) {
          _leagueImageUrl.text = url;
        } else {
          _sponsorImageUrl.text = url;
        }
      });
      _showSnack('Image uploaded successfully.');
    } catch (e) {
      _showSnack('Failed to upload image. Please try again.');
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingLeagueImage = false;
        _uploadingSponsorImage = false;
      });
    }
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueJoinCode() async {
    final firestore = FirebaseFirestore.instance;
    for (int i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return code;
    }
    throw StateError("Couldn't generate a code. Try again.");
  }

  Future<void> _validateAndNext() async {
    if (_checkingAccess ||
        !_hasLeagueAccess ||
        _basicLimitReachedForNewLeague) return;

    if (_step == 1 && _name.text.trim().isEmpty) {
      _showSnack(context.l10n.tr('league_create_error_name_required'));
      return;
    }

    if (_step < 3) {
      setState(() => _step++);
    } else {
      await _createLeague();
    }
  }

  void _backOrClose() {
    if (_submitting) return;
    if (_step == 0) {
      context.pop();
    } else {
      setState(() => _step--);
    }
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
    if (_createdLeague != null) return _buildSuccessView();

    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      useBubbles: false,
      appBar: AppBar(
        title: Text(
          _inMasterLeagueMode
              ? 'Create Workspace Competition'
              : 'Create League',
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _backOrClose,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(24),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStepper(brightness),
                    const SizedBox(height: 24),
                    _buildAccessBanner(brightness),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildCurrentStep(brightness),
                    ),
                    const SizedBox(height: 32),
                    _buildFooter(brightness),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepper(Brightness brightness) {
    final steps = [
      {'icon': Icons.auto_awesome, 'label': 'Type'},
      {'icon': Icons.subject, 'label': 'Details'},
      {'icon': Icons.lock_outline, 'label': 'Rules'},
      {'icon': Icons.check_circle_outline, 'label': 'Confirm'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'League Creation',
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(steps.length, (index) {
            final isActive = _step == index;
            final isDone = _step > index;
            final color = isActive || isDone
                ? AppTheme.limeAccentDark
                : AppTheme.secondaryText(brightness).withOpacity(0.5);

            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.limeAccentDark.withOpacity(0.1)
                      : Colors.transparent,
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(steps[index]['icon'] as IconData,
                        size: 16, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        steps[index]['label'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? AppTheme.primaryText(brightness)
                              : color,
                          fontWeight:
                              isActive ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: (_step + 1) / steps.length,
            backgroundColor: AppTheme.searchBackground(brightness),
            color: AppTheme.limeAccentDark,
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildAccessBanner(Brightness brightness) {
    if (_checkingAccess) return const SizedBox.shrink();

    final isLimit = _basicLimitReachedForNewLeague;
    final color = isLimit ? _premiumAmber : AppTheme.limeAccentDark;
    final icon = isLimit ? Icons.lock : Icons.verified;
    final title = isLimit ? 'Upgrade Required' : 'Creation Status';
    final desc = isLimit
        ? 'You have reached the Basic plan limit ($_freeLeagueListLimit leagues).'
        : (_isPaidPlanUser
            ? '$_activePlanLabel Plan active. Create without limits.'
            : 'Basic Plan. $_currentLeagueCardCount/$_freeLeagueListLimit used.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (isLimit)
            TextButton(
              onPressed: _openPlanUpgradeFlow,
              style: TextButton.styleFrom(foregroundColor: color),
              child: const Text('Upgrade',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep(Brightness brightness) {
    switch (_step) {
      case 0:
        return _buildStepType(brightness);
      case 1:
        return _buildStepDetails(brightness);
      case 2:
        return _buildStepRules(brightness);
      case 3:
        return _buildStepConfirm(brightness);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepType(Brightness brightness) {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose one league type. This affects fixtures, qualification, and standings.',
          style: TextStyle(
            color: AppTheme.secondaryText(brightness),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _PremiumSelectionCard(
          title: 'Series League',
          subtitle: 'UCL-style Swiss model. Supported sizes: 18 or 36 teams.',
          icon: Icons.timeline_rounded,
          isSelected: _format == LeagueFormat.uclSwiss,
          brightness: brightness,
          onTap: () => setState(() {
            _format = LeagueFormat.uclSwiss;
            _homeAwayEnabled = false;
          }),
        ),
        const SizedBox(height: 12),
        _PremiumSelectionCard(
          title: 'Group League',
          subtitle: 'UCL-style groups of 4. Supported sizes: 16 or 32 teams.',
          icon: Icons.grid_view_rounded,
          isSelected: _format == LeagueFormat.uclGroup,
          brightness: brightness,
          onTap: () => setState(() => _format = LeagueFormat.uclGroup),
        ),
        const SizedBox(height: 12),
        _PremiumSelectionCard(
          title: 'Classic League',
          subtitle: 'League table format. Flexible team counts up to 20.',
          icon: Icons.format_list_numbered_rounded,
          isSelected: _format == LeagueFormat.classic,
          brightness: brightness,
          onTap: () => setState(() => _format = LeagueFormat.classic),
        ),
      ],
    );
  }

  Widget _buildStepDetails(Brightness brightness) {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizardTextField(
          controller: _name,
          label: 'League Name (required)',
          icon: Icons.edit_outlined,
          brightness: brightness,
        ),
        const SizedBox(height: 16),
        _WizardTextField(
          controller: _description,
          label: 'League Description (optional)',
          icon: Icons.subject,
          maxLines: 4,
          brightness: brightness,
        ),
        const SizedBox(height: 24),
        Text(
          'Images (optional)',
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        _WizardImageDropzone(
          label: 'League Image',
          controller: _leagueImageUrl,
          isUploading: _uploadingLeagueImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.leagueImage),
          brightness: brightness,
        ),
        const SizedBox(height: 12),
        _WizardImageDropzone(
          label: 'Sponsor Image',
          controller: _sponsorImageUrl,
          isUploading: _uploadingSponsorImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.sponsorImage),
          brightness: brightness,
        ),
      ],
    );
  }

  Widget _buildStepRules(Brightness brightness) {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Privacy',
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        _PremiumSelectionCard(
          title: 'Public League',
          subtitle: 'Discoverable globally. Anyone can join.',
          icon: Icons.public,
          isSelected: _privacy == LeaguePrivacy.public,
          brightness: brightness,
          onTap: () => setState(() => _privacy = LeaguePrivacy.public),
        ),
        const SizedBox(height: 12),
        _PremiumSelectionCard(
          title: 'Private League',
          subtitle: 'Invite-only. Join via code.',
          icon: Icons.lock_outline,
          isSelected: _privacy == LeaguePrivacy.private,
          brightness: brightness,
          onTap: () => setState(() => _privacy = LeaguePrivacy.private),
        ),
        const SizedBox(height: 24),
        Text(
          'Match Rules',
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (_supportsHomeAwayMatches) ...[
          _WizardToggleRow(
            title: 'Home and Away Matches',
            subtitle: _homeAwayEnabled
                ? 'Each team plays twice.'
                : 'Each team plays once.',
            value: _homeAwayEnabled,
            onChanged: (v) => setState(() {
              _homeAwayEnabled = v;
              _doubleRoundRobin = v;
            }),
            brightness: brightness,
          ),
          const SizedBox(height: 12),
        ],
        _WizardToggleRow(
          title: 'League Rewards',
          subtitle: _containsRewards
              ? 'Enabled. Set up rewards after creation.'
              : 'Disabled.',
          value: _containsRewards,
          onChanged: (v) => setState(() => _containsRewards = v),
          brightness: brightness,
        ),
      ],
    );
  }

  Widget _buildStepConfirm(Brightness brightness) {
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.searchBackground(brightness),
            border: Border.all(color: AppTheme.searchOutline(brightness)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _ConfirmRow(
                  label: 'Name',
                  value: _name.text,
                  brightness: brightness),
              const Divider(height: 24),
              _ConfirmRow(
                  label: 'Format',
                  value: _format.displayName,
                  brightness: brightness),
              const Divider(height: 24),
              _ConfirmRow(
                  label: 'Max Teams',
                  value: '$_maxTeams',
                  brightness: brightness),
              const Divider(height: 24),
              _ConfirmRow(
                  label: 'Privacy',
                  value: _privacy.name.toUpperCase(),
                  brightness: brightness),
              if (_supportsHomeAwayMatches) ...[
                const Divider(height: 24),
                _ConfirmRow(
                    label: 'Home/Away',
                    value: _homeAwayEnabled ? 'Yes' : 'No',
                    brightness: brightness),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(Brightness brightness) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _submitting ? null : _backOrClose,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              side: BorderSide(color: AppTheme.cardBorder(brightness)),
              foregroundColor: AppTheme.primaryText(brightness),
            ),
            child: Text(_step == 0 ? 'CANCEL' : 'BACK',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            onPressed: _submitting || _basicLimitReachedForNewLeague
                ? null
                : _validateAndNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: AppTheme.darkText),
                  )
                : Text(_step == 3 ? 'CREATE LEAGUE' : 'NEXT',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    final league = _createdLeague!;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final qrColor =
        brightness == Brightness.dark ? Colors.white : Colors.black;

    return GlassScaffold(
      useBubbles: false,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                LeagueFlipCard(
                  leagueId: league.id,
                  leagueName: league.name,
                  leagueCode: league.code,
                  distribution:
                      '${league.format.displayName} • ${league.season}',
                  subtitle: '0 / ${league.maxTeams} Teams',
                  onDoubleTap: () => context.push('/leagues/${league.id}'),
                  qrWidget: QrImageView(
                    data: league.qrPayload,
                    version: QrVersions.auto,
                    gapless: true,
                    eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square, color: qrColor),
                    dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: qrColor),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => context.go('/'),
                  child: const Text('GO TO DASHBOARD',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => context.push('/leagues/${league.id}'),
                  child: const Text('OPEN LEAGUE DETAILS',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createLeague() async {
    setState(() => _submitting = true);
    try {
      final organizerUid =
          (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      final joinCode = await _generateUniqueJoinCode();
      final effectiveHomeAwayEnabled =
          _supportsHomeAwayMatches ? _homeAwayEnabled : false;

      final pendingLeague = League(
        id: _inMasterLeagueMode ? '' : _draftLeagueId,
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
        region: 'Global',
        maxTeams: _maxTeams,
        season: DateTime.now().year.toString(),
        organizerUid: organizerUid,
        organizerUserId: organizerUid,
        code: joinCode,
        qrPayloadOverride: '',
        settings: LeagueSettings.defaultsFor(_format).copyWith(
          doubleRoundRobin: effectiveHomeAwayEnabled,
          lastPulledAtMs: 0,
        ),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        version: 1,
      );

      final savedId =
          await LeaguesRepositoryFirebase().saveLeague(pendingLeague);
      setState(() {
        _createdLeague = pendingLeague.copyWith(id: savedId);
        _submitting = false;
      });
    } catch (e) {
      setState(() => _submitting = false);
      _showSnack('Creation failed. Try again.');
    }
  }
}

class _PremiumSelectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final Brightness brightness;
  final VoidCallback onTap;

  const _PremiumSelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.limeAccentDark.withOpacity(0.08)
              : AppTheme.searchBackground(brightness),
          border: Border.all(
            color: isSelected
                ? AppTheme.limeAccentDark
                : AppTheme.searchOutline(brightness),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.limeAccentDark.withOpacity(0.2)
                    : AppTheme.iconCircleBackground(brightness),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: isSelected
                      ? AppTheme.limeAccentDark
                      : AppTheme.secondaryText(brightness)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppTheme.limeAccentDark),
          ],
        ),
      ),
    );
  }
}

class _WizardTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Brightness brightness;
  final int maxLines;

  const _WizardTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.brightness,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
          color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.secondaryText(brightness)),
        filled: true,
        fillColor: AppTheme.searchBackground(brightness),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.limeAccentDark)),
      ),
    );
  }
}

class _WizardImageDropzone extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isUploading;
  final VoidCallback onUpload;
  final Brightness brightness;

  const _WizardImageDropzone({
    required this.label,
    required this.controller,
    required this.isUploading,
    required this.onUpload,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final hasImage = value.text.isNotEmpty;
        return InkWell(
          onTap: onUpload,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.searchBackground(brightness),
              border: Border.all(color: AppTheme.searchOutline(brightness)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                if (isUploading)
                  const CircularProgressIndicator(
                      color: AppTheme.limeAccentDark)
                else if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(value.text,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image)),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: AppTheme.iconCircleBackground(brightness),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.cloud_upload_outlined),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              color: AppTheme.primaryText(brightness),
                              fontWeight: FontWeight.w900)),
                      Text(
                          hasImage
                              ? 'Image uploaded successfully.'
                              : 'Click to select and upload an image',
                          style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WizardToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Brightness brightness;

  const _WizardToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
          Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.limeAccentDark),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final Brightness brightness;

  const _ConfirmRow(
      {required this.label, required this.value, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        Text(value,
            style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 15)),
      ],
    );
  }
}
