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

  static const Map<String, String> _fairPlayLabels = {
    'fair_play_respect': 'Fair play & respect are mandatory',
    'no_harassment': 'No harassment',
    'no_abusive_language': 'No abusive language',
    'no_discrimination': 'No discrimination',
    'no_cheating': 'No cheating',
    'no_match_fixing': 'No match fixing',
    'no_collusion': 'No collusion',
    'no_impersonation': 'No impersonation',
    'no_account_sharing': 'No account sharing',
    'no_deliberate_exploitation': 'No deliberate exploitation of glitches',
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
          ? 'Rules published and locked (v${saved.version}).'
          : 'Rules saved as draft (v${saved.version}).');
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
        title: const Text('Competition Rules'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Reload',
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
                ? 'Editing v$_loadedVersion'
                : 'New Competition Rules',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Define what participants must follow in this competition. '
            'This is separate from Organizer Discipline, which stays where '
            'it is.',
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
                children: const [
                  Icon(Icons.lock_rounded, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These rules are locked. Saving changes will publish '
                      'a new version and keep the old one for history.',
                      style: TextStyle(
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
            'Competition Type',
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
    return _sectionCard(
      brightness,
      theme,
      title: '1. Match Scheduling',
      subtitle: 'Do not assume a 24-hour deadline — pick what fits this '
          'competition.',
      children: [
        DropdownButtonFormField<SchedulingMethod>(
          value: _schedulingMethod,
          decoration: const InputDecoration(labelText: 'Scheduling method'),
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
          _numberField(_matchDeadlineHoursCtrl, 'Match deadline', suffix: 'hours'),
          _rowGap(),
        ],
        _switchTile('Allow rescheduling', _allowRescheduling,
            (v) => setState(() => _allowRescheduling = v)),
        _switchTile('Allow deadline extensions', _deadlineExtensionAllowed,
            (v) => setState(() => _deadlineExtensionAllowed = v)),
        _rowGap(),
        _textField(_timezoneCtrl, 'Timezone (optional)'),
        _rowGap(),
        _textField(_venueCtrl, 'Venue / location (optional)'),
        _rowGap(),
        _textField(_schedulingNotesCtrl, 'Scheduling notes (optional)',
            maxLines: 3),
      ],
    );
  }

  Widget _buildMatchSettingsCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '2. Match Settings',
      subtitle: 'Only fill in what applies to this competition/game type.',
      children: [
        _numberField(_matchDurationCtrl, 'Match duration', suffix: 'minutes'),
        _rowGap(),
        DropdownButtonFormField<int>(
          value: _legs,
          decoration: const InputDecoration(labelText: 'Legs'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Single match')),
            DropdownMenuItem(value: 2, child: Text('Home & away (2 legs)')),
          ],
          onChanged: _saving ? null : (v) => setState(() => _legs = v ?? 1),
        ),
        _switchTile('Extra time enabled', _extraTimeEnabled,
            (v) => setState(() => _extraTimeEnabled = v)),
        _switchTile('Penalty shootout enabled', _penaltiesEnabled,
            (v) => setState(() => _penaltiesEnabled = v)),
        _rowGap(),
        _textField(_conditionCtrl, 'Game condition (e.g. "Excellent", "Any")'),
        _rowGap(),
        _textField(_substitutionsCtrl, 'Substitutions (-1 = unlimited)'),
        _rowGap(),
        _textField(_matchSettingsNotesCtrl, 'Match settings notes (optional)',
            maxLines: 3),
      ],
    );
  }

  Widget _buildGameplayCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '3. Gameplay Rules',
      subtitle: 'One rule per line.',
      children: [
        _textField(_allowedCtrl, 'Allowed gameplay settings', maxLines: 3),
        _rowGap(),
        _textField(_prohibitedCtrl, 'Prohibited behavior / glitches / cheating',
            maxLines: 3),
        _rowGap(),
        _textField(_gameplayCustomCtrl, 'Custom organizer rules', maxLines: 3),
      ],
    );
  }

  Widget _buildConnectionCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '4. Connection & Disconnection',
      subtitle: 'Leave disabled for physical/local competitions.',
      children: [
        _switchTile('Applies to this competition', _connectionEnabled,
            (v) => setState(() => _connectionEnabled = v)),
        if (_connectionEnabled) ...[
          _rowGap(),
          _numberField(_reconnectWindowCtrl, 'Time to reconnect',
              suffix: 'minutes'),
          _switchTile('Replay allowed', _replayAllowed,
              (v) => setState(() => _replayAllowed = v)),
          _switchTile('Evidence required', _connectionEvidenceRequired,
              (v) => setState(() => _connectionEvidenceRequired = v)),
          _rowGap(),
          _textField(_decidedByCtrl, 'Who decides the outcome'),
          _rowGap(),
          _textField(_repeatedDisconnectionCtrl,
              'Repeated disconnection consequence', maxLines: 2),
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
        _numberField(_waitingPeriodCtrl, 'Waiting period before forfeit',
            suffix: 'minutes'),
        _switchTile('Warn before forfeit', _warningBeforeForfeit,
            (v) => setState(() => _warningBeforeForfeit = v)),
        _switchTile('Automatic forfeit', _autoForfeit,
            (v) => setState(() => _autoForfeit = v)),
        _rowGap(),
        _textField(_forfeitScoreCtrl, 'Forfeit score (e.g. "3-0")'),
        _rowGap(),
        _numberField(_missedMatchesCtrl, 'Missed matches allowed'),
        _rowGap(),
        _numberField(
            _disqualificationThresholdCtrl, 'Disqualification threshold'),
      ],
    );
  }

  Widget _buildResultSubmissionCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '6. Result Submission',
      subtitle: 'Who submits results and how disputes are triggered.',
      children: [
        DropdownButtonFormField<ResultSubmissionMode>(
          value: _resultMode,
          decoration: const InputDecoration(labelText: 'Submission mode'),
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
        _switchTile('Screenshot required', _screenshotRequired,
            (v) => setState(() => _screenshotRequired = v)),
        _switchTile('Video required', _videoRequired,
            (v) => setState(() => _videoRequired = v)),
        _switchTile('Auto-confirm if no dispute is raised',
            _autoConfirmIfNoDispute,
            (v) => setState(() => _autoConfirmIfNoDispute = v)),
        _rowGap(),
        _numberField(_submissionDeadlineCtrl, 'Submission deadline',
            suffix: 'hours'),
        _rowGap(),
        _numberField(_disputeWindowCtrl, 'Dispute window', suffix: 'hours'),
      ],
    );
  }

  Widget _buildEvidenceCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '7. Evidence',
      subtitle: 'Not required for every competition by default.',
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
      title: '8. Participant & Team Eligibility',
      subtitle: 'Free text — keep it as strict or as open as this '
          'competition needs.',
      children: [
        _textField(_ageRestrictionCtrl, 'Age restriction (e.g. "16+", optional)'),
        _rowGap(),
        _textField(_rosterNotesCtrl, 'Roster / registration notes',
            maxLines: 2),
        _switchTile('Duplicate teams allowed', _duplicateTeamsAllowed,
            (v) => setState(() => _duplicateTeamsAllowed = v)),
        _rowGap(),
        _textField(_registrationDeadlineCtrl, 'Registration deadline (optional)'),
        _rowGap(),
        _textField(_eligibilityNotesCtrl, 'Other eligibility notes',
            maxLines: 2),
      ],
    );
  }

  Widget _buildFairPlayCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '9. Fair Play & Conduct',
      subtitle: 'Toggle the standard rules that apply, add custom ones '
          'below.',
      children: [
        ..._fairPlayLabels.entries.map((entry) {
          final enabled = _enabledFairPlayKeys.contains(entry.key);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: enabled,
            title: Text(entry.value,
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
        _textField(_fairPlayCustomCtrl, 'Custom fair play rules (one per line)',
            maxLines: 3),
      ],
    );
  }

  Widget _buildDisputesCard(ThemeData theme, Brightness brightness) {
    return _sectionCard(
      brightness,
      theme,
      title: '10. Disputes & Appeals',
      subtitle: 'Participants should know how disputes are handled before '
          'joining.',
      children: [
        _numberField(_disputeWindowHoursCtrl, 'Dispute window', suffix: 'hours'),
        _rowGap(),
        _textField(_whoCanSubmitCtrl, 'Who can submit a dispute'),
        _switchTile('Evidence required for disputes', _disputeEvidenceRequired,
            (v) => setState(() => _disputeEvidenceRequired = v)),
        _rowGap(),
        _textField(_finalAuthorityCtrl, 'Final decision authority (e.g. "Organizer")'),
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
            'Review & Publish',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Participants will see exactly these settings on the rules '
            'screen shown when they join.',
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
              label: Text(_saving ? 'Saving...' : 'Save as Draft',
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
                    ? 'Publishing...'
                    : (_locked ? 'Save New Locked Version' : 'Publish & Lock Rules'),
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
