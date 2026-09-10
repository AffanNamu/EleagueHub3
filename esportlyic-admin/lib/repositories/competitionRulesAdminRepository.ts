// lib/repositories/competitionRulesAdminRepository.ts
//
// Server-only reads/writes of leagues/{leagueId}/competitionRules/current,
// matching CompetitionRulesFirestorePaths and the CompetitionRules model
// exactly. Implements the locked/version-archive behavior specified in
// the model's own comments: once locked=true, the NEXT edit must first
// copy the current doc to competitionRules/v{version} before writing the
// new content — done here as a transaction so the archive and the new
// write are atomic (never archive without writing, or vice versa).
//
// A missing document is NOT an error — the model's own docs say "no
// rules configured yet" is a valid, common state, not a broken
// competition. getCompetitionRules() returns null in that case.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { CompetitionRules } from '@/types/competitionRules';

const LEAGUES_COLLECTION = 'leagues';
const RULES_SUBCOLLECTION = 'competitionRules';
const CURRENT_DOC_ID = 'current';

function historyDocId(version: number): string {
  return `v${version}`;
}

function toCompetitionRules(leagueId: string, data: FirebaseFirestore.DocumentData): CompetitionRules {
  const scheduling = data.scheduling ?? {};
  const matchSettings = data.matchSettings ?? {};
  const gameplay = data.gameplay ?? {};
  const connection = data.connection ?? {};
  const noShow = data.noShow ?? {};
  const resultSubmission = data.resultSubmission ?? {};
  const evidence = data.evidence ?? {};
  const eligibility = data.eligibility ?? {};
  const fairPlay = data.fairPlay ?? {};
  const disputes = data.disputes ?? {};

  return {
    leagueId: data.leagueId || leagueId,
    version: typeof data.version === 'number' ? data.version : 1,
    locked: data.locked === true,
    competitionType: data.competitionType ?? 'online',
    scheduling: {
      method: scheduling.method ?? 'organizerScheduled',
      matchDeadlineHours: scheduling.matchDeadlineHours ?? 0,
      allowRescheduling: scheduling.allowRescheduling !== false,
      deadlineExtensionAllowed: scheduling.deadlineExtensionAllowed === true,
      timezone: scheduling.timezone ?? '',
      venue: scheduling.venue ?? '',
      notes: scheduling.notes ?? '',
    },
    matchSettings: {
      matchDurationMinutes: matchSettings.matchDurationMinutes ?? 0,
      legs: matchSettings.legs ?? 1,
      extraTimeEnabled: matchSettings.extraTimeEnabled === true,
      penaltiesEnabled: matchSettings.penaltiesEnabled === true,
      condition: matchSettings.condition ?? '',
      substitutions: matchSettings.substitutions ?? -1,
      notes: matchSettings.notes ?? '',
    },
    gameplay: {
      allowed: Array.isArray(gameplay.allowed) ? gameplay.allowed : [],
      prohibited: Array.isArray(gameplay.prohibited) ? gameplay.prohibited : [],
      customRules: Array.isArray(gameplay.customRules) ? gameplay.customRules : [],
    },
    connection: {
      enabled: connection.enabled === true,
      reconnectWindowMinutes: connection.reconnectWindowMinutes ?? 0,
      replayAllowed: connection.replayAllowed === true,
      evidenceRequired: connection.evidenceRequired === true,
      decidedBy: connection.decidedBy ?? '',
      repeatedDisconnectionConsequence: connection.repeatedDisconnectionConsequence ?? '',
    },
    noShow: {
      waitingPeriodMinutes: noShow.waitingPeriodMinutes ?? 0,
      warningBeforeForfeit: noShow.warningBeforeForfeit !== false,
      autoForfeit: noShow.autoForfeit === true,
      forfeitScore: noShow.forfeitScore ?? '',
      missedMatchesAllowed: noShow.missedMatchesAllowed ?? 0,
      disqualificationThreshold: noShow.disqualificationThreshold ?? 0,
    },
    resultSubmission: {
      mode: resultSubmission.mode ?? 'bothConfirm',
      screenshotRequired: resultSubmission.screenshotRequired === true,
      videoRequired: resultSubmission.videoRequired === true,
      submissionDeadlineHours: resultSubmission.submissionDeadlineHours ?? 0,
      disputeWindowHours: resultSubmission.disputeWindowHours ?? 0,
      autoConfirmIfNoDispute: resultSubmission.autoConfirmIfNoDispute === true,
    },
    evidence: {
      acceptedTypes: Array.isArray(evidence.acceptedTypes) ? evidence.acceptedTypes : [],
    },
    eligibility: {
      ageRestriction: eligibility.ageRestriction ?? '',
      rosterNotes: eligibility.rosterNotes ?? '',
      duplicateTeamsAllowed: eligibility.duplicateTeamsAllowed === true,
      registrationDeadline: eligibility.registrationDeadline ?? '',
      notes: eligibility.notes ?? '',
    },
    fairPlay: {
      enabledStandardRuleKeys: Array.isArray(fairPlay.enabledStandardRuleKeys) ? fairPlay.enabledStandardRuleKeys : [],
      customRules: Array.isArray(fairPlay.customRules) ? fairPlay.customRules : [],
    },
    disputes: {
      disputeWindowHours: disputes.disputeWindowHours ?? 0,
      whoCanSubmit: disputes.whoCanSubmit ?? '',
      evidenceRequired: disputes.evidenceRequired === true,
      finalDecisionAuthority: disputes.finalDecisionAuthority ?? '',
    },
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
    updatedBy: data.updatedBy ?? '',
    updatedByName: data.updatedByName ?? '',
  };
}

