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

  String _durationLabel(int hours) =>
      hours == 1 ? '1 hour' : '$hours hours';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Competition Rules'),
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
                            label: const Text(
                              'Continue to League',
                              style: TextStyle(fontWeight: FontWeight.w900),
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
              '📜 Match Rules',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please review this competition\'s rules before continuing.',
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

    switch (s.method) {
      case SchedulingMethod.fixedWindow:
        if (s.matchDeadlineHours > 0) {
          lines.add(_line(theme, brightness,
              '⏰ Match deadline: ${_durationLabel(s.matchDeadlineHours)}'));
        }
        break;
      case SchedulingMethod.organizerScheduled:
        lines.add(_line(
            theme, brightness, '📅 Matches are scheduled by the organizer.'));
        break;
      case SchedulingMethod.participantAgreed:
        lines.add(_line(theme, brightness,
            '🤝 Teams agree on a match time between themselves.'));
        break;
    }

    if (s.venue.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '📍 Venue: ${s.venue.trim()}'));
    }
    if (s.timezone.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '🌐 Timezone: ${s.timezone.trim()}'));
    }
    lines.add(_line(
      theme,
      brightness,
      s.allowRescheduling
          ? '🔄 Rescheduling is allowed.'
          : '🚫 Rescheduling is not allowed.',
    ));
    if (s.notes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, s.notes.trim()));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '⏱️', title: 'Scheduling', lines: lines);
  }

  Widget? _matchSettingsSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final m = r.matchSettings;
    final lines = <Widget>[];

    if (m.matchDurationMinutes > 0) {
      lines.add(_line(
          theme, brightness, '⏱️ Match duration: ${m.matchDurationMinutes} minutes'));
    }
    if (m.legs > 1) {
      lines.add(_line(theme, brightness, '🏟️ Legs: ${m.legs} (home & away)'));
    }
    lines.add(_line(theme, brightness,
        m.extraTimeEnabled ? '➕ Extra time: Enabled' : '🚫 Extra time: Disabled'));
    lines.add(_line(theme, brightness,
        m.penaltiesEnabled ? '🎯 Penalties: Enabled' : '🚫 Penalties: Disabled'));
    if (m.condition.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '⚙️ Condition: ${m.condition.trim()}'));
    }
    if (m.substitutions >= 0) {
      lines.add(_line(theme, brightness, '🔄 Substitutions: ${m.substitutions}'));
    }
    if (m.notes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, m.notes.trim()));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '⚙️', title: 'Match Settings', lines: lines);
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
        emoji: '🎮', title: 'Gameplay Rules', lines: lines);
  }

  Widget? _connectionSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final c = r.connection;
    if (!c.enabled) return null;

    final lines = <Widget>[];
    if (c.reconnectWindowMinutes > 0) {
      lines.add(_line(theme, brightness,
          '🔌 Reconnection window: ${c.reconnectWindowMinutes} minutes'));
    }
    lines.add(_line(theme, brightness,
        c.replayAllowed ? '🔁 Replays are allowed.' : '🚫 Replays are not allowed.'));
    if (c.evidenceRequired) {
      lines.add(_line(theme, brightness, '📸 Evidence is required.'));
    }
    if (c.decidedBy.trim().isNotEmpty) {
      lines.add(
          _line(theme, brightness, '⚖️ Outcome decided by: ${c.decidedBy.trim()}'));
    }
    if (c.repeatedDisconnectionConsequence.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '⚠️ Repeated disconnections: ${c.repeatedDisconnectionConsequence.trim()}'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🔌', title: 'Connection & Disconnection', lines: lines);
  }

  Widget? _noShowSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final n = r.noShow;
    final lines = <Widget>[];

    if (n.waitingPeriodMinutes > 0) {
      lines.add(_line(theme, brightness,
          '⏳ Waiting period before forfeit: ${n.waitingPeriodMinutes} minutes'));
    }
    if (n.warningBeforeForfeit) {
      lines.add(_line(theme, brightness, '⚠️ A warning is given before forfeit.'));
    }
    if (n.autoForfeit) {
      lines.add(_line(theme, brightness, '🚫 Automatic forfeit applies.'));
    }
    if (n.forfeitScore.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '📉 Forfeit score: ${n.forfeitScore.trim()}'));
    }
    if (n.missedMatchesAllowed > 0) {
      lines.add(_line(theme, brightness,
          '🔁 Missed matches allowed: ${n.missedMatchesAllowed}'));
    }
    if (n.disqualificationThreshold > 0) {
      lines.add(_line(theme, brightness,
          '❌ Disqualification after: ${n.disqualificationThreshold} missed matches'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '⚖️', title: 'No-Show & Forfeit', lines: lines);
  }

  Widget? _resultsSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final res = r.resultSubmission;
    final lines = <Widget>[
      _line(theme, brightness, '📝 Result submission: ${res.mode.displayName}'),
    ];

    if (res.screenshotRequired) {
      lines.add(_line(theme, brightness, '📸 Screenshot required.'));
    }
    if (res.videoRequired) {
      lines.add(_line(theme, brightness, '🎥 Video evidence required.'));
    }
    if (res.submissionDeadlineHours > 0) {
      lines.add(_line(theme, brightness,
          '⏰ Submission deadline: ${_durationLabel(res.submissionDeadlineHours)}'));
    }
    if (res.disputeWindowHours > 0) {
      lines.add(_line(theme, brightness,
          '⏳ Dispute window: ${_durationLabel(res.disputeWindowHours)}'));
    }
    if (r.evidence.acceptedTypes.isNotEmpty) {
      final types = r.evidence.acceptedTypes
          .map((t) => t.replaceAll('_', ' '))
          .join(', ');
      lines.add(_line(theme, brightness, '📂 Accepted evidence: $types'));
    }

    return _card(brightness, theme,
        emoji: '📋', title: 'Results & Evidence', lines: lines);
  }

  Widget? _eligibilitySection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final e = r.eligibility;
    final lines = <Widget>[];

    if (e.ageRestriction.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '🔞 Age restriction: ${e.ageRestriction.trim()}'));
    }
    if (e.rosterNotes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '📋 ${e.rosterNotes.trim()}'));
    }
    if (!e.duplicateTeamsAllowed) {
      lines.add(_line(theme, brightness, '🚫 Duplicate teams are not allowed.'));
    }
    if (e.registrationDeadline.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '📅 Registration deadline: ${e.registrationDeadline.trim()}'));
    }
    if (e.notes.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, e.notes.trim()));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🧑\u200d🤝\u200d🧑', title: 'Eligibility', lines: lines);
  }

  Widget? _fairPlaySection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final f = r.fairPlay;
    final lines = <Widget>[];

    for (final key in f.enabledStandardRuleKeys) {
      final label = _fairPlayLabels[key];
      if (label != null) lines.add(_line(theme, brightness, '✔️ $label'));
    }
    for (final custom in f.customRules) {
      lines.add(_line(theme, brightness, '• $custom'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '🤝', title: 'Fair Play & Conduct', lines: lines);
  }

  Widget? _disputesSection(
      ThemeData theme, Brightness brightness, CompetitionRules r) {
    final d = r.disputes;
    final lines = <Widget>[];

    if (d.disputeWindowHours > 0) {
      lines.add(_line(theme, brightness,
          '⏳ Dispute window: ${_durationLabel(d.disputeWindowHours)}'));
    }
    if (d.whoCanSubmit.trim().isNotEmpty) {
      lines.add(_line(theme, brightness, '🙋 Who can dispute: ${d.whoCanSubmit.trim()}'));
    }
    if (d.evidenceRequired) {
      lines.add(_line(theme, brightness, '📸 Evidence required for disputes.'));
    }
    if (d.finalDecisionAuthority.trim().isNotEmpty) {
      lines.add(_line(theme, brightness,
          '⚖️ Final decision: ${d.finalDecisionAuthority.trim()}'));
    }

    if (lines.isEmpty) return null;
    return _card(brightness, theme,
        emoji: '📢', title: 'Disputes & Appeals', lines: lines);
  }
}
