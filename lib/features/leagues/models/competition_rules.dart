// lib/features/leagues/models/competition_rules.dart
//
// NEW FILE — Competition Rules & Configuration system.
//
// This is the canonical, structured "rules" model for a single League
// (competition). It is intentionally kept SEPARATE from the existing
// Organizer Discipline system (`disciplineActions`):
//
//   Competition Rules = what participants must follow.
//   Discipline        = what organizers/admins can do when rules are broken.
//
// This model must work for both:
//   - Online esports competitions (e.g. eFootball, short deadlines)
//   - Local/physical football competitions (dates/weeks apart, venues)
//
// so nothing here assumes a 24-hour deadline or any other single shape —
// every section is optional/organizer-configured, with sensible defaults.
//
// Storage: Firestore, at
//   leagues/{leagueId}/competitionRules/current   (live/published doc)
//   leagues/{leagueId}/competitionRules/v{n}      (archived versions, only
//                                                   created once a version
//                                                   has been locked)
//
// Backward compatibility: if no document exists at `competitionRules/current`
// for a league, that means "no rules configured yet" — NOT an error and NOT
// a blank/broken competition. Callers should treat a null [CompetitionRules]
// as "skip the rules gate, nothing to show".

import 'dart:convert';

/// Broad competition type. Drives which sections are relevant/shown in the
/// organizer editor and the participant-facing rules screen.
enum CompetitionType { online, physical, hybrid }

extension CompetitionTypeX on CompetitionType {
  String get storageValue => name;

  String get displayName {
    switch (this) {
      case CompetitionType.online:
        return 'Online Esports';
      case CompetitionType.physical:
        return 'Local / Physical Football';
      case CompetitionType.hybrid:
        return 'Hybrid';
    }
  }

  static CompetitionType fromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'physical':
        return CompetitionType.physical;
      case 'hybrid':
        return CompetitionType.hybrid;
      case 'online':
      default:
        return CompetitionType.online;
    }
  }
}

/// How matches get scheduled for this competition.
enum SchedulingMethod {
  /// Organizer sets exact date/time for every match (typical local football).
  organizerScheduled,

  /// Participants agree on a time between themselves, within a window.
  participantAgreed,

  /// A fixed match-deadline window from when the fixture is created
  /// (typical online esports, e.g. "24 hours").
  fixedWindow,
}

extension SchedulingMethodX on SchedulingMethod {
  String get storageValue => name;

  String get displayName {
    switch (this) {
      case SchedulingMethod.organizerScheduled:
        return 'Organizer schedules matches';
      case SchedulingMethod.participantAgreed:
        return 'Participants agree on a time';
      case SchedulingMethod.fixedWindow:
        return 'Fixed match deadline window';
    }
  }

  static SchedulingMethod fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'participantAgreed':
        return SchedulingMethod.participantAgreed;
      case 'fixedWindow':
        return SchedulingMethod.fixedWindow;
      case 'organizerScheduled':
      default:
        return SchedulingMethod.organizerScheduled;
    }
  }
}

/// Who is responsible for submitting a match result.
enum ResultSubmissionMode {
  /// Both participants must submit/confirm before it counts.
  bothConfirm,

  /// Either participant may submit; the other has a window to dispute.
  eitherSubmits,

  /// Only the organizer/admin records results.
  organizerOnly,
}

extension ResultSubmissionModeX on ResultSubmissionMode {
  String get storageValue => name;

  String get displayName {
    switch (this) {
      case ResultSubmissionMode.bothConfirm:
        return 'Both participants must confirm';
      case ResultSubmissionMode.eitherSubmits:
        return 'Either participant submits';
      case ResultSubmissionMode.organizerOnly:
        return 'Organizer/admin only';
    }
  }

  static ResultSubmissionMode fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'eitherSubmits':
        return ResultSubmissionMode.eitherSubmits;
      case 'organizerOnly':
        return ResultSubmissionMode.organizerOnly;
      case 'bothConfirm':
      default:
        return ResultSubmissionMode.bothConfirm;
    }
  }
}

// ── Helpers (mirrors patterns already used in League/LeagueSettings) ───────

String _s(dynamic v) => (v is String) ? v : '';

