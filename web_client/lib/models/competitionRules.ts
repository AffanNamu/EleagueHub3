// lib/models/competitionRules.ts
//
// Mirrors lib/features/leagues/models/competition_rules.dart — the
// Competition Rules & Configuration model. Kept SEPARATE from the
// Organizer Discipline system (disciplineActions):
//
//   Competition Rules = what participants must follow.
//   Discipline        = what organizers/admins can do when rules are broken.
//
// Storage: leagues/{leagueId}/competitionRules/current (live/published),
// leagues/{leagueId}/competitionRules/v{n} (archived, only once locked).
// A missing 'current' doc means "no rules configured yet" — not an error.

export type CompetitionType = 'online' | 'physical' | 'hybrid';

export const competitionTypeDisplayName: Record<CompetitionType, string> = {
  online: 'Online Esports',
  physical: 'Local / Physical Football',
  hybrid: 'Hybrid',
};

export function competitionTypeFromStorage(raw: string | undefined | null): CompetitionType {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'physical': return 'physical';
    case 'hybrid': return 'hybrid';
    default: return 'online';
  }
}

export type SchedulingMethod = 'organizerScheduled' | 'participantAgreed' | 'fixedWindow';

export const schedulingMethodDisplayName: Record<SchedulingMethod, string> = {
  organizerScheduled: 'Organizer schedules matches',
  participantAgreed: 'Participants agree on a time',
  fixedWindow: 'Fixed match deadline window',
};

export function schedulingMethodFromStorage(raw: string | undefined | null): SchedulingMethod {
  switch ((raw ?? '').trim()) {
    case 'participantAgreed': return 'participantAgreed';
    case 'fixedWindow': return 'fixedWindow';
    default: return 'organizerScheduled';
  }
}

export type ResultSubmissionMode = 'bothConfirm' | 'eitherSubmits' | 'organizerOnly';

export const resultSubmissionModeDisplayName: Record<ResultSubmissionMode, string> = {
  bothConfirm: 'Both participants must confirm',
  eitherSubmits: 'Either participant submits',
  organizerOnly: 'Organizer/admin only',
};

