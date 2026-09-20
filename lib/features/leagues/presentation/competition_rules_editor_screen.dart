// lib/features/leagues/presentation/competition_rules_editor_screen.dart
//
// NEW FILE — Organizer-facing Competition Rules & Configuration editor.
//
// Separate from OrganizerDisciplineScreen (master-league scoped, enforcement
// actions). This screen is League-scoped (one competition) and edits WHAT
// PARTICIPANTS MUST FOLLOW, stored via CompetitionRules /
// LeaguesRepositoryFirebase.saveCompetitionRules.
//
// UX: sectioned form, one Glass card per rule category, matching the
// pattern used by OrganizerDisciplineScreen. A "Review & Publish" card at
// the bottom lets the organizer save as an editable draft or publish+lock.

import 'package:flutter/material.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/leagues_repository_firebase.dart';
import '../models/competition_rules.dart';
import '../models/football_category.dart';

class CompetitionRulesEditorScreen extends StatefulWidget {
  const CompetitionRulesEditorScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  State<CompetitionRulesEditorScreen> createState() =>
      _CompetitionRulesEditorScreenState();
}

class _CompetitionRulesEditorScreenState
    extends State<CompetitionRulesEditorScreen> {
  final LeaguesRepositoryFirebase _repo = LeaguesRepositoryFirebase();

  // Values are l10n keys (translated via context.l10n.tr at display time),
  // not raw display text.
  static const Map<String, String> _fairPlayLabels = {
    'fair_play_respect':
        'competition_rules_editor_fair_play_respect_mandatory',
    'no_harassment': 'competition_rules_editor_fair_play_no_harassment',
    'no_abusive_language':
        'competition_rules_editor_fair_play_no_abusive_language',
    'no_discrimination':
        'competition_rules_editor_fair_play_no_discrimination',
    'no_cheating': 'competition_rules_editor_fair_play_no_cheating',
    'no_match_fixing': 'competition_rules_editor_fair_play_no_match_fixing',
    'no_collusion': 'competition_rules_editor_fair_play_no_collusion',
    'no_impersonation':
        'competition_rules_editor_fair_play_no_impersonation',
    'no_account_sharing':
        'competition_rules_editor_fair_play_no_account_sharing',
    'no_deliberate_exploitation':
        'competition_rules_editor_fair_play_no_deliberate_exploitation',
  };

  static const List<String> _evidenceTypeOptions = [
    'screenshot',
    'video',
    'match_recording',
    'system_generated',
    'other',
  ];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _hadExistingDoc = false;
  int _loadedVersion = 1;

  CompetitionType _competitionType = CompetitionType.online;
  bool _locked = false;

  // Scheduling
  SchedulingMethod _schedulingMethod = SchedulingMethod.organizerScheduled;
  final _matchDeadlineHoursCtrl = TextEditingController();
  bool _allowRescheduling = true;
  bool _deadlineExtensionAllowed = false;
  final _timezoneCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();
  final _schedulingNotesCtrl = TextEditingController();

  // Match settings
  final _matchDurationCtrl = TextEditingController();
  int _legs = 1;
  bool _extraTimeEnabled = false;
  bool _penaltiesEnabled = false;
  final _conditionCtrl = TextEditingController();
  final _substitutionsCtrl = TextEditingController(text: '-1');
  final _matchSettingsNotesCtrl = TextEditingController();

  // Gameplay
  final _allowedCtrl = TextEditingController();
  final _prohibitedCtrl = TextEditingController();
  final _gameplayCustomCtrl = TextEditingController();

  // Connection & disconnection
  bool _connectionEnabled = false;
  final _reconnectWindowCtrl = TextEditingController();
  bool _replayAllowed = false;
  bool _connectionEvidenceRequired = false;
  final _decidedByCtrl = TextEditingController();
  final _repeatedDisconnectionCtrl = TextEditingController();

  // No-show & forfeit
  final _waitingPeriodCtrl = TextEditingController();
  bool _warningBeforeForfeit = true;
  bool _autoForfeit = false;
  final _forfeitScoreCtrl = TextEditingController();
  final _missedMatchesCtrl = TextEditingController(text: '0');
  final _disqualificationThresholdCtrl = TextEditingController(text: '0');

  // Result submission
  ResultSubmissionMode _resultMode = ResultSubmissionMode.bothConfirm;
  bool _screenshotRequired = false;
  bool _videoRequired = false;
  final _submissionDeadlineCtrl = TextEditingController();
  final _disputeWindowCtrl = TextEditingController();
  bool _autoConfirmIfNoDispute = false;

  // Evidence
  final Set<String> _acceptedEvidenceTypes = <String>{};

  // Eligibility
  final _ageRestrictionCtrl = TextEditingController();
  final _rosterNotesCtrl = TextEditingController();
  bool _duplicateTeamsAllowed = false;
  final _registrationDeadlineCtrl = TextEditingController();
  final _eligibilityNotesCtrl = TextEditingController();

  // Fair play
  final Set<String> _enabledFairPlayKeys = {...kStandardFairPlayRuleKeys};
  final _fairPlayCustomCtrl = TextEditingController();

  // Disputes
  final _disputeWindowHoursCtrl = TextEditingController();
  final _whoCanSubmitCtrl = TextEditingController();
  bool _disputeEvidenceRequired = false;
  final _finalAuthorityCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _matchDeadlineHoursCtrl,
      _timezoneCtrl,
      _venueCtrl,
      _schedulingNotesCtrl,
      _matchDurationCtrl,
      _conditionCtrl,
      _substitutionsCtrl,
      _matchSettingsNotesCtrl,
      _allowedCtrl,
      _prohibitedCtrl,
      _gameplayCustomCtrl,
      _reconnectWindowCtrl,
      _decidedByCtrl,
      _repeatedDisconnectionCtrl,
      _waitingPeriodCtrl,
      _forfeitScoreCtrl,
      _missedMatchesCtrl,
      _disqualificationThresholdCtrl,
      _submissionDeadlineCtrl,
      _disputeWindowCtrl,
      _ageRestrictionCtrl,
      _rosterNotesCtrl,
      _registrationDeadlineCtrl,
      _eligibilityNotesCtrl,
      _fairPlayCustomCtrl,
      _disputeWindowHoursCtrl,
      _whoCanSubmitCtrl,
      _finalAuthorityCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  List<String> _linesOf(String raw) => raw
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  int _intOf(String raw, {int fallback = 0}) =>
      int.tryParse(raw.trim()) ?? fallback;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final league = await _repo.getLeagueById(widget.leagueId);
      final existing = await _repo.getCompetitionRules(widget.leagueId);

      final defaultType = (league?.footballCategory ==
              FootballCategory.localFootball)
          ? CompetitionType.physical
          : CompetitionType.online;

      final rules = existing ??
          CompetitionRules.defaultsFor(
            leagueId: widget.leagueId,
            competitionType: defaultType,
          );

      _hadExistingDoc = existing != null;
      _loadedVersion = rules.version;
      _seedFrom(rules);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _seedFrom(CompetitionRules r) {
    _competitionType = r.competitionType;
    _locked = r.locked;

    _schedulingMethod = r.scheduling.method;
    _matchDeadlineHoursCtrl.text = r.scheduling.matchDeadlineHours > 0
        ? '${r.scheduling.matchDeadlineHours}'
        : '';
    _allowRescheduling = r.scheduling.allowRescheduling;
    _deadlineExtensionAllowed = r.scheduling.deadlineExtensionAllowed;
    _timezoneCtrl.text = r.scheduling.timezone;
    _venueCtrl.text = r.scheduling.venue;
    _schedulingNotesCtrl.text = r.scheduling.notes;

    _matchDurationCtrl.text = r.matchSettings.matchDurationMinutes > 0
        ? '${r.matchSettings.matchDurationMinutes}'
        : '';
    _legs = r.matchSettings.legs <= 0 ? 1 : r.matchSettings.legs;
    _extraTimeEnabled = r.matchSettings.extraTimeEnabled;
    _penaltiesEnabled = r.matchSettings.penaltiesEnabled;
    _conditionCtrl.text = r.matchSettings.condition;
    _substitutionsCtrl.text = '${r.matchSettings.substitutions}';
    _matchSettingsNotesCtrl.text = r.matchSettings.notes;

    _allowedCtrl.text = r.gameplay.allowed.join('\n');
    _prohibitedCtrl.text = r.gameplay.prohibited.join('\n');
    _gameplayCustomCtrl.text = r.gameplay.customRules.join('\n');

    _connectionEnabled = r.connection.enabled;
    _reconnectWindowCtrl.text = r.connection.reconnectWindowMinutes > 0
        ? '${r.connection.reconnectWindowMinutes}'
        : '';
    _replayAllowed = r.connection.replayAllowed;
    _connectionEvidenceRequired = r.connection.evidenceRequired;
    _decidedByCtrl.text = r.connection.decidedBy;
    _repeatedDisconnectionCtrl.text =
        r.connection.repeatedDisconnectionConsequence;

    _waitingPeriodCtrl.text =
        r.noShow.waitingPeriodMinutes > 0 ? '${r.noShow.waitingPeriodMinutes}' : '';
    _warningBeforeForfeit = r.noShow.warningBeforeForfeit;
    _autoForfeit = r.noShow.autoForfeit;
    _forfeitScoreCtrl.text = r.noShow.forfeitScore;
    _missedMatchesCtrl.text = '${r.noShow.missedMatchesAllowed}';
    _disqualificationThresholdCtrl.text = '${r.noShow.disqualificationThreshold}';

    _resultMode = r.resultSubmission.mode;
    _screenshotRequired = r.resultSubmission.screenshotRequired;
    _videoRequired = r.resultSubmission.videoRequired;
    _submissionDeadlineCtrl.text = r.resultSubmission.submissionDeadlineHours > 0
        ? '${r.resultSubmission.submissionDeadlineHours}'
        : '';
    _disputeWindowCtrl.text = r.resultSubmission.disputeWindowHours > 0
        ? '${r.resultSubmission.disputeWindowHours}'
        : '';
    _autoConfirmIfNoDispute = r.resultSubmission.autoConfirmIfNoDispute;

    _acceptedEvidenceTypes
      ..clear()
      ..addAll(r.evidence.acceptedTypes);

    _ageRestrictionCtrl.text = r.eligibility.ageRestriction;
    _rosterNotesCtrl.text = r.eligibility.rosterNotes;
    _duplicateTeamsAllowed = r.eligibility.duplicateTeamsAllowed;
    _registrationDeadlineCtrl.text = r.eligibility.registrationDeadline;
    _eligibilityNotesCtrl.text = r.eligibility.notes;

    _enabledFairPlayKeys
      ..clear()
      ..addAll(r.fairPlay.enabledStandardRuleKeys);
    _fairPlayCustomCtrl.text = r.fairPlay.customRules.join('\n');

    _disputeWindowHoursCtrl.text =
        r.disputes.disputeWindowHours > 0 ? '${r.disputes.disputeWindowHours}' : '';
    _whoCanSubmitCtrl.text = r.disputes.whoCanSubmit;
    _disputeEvidenceRequired = r.disputes.evidenceRequired;
    _finalAuthorityCtrl.text = r.disputes.finalDecisionAuthority;
  }

  CompetitionRules _buildRulesFromForm({required bool publishLocked}) {
    return CompetitionRules(
      leagueId: widget.leagueId,
      version: _loadedVersion,
      locked: publishLocked,
      competitionType: _competitionType,
      scheduling: SchedulingRules(
        method: _schedulingMethod,
        matchDeadlineHours: _intOf(_matchDeadlineHoursCtrl.text),
        allowRescheduling: _allowRescheduling,
        deadlineExtensionAllowed: _deadlineExtensionAllowed,
        timezone: _timezoneCtrl.text.trim(),
        venue: _venueCtrl.text.trim(),
        notes: _schedulingNotesCtrl.text.trim(),
      ),
      matchSettings: MatchSettingsRules(
        matchDurationMinutes: _intOf(_matchDurationCtrl.text),
        legs: _legs,
        extraTimeEnabled: _extraTimeEnabled,
        penaltiesEnabled: _penaltiesEnabled,
        condition: _conditionCtrl.text.trim(),
        substitutions: _intOf(_substitutionsCtrl.text, fallback: -1),
        notes: _matchSettingsNotesCtrl.text.trim(),
      ),
      gameplay: GameplayRules(
        allowed: _linesOf(_allowedCtrl.text),
        prohibited: _linesOf(_prohibitedCtrl.text),
        customRules: _linesOf(_gameplayCustomCtrl.text),
      ),
      connection: ConnectionRules(
        enabled: _connectionEnabled,
        reconnectWindowMinutes: _intOf(_reconnectWindowCtrl.text),
        replayAllowed: _replayAllowed,
        evidenceRequired: _connectionEvidenceRequired,
        decidedBy: _decidedByCtrl.text.trim(),
        repeatedDisconnectionConsequence:
            _repeatedDisconnectionCtrl.text.trim(),
      ),
      noShow: NoShowRules(
        waitingPeriodMinutes: _intOf(_waitingPeriodCtrl.text),
        warningBeforeForfeit: _warningBeforeForfeit,
        autoForfeit: _autoForfeit,
        forfeitScore: _forfeitScoreCtrl.text.trim(),
        missedMatchesAllowed: _intOf(_missedMatchesCtrl.text),
        disqualificationThreshold: _intOf(_disqualificationThresholdCtrl.text),
      ),
      resultSubmission: ResultSubmissionRules(
        mode: _resultMode,
        screenshotRequired: _screenshotRequired,
        videoRequired: _videoRequired,
        submissionDeadlineHours: _intOf(_submissionDeadlineCtrl.text),
        disputeWindowHours: _intOf(_disputeWindowCtrl.text),
        autoConfirmIfNoDispute: _autoConfirmIfNoDispute,
      ),
      evidence: EvidenceRules(
        acceptedTypes: _acceptedEvidenceTypes.toList(growable: false),
      ),
      eligibility: EligibilityRules(
        ageRestriction: _ageRestrictionCtrl.text.trim(),
        rosterNotes: _rosterNotesCtrl.text.trim(),
        duplicateTeamsAllowed: _duplicateTeamsAllowed,
        registrationDeadline: _registrationDeadlineCtrl.text.trim(),
        notes: _eligibilityNotesCtrl.text.trim(),
      ),
      fairPlay: FairPlayRules(
        enabledStandardRuleKeys: _enabledFairPlayKeys.toList(growable: false),
        customRules: _linesOf(_fairPlayCustomCtrl.text),
      ),
      disputes: DisputeRules(
        disputeWindowHours: _intOf(_disputeWindowHoursCtrl.text),
        whoCanSubmit: _whoCanSubmitCtrl.text.trim(),
        evidenceRequired: _disputeEvidenceRequired,
        finalDecisionAuthority: _finalAuthorityCtrl.text.trim(),
      ),
    );
  }

  Future<void> _save({required bool publishLocked}) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final rules = _buildRulesFromForm(publishLocked: publishLocked);
      final saved = await _repo.saveCompetitionRules(rules);

      if (!mounted) return;
      setState(() {
        _saving = false;
        _hadExistingDoc = true;
        _loadedVersion = saved.version;
        _locked = saved.locked;
      });

      _snack(publishLocked
          ? '${context.l10n.tr('competition_rules_editor_published_locked_prefix')}${saved.version}${context.l10n.tr('competition_rules_editor_published_locked_suffix')}'
          : '${context.l10n.tr('competition_rules_editor_saved_draft_prefix')}${saved.version}${context.l10n.tr('competition_rules_editor_saved_draft_suffix')}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('$e', error: true);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────

  Widget _sectionCard(
    Brightness brightness,
    ThemeData theme, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Glass(
        borderRadius: 22,
        padding: const EdgeInsets.all(16),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _rowGap() => const SizedBox(height: 10);

  Widget _numberField(TextEditingController ctrl, String label, {String? suffix}) {
    return TextField(
      controller: ctrl,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      enabled: !_saving,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      value: value,
      onChanged: _saving ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
            context.l10n.tr('competition_rules_editor_app_bar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip:
                context.l10n.tr('competition_rules_editor_reload_tooltip'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _buildHeaderCard(theme, brightness),
                      const SizedBox(height: 4),
                      _buildSchedulingCard(theme, brightness),
                      _buildMatchSettingsCard(theme, brightness),
                      _buildGameplayCard(theme, brightness),
                      _buildConnectionCard(theme, brightness),
                      _buildNoShowCard(theme, brightness),
                      _buildResultSubmissionCard(theme, brightness),
                      _buildEvidenceCard(theme, brightness),
                      _buildEligibilityCard(theme, brightness),
                      _buildFairPlayCard(theme, brightness),
                      _buildDisputesCard(theme, brightness),
                      _buildPublishCard(theme, brightness),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, Brightness brightness) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hadExistingDoc
                ? '${context.l10n.tr('competition_rules_editor_editing_version_prefix')}$_loadedVersion'
                : context.l10n
                    .tr('competition_rules_editor_new_rules_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr('competition_rules_editor_header_subtitle'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (_locked) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.tr(
                          'competition_rules_editor_locked_banner'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            context.l10n.tr('competition_rules_editor_competition_type'),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CompetitionType.values.map((t) {
              final selected = _competitionType == t;
              return ChoiceChip(
                label: Text(t.displayName),
                selected: selected,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _competitionType = t),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulingCard(ThemeData theme, Brightness brightness) {
    final l10n = context.l10n;
    return _sectionCard(
      brightness,
      theme,
      title: l10n.tr('competition_rules_editor_scheduling_title'),
      subtitle: l10n.tr('competition_rules_editor_scheduling_subtitle'),
      children: [
        DropdownButtonFormField<SchedulingMethod>(
          value: _schedulingMethod,
          decoration: InputDecoration(
              labelText: l10n
                  .tr('competition_rules_editor_scheduling_method_label')),
          items: SchedulingMethod.values
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m.displayName),
                  ))
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (v) => setState(
                  () => _schedulingMethod = v ?? _schedulingMethod),
        ),
        _rowGap(),
        if (_schedulingMethod == SchedulingMethod.fixedWindow) ...[
          _numberField(
              _matchDeadlineHoursCtrl,
              l10n.tr(
                  'competition_rules_editor_match_deadline_label'),
              suffix: l10n.tr('competition_rules_editor_unit_hours')),
          _rowGap(),
        ],
        _switchTile(
            l10n.tr('competition_rules_editor_allow_rescheduling'),
            _allowRescheduling,
            (v) => setState(() => _allowRescheduling = v)),
        _switchTile(
            l10n.tr(
                'competition_rules_editor_allow_deadline_extensions'),
            _deadlineExtensionAllowed,
            (v) => setState(() => _deadlineExtensionAllowed = v)),
        _rowGap(),
        _textField(_timezoneCtrl,
            l10n.tr('competition_rules_editor_timezone_optional')),
        _rowGap(),
        _textField(_venueCtrl,
            l10n.tr('competition_rules_editor_venue_optional')),
        _rowGap(),
        _textField(
            _schedulingNotesCtrl,
            l10n.tr(
                'competition_rules_editor_scheduling_notes_optional'),
            maxLines: 3),
      ],
    );
  }

  Widget _buildMatchSettingsCard(ThemeData theme, Brightness brightness) {
    final l10n = context.l10n;
    return _sectionCard(
      brightness,
      theme,
      title: l10n.tr('competition_rules_editor_match_settings_title'),
      subtitle:
          l10n.tr('competition_rules_editor_match_settings_subtitle'),
      children: [
        _numberField(
            _matchDurationCtrl,
            l10n.tr('competition_rules_editor_match_duration_label'),
            suffix: l10n.tr('competition_rules_editor_unit_minutes')),
        _rowGap(),
        DropdownButtonFormField<int>(
          value: _legs,
          decoration: InputDecoration(
              labelText:
                  l10n.tr('competition_rules_editor_legs_label')),
          items: [
            DropdownMenuItem(
                value: 1,
                child: Text(l10n
                    .tr('competition_rules_editor_single_match'))),
            DropdownMenuItem(
                value: 2,
                child: Text(l10n.tr(
                    'competition_rules_editor_home_and_away'))),
          ],
          onChanged: _saving ? null : (v) => setState(() => _legs = v ?? 1),
        ),
        _switchTile(
            l10n.tr('competition_rules_editor_extra_time_enabled'),
            _extraTimeEnabled,
            (v) => setState(() => _extraTimeEnabled = v)),
        _switchTile(
            l10n.tr(
                'competition_rules_editor_penalty_shootout_enabled'),
            _penaltiesEnabled,
            (v) => setState(() => _penaltiesEnabled = v)),
        _rowGap(),
        _textField(
            _conditionCtrl,
            l10n.tr(
                'competition_rules_editor_game_condition_label')),
        _rowGap(),
        _textField(
            _substitutionsCtrl,
            l10n.tr(
                'competition_rules_editor_substitutions_label')),
        _rowGap(),
        _textField(
            _matchSettingsNotesCtrl,
            l10n.tr(
                'competition_rules_editor_match_settings_notes_optional'),
            maxLines: 3),
      ],
    );
  }

  Widget _buildGameplayCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_gameplay_title'),
      subtitle: context.l10n.tr('competition_rules_editor_gameplay_subtitle'),
      children: [
        _textField(_allowedCtrl, context.l10n.tr('competition_rules_editor_allowed_gameplay_settings'), maxLines: 3),
        _rowGap(),
        _textField(_prohibitedCtrl, context.l10n.tr('competition_rules_editor_prohibited_behavior'),
            maxLines: 3),
        _rowGap(),
        _textField(_gameplayCustomCtrl, context.l10n.tr('competition_rules_editor_custom_organizer_rules'), maxLines: 3),
      ],
    );
  }

  Widget _buildConnectionCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_connection_title'),
      subtitle: context.l10n.tr('competition_rules_editor_connection_subtitle'),
      children: [
        _switchTile(context.l10n.tr('competition_rules_editor_applies_to_competition'), _connectionEnabled,
            (v) => setState(() => _connectionEnabled = v)),
        if (_connectionEnabled) ...[
          _rowGap(),
          _numberField(_reconnectWindowCtrl, context.l10n.tr('competition_rules_editor_time_to_reconnect'),
              suffix: context.l10n.tr('competition_rules_editor_unit_minutes')),
          _switchTile(context.l10n.tr('competition_rules_editor_replay_allowed'), _replayAllowed,
              (v) => setState(() => _replayAllowed = v)),
          _switchTile(context.l10n.tr('competition_rules_editor_evidence_required'), _connectionEvidenceRequired,
              (v) => setState(() => _connectionEvidenceRequired = v)),
          _rowGap(),
          _textField(_decidedByCtrl, context.l10n.tr('competition_rules_editor_who_decides_outcome')),
          _rowGap(),
          _textField(_repeatedDisconnectionCtrl,
              context.l10n.tr('competition_rules_editor_repeated_disconnection'), maxLines: 2),
        ],
      ],
    );
  }

  Widget _buildNoShowCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '5. No-Show & Forfeit',
      subtitle: 'Works for both "missed the 24h deadline" and '
          '"failed to appear on the scheduled date".',
      children: [
        _numberField(_waitingPeriodCtrl, context.l10n.tr('competition_rules_editor_waiting_period_forfeit'),
            suffix: context.l10n.tr('competition_rules_editor_unit_minutes')),
        _switchTile(context.l10n.tr('competition_rules_editor_warn_before_forfeit'), _warningBeforeForfeit,
            (v) => setState(() => _warningBeforeForfeit = v)),
        _switchTile(context.l10n.tr('competition_rules_editor_automatic_forfeit'), _autoForfeit,
            (v) => setState(() => _autoForfeit = v)),
        _rowGap(),
        _textField(_forfeitScoreCtrl, context.l10n.tr('competition_rules_editor_forfeit_score')),
        _rowGap(),
        _numberField(_missedMatchesCtrl, context.l10n.tr('competition_rules_editor_missed_matches_allowed')),
        _rowGap(),
        _numberField(
            _disqualificationThresholdCtrl, context.l10n.tr('competition_rules_editor_disqualification_threshold')),
      ],
    );
  }

  Widget _buildResultSubmissionCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_result_submission_title'),
      subtitle: context.l10n.tr('competition_rules_editor_result_submission_subtitle'),
      children: [
        DropdownButtonFormField<ResultSubmissionMode>(
          value: _resultMode,
          decoration: InputDecoration(labelText: context.l10n.tr('competition_rules_editor_submission_mode')),
          items: ResultSubmissionMode.values
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m.displayName),
                  ))
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (v) => setState(() => _resultMode = v ?? _resultMode),
        ),
        _switchTile(context.l10n.tr('competition_rules_editor_screenshot_required'), _screenshotRequired,
            (v) => setState(() => _screenshotRequired = v)),
        _switchTile(context.l10n.tr('competition_rules_editor_video_required'), _videoRequired,
            (v) => setState(() => _videoRequired = v)),
        _switchTile(context.l10n.tr('competition_rules_editor_auto_confirm_no_dispute'),
            _autoConfirmIfNoDispute,
            (v) => setState(() => _autoConfirmIfNoDispute = v)),
        _rowGap(),
        _numberField(_submissionDeadlineCtrl, context.l10n.tr('competition_rules_editor_submission_deadline'),
            suffix: context.l10n.tr('competition_rules_editor_unit_hours')),
        _rowGap(),
        _numberField(_disputeWindowCtrl, context.l10n.tr('competition_rules_editor_dispute_window'), suffix: context.l10n.tr('competition_rules_editor_unit_hours')),
      ],
    );
  }

  Widget _buildEvidenceCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_evidence_title'),
      subtitle: context.l10n.tr('competition_rules_editor_evidence_subtitle'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _evidenceTypeOptions.map((type) {
            final selected = _acceptedEvidenceTypes.contains(type);
            return FilterChip(
              label: Text(type.replaceAll('_', ' ')),
              selected: selected,
              onSelected: _saving
                  ? null
                  : (v) => setState(() {
                        if (v) {
                          _acceptedEvidenceTypes.add(type);
                        } else {
                          _acceptedEvidenceTypes.remove(type);
                        }
                      }),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildEligibilityCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_eligibility_title'),
      subtitle: context.l10n.tr('competition_rules_editor_eligibility_subtitle'),
      children: [
        _textField(_ageRestrictionCtrl, context.l10n.tr('competition_rules_editor_age_restriction')),
        _rowGap(),
        _textField(_rosterNotesCtrl, context.l10n.tr('competition_rules_editor_roster_notes'),
            maxLines: 2),
        _switchTile(context.l10n.tr('competition_rules_editor_duplicate_teams_allowed'), _duplicateTeamsAllowed,
            (v) => setState(() => _duplicateTeamsAllowed = v)),
        _rowGap(),
        _textField(_registrationDeadlineCtrl, context.l10n.tr('competition_rules_editor_registration_deadline_optional')),
        _rowGap(),
        _textField(_eligibilityNotesCtrl, context.l10n.tr('competition_rules_editor_other_eligibility_notes'),
            maxLines: 2),
      ],
    );
  }

  Widget _buildFairPlayCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_fair_play_title'),
      subtitle: context.l10n.tr('competition_rules_editor_fair_play_subtitle'),
      children: [
        ..._fairPlayLabels.entries.map((entry) {
          final enabled = _enabledFairPlayKeys.contains(entry.key);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: enabled,
            title: Text(context.l10n.tr(entry.value),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _enabledFairPlayKeys.add(entry.key);
                      } else {
                        _enabledFairPlayKeys.remove(entry.key);
                      }
                    }),
          );
        }),
        _rowGap(),
        _textField(_fairPlayCustomCtrl, context.l10n.tr('competition_rules_editor_custom_fair_play_rules'),
            maxLines: 3),
      ],
    );
  }

  Widget _buildDisputesCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: context.l10n.tr('competition_rules_editor_disputes_title'),
      subtitle: context.l10n.tr('competition_rules_editor_disputes_subtitle'),
      children: [
        _numberField(_disputeWindowHoursCtrl, context.l10n.tr('competition_rules_editor_dispute_window'), suffix: context.l10n.tr('competition_rules_editor_unit_hours')),
        _rowGap(),
        _textField(_whoCanSubmitCtrl, context.l10n.tr('competition_rules_editor_who_can_submit_dispute')),
        _switchTile(context.l10n.tr('competition_rules_editor_evidence_required_disputes'), _disputeEvidenceRequired,
            (v) => setState(() => _disputeEvidenceRequired = v)),
        _rowGap(),
        _textField(_finalAuthorityCtrl, context.l10n.tr('competition_rules_editor_final_authority')),
      ],
    );
  }

  Widget _buildPublishCard(ThemeData theme, Brightness brightness) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('competition_rules_editor_review_publish_title'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr('competition_rules_editor_review_publish_body'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.cardBorder(brightness)),
                foregroundColor: AppTheme.limeAccentDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? context.l10n.tr('competition_rules_editor_saving') : context.l10n.tr('competition_rules_editor_save_as_draft'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              onPressed: _saving ? null : () => _save(publishLocked: false),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.darkText),
                    )
                  : const Icon(Icons.lock_rounded),
              label: Text(
                _saving
                    ? context.l10n.tr('competition_rules_editor_publishing')
                    : (_locked ? context.l10n.tr('competition_rules_editor_save_new_locked_version') : context.l10n.tr('competition_rules_editor_publish_lock_rules')),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              onPressed: _saving ? null : () => _save(publishLocked: true),
            ),
          ),
        ],
      ),
    );
  }
}