int _i(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

bool _b(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v.toInt() == 1;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return fallback;
}

List<String> _list(dynamic v) {
  if (v is List) {
    return v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

// ── 1. Match Scheduling ──────────────────────────────────────────────────

class SchedulingRules {
  final SchedulingMethod method;

  /// Only meaningful when [method] == fixedWindow. 0 = not set.
  final int matchDeadlineHours;

  final bool allowRescheduling;
  final bool deadlineExtensionAllowed;
  final String timezone;

  /// Only relevant for physical competitions.
  final String venue;

  final String notes;

  const SchedulingRules({
    this.method = SchedulingMethod.organizerScheduled,
    this.matchDeadlineHours = 0,
    this.allowRescheduling = true,
    this.deadlineExtensionAllowed = false,
    this.timezone = '',
    this.venue = '',
    this.notes = '',
  });

  factory SchedulingRules.defaultsFor(CompetitionType type) {
    if (type == CompetitionType.online) {
      return const SchedulingRules(
        method: SchedulingMethod.fixedWindow,
        matchDeadlineHours: 24,
        allowRescheduling: false,
      );
    }
    return const SchedulingRules(
      method: SchedulingMethod.organizerScheduled,
      matchDeadlineHours: 0,
      allowRescheduling: true,
    );
  }

  Map<String, dynamic> toMap() => {
        'method': method.storageValue,
        'matchDeadlineHours': matchDeadlineHours,
        'allowRescheduling': allowRescheduling,
        'deadlineExtensionAllowed': deadlineExtensionAllowed,
        'timezone': timezone,
        'venue': venue,
        'notes': notes,
      };

  factory SchedulingRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return SchedulingRules(
      method: SchedulingMethodX.fromStorage(_s(m['method'])),
      matchDeadlineHours: _i(m['matchDeadlineHours']),
      allowRescheduling: _b(m['allowRescheduling'], fallback: true),
      deadlineExtensionAllowed: _b(m['deadlineExtensionAllowed']),
      timezone: _s(m['timezone']),
      venue: _s(m['venue']),
      notes: _s(m['notes']),
    );
  }

  SchedulingRules copyWith({
    SchedulingMethod? method,
    int? matchDeadlineHours,
    bool? allowRescheduling,
    bool? deadlineExtensionAllowed,
    String? timezone,
    String? venue,
    String? notes,
  }) {
    return SchedulingRules(
      method: method ?? this.method,
      matchDeadlineHours: matchDeadlineHours ?? this.matchDeadlineHours,
      allowRescheduling: allowRescheduling ?? this.allowRescheduling,
      deadlineExtensionAllowed:
          deadlineExtensionAllowed ?? this.deadlineExtensionAllowed,
      timezone: timezone ?? this.timezone,
      venue: venue ?? this.venue,
      notes: notes ?? this.notes,
    );
  }
}

// ── 2. Match Settings ────────────────────────────────────────────────────

class MatchSettingsRules {
  final int matchDurationMinutes; // 0 = not applicable/not set
  final int legs; // 1 = single match, 2 = home & away
  final bool extraTimeEnabled;
  final bool penaltiesEnabled;
  final String condition; // free text, e.g. "Excellent", "Any"
  final int substitutions; // -1 = unlimited, 0 = disabled
  final String notes;

  const MatchSettingsRules({
    this.matchDurationMinutes = 0,
    this.legs = 1,
    this.extraTimeEnabled = false,
    this.penaltiesEnabled = false,
    this.condition = '',
    this.substitutions = -1,
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        'matchDurationMinutes': matchDurationMinutes,
        'legs': legs,
        'extraTimeEnabled': extraTimeEnabled,
        'penaltiesEnabled': penaltiesEnabled,
        'condition': condition,
        'substitutions': substitutions,
        'notes': notes,
      };

  factory MatchSettingsRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return MatchSettingsRules(
      matchDurationMinutes: _i(m['matchDurationMinutes']),
      legs: _i(m['legs'], fallback: 1),
      extraTimeEnabled: _b(m['extraTimeEnabled']),
      penaltiesEnabled: _b(m['penaltiesEnabled']),
      condition: _s(m['condition']),
      substitutions: _i(m['substitutions'], fallback: -1),
      notes: _s(m['notes']),
    );
  }

  MatchSettingsRules copyWith({
    int? matchDurationMinutes,
    int? legs,
    bool? extraTimeEnabled,
    bool? penaltiesEnabled,
    String? condition,
    int? substitutions,
    String? notes,
  }) {
    return MatchSettingsRules(
      matchDurationMinutes: matchDurationMinutes ?? this.matchDurationMinutes,
      legs: legs ?? this.legs,
      extraTimeEnabled: extraTimeEnabled ?? this.extraTimeEnabled,
      penaltiesEnabled: penaltiesEnabled ?? this.penaltiesEnabled,
      condition: condition ?? this.condition,
      substitutions: substitutions ?? this.substitutions,
      notes: notes ?? this.notes,
    );
  }
}

// ── 3. Gameplay Rules ────────────────────────────────────────────────────

class GameplayRules {
  final List<String> allowed;
  final List<String> prohibited;
  final List<String> customRules;

  const GameplayRules({
    this.allowed = const [],
    this.prohibited = const [],
    this.customRules = const [],
  });

  Map<String, dynamic> toMap() => {
        'allowed': allowed,
        'prohibited': prohibited,
        'customRules': customRules,
      };

  factory GameplayRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return GameplayRules(
      allowed: _list(m['allowed']),
      prohibited: _list(m['prohibited']),
      customRules: _list(m['customRules']),
    );
  }

  GameplayRules copyWith({
    List<String>? allowed,
    List<String>? prohibited,
    List<String>? customRules,
  }) {
    return GameplayRules(
      allowed: allowed ?? this.allowed,
      prohibited: prohibited ?? this.prohibited,
      customRules: customRules ?? this.customRules,
    );
  }
}

// ── 4. Connection & Disconnection Rules (online only, in practice) ─────────

class ConnectionRules {
  final bool enabled;
  final int reconnectWindowMinutes;
  final bool replayAllowed;
  final bool evidenceRequired;
  final String decidedBy; // free text, e.g. "Organizer", "Admin on duty"
  final String repeatedDisconnectionConsequence;

  const ConnectionRules({
    this.enabled = false,
    this.reconnectWindowMinutes = 0,
    this.replayAllowed = false,
    this.evidenceRequired = false,
    this.decidedBy = '',
    this.repeatedDisconnectionConsequence = '',
  });

  factory ConnectionRules.defaultsFor(CompetitionType type) {
    if (type == CompetitionType.online) {
      return const ConnectionRules(
        enabled: true,
        reconnectWindowMinutes: 5,
        replayAllowed: true,
        evidenceRequired: true,
        decidedBy: 'Organizer',
      );
    }
    return const ConnectionRules(enabled: false);
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'reconnectWindowMinutes': reconnectWindowMinutes,
        'replayAllowed': replayAllowed,
        'evidenceRequired': evidenceRequired,
        'decidedBy': decidedBy,
        'repeatedDisconnectionConsequence': repeatedDisconnectionConsequence,
      };

  factory ConnectionRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return ConnectionRules(
      enabled: _b(m['enabled']),
      reconnectWindowMinutes: _i(m['reconnectWindowMinutes']),
      replayAllowed: _b(m['replayAllowed']),
      evidenceRequired: _b(m['evidenceRequired']),
      decidedBy: _s(m['decidedBy']),
      repeatedDisconnectionConsequence:
          _s(m['repeatedDisconnectionConsequence']),
    );
  }

  ConnectionRules copyWith({
    bool? enabled,
    int? reconnectWindowMinutes,
    bool? replayAllowed,
    bool? evidenceRequired,
    String? decidedBy,
    String? repeatedDisconnectionConsequence,
  }) {
    return ConnectionRules(
      enabled: enabled ?? this.enabled,
      reconnectWindowMinutes:
          reconnectWindowMinutes ?? this.reconnectWindowMinutes,
      replayAllowed: replayAllowed ?? this.replayAllowed,
      evidenceRequired: evidenceRequired ?? this.evidenceRequired,
      decidedBy: decidedBy ?? this.decidedBy,
      repeatedDisconnectionConsequence: repeatedDisconnectionConsequence ??
          this.repeatedDisconnectionConsequence,
    );
  }
}

