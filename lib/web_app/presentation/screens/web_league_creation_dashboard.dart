import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
import '../../../core/widgets/glass.dart';
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

enum LeagueCreationType { series, group, classic }

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

  static const Color _premiumAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _draftLeagueId = _uuid.v4();
    _loadPlanLimitState();
  }

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
    final snap = await _firestore
        .collection('leagues')
        .where('organizerUid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    return snap.docs.length;
  }

  bool get _freeLimitReachedForNewLeague =>
      _hasLeagueAccess && !_isPaidPlanUser && _currentLeagueCardCount >= _freeLeagueListLimit;

  String get _freeLimitText =>
      'Basic users can create up to $_freeLeagueListLimit leagues/competitions total. Upgrade to Pro or Elite to create more.';

  Future<void> _openPlanUpgradeFlow() async {
    final success = await LeaguePremiumUpgradeHelper.openUpgradeFlow(
      context,
      leagueName: _name.text.trim().isEmpty ? 'Organizer Plan' : _name.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      _showSnack('Plan purchase completed. Refreshing access...');
      await _loadPlanLimitState();
      return;
    }

    _showSnack('Plan purchase cancelled.');
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

    final String? typeString = (extra['type'] as String?)?.trim().toLowerCase();
    final String templateName = (extra['templateName'] as String?)?.trim() ?? '';
    final String templateDescription = (extra['templateDescription'] as String?)?.trim() ?? '';
    final String templatePrivacy = (extra['templatePrivacy'] as String?)?.trim().toLowerCase() ?? '';
    final bool templateHomeAwayEnabled = extra['templateHomeAwayEnabled'] == true;
    final bool templateContainsRewards = extra['templateContainsRewards'] == true;
    final int? templateMaxTeams = extra['maxTeams'] is int
        ? extra['maxTeams'] as int
        : (extra['maxTeams'] is num ? (extra['maxTeams'] as num).toInt() : null);

    LeagueCreationType? inferredType;
    if (initialFormat != null) {
      inferredType = _creationTypeFromFormat(initialFormat);
    } else if (typeString != null && typeString.isNotEmpty) {
      inferredType = _creationTypeFromString(typeString);
    }

    if (mounted) {
      setState(() {
        _masterLeagueId = ml;
        if (templateName.isNotEmpty) _name.text = templateName;
        if (templateDescription.isNotEmpty) _description.text = templateDescription;
        if (templatePrivacy == 'public') _privacy = LeaguePrivacy.public;
        else if (templatePrivacy == 'private') _privacy = LeaguePrivacy.private;
        
        _containsRewards = templateContainsRewards;

        if (inferredType != null) {
          _type = inferredType;
          final fmt = _format;

          if (templateMaxTeams != null && _allowedMaxTeams.contains(templateMaxTeams)) {
            _selectedMaxTeams = templateMaxTeams;
          } else if (fmt == LeagueFormat.uclGroup) {
            _selectedMaxTeams = 32;
          } else if (fmt == LeagueFormat.uclSwiss) {
            _selectedMaxTeams = 36;
          } else {
            _selectedMaxTeams = 20;
          }

          _homeAwayEnabled = _supportsHomeAwayMatches ? templateHomeAwayEnabled : false;
          _step = 1;
        }
      });
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

  bool get _inMasterLeagueMode => _masterLeagueId.trim().isNotEmpty;

  LeagueCreationType _creationTypeFromFormat(LeagueFormat format) {
    switch (format) {
      case LeagueFormat.uclSwiss: return LeagueCreationType.series;
      case LeagueFormat.uclGroup: return LeagueCreationType.group;
      case LeagueFormat.classic: return LeagueCreationType.classic;
    }
  }

  LeagueCreationType? _creationTypeFromString(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'classic') return LeagueCreationType.classic;
    if (s == 'swiss' || s == 'series') return LeagueCreationType.series;
    if (s == 'ucl' || s == 'group') return LeagueCreationType.group;
    return null;
  }

  void _showSnack(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.trim()), behavior: SnackBarBehavior.floating),
    );
  }

  LeagueFormat get _format {
    switch (_type) {
      case LeagueCreationType.series: return LeagueFormat.uclSwiss;
      case LeagueCreationType.group: return LeagueFormat.uclGroup;
      case LeagueCreationType.classic:
      default: return LeagueFormat.classic;
    }
  }

  bool get _supportsHomeAwayMatches =>
      _format == LeagueFormat.classic || _format == LeagueFormat.uclGroup;

  List<int> get _allowedMaxTeams {
    switch (_format) {
      case LeagueFormat.uclGroup: return const [16, 32];
      case LeagueFormat.uclSwiss: return const [18, 36];
      case LeagueFormat.classic:
      default: return const [20];
    }
  }

  int get _maxTeams {
    if (_selectedMaxTeams != null) return _selectedMaxTeams!;
    switch (_format) {
      case LeagueFormat.classic: return 20;
      case LeagueFormat.uclGroup: return 32;
      case LeagueFormat.uclSwiss: return 36;
    }
  }

  String get _typeLabel {
    if (_type == null) return 'Not Selected';
    switch (_type!) {
      case LeagueCreationType.series: return 'Swiss / Series League';
      case LeagueCreationType.group: return 'Group Stage League';
      case LeagueCreationType.classic: return 'Classic League';
    }
  }

  void _setType(LeagueCreationType t) {
    if (!_hasLeagueAccess || _freeLimitReachedForNewLeague) return;
    setState(() {
      _type = t;
      final fmt = _format;
      _selectedMaxTeams = (fmt == LeagueFormat.uclGroup) ? 32 : (fmt == LeagueFormat.uclSwiss ? 36 : 20);
      if (!_supportsHomeAwayMatches) _homeAwayEnabled = false;
    });
  }

  Future<void> _uploadImage({required LeagueMediaKind kind}) async {
    if (_submitting || !_hasLeagueAccess || _freeLimitReachedForNewLeague) return;

    if (kind == LeagueMediaKind.leagueImage) {
      if (_uploadingLeagueImage) return;
      setState(() => _uploadingLeagueImage = true);
    } else {
      if (_uploadingSponsorImage) return;
      setState(() => _uploadingSponsorImage = true);
    }

    try {
      final service = LeagueMediaService();
      final url = await service.pickAndUploadImage(leagueId: _draftLeagueId, kind: kind)
          .timeout(const Duration(seconds: 40));

      if (url == null || url.trim().isEmpty) throw StateError('Upload failed.');

      if (mounted) {
        setState(() {
          if (kind == LeagueMediaKind.leagueImage) _leagueImageUrl.text = url;
          else _sponsorImageUrl.text = url;
        });
      }
    } catch (e) {
      _showSnack(UserFriendlyError.toMessage(e));
    } finally {
      if (mounted) setState(() { _uploadingLeagueImage = false; _uploadingSponsorImage = false; });
    }
  }

  Future<String> _generateUniqueJoinCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    for (int i = 0; i < 6; i++) {
      final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      final snap = await _firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();
      if (snap.docs.isEmpty) return code;
    }
    throw StateError("We couldn't create a join code. Please try again.");
  }

  Future<void> _create(BuildContext context) async {
    if (_checkingAccess || !_hasLeagueAccess || _submitting) return;
    if (_freeLimitReachedForNewLeague) { await _openPlanUpgradeFlow(); return; }
    if (_type == null || _name.text.trim().isEmpty) { _showSnack('Please complete required fields.'); return; }

    setState(() => _submitting = true);

    try {
      final organizerAuthUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (organizerAuthUid.isEmpty) throw FirebaseAuthException(code: 'unauthenticated');

      final derivedShareId = UserProfile.deriveShareIdFromUid(organizerAuthUid).trim();
      final organizerUserId = derivedShareId.isNotEmpty ? derivedShareId : organizerAuthUid;

      if (_creatorWillParticipate) {
        final profile = await UserProfileRepository().fetchByUserId(organizerAuthUid);
        if ((profile?.teamName.trim() ?? '').isEmpty) throw StateError('Your profile is missing a team name.');
      }

      final joinCode = await _generateUniqueJoinCode();
      final now = DateTime.now().millisecondsSinceEpoch;
      final baseDefaults = LeagueSettings.defaultsFor(_format);

      final league = League(
        id: _inMasterLeagueMode ? '' : _draftLeagueId,
        name: _name.text.trim(),
        masterLeagueId: _masterLeagueId.trim(),
        description: _description.text.trim(),
        leagueImageUrl: _leagueImageUrl.text.trim(),
        sponsorImageUrl: _sponsorImageUrl.text.trim(),
        viewerCapacity: 0,
        couponsEnabled: false,
        couponDiscountPercent: 0,
        couponCount: 0,
        homeAwayEnabled: _supportsHomeAwayMatches ? _homeAwayEnabled : false,
        format: _format,
        privacy: _privacy,
        region: 'Global',
        maxTeams: _maxTeams,
        season: '2026',
        organizerUid: organizerAuthUid,
        organizerUserId: organizerUserId,
        code: joinCode,
        qrPayloadOverride: '',
        settings: baseDefaults.copyWith(
          doubleRoundRobin: _supportsHomeAwayMatches ? _homeAwayEnabled : baseDefaults.doubleRoundRobin,
          lastPulledAtMs: 0,
        ),
        updatedAtMs: now,
        version: 1,
      );

      final repo = LeaguesRepositoryFirebase();
      final savedId = await repo.saveLeague(league).timeout(const Duration(seconds: 25));
      final created = league.copyWith(id: savedId);

      if (_inMasterLeagueMode) {
        try {
          final p = await UserProfileRepository().fetchByUserId(organizerAuthUid);
          await _organizerFeed.addCompetitionCreatedEvent(
            masterLeagueId: _masterLeagueId.trim(),
            leagueId: created.id,
            actorId: organizerAuthUid,
            actorName: p?.teamName.trim().isNotEmpty == true ? p!.teamName.trim() : 'Organizer',
            competitionName: created.name,
          );
        } catch (_) {}
      }

      if (mounted) setState(() { _createdLeague = created; _submitting = false; _currentLeagueCardCount++; });
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      _showSnack('Failed to create: ${UserFriendlyError.toMessage(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (FirebaseAuth.instance.currentUser?.uid.trim().isEmpty ?? true) {
      return GlassScaffold(
        appBar: AppBar(title: const Text('Create Competition'), elevation: 0, backgroundColor: Colors.transparent),
        body: Center(child: Text('Sign in required.', style: theme.textTheme.titleMedium)),
      );
    }

    if (_createdLeague != null) return _buildSuccessScreen(_createdLeague!, theme);

    return GlassScaffold(
      appBar: AppBar(
        title: Text(_inMasterLeagueMode ? 'Create Workspace Competition' : 'Create League'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SelectionArea(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _buildForm(theme)),
                          const SizedBox(width: 32),
                          Expanded(flex: 4, child: _buildSummary(theme)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildForm(theme),
                          const SizedBox(height: 24),
                          _buildSummary(theme),
                        ],
                      );

                return SingleChildScrollView(
                  padding: EdgeInsets.all(isWide ? 32 : 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 1200 : 600),
                    child: content,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Glass(
      borderRadius: 30,
      padding: const EdgeInsets.all(32),
      fill: AppTheme.cardColor(theme.brightness),
      borderColor: AppTheme.cardBorder(theme.brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepIndicators(theme),
          const SizedBox(height: 32),
          _buildActiveStep(theme),
          const SizedBox(height: 48),
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicators(ThemeData theme) {
    final steps = ['Type', 'Details', 'Privacy', 'Payment', 'Confirm'];
    return Row(
      children: List.generate(steps.length, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? AppTheme.limeAccentDark.withOpacity(0.1) : (done ? AppTheme.searchBackground(theme.brightness) : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active || done ? AppTheme.limeAccentDark : AppTheme.cardBorder(theme.brightness)),
            ),
            alignment: Alignment.center,
            child: Text(
              steps[i].toUpperCase(),
              style: TextStyle(
                color: active || done ? AppTheme.limeAccentDark : AppTheme.secondaryText(theme.brightness),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildActiveStep(ThemeData theme) {
    switch (_step) {
      case 0: return _stepType(theme);
      case 1: return _stepDetails(theme);
      case 2: return _stepPrivacy(theme);
      case 3: return _stepPayment(theme);
      case 4: return _stepConfirm(theme);
      default: return const SizedBox.shrink();
    }
  }

  Widget _stepType(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Competition Type', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        _typeCard(LeagueCreationType.series, 'Swiss / Series', 'Dynamic matchmaking based on performance.', Icons.auto_graph, theme),
        const SizedBox(height: 12),
        _typeCard(LeagueCreationType.group, 'Group Stage (UCL)', 'Multiple groups advancing to knockouts.', Icons.grid_view, theme),
        const SizedBox(height: 12),
        _typeCard(LeagueCreationType.classic, 'Classic League', 'Standard round-robin point table.', Icons.table_chart, theme),
        if (_type != null && _allowedMaxTeams.length > 1) ...[
          const SizedBox(height: 24),
          Text('Maximum Teams', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: _allowedMaxTeams.map((n) {
              return ChoiceChip(
                label: Text('$n Teams'),
                selected: _maxTeams == n,
                selectedColor: AppTheme.limeAccent,
                onSelected: (v) { if (v) setState(() => _selectedMaxTeams = n); },
              );
            }).toList(),
          ),
        ]
      ],
    );
  }

  Widget _typeCard(LeagueCreationType type, String title, String subtitle, IconData icon, ThemeData theme) {
    final selected = _type == type;
    return InkWell(
      onTap: () => _setType(type),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppTheme.limeAccentDark : AppTheme.cardBorder(theme.brightness), width: selected ? 2 : 1),
          color: selected ? AppTheme.limeAccentDark.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppTheme.limeAccentDark : AppTheme.secondaryText(theme.brightness), size: 32),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.secondaryText(theme.brightness))),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _stepDetails(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Competition Details', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Competition Name', prefixIcon: Icon(Icons.edit))),
        const SizedBox(height: 16),
        TextField(controller: _description, maxLines: 4, decoration: const InputDecoration(labelText: 'Description (optional)', prefixIcon: Icon(Icons.notes))),
        const SizedBox(height: 24),
        _buildImageUploader('League Banner', _leagueImageUrl, _uploadingLeagueImage, () => _uploadImage(kind: LeagueMediaKind.leagueImage)),
        const SizedBox(height: 16),
        _buildImageUploader('Sponsor Logo', _sponsorImageUrl, _uploadingSponsorImage, () => _uploadImage(kind: LeagueMediaKind.sponsorImage)),
      ],
    );
  }

  Widget _buildImageUploader(String label, TextEditingController ctrl, bool uploading, VoidCallback onUpload) {
    final hasImage = ctrl.text.isNotEmpty;
    return Row(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
          child: hasImage ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(ctrl.text, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        uploading
            ? const CircularProgressIndicator()
            : OutlinedButton.icon(onPressed: onUpload, icon: const Icon(Icons.upload), label: const Text('Upload')),
      ],
    );
  }

  Widget _stepPrivacy(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Privacy Settings', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),
        RadioListTile<LeaguePrivacy>(
          title: const Text('Public', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Anyone can find and join this league.'),
          value: LeaguePrivacy.public,
          groupValue: _privacy,
          onChanged: (v) => setState(() => _privacy = v!),
          activeColor: AppTheme.limeAccentDark,
        ),
        RadioListTile<LeaguePrivacy>(
          title: const Text('Private', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Only users with the join code or QR can enter.'),
          value: LeaguePrivacy.private,
          groupValue: _privacy,
          onChanged: (v) => setState(() => _privacy = v!),
          activeColor: AppTheme.limeAccentDark,
        ),
      ],
    );
  }

  Widget _stepPayment(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Creation Status', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: AppTheme.limeAccentDark.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.limeAccentDark)),
          child: Row(
            children: [
              const Icon(Icons.verified, color: AppTheme.limeAccentDark, size: 48),
              const SizedBox(width: 16),
              Expanded(child: Text('Included in $_activePlanLabel plan allowance.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepConfirm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Final Review', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),
        if (_supportsHomeAwayMatches)
          SwitchListTile(title: const Text('Home & Away Matches', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Each team plays twice.'), value: _homeAwayEnabled, onChanged: (v) => setState(() => _homeAwayEnabled = v)),
        SwitchListTile(title: const Text('I will participate', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Add me as a team.'), value: _creatorWillParticipate, onChanged: (v) => setState(() => _creatorWillParticipate = v)),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return Glass(
      borderRadius: 30,
      padding: const EdgeInsets.all(32),
      fill: AppTheme.cardColor(theme.brightness),
      borderColor: AppTheme.cardBorder(theme.brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Summary', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          _summaryRow('Type', _typeLabel),
          _summaryRow('Name', _name.text.isEmpty ? 'Not set' : _name.text),
          _summaryRow('Privacy', _privacy.name.toUpperCase()),
          _summaryRow('Teams', '$_maxTeams Maximum'),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      children: [
        if (_step > 0)
          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)), onPressed: () => setState(() => _step--), child: const Text('BACK', style: TextStyle(fontWeight: FontWeight.w900)))),
        if (_step > 0) const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.limeAccent, foregroundColor: AppTheme.darkText, padding: const EdgeInsets.symmetric(vertical: 20)),
            onPressed: () async {
              if (_step < 4) { if (await _validateAndAdvance(context)) setState(() => _step++); }
              else { _create(context); }
            },
            child: _submitting ? const CircularProgressIndicator(color: Colors.black) : Text(_step == 4 ? 'CREATE COMPETITION' : 'NEXT STEP', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Future<bool> _validateAndAdvance(BuildContext context) async {
    if (_step == 0 && _type == null) { _showSnack('Please select a type.'); return false; }
    if (_step == 1 && _name.text.trim().isEmpty) { _showSnack('Please enter a name.'); return false; }
    return true;
  }

  Widget _buildSuccessScreen(League league, ThemeData theme) {
    return GlassScaffold(
      appBar: AppBar(title: const Text('Success'), backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 400, child: LeagueFlipCard(league: league, leagueId: league.id, leagueName: league.name, leagueCode: league.code, distribution: league.format.displayName, subtitle: league.region, imageUrl: league.leagueImageUrl, isOwner: true, qrWidget: QrImageView(data: league.qrPayload, version: QrVersions.auto, backgroundColor: Colors.white))),
              const SizedBox(height: 32),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.limeAccent, foregroundColor: AppTheme.darkText, padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20)), onPressed: () => context.go('/leagues/${league.id}'), child: const Text('OPEN COMPETITION DASHBOARD', style: TextStyle(fontWeight: FontWeight.w900))),
            ],
          ),
        ),
      ),
    );
  }
}