export function resultSubmissionModeFromStorage(raw: string | undefined | null): ResultSubmissionMode {
  switch ((raw ?? '').trim()) {
    case 'eitherSubmits': return 'eitherSubmits';
    case 'organizerOnly': return 'organizerOnly';
    default: return 'bothConfirm';
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

function s(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function i(v: unknown, fallback = 0): number {
  if (v === null || v === undefined) return fallback;
  if (typeof v === 'number') return Math.trunc(v);
  if (typeof v === 'string') {
    const parsed = parseInt(v.trim(), 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

function b(v: unknown, fallback = false): boolean {
  if (v === null || v === undefined) return fallback;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v === 1;
  if (typeof v === 'string') {
    const t = v.trim().toLowerCase();
    if (t === 'true' || t === '1' || t === 'yes') return true;
    if (t === 'false' || t === '0' || t === 'no') return false;
  }
  return fallback;
}

function list(v: unknown): string[] {
  if (Array.isArray(v)) {
    return v.map((e) => (e === null || e === undefined ? '' : String(e))).filter((e) => e.length > 0);
  }
  return [];
}

// ── 1. Match Scheduling ──────────────────────────────────────────────────

export interface SchedulingRules {
  method: SchedulingMethod;
  matchDeadlineHours: number;
  allowRescheduling: boolean;
  deadlineExtensionAllowed: boolean;
  timezone: string;
  venue: string;
  notes: string;
}

export function defaultSchedulingRules(): SchedulingRules {
  return {
    method: 'organizerScheduled',
    matchDeadlineHours: 0,
    allowRescheduling: true,
    deadlineExtensionAllowed: false,
    timezone: '',
    venue: '',
    notes: '',
  };
}

export function schedulingRulesDefaultsFor(type: CompetitionType): SchedulingRules {
  if (type === 'online') {
    return { ...defaultSchedulingRules(), method: 'fixedWindow', matchDeadlineHours: 24, allowRescheduling: false };
  }
  return { ...defaultSchedulingRules(), method: 'organizerScheduled', matchDeadlineHours: 0, allowRescheduling: true };
}

function schedulingRulesFromMap(m: Record<string, unknown> | undefined | null): SchedulingRules {
  const d = m ?? {};
  return {
    method: schedulingMethodFromStorage(s(d.method)),
    matchDeadlineHours: i(d.matchDeadlineHours),
    allowRescheduling: b(d.allowRescheduling, true),
    deadlineExtensionAllowed: b(d.deadlineExtensionAllowed),
    timezone: s(d.timezone),
    venue: s(d.venue),
    notes: s(d.notes),
  };
}

// ── 2. Match Settings ────────────────────────────────────────────────────

export interface MatchSettingsRules {
  matchDurationMinutes: number;
  legs: number;
  extraTimeEnabled: boolean;
  penaltiesEnabled: boolean;
  condition: string;
  substitutions: number; // -1 = unlimited, 0 = disabled
  notes: string;
}

export function defaultMatchSettingsRules(): MatchSettingsRules {
  return {
    matchDurationMinutes: 0,
    legs: 1,
    extraTimeEnabled: false,
    penaltiesEnabled: false,
    condition: '',
    substitutions: -1,
    notes: '',
  };
}

function matchSettingsRulesFromMap(m: Record<string, unknown> | undefined | null): MatchSettingsRules {
  const d = m ?? {};
  return {
    matchDurationMinutes: i(d.matchDurationMinutes),
    legs: i(d.legs, 1),
    extraTimeEnabled: b(d.extraTimeEnabled),
    penaltiesEnabled: b(d.penaltiesEnabled),
    condition: s(d.condition),
    substitutions: i(d.substitutions, -1),
    notes: s(d.notes),
  };
}

// ── 3. Gameplay Rules ────────────────────────────────────────────────────

export interface GameplayRules {
  allowed: string[];
  prohibited: string[];
  customRules: string[];
}

export function defaultGameplayRules(): GameplayRules {
  return { allowed: [], prohibited: [], customRules: [] };
}

function gameplayRulesFromMap(m: Record<string, unknown> | undefined | null): GameplayRules {
  const d = m ?? {};
  return { allowed: list(d.allowed), prohibited: list(d.prohibited), customRules: list(d.customRules) };
}

// ── 4. Connection & Disconnection Rules ─────────────────────────────────

export interface ConnectionRules {
  enabled: boolean;
  reconnectWindowMinutes: number;
  replayAllowed: boolean;
  evidenceRequired: boolean;
  decidedBy: string;
  repeatedDisconnectionConsequence: string;
}

export function defaultConnectionRules(): ConnectionRules {
  return {
    enabled: false,
    reconnectWindowMinutes: 0,
    replayAllowed: false,
    evidenceRequired: false,
    decidedBy: '',
    repeatedDisconnectionConsequence: '',
  };
}

export function connectionRulesDefaultsFor(type: CompetitionType): ConnectionRules {
  if (type === 'online') {
    return {
      ...defaultConnectionRules(),
      enabled: true,
      reconnectWindowMinutes: 5,
      replayAllowed: true,
      evidenceRequired: true,
      decidedBy: 'Organizer',
    };
  }
  return { ...defaultConnectionRules(), enabled: false };
}

function connectionRulesFromMap(m: Record<string, unknown> | undefined | null): ConnectionRules {
  const d = m ?? {};
  return {
    enabled: b(d.enabled),
    reconnectWindowMinutes: i(d.reconnectWindowMinutes),
    replayAllowed: b(d.replayAllowed),
    evidenceRequired: b(d.evidenceRequired),
    decidedBy: s(d.decidedBy),
    repeatedDisconnectionConsequence: s(d.repeatedDisconnectionConsequence),
  };
}

// ── 5. No-Show & Forfeit Rules ──────────────────────────────────────────

export interface NoShowRules {
  waitingPeriodMinutes: number;
  warningBeforeForfeit: boolean;
  autoForfeit: boolean;
  forfeitScore: string;
  missedMatchesAllowed: number;
  disqualificationThreshold: number;
}

export function defaultNoShowRules(): NoShowRules {
  return {
    waitingPeriodMinutes: 0,
    warningBeforeForfeit: true,
    autoForfeit: false,
    forfeitScore: '',
    missedMatchesAllowed: 0,
    disqualificationThreshold: 0,
  };
}

function noShowRulesFromMap(m: Record<string, unknown> | undefined | null): NoShowRules {
  const d = m ?? {};
  return {
    waitingPeriodMinutes: i(d.waitingPeriodMinutes),
    warningBeforeForfeit: b(d.warningBeforeForfeit, true),
    autoForfeit: b(d.autoForfeit),
    forfeitScore: s(d.forfeitScore),
    missedMatchesAllowed: i(d.missedMatchesAllowed),
    disqualificationThreshold: i(d.disqualificationThreshold),
  };
}

// ── 6. Result Submission ─────────────────────────────────────────────────

export interface ResultSubmissionRules {
  mode: ResultSubmissionMode;
  screenshotRequired: boolean;
  videoRequired: boolean;
  submissionDeadlineHours: number;
  disputeWindowHours: number;
  autoConfirmIfNoDispute: boolean;
}

export function defaultResultSubmissionRules(): ResultSubmissionRules {
  return {
    mode: 'bothConfirm',
    screenshotRequired: false,
    videoRequired: false,
    submissionDeadlineHours: 0,
    disputeWindowHours: 0,
    autoConfirmIfNoDispute: false,
  };
}

function resultSubmissionRulesFromMap(m: Record<string, unknown> | undefined | null): ResultSubmissionRules {
  const d = m ?? {};
  return {
    mode: resultSubmissionModeFromStorage(s(d.mode)),
    screenshotRequired: b(d.screenshotRequired),
    videoRequired: b(d.videoRequired),
    submissionDeadlineHours: i(d.submissionDeadlineHours),
    disputeWindowHours: i(d.disputeWindowHours),
    autoConfirmIfNoDispute: b(d.autoConfirmIfNoDispute),
  };
}

// ── 7. Evidence ──────────────────────────────────────────────────────────

export interface EvidenceRules {
  acceptedTypes: string[];
}

export function defaultEvidenceRules(): EvidenceRules {
  return { acceptedTypes: [] };
}

function evidenceRulesFromMap(m: Record<string, unknown> | undefined | null): EvidenceRules {
  const d = m ?? {};
  return { acceptedTypes: list(d.acceptedTypes) };
}

// ── 8. Participant & Team Eligibility ────────────────────────────────────

export interface EligibilityRules {
  ageRestriction: string;
  rosterNotes: string;
  duplicateTeamsAllowed: boolean;
  registrationDeadline: string;
  notes: string;
}

export function defaultEligibilityRules(): EligibilityRules {
  return { ageRestriction: '', rosterNotes: '', duplicateTeamsAllowed: false, registrationDeadline: '', notes: '' };
}

function eligibilityRulesFromMap(m: Record<string, unknown> | undefined | null): EligibilityRules {
  const d = m ?? {};
  return {
    ageRestriction: s(d.ageRestriction),
    rosterNotes: s(d.rosterNotes),
    duplicateTeamsAllowed: b(d.duplicateTeamsAllowed),
    registrationDeadline: s(d.registrationDeadline),
    notes: s(d.notes),
  };
}

// ── 9. Fair Play & Conduct ───────────────────────────────────────────────

export const STANDARD_FAIR_PLAY_RULE_KEYS = [
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
] as const;

export const FAIR_PLAY_RULE_LABELS: Record<string, string> = {
  fair_play_respect: 'Fair play & respect are mandatory',
  no_harassment: 'No harassment',
  no_abusive_language: 'No abusive language',
  no_discrimination: 'No discrimination',
  no_cheating: 'No cheating',
  no_match_fixing: 'No match fixing',
  no_collusion: 'No collusion',
  no_impersonation: 'No impersonation',
  no_account_sharing: 'No account sharing',
  no_deliberate_exploitation: 'No deliberate exploitation of glitches',
};

export interface FairPlayRules {
  enabledStandardRuleKeys: string[];
  customRules: string[];
}

export function defaultFairPlayRules(): FairPlayRules {
  return { enabledStandardRuleKeys: [...STANDARD_FAIR_PLAY_RULE_KEYS], customRules: [] };
}

function fairPlayRulesFromMap(m: Record<string, unknown> | undefined | null): FairPlayRules {
  const d = m ?? {};
  if (!('enabledStandardRuleKeys' in d)) {
    return { enabledStandardRuleKeys: [], customRules: list(d.customRules) };
  }
  return { enabledStandardRuleKeys: list(d.enabledStandardRuleKeys), customRules: list(d.customRules) };
}

// ── 12. Disputes & Appeals ───────────────────────────────────────────────
// (Section 11, Discipline & Penalties, is intentionally NOT modeled here —
// it stays owned by the Organizer Discipline system.)

export interface DisputeRules {
  disputeWindowHours: number;
  whoCanSubmit: string;
  evidenceRequired: boolean;
  finalDecisionAuthority: string;
}

export function defaultDisputeRules(): DisputeRules {
  return { disputeWindowHours: 0, whoCanSubmit: '', evidenceRequired: false, finalDecisionAuthority: '' };
}

function disputeRulesFromMap(m: Record<string, unknown> | undefined | null): DisputeRules {
  const d = m ?? {};
  return {
    disputeWindowHours: i(d.disputeWindowHours),
    whoCanSubmit: s(d.whoCanSubmit),
    evidenceRequired: b(d.evidenceRequired),
    finalDecisionAuthority: s(d.finalDecisionAuthority),
  };
}

// ── Top-level Competition Rules document ────────────────────────────────

export interface CompetitionRules {
  leagueId: string;
  version: number;
  locked: boolean;
  competitionType: CompetitionType;
  scheduling: SchedulingRules;
  matchSettings: MatchSettingsRules;
  gameplay: GameplayRules;
  connection: ConnectionRules;
  noShow: NoShowRules;
  resultSubmission: ResultSubmissionRules;
  evidence: EvidenceRules;
  eligibility: EligibilityRules;
  fairPlay: FairPlayRules;
  disputes: DisputeRules;
  updatedAtMs: number;
  updatedBy: string;
  updatedByName: string;
}

export function defaultCompetitionRules(leagueId: string): CompetitionRules {
  return {
    leagueId,
    version: 1,
    locked: false,
    competitionType: 'online',
    scheduling: defaultSchedulingRules(),
    matchSettings: defaultMatchSettingsRules(),
    gameplay: defaultGameplayRules(),
    connection: defaultConnectionRules(),
    noShow: defaultNoShowRules(),
    resultSubmission: defaultResultSubmissionRules(),
    evidence: defaultEvidenceRules(),
    eligibility: defaultEligibilityRules(),
    fairPlay: defaultFairPlayRules(),
    disputes: defaultDisputeRules(),
    updatedAtMs: 0,
    updatedBy: '',
    updatedByName: '',
  };
}

/** A sensible starting point seeded from a competition type — organizers customize freely from here. */
export function competitionRulesDefaultsFor(leagueId: string, competitionType: CompetitionType): CompetitionRules {
  return {
    ...defaultCompetitionRules(leagueId),
    competitionType,
    scheduling: schedulingRulesDefaultsFor(competitionType),
    connection: connectionRulesDefaultsFor(competitionType),
    resultSubmission: { ...defaultResultSubmissionRules(), screenshotRequired: competitionType === 'online' },
    evidence: { acceptedTypes: competitionType === 'online' ? ['screenshot', 'video'] : [] },
  };
}

export function competitionRulesToMap(r: CompetitionRules): Record<string, unknown> {
  return {
    leagueId: r.leagueId,
    version: r.version,
    locked: r.locked,
    competitionType: r.competitionType,
    scheduling: { ...r.scheduling },
    matchSettings: { ...r.matchSettings },
    gameplay: { ...r.gameplay },
    connection: { ...r.connection },
    noShow: { ...r.noShow },
    resultSubmission: { ...r.resultSubmission },
    evidence: { ...r.evidence },
    eligibility: { ...r.eligibility },
    fairPlay: { ...r.fairPlay },
    disputes: { ...r.disputes },
    updatedAtMs: r.updatedAtMs,
    updatedBy: r.updatedBy,
    updatedByName: r.updatedByName,
  };
}

export function competitionRulesFromMap(map: Record<string, unknown>, fallbackLeagueId: string): CompetitionRules {
  const leagueId = s(map.leagueId).trim().length > 0 ? s(map.leagueId) : fallbackLeagueId;
  return {
    leagueId,
    version: i(map.version, 1),
    locked: b(map.locked),
    competitionType: competitionTypeFromStorage(s(map.competitionType)),
    scheduling: schedulingRulesFromMap(map.scheduling as Record<string, unknown>),
    matchSettings: matchSettingsRulesFromMap(map.matchSettings as Record<string, unknown>),
    gameplay: gameplayRulesFromMap(map.gameplay as Record<string, unknown>),
    connection: connectionRulesFromMap(map.connection as Record<string, unknown>),
    noShow: noShowRulesFromMap(map.noShow as Record<string, unknown>),
    resultSubmission: resultSubmissionRulesFromMap(map.resultSubmission as Record<string, unknown>),
    evidence: evidenceRulesFromMap(map.evidence as Record<string, unknown>),
    eligibility: eligibilityRulesFromMap(map.eligibility as Record<string, unknown>),
    fairPlay: fairPlayRulesFromMap(map.fairPlay as Record<string, unknown>),
    disputes: disputeRulesFromMap(map.disputes as Record<string, unknown>),
    updatedAtMs: i(map.updatedAtMs),
    updatedBy: s(map.updatedBy),
    updatedByName: s(map.updatedByName),
  };
}