// ── 5. No-Show & Forfeit Rules ──────────────────────────────────────────

class NoShowRules {
  final int waitingPeriodMinutes; // for online: minutes past deadline/start
  final bool warningBeforeForfeit;
  final bool autoForfeit;
  final String forfeitScore; // free text, e.g. "3-0"
  final int missedMatchesAllowed;
  final int disqualificationThreshold; // 0 = not set

  const NoShowRules({
    this.waitingPeriodMinutes = 0,
    this.warningBeforeForfeit = true,
    this.autoForfeit = false,
    this.forfeitScore = '',
    this.missedMatchesAllowed = 0,
    this.disqualificationThreshold = 0,
  });

  Map<String, dynamic> toMap() => {
        'waitingPeriodMinutes': waitingPeriodMinutes,
        'warningBeforeForfeit': warningBeforeForfeit,
        'autoForfeit': autoForfeit,
        'forfeitScore': forfeitScore,
        'missedMatchesAllowed': missedMatchesAllowed,
        'disqualificationThreshold': disqualificationThreshold,
      };

  factory NoShowRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return NoShowRules(
      waitingPeriodMinutes: _i(m['waitingPeriodMinutes']),
      warningBeforeForfeit: _b(m['warningBeforeForfeit'], fallback: true),
      autoForfeit: _b(m['autoForfeit']),
      forfeitScore: _s(m['forfeitScore']),
      missedMatchesAllowed: _i(m['missedMatchesAllowed']),
      disqualificationThreshold: _i(m['disqualificationThreshold']),
    );
  }

  NoShowRules copyWith({
    int? waitingPeriodMinutes,
    bool? warningBeforeForfeit,
    bool? autoForfeit,
    String? forfeitScore,
    int? missedMatchesAllowed,
    int? disqualificationThreshold,
  }) {
    return NoShowRules(
      waitingPeriodMinutes: waitingPeriodMinutes ?? this.waitingPeriodMinutes,
      warningBeforeForfeit: warningBeforeForfeit ?? this.warningBeforeForfeit,
      autoForfeit: autoForfeit ?? this.autoForfeit,
      forfeitScore: forfeitScore ?? this.forfeitScore,
      missedMatchesAllowed: missedMatchesAllowed ?? this.missedMatchesAllowed,
      disqualificationThreshold:
          disqualificationThreshold ?? this.disqualificationThreshold,
    );
  }
}