export async function getCompetitionRules(leagueId: string): Promise<CompetitionRules | null> {
  const snap = await adminDb
    .collection(LEAGUES_COLLECTION)
    .doc(leagueId)
    .collection(RULES_SUBCOLLECTION)
    .doc(CURRENT_DOC_ID)
    .get();

  if (!snap.exists) return null;
  return toCompetitionRules(leagueId, snap.data() ?? {});
}

export class CompetitionRulesError extends Error {}

export async function updateCompetitionRules(params: {
  leagueId: string;
  updates: Partial<Pick<CompetitionRules,
    'competitionType' | 'scheduling' | 'matchSettings' | 'noShow' | 'resultSubmission' | 'disputes'
  >>;
  actorUid: string;
  actorEmail?: string | null;
  actorName: string;
}): Promise<CompetitionRules> {
  const { leagueId, updates, actorUid, actorName } = params;
  const currentRef = adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection(RULES_SUBCOLLECTION).doc(CURRENT_DOC_ID);

  const result = await adminDb.runTransaction(async (transaction) => {
    const currentSnap = await transaction.get(currentRef);
    const nowMs = Date.now();

    const existing = currentSnap.exists ? toCompetitionRules(leagueId, currentSnap.data() ?? {}) : null;

    if (existing?.locked) {
      // Archive the current locked version before overwriting it.
      const historyRef = adminDb
        .collection(LEAGUES_COLLECTION)
        .doc(leagueId)
        .collection(RULES_SUBCOLLECTION)
        .doc(historyDocId(existing.version));
      transaction.set(historyRef, currentSnap.data());
    }

    const merged: CompetitionRules = {
      leagueId,
      version: existing ? existing.version + (existing.locked ? 1 : 0) : 1,
      locked: false, // an edit always unlocks — organizer/admin must re-lock explicitly via the mobile "Publish & Lock" action
      competitionType: updates.competitionType ?? existing?.competitionType ?? 'online',
      scheduling: updates.scheduling ?? existing?.scheduling ?? {
        method: 'organizerScheduled', matchDeadlineHours: 0, allowRescheduling: true,
        deadlineExtensionAllowed: false, timezone: '', venue: '', notes: '',
      },
      matchSettings: updates.matchSettings ?? existing?.matchSettings ?? {
        matchDurationMinutes: 0, legs: 1, extraTimeEnabled: false, penaltiesEnabled: false,
        condition: '', substitutions: -1, notes: '',
      },
      gameplay: existing?.gameplay ?? { allowed: [], prohibited: [], customRules: [] },
      connection: existing?.connection ?? {
        enabled: false, reconnectWindowMinutes: 0, replayAllowed: false,
        evidenceRequired: false, decidedBy: '', repeatedDisconnectionConsequence: '',
      },
      noShow: updates.noShow ?? existing?.noShow ?? {
        waitingPeriodMinutes: 0, warningBeforeForfeit: true, autoForfeit: false,
        forfeitScore: '', missedMatchesAllowed: 0, disqualificationThreshold: 0,
      },
      resultSubmission: updates.resultSubmission ?? existing?.resultSubmission ?? {
        mode: 'bothConfirm', screenshotRequired: false, videoRequired: false,
        submissionDeadlineHours: 0, disputeWindowHours: 0, autoConfirmIfNoDispute: false,
      },
      evidence: existing?.evidence ?? { acceptedTypes: [] },
      eligibility: existing?.eligibility ?? {
        ageRestriction: '', rosterNotes: '', duplicateTeamsAllowed: false, registrationDeadline: '', notes: '',
      },
      fairPlay: existing?.fairPlay ?? { enabledStandardRuleKeys: [], customRules: [] },
      disputes: updates.disputes ?? existing?.disputes ?? {
        disputeWindowHours: 0, whoCanSubmit: '', evidenceRequired: false, finalDecisionAuthority: '',
      },
      updatedAtMs: nowMs,
      updatedBy: actorUid,
      updatedByName: actorName,
    };

    transaction.set(currentRef, merged);
    return merged;
  });

  await recordAuditLog({
    actorUid,
    actorEmail: params.actorEmail,
    action: 'competition_rules.update',
    targetType: 'league',
    targetId: leagueId,
    summary: `Updated competition rules for league ${leagueId} (now v${result.version})`,
  });

  return result;
}
