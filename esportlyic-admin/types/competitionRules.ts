// types/competitionRules.ts
//
// Mirrors competition_rules.dart's toMap()/fromMap() keys exactly —
// field names here must match the Dart model byte-for-byte since both
// sides read/write the same Firestore document.

export type CompetitionType = 'online' | 'physical' | 'hybrid';
export type SchedulingMethod = 'organizerScheduled' | 'participantAgreed' | 'fixedWindow';
export type ResultSubmissionMode = 'bothConfirm' | 'eitherSubmits' | 'organizerOnly';

export interface SchedulingRules {
  method: SchedulingMethod;
  matchDeadlineHours: number;
  allowRescheduling: boolean;
  deadlineExtensionAllowed: boolean;
  timezone: string;
  venue: string;
  notes: string;
}

export interface MatchSettingsRules {
  matchDurationMinutes: number;
  legs: number;
  extraTimeEnabled: boolean;
  penaltiesEnabled: boolean;
  condition: string;
  substitutions: number;
  notes: string;
}

export interface GameplayRules {
  allowed: string[];
  prohibited: string[];
  customRules: string[];
}

export interface ConnectionRules {
  enabled: boolean;
  reconnectWindowMinutes: number;
  replayAllowed: boolean;
  evidenceRequired: boolean;
  decidedBy: string;
  repeatedDisconnectionConsequence: string;
}

export interface NoShowRules {
  waitingPeriodMinutes: number;
  warningBeforeForfeit: boolean;
  autoForfeit: boolean;
  forfeitScore: string;
  missedMatchesAllowed: number;
  disqualificationThreshold: number;
}

export interface ResultSubmissionRules {
  mode: ResultSubmissionMode;
  screenshotRequired: boolean;
  videoRequired: boolean;
  submissionDeadlineHours: number;
  disputeWindowHours: number;
  autoConfirmIfNoDispute: boolean;
}

export interface EvidenceRules {
  acceptedTypes: string[];
}

export interface EligibilityRules {
  ageRestriction: string;
  rosterNotes: string;
  duplicateTeamsAllowed: boolean;
  registrationDeadline: string;
  notes: string;
}

export interface FairPlayRules {
  enabledStandardRuleKeys: string[];
  customRules: string[];
}

export interface DisputeRules {
  disputeWindowHours: number;
  whoCanSubmit: string;
  evidenceRequired: boolean;
  finalDecisionAuthority: string;
}

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