// ── 6. Result Submission ─────────────────────────────────────────────────

class ResultSubmissionRules {
  final ResultSubmissionMode mode;
  final bool screenshotRequired;
  final bool videoRequired;
  final int submissionDeadlineHours; // 0 = not set
  final int disputeWindowHours; // 0 = not set
  final bool autoConfirmIfNoDispute;

  const ResultSubmissionRules({
    this.mode = ResultSubmissionMode.bothConfirm,
    this.screenshotRequired = false,
    this.videoRequired = false,
    this.submissionDeadlineHours = 0,
    this.disputeWindowHours = 0,
    this.autoConfirmIfNoDispute = false,
  });

  Map<String, dynamic> toMap() => {
        'mode': mode.storageValue,
        'screenshotRequired': screenshotRequired,
        'videoRequired': videoRequired,
        'submissionDeadlineHours': submissionDeadlineHours,
        'disputeWindowHours': disputeWindowHours,
        'autoConfirmIfNoDispute': autoConfirmIfNoDispute,
      };

  factory ResultSubmissionRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return ResultSubmissionRules(
      mode: ResultSubmissionModeX.fromStorage(_s(m['mode'])),
      screenshotRequired: _b(m['screenshotRequired']),
      videoRequired: _b(m['videoRequired']),
      submissionDeadlineHours: _i(m['submissionDeadlineHours']),
      disputeWindowHours: _i(m['disputeWindowHours']),
      autoConfirmIfNoDispute: _b(m['autoConfirmIfNoDispute']),
    );
  }

  ResultSubmissionRules copyWith({
    ResultSubmissionMode? mode,
    bool? screenshotRequired,
    bool? videoRequired,
    int? submissionDeadlineHours,
    int? disputeWindowHours,
    bool? autoConfirmIfNoDispute,
  }) {
    return ResultSubmissionRules(
      mode: mode ?? this.mode,
      screenshotRequired: screenshotRequired ?? this.screenshotRequired,
      videoRequired: videoRequired ?? this.videoRequired,
      submissionDeadlineHours:
          submissionDeadlineHours ?? this.submissionDeadlineHours,
      disputeWindowHours: disputeWindowHours ?? this.disputeWindowHours,
      autoConfirmIfNoDispute:
          autoConfirmIfNoDispute ?? this.autoConfirmIfNoDispute,
    );
  }
}

