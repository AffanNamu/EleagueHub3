// lib/features/leagues/presentation/competition_rules_gate_screen.dart
//
// NEW FILE — Participant-facing Competition Rules gate.
//
// Shown right after a user joins a league AS A PARTICIPANT (via QR scan or
// join-by-code), before they land on LeagueDetailScreen. Per product
// decision:
//   - Informational only — no mandatory "I agree" checkbox, no agreement
//     stored. A "Continue" button is enough.
//   - Participant joins only. Call sites must not route Viewer joins here.
//   - If the organizer hasn't configured any rules yet, this screen skips
//     itself automatically and the user lands straight on League Detail —
//     an unconfigured competition is a normal, backward-compatible state,
//     not an error.
//
// This screen READS ONLY. Editing rules happens in
// CompetitionRulesEditorScreen (organizer-only, separate route).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/leagues_repository_firebase.dart';
import '../models/competition_rules.dart';

class CompetitionRulesGateScreen extends StatefulWidget {
  const CompetitionRulesGateScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  State<CompetitionRulesGateScreen> createState() =>
      _CompetitionRulesGateScreenState();
}

class _CompetitionRulesGateScreenState
    extends State<CompetitionRulesGateScreen> {
  final LeaguesRepositoryFirebase _repo = LeaguesRepositoryFirebase();

  Map<String, String> _fairPlayLabels(BuildContext context) {
    final l10n = context.l10n;
    return {
      'fair_play_respect':
          l10n.tr('competition_rules_gate_fair_play_respect'),
      'no_harassment': l10n.tr('competition_rules_gate_no_harassment'),
      'no_abusive_language':
          l10n.tr('competition_rules_gate_no_abusive_language'),
      'no_discrimination':
          l10n.tr('competition_rules_gate_no_discrimination'),
      'no_cheating': l10n.tr('competition_rules_gate_no_cheating'),
      'no_match_fixing': l10n.tr('competition_rules_gate_no_match_fixing'),
      'no_collusion': l10n.tr('competition_rules_gate_no_collusion'),
      'no_impersonation':
          l10n.tr('competition_rules_gate_no_impersonation'),
      'no_account_sharing':
          l10n.tr('competition_rules_gate_no_account_sharing'),
      'no_deliberate_exploitation':
          l10n.tr('competition_rules_gate_no_deliberate_exploitation'),
    };
  }

  bool _loading = true;
  String? _error;
  CompetitionRules? _rules;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await _repo.getCompetitionRules(widget.leagueId);

      if (!mounted) return;

      if (rules == null) {
        // Nothing configured — skip straight to League Detail. Use
        // pushReplacement so this screen doesn't sit in the back stack.
        context.pushReplacement('/leagues/${widget.leagueId}');
        return;
      }

      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // If rules can't be loaded (offline, transient error), don't block
      // the user from reaching the league — fail open to League Detail.
      context.pushReplacement('/leagues/${widget.leagueId}');
    }
  }

  void _continue() {
    context.pushReplacement('/leagues/${widget.leagueId}');
  }

  String _durationLabel(int hours) {
    final l10n = context.l10n;
    return hours == 1
        ? l10n.tr('competition_rules_gate_duration_one_hour')
        : '$hours${l10n.tr('competition_rules_gate_duration_hours_suffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('competition_rules_gate_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          children: _buildSections(theme, brightness),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.limeAccent,
                              foregroundColor: AppTheme.darkText,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check_circle_rounded),
                            label: Text(
                              context.l10n
                                  .tr('competition_rules_gate_continue_button'),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            onPressed: _continue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildSections(ThemeData theme, Brightness brightness) {
    final r = _rules;
    if (r == null) return const [];

    final sections = <Widget>[
      _headerCard(theme, brightness, r),
    ];

    final scheduling = _schedulingSection(theme, brightness, r);
    if (scheduling != null) sections.add(scheduling);

    final matchSettings = _matchSettingsSection(theme, brightness, r);
    if (matchSettings != null) sections.add(matchSettings);

    final gameplay = _gameplaySection(theme, brightness, r);
    if (gameplay != null) sections.add(gameplay);

    final connection = _connectionSection(theme, brightness, r);
    if (connection != null) sections.add(connection);

    final noShow = _noShowSection(theme, brightness, r);
    if (noShow != null) sections.add(noShow);

    final results = _resultsSection(theme, brightness, r);
    if (results != null) sections.add(results);

    final eligibility = _eligibilitySection(theme, brightness, r);
    if (eligibility != null) sections.add(eligibility);

    final fairPlay = _fairPlaySection(theme, brightness, r);
    if (fairPlay != null) sections.add(fairPlay);

    final disputes = _disputesSection(theme, brightness, r);
    if (disputes != null) sections.add(disputes);

    return sections;
  }

  Widget _card(
    Brightness brightness,
    ThemeData theme, {
    required String emoji,
    required String title,
    required List<Widget> lines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        borderRadius: 20,
        padding: const EdgeInsets.all(16),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$emoji  $title',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 10),
            ...lines,
          ],
        ),
      ),
    );
  }

  Widget _line(ThemeData theme, Brightness brightness, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppTheme.secondaryText(brightness),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _headerCard(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Glass(
        borderRadius: 22,
        padding: const EdgeInsets.all(16),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📜 ${context.l10n.tr('competition_rules_gate_header_title')}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.tr('competition_rules_gate_header_subtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _schedulingSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final s = r.scheduling;
    final lines = <Widget>[];

    final l10n = context.l10n;

    switch (s.method) {
      case SchedulingMethod.fixedWindow:
        if (s.matchDeadlineHours > 0) {
          lines.add(_line(theme, brightness,
              '⏰ ${l10n.tr('competition_rules_gate_sched_deadline_prefix')}${_durationLabel(s.matchDeadlineHours)}'));
        }
        break;
      case SchedulingMethod.organizerScheduled:
        lines.add(_line(theme, brightness,
            '📅 ${l10n.tr('competition_rules_gate_sched_organizer_scheduled')}'));
        break;
      case SchedulingMethod.participantAgreed:
        lines.add(_line(theme, brightness,
            '🤝 ${l10n.tr('competition_rules_gate_sched_participant_agreed')}'));
        break;
    }

    if (s.venue.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '📍 ${l10n.tr('competition_rules_gate_sched_venue_prefix')}${s.venue.trim()}'));
    }
    if (s.timezone.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '🌐 ${l10n.tr('competition_rules_gate_sched_timezone_prefix')}${s.timezone.trim()}'));
    }
    lines.add(_line(
      theme,
      brightness,
      s.allowRescheduling
          ? '🔄 ${l10n.tr('competition_rules_gate_sched_reschedule_allowed')}'
          : '🚫 ${l10n.tr('competition_rules_gate_sched_reschedule_not_allowed')}',
    ));
    if (s.notes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, s.notes.trim()));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '⏱️',
        title: l10n.tr('competition_rules_gate_section_scheduling'),
        lines: lines);
  }

  Widget? _matchSettingsSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final m = r.matchSettings;
    final lines = <Widget>[];
    final l10n = context.l10n;

    if (m.matchDurationMinutes > 0) {
      lines.add(_line(theme, brightness,
          '⏱️ ${l10n.tr('competition_rules_gate_match_duration_prefix')}${m.matchDurationMinutes}${l10n.tr('competition_rules_gate_unit_minutes_suffix')}'));
    }
    if (m.legs > 1) {
      lines.add(_line(theme, brightness,
          '🏟️ ${l10n.tr('competition_rules_gate_legs_prefix')}${m.legs}${l10n.tr('competition_rules_gate_legs_suffix')}'));
    }
    lines.add(_line(
        theme,
        brightness,
        m.extraTimeEnabled
            ? '➕ ${l10n.tr('competition_rules_gate_extra_time_enabled')}'
            : '🚫 ${l10n.tr('competition_rules_gate_extra_time_disabled')}'));
    lines.add(_line(
        theme,
        brightness,
        m.penaltiesEnabled
            ? '🎯 ${l10n.tr('competition_rules_gate_penalties_enabled')}'
            : '🚫 ${l10n.tr('competition_rules_gate_penalties_disabled')}'));
    if (m.condition.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '⚙️ ${l10n.tr('competition_rules_gate_condition_prefix')}${m.condition.trim()}'));
    }
    if (m.substitutions >= 0) {
      lines.add(_line(theme, brightness,
          '🔄 ${l10n.tr('competition_rules_gate_substitutions_prefix')}${m.substitutions}'));
    }
    if (m.notes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, m.notes.trim()));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '⚙️',
        title: l10n.tr('competition_rules_gate_section_match_settings'),
        lines: lines);
  }

  Widget? _gameplaySection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final g = r.gameplay;
    final lines = <Widget>[];

    for (final a in g.allowed) {
      lines.add(_line(theme, brightness, '✅ $a'));
    }
    for (final p in g.prohibited) {
      lines.add(_line(theme, brightness, '🚫 $p'));
    }
    for (final c in g.customRules) {
      lines.add(_line(theme, brightness, '• $c'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🎮',
        title: context.l10n.tr('competition_rules_gate_section_gameplay'),
        lines: lines);
  }

  Widget? _connectionSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final c = r.connection;
    if (!c.enabled) return null;

    final lines = <Widget>[];
    final l10n = context.l10n;
    if (c.reconnectWindowMinutes > 0) {
      lines.add(_line(theme, brightness,
          '🔌 ${l10n.tr('competition_rules_gate_reconnect_window_prefix')}${c.reconnectWindowMinutes}${l10n.tr('competition_rules_gate_unit_minutes_suffix')}'));
    }
    lines.add(_line(
        theme,
        brightness,
        c.replayAllowed
            ? '🔁 ${l10n.tr('competition_rules_gate_replays_allowed')}'
            : '🚫 ${l10n.tr('competition_rules_gate_replays_not_allowed')}'));
    if (c.evidenceRequired) {
      lines.add(_line(theme, brightness,
          '📸 ${l10n.tr('competition_rules_gate_evidence_required')}'));
    }
    if (c.decidedBy.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '⚖️ ${l10n.tr('competition_rules_gate_outcome_decided_by_prefix')}${c.decidedBy.trim()}'));
    }
    if (c.repeatedDisconnectionConsequence.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '⚠️ ${l10n.tr('competition_rules_gate_repeated_disconnections_prefix')}${c.repeatedDisconnectionConsequence.trim()}'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🔌',
        title: l10n.tr('competition_rules_gate_section_connection'),
        lines: lines);
  }

  Widget? _noShowSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final n = r.noShow;
    final lines = <Widget>[];
    final l10n = context.l10n;

    if (n.waitingPeriodMinutes > 0) {
      lines.add(_line(theme, brightness,
          '⏳ ${l10n.tr('competition_rules_gate_waiting_period_prefix')}${n.waitingPeriodMinutes}${l10n.tr('competition_rules_gate_unit_minutes_suffix')}'));
    }
    if (n.warningBeforeForfeit) {
      lines.add(_line(theme, brightness,
          '⚠️ ${l10n.tr('competition_rules_gate_warning_before_forfeit')}'));
    }
    if (n.autoForfeit) {
      lines.add(_line(theme, brightness,
          '🚫 ${l10n.tr('competition_rules_gate_automatic_forfeit')}'));
    }
    if (n.forfeitScore.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '📉 ${l10n.tr('competition_rules_gate_forfeit_score_prefix')}${n.forfeitScore.trim()}'));
    }
    if (n.missedMatchesAllowed > 0) {
      lines.add(_line(theme, brightness,
          '🔁 ${l10n.tr('competition_rules_gate_missed_matches_allowed_prefix')}${n.missedMatchesAllowed}'));
    }
    if (n.disqualificationThreshold > 0) {
      lines.add(_line(theme, brightness,
          '❌ ${l10n.tr('competition_rules_gate_disqualification_after_prefix')}${n.disqualificationThreshold}${l10n.tr('competition_rules_gate_missed_matches_suffix')}'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '⚖️',
        title: l10n.tr('competition_rules_gate_section_no_show'),
        lines: lines);
  }

  Widget? _resultsSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final res = r.resultSubmission;
    final l10n = context.l10n;
    final lines = <Widget>[
      _line(theme, brightness,
          '📝 ${l10n.tr('competition_rules_gate_result_submission_prefix')}${res.mode.displayName}'),
    ];

    if (res.screenshotRequired) {
      lines.add(_line(theme, brightness,
          '📸 ${l10n.tr('competition_rules_gate_screenshot_required')}'));
    }
    if (res.videoRequired) {
      lines.add(_line(theme, brightness,
          '🎥 ${l10n.tr('competition_rules_gate_video_evidence_required')}'));
    }
    if (res.submissionDeadlineHours > 0) {
      lines.add(_line(theme, brightness,
          '⏰ ${l10n.tr('competition_rules_gate_submission_deadline_prefix')}${_durationLabel(res.submissionDeadlineHours)}'));
    }
    if (res.disputeWindowHours > 0) {
      lines.add(_line(theme, brightness,
          '⏳ ${l10n.tr('competition_rules_gate_dispute_window_prefix')}${_durationLabel(res.disputeWindowHours)}'));
    }
    if (r.evidence.acceptedTypes.isNotEmpty) {
      final types = r.evidence.acceptedTypes
          .map((t) => t.replaceAll('_', ' '))
          .join(', ');
      lines.add(_line(theme, brightness,
          '📂 ${l10n.tr('competition_rules_gate_accepted_evidence_prefix')}$types'));
    }

    return _card(brightness, theme,
        emoji: '📋',
        title: l10n.tr('competition_rules_gate_section_results'),
        lines: lines);
  }

  Widget? _eligibilitySection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final e = r.eligibility;
    final lines = <Widget>[];
    final l10n = context.l10n;

    if (e.ageRestriction.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '🔞 ${l10n.tr('competition_rules_gate_age_restriction_prefix')}${e.ageRestriction.trim()}'));
    }
    if (e.rosterNotes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '📋 ${e.rosterNotes.trim()}'));
    }
    if (!e.duplicateTeamsAllowed) {
      lines.add(_line(theme, brightness,
          '🚫 ${l10n.tr('competition_rules_gate_duplicate_teams_not_allowed')}'));
    }
    if (e.registrationDeadline.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '📅 ${l10n.tr('competition_rules_gate_registration_deadline_prefix')}${e.registrationDeadline.trim()}'));
    }
    if (e.notes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, e.notes.trim()));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🧑\u200d🤝\u200d🧑',
        title: l10n.tr('competition_rules_gate_section_eligibility'),
        lines: lines);
  }

  Widget? _fairPlaySection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final f = r.fairPlay;
    final lines = <Widget>[];
    final l10n = context.l10n;
    final fairPlayLabels = _fairPlayLabels(context);

    for (final key in f.enabledStandardRuleKeys) {
      final label = fairPlayLabels[key];
      if (label != null) lines.add(_line(theme, brightness, '✔️ $label'));
    }
    for (final custom in f.customRules) {
      lines.add(_line(theme, brightness, '• $custom'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🤝',
        title: l10n.tr('competition_rules_gate_section_fair_play'),
        lines: lines);
  }

  Widget? _disputesSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final d = r.disputes;
    final lines = <Widget>[];
    final l10n = context.l10n;

    if (d.disputeWindowHours > 0) {
      lines.add(_line(theme, brightness,
          '⏳ ${l10n.tr('competition_rules_gate_dispute_window_prefix')}${_durationLabel(d.disputeWindowHours)}'));
    }
    if (d.whoCanSubmit.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '🙋 ${l10n.tr('competition_rules_gate_who_can_dispute_prefix')}${d.whoCanSubmit.trim()}'));
    }
    if (d.evidenceRequired) {
      lines.add(_line(theme, brightness,
          '📸 ${l10n.tr('competition_rules_gate_evidence_required_for_disputes')}'));
    }
    if (d.finalDecisionAuthority.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '⚖️ ${l10n.tr('competition_rules_gate_final_decision_prefix')}${d.finalDecisionAuthority.trim()}'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '📢',
        title: l10n.tr('competition_rules_gate_section_disputes'),
        lines: lines);
  }
}