// ── 7. Evidence ──────────────────────────────────────────────────────────

class EvidenceRules {
  final List<String> acceptedTypes; // e.g. ["screenshot","video"]

  const EvidenceRules({this.acceptedTypes = const []});

  Map<String, dynamic> toMap() => {'acceptedTypes': acceptedTypes};

  factory EvidenceRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return EvidenceRules(acceptedTypes: _list(m['acceptedTypes']));
  }

  EvidenceRules copyWith({List<String>? acceptedTypes}) {
    return EvidenceRules(acceptedTypes: acceptedTypes ?? this.acceptedTypes);
  }
}

// ── 8. Participant & Team Eligibility ────────────────────────────────────

class EligibilityRules {
  final String ageRestriction; // free text, e.g. "16+"
  final String rosterNotes;
  final bool duplicateTeamsAllowed;
  final String registrationDeadline; // free text or ISO string, organizer set
  final String notes;

  const EligibilityRules({
    this.ageRestriction = '',
    this.rosterNotes = '',
    this.duplicateTeamsAllowed = false,
    this.registrationDeadline = '',
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        'ageRestriction': ageRestriction,
        'rosterNotes': rosterNotes,
        'duplicateTeamsAllowed': duplicateTeamsAllowed,
        'registrationDeadline': registrationDeadline,
        'notes': notes,
      };

  factory EligibilityRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return EligibilityRules(
      ageRestriction: _s(m['ageRestriction']),
      rosterNotes: _s(m['rosterNotes']),
      duplicateTeamsAllowed: _b(m['duplicateTeamsAllowed']),
      registrationDeadline: _s(m['registrationDeadline']),
      notes: _s(m['notes']),
    );
  }

  EligibilityRules copyWith({
    String? ageRestriction,
    String? rosterNotes,
    bool? duplicateTeamsAllowed,
    String? registrationDeadline,
    String? notes,
  }) {
    return EligibilityRules(
      ageRestriction: ageRestriction ?? this.ageRestriction,
      rosterNotes: rosterNotes ?? this.rosterNotes,
      duplicateTeamsAllowed:
          duplicateTeamsAllowed ?? this.duplicateTeamsAllowed,
      registrationDeadline: registrationDeadline ?? this.registrationDeadline,
      notes: notes ?? this.notes,
    );
  }
}

// ── 9. Fair Play & Conduct ───────────────────────────────────────────────

/// Fixed catalog of standard fair-play rules organizers can toggle on/off.
/// Storage value is the key; display text lives in the UI/l10n layer.
const List<String> kStandardFairPlayRuleKeys = [
  'fair_play_respect',
  'no_harassment',
  'no_abusive_language',
  'no_discrimination',
  'no_cheating',
  'no_match_fixing',
  'no_collusion',
  'no_impersonation',
  'no_account_sharing',
  'no_deliberate_exploitation',
];

class FairPlayRules {
  final List<String> enabledStandardRuleKeys;
  final List<String> customRules;

  const FairPlayRules({
    this.enabledStandardRuleKeys = kStandardFairPlayRuleKeys,
    this.customRules = const [],
  });

  Map<String, dynamic> toMap() => {
        'enabledStandardRuleKeys': enabledStandardRuleKeys,
        'customRules': customRules,
      };

  factory FairPlayRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    if (!m.containsKey('enabledStandardRuleKeys')) {
      return FairPlayRules(customRules: _list(m['customRules']));
    }
    return FairPlayRules(
      enabledStandardRuleKeys: _list(m['enabledStandardRuleKeys']),
      customRules: _list(m['customRules']),
    );
  }

  FairPlayRules copyWith({
    List<String>? enabledStandardRuleKeys,
    List<String>? customRules,
  }) {
    return FairPlayRules(
      enabledStandardRuleKeys:
          enabledStandardRuleKeys ?? this.enabledStandardRuleKeys,
      customRules: customRules ?? this.customRules,
    );
  }
}

// ── 12. Disputes & Appeals ───────────────────────────────────────────────
// (Section 11, Discipline & Penalties, is intentionally NOT modeled here —
// it stays fully owned by the existing Organizer Discipline system. Rules
// only need to be readable *alongside* discipline, not to duplicate it.)

class DisputeRules {
  final int disputeWindowHours; // 0 = not set
  final String whoCanSubmit; // free text, e.g. "Either participant"
  final bool evidenceRequired;
  final String finalDecisionAuthority; // free text, e.g. "Organizer"

  const DisputeRules({
    this.disputeWindowHours = 0,
    this.whoCanSubmit = '',
    this.evidenceRequired = false,
    this.finalDecisionAuthority = '',
  });

  Map<String, dynamic> toMap() => {
        'disputeWindowHours': disputeWindowHours,
        'whoCanSubmit': whoCanSubmit,
        'evidenceRequired': evidenceRequired,
        'finalDecisionAuthority': finalDecisionAuthority,
      };

  factory DisputeRules.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return DisputeRules(
      disputeWindowHours: _i(m['disputeWindowHours']),
      whoCanSubmit: _s(m['whoCanSubmit']),
      evidenceRequired: _b(m['evidenceRequired']),
      finalDecisionAuthority: _s(m['finalDecisionAuthority']),
    );
  }

  DisputeRules copyWith({
    int? disputeWindowHours,
    String? whoCanSubmit,
    bool? evidenceRequired,
    String? finalDecisionAuthority,
  }) {
    return DisputeRules(
      disputeWindowHours: disputeWindowHours ?? this.disputeWindowHours,
      whoCanSubmit: whoCanSubmit ?? this.whoCanSubmit,
      evidenceRequired: evidenceRequired ?? this.evidenceRequired,
      finalDecisionAuthority:
          finalDecisionAuthority ?? this.finalDecisionAuthority,
    );
  }
}

// ── Top-level Competition Rules document ────────────────────────────────

class CompetitionRules {
  final String leagueId;

  /// Bumped every time the document is saved. Used for version history once
  /// [locked] has been true at some point.
  final int version;

  /// Once true, the next edit archives the current doc under
  /// `competitionRules/v{version}` before writing the new version.
  /// Toggled explicitly by the organizer (e.g. "Publish & Lock Rules") —
  /// there is no automatic "competition started" signal in the data model
  /// today, so this is intentionally organizer-controlled rather than
  /// inferred.
  final bool locked;

  final CompetitionType competitionType;

  final SchedulingRules scheduling;
  final MatchSettingsRules matchSettings;
  final GameplayRules gameplay;
  final ConnectionRules connection;
  final NoShowRules noShow;
  final ResultSubmissionRules resultSubmission;
  final EvidenceRules evidence;
  final EligibilityRules eligibility;
  final FairPlayRules fairPlay;
  final DisputeRules disputes;

  final int updatedAtMs;
  final String updatedBy; // Firebase Auth UID
  final String updatedByName;

  const CompetitionRules({
    required this.leagueId,
    this.version = 1,
    this.locked = false,
    this.competitionType = CompetitionType.online,
    this.scheduling = const SchedulingRules(),
    this.matchSettings = const MatchSettingsRules(),
    this.gameplay = const GameplayRules(),
    this.connection = const ConnectionRules(),
    this.noShow = const NoShowRules(),
    this.resultSubmission = const ResultSubmissionRules(),
    this.evidence = const EvidenceRules(),
    this.eligibility = const EligibilityRules(),
    this.fairPlay = const FairPlayRules(),
    this.disputes = const DisputeRules(),
    this.updatedAtMs = 0,
    this.updatedBy = '',
    this.updatedByName = '',
  });

  /// A sensible starting point for a brand-new rules doc, seeded from a
  /// competition type. Organizers customize freely from here — this is a
  /// starting configuration, not a restriction (see Rule Templates).
  factory CompetitionRules.defaultsFor({
    required String leagueId,
    required CompetitionType competitionType,
  }) {
    return CompetitionRules(
      leagueId: leagueId,
      competitionType: competitionType,
      scheduling: SchedulingRules.defaultsFor(competitionType),
      connection: ConnectionRules.defaultsFor(competitionType),
      resultSubmission: ResultSubmissionRules(
        screenshotRequired: competitionType == CompetitionType.online,
      ),
      evidence: EvidenceRules(
        acceptedTypes: competitionType == CompetitionType.online
            ? const ['screenshot', 'video']
            : const [],
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'leagueId': leagueId,
        'version': version,
        'locked': locked,
        'competitionType': competitionType.storageValue,
        'scheduling': scheduling.toMap(),
        'matchSettings': matchSettings.toMap(),
        'gameplay': gameplay.toMap(),
        'connection': connection.toMap(),
        'noShow': noShow.toMap(),
        'resultSubmission': resultSubmission.toMap(),
        'evidence': evidence.toMap(),
        'eligibility': eligibility.toMap(),
        'fairPlay': fairPlay.toMap(),
        'disputes': disputes.toMap(),
        'updatedAtMs': updatedAtMs,
        'updatedBy': updatedBy,
        'updatedByName': updatedByName,
      };

  String toJson() => jsonEncode(toMap());

  factory CompetitionRules.fromMap(
    Map<String, dynamic> map, {
    required String fallbackLeagueId,
  }) {
    return CompetitionRules(
      leagueId: _s(map['leagueId']).trim().isNotEmpty
          ? _s(map['leagueId'])
          : fallbackLeagueId,
      version: _i(map['version'], fallback: 1),
      locked: _b(map['locked']),
      competitionType:
          CompetitionTypeX.fromStorage(_s(map['competitionType'])),
      scheduling: SchedulingRules.fromMap(
          (map['scheduling'] as Map?)?.cast<String, dynamic>()),
      matchSettings: MatchSettingsRules.fromMap(
          (map['matchSettings'] as Map?)?.cast<String, dynamic>()),
      gameplay: GameplayRules.fromMap(
          (map['gameplay'] as Map?)?.cast<String, dynamic>()),
      connection: ConnectionRules.fromMap(
          (map['connection'] as Map?)?.cast<String, dynamic>()),
      noShow: NoShowRules.fromMap(
          (map['noShow'] as Map?)?.cast<String, dynamic>()),
      resultSubmission: ResultSubmissionRules.fromMap(
          (map['resultSubmission'] as Map?)?.cast<String, dynamic>()),
      evidence: EvidenceRules.fromMap(
          (map['evidence'] as Map?)?.cast<String, dynamic>()),
      eligibility: EligibilityRules.fromMap(
          (map['eligibility'] as Map?)?.cast<String, dynamic>()),
      fairPlay: FairPlayRules.fromMap(
          (map['fairPlay'] as Map?)?.cast<String, dynamic>()),
      disputes: DisputeRules.fromMap(
          (map['disputes'] as Map?)?.cast<String, dynamic>()),
      updatedAtMs: _i(map['updatedAtMs']),
      updatedBy: _s(map['updatedBy']),
      updatedByName: _s(map['updatedByName']),
    );
  }

  factory CompetitionRules.fromJson(String raw, {required String leagueId}) {
    final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
    return CompetitionRules.fromMap(map, fallbackLeagueId: leagueId);
  }

  CompetitionRules copyWith({
    String? leagueId,
    int? version,
    bool? locked,
    CompetitionType? competitionType,
    SchedulingRules? scheduling,
    MatchSettingsRules? matchSettings,
    GameplayRules? gameplay,
    ConnectionRules? connection,
    NoShowRules? noShow,
    ResultSubmissionRules? resultSubmission,
    EvidenceRules? evidence,
    EligibilityRules? eligibility,
    FairPlayRules? fairPlay,
    DisputeRules? disputes,
    int? updatedAtMs,
    String? updatedBy,
    String? updatedByName,
  }) {
    return CompetitionRules(
      leagueId: leagueId ?? this.leagueId,
      version: version ?? this.version,
      locked: locked ?? this.locked,
      competitionType: competitionType ?? this.competitionType,
      scheduling: scheduling ?? this.scheduling,
      matchSettings: matchSettings ?? this.matchSettings,
      gameplay: gameplay ?? this.gameplay,
      connection: connection ?? this.connection,
      noShow: noShow ?? this.noShow,
      resultSubmission: resultSubmission ?? this.resultSubmission,
      evidence: evidence ?? this.evidence,
      eligibility: eligibility ?? this.eligibility,
      fairPlay: fairPlay ?? this.fairPlay,
      disputes: disputes ?? this.disputes,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
    );
  }
}
