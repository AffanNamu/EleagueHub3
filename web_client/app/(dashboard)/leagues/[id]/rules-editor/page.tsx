'use client';

// Mirrors lib/features/leagues/presentation/competition_rules_editor_screen.dart
// — the organizer-facing Competition Rules & Configuration editor. League-scoped
// (one competition), separate from Organizer Discipline (master-league scoped,
// enforcement actions). Edits WHAT PARTICIPANTS MUST FOLLOW, stored via
// competitionRulesRepository.saveCompetitionRules.

import { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { fetchFullLeagueDetails } from '@/lib/leagues/leagueDetailsRepository';
import { getCompetitionRules, saveCompetitionRules } from '@/lib/leagues/competitionRulesRepository';
import {
  CompetitionRules, CompetitionType, SchedulingMethod, ResultSubmissionMode,
  competitionRulesDefaultsFor, competitionTypeDisplayName, schedulingMethodDisplayName,
  resultSubmissionModeDisplayName, STANDARD_FAIR_PLAY_RULE_KEYS, FAIR_PLAY_RULE_LABELS,
} from '@/lib/models/competitionRules';
import { ArrowLeft, Lock, Loader2, Save, ShieldCheck, RefreshCw } from 'lucide-react';

const EVIDENCE_TYPE_OPTIONS = ['screenshot', 'video', 'match_recording', 'system_generated', 'other'];

function linesOf(raw: string): string[] {
  return raw.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
}

function intOf(raw: string, fallback = 0): number {
  const n = parseInt(raw.trim(), 10);
  return Number.isFinite(n) ? n : fallback;
}

export default function CompetitionRulesEditorPage() {
  const router = useRouter();
  const params = useParams();
  const leagueId = params?.id as string;

  const [authUid, setAuthUid] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [authorized, setAuthorized] = useState<boolean | null>(null);

  const [hadExistingDoc, setHadExistingDoc] = useState(false);
  const [loadedVersion, setLoadedVersion] = useState(1);
  const [locked, setLocked] = useState(false);

  const [competitionType, setCompetitionType] = useState<CompetitionType>('online');

  // Scheduling
  const [schedulingMethod, setSchedulingMethod] = useState<SchedulingMethod>('organizerScheduled');
  const [matchDeadlineHours, setMatchDeadlineHours] = useState('');
  const [allowRescheduling, setAllowRescheduling] = useState(true);
  const [deadlineExtensionAllowed, setDeadlineExtensionAllowed] = useState(false);
  const [timezone, setTimezone] = useState('');
  const [venue, setVenue] = useState('');
  const [schedulingNotes, setSchedulingNotes] = useState('');

  // Match settings
  const [matchDuration, setMatchDuration] = useState('');
  const [legs, setLegs] = useState(1);
  const [extraTimeEnabled, setExtraTimeEnabled] = useState(false);
  const [penaltiesEnabled, setPenaltiesEnabled] = useState(false);
  const [condition, setCondition] = useState('');
  const [substitutions, setSubstitutions] = useState('-1');
  const [matchSettingsNotes, setMatchSettingsNotes] = useState('');

  // Gameplay
  const [allowedText, setAllowedText] = useState('');
  const [prohibitedText, setProhibitedText] = useState('');
  const [gameplayCustomText, setGameplayCustomText] = useState('');

  // Connection & disconnection
  const [connectionEnabled, setConnectionEnabled] = useState(false);
  const [reconnectWindow, setReconnectWindow] = useState('');
  const [replayAllowed, setReplayAllowed] = useState(false);
  const [connectionEvidenceRequired, setConnectionEvidenceRequired] = useState(false);
  const [decidedBy, setDecidedBy] = useState('');
  const [repeatedDisconnection, setRepeatedDisconnection] = useState('');

  // No-show & forfeit
  const [waitingPeriod, setWaitingPeriod] = useState('');
  const [warningBeforeForfeit, setWarningBeforeForfeit] = useState(true);
  const [autoForfeit, setAutoForfeit] = useState(false);
  const [forfeitScore, setForfeitScore] = useState('');
  const [missedMatches, setMissedMatches] = useState('0');
  const [disqualificationThreshold, setDisqualificationThreshold] = useState('0');

  // Result submission
  const [resultMode, setResultMode] = useState<ResultSubmissionMode>('bothConfirm');
  const [screenshotRequired, setScreenshotRequired] = useState(false);
  const [videoRequired, setVideoRequired] = useState(false);
  const [submissionDeadline, setSubmissionDeadline] = useState('');
  const [disputeWindow, setDisputeWindow] = useState('');
  const [autoConfirmIfNoDispute, setAutoConfirmIfNoDispute] = useState(false);

  // Evidence
  const [acceptedEvidenceTypes, setAcceptedEvidenceTypes] = useState<Set<string>>(new Set());

  // Eligibility
  const [ageRestriction, setAgeRestriction] = useState('');
  const [rosterNotes, setRosterNotes] = useState('');
  const [duplicateTeamsAllowed, setDuplicateTeamsAllowed] = useState(false);
  const [registrationDeadline, setRegistrationDeadline] = useState('');
  const [eligibilityNotes, setEligibilityNotes] = useState('');

  // Fair play
  const [enabledFairPlayKeys, setEnabledFairPlayKeys] = useState<Set<string>>(new Set(STANDARD_FAIR_PLAY_RULE_KEYS));
  const [fairPlayCustomText, setFairPlayCustomText] = useState('');

  // Disputes
  const [disputeWindowHours, setDisputeWindowHours] = useState('');
  const [whoCanSubmit, setWhoCanSubmit] = useState('');
  const [disputeEvidenceRequired, setDisputeEvidenceRequired] = useState(false);
  const [finalAuthority, setFinalAuthority] = useState('');

  useEffect(() => {
    const unsub = auth.onAuthStateChanged((u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  const seedFrom = (r: CompetitionRules) => {
    setCompetitionType(r.competitionType);
    setLocked(r.locked);

    setSchedulingMethod(r.scheduling.method);
    setMatchDeadlineHours(r.scheduling.matchDeadlineHours > 0 ? String(r.scheduling.matchDeadlineHours) : '');
    setAllowRescheduling(r.scheduling.allowRescheduling);
    setDeadlineExtensionAllowed(r.scheduling.deadlineExtensionAllowed);
    setTimezone(r.scheduling.timezone);
    setVenue(r.scheduling.venue);
    setSchedulingNotes(r.scheduling.notes);

    setMatchDuration(r.matchSettings.matchDurationMinutes > 0 ? String(r.matchSettings.matchDurationMinutes) : '');
    setLegs(r.matchSettings.legs <= 0 ? 1 : r.matchSettings.legs);
    setExtraTimeEnabled(r.matchSettings.extraTimeEnabled);
    setPenaltiesEnabled(r.matchSettings.penaltiesEnabled);
    setCondition(r.matchSettings.condition);
    setSubstitutions(String(r.matchSettings.substitutions));
    setMatchSettingsNotes(r.matchSettings.notes);

    setAllowedText(r.gameplay.allowed.join('\n'));
    setProhibitedText(r.gameplay.prohibited.join('\n'));
    setGameplayCustomText(r.gameplay.customRules.join('\n'));

    setConnectionEnabled(r.connection.enabled);
    setReconnectWindow(r.connection.reconnectWindowMinutes > 0 ? String(r.connection.reconnectWindowMinutes) : '');
    setReplayAllowed(r.connection.replayAllowed);
    setConnectionEvidenceRequired(r.connection.evidenceRequired);
    setDecidedBy(r.connection.decidedBy);
    setRepeatedDisconnection(r.connection.repeatedDisconnectionConsequence);

    setWaitingPeriod(r.noShow.waitingPeriodMinutes > 0 ? String(r.noShow.waitingPeriodMinutes) : '');
    setWarningBeforeForfeit(r.noShow.warningBeforeForfeit);
    setAutoForfeit(r.noShow.autoForfeit);
    setForfeitScore(r.noShow.forfeitScore);
    setMissedMatches(String(r.noShow.missedMatchesAllowed));
    setDisqualificationThreshold(String(r.noShow.disqualificationThreshold));

    setResultMode(r.resultSubmission.mode);
    setScreenshotRequired(r.resultSubmission.screenshotRequired);
    setVideoRequired(r.resultSubmission.videoRequired);
    setSubmissionDeadline(r.resultSubmission.submissionDeadlineHours > 0 ? String(r.resultSubmission.submissionDeadlineHours) : '');
    setDisputeWindow(r.resultSubmission.disputeWindowHours > 0 ? String(r.resultSubmission.disputeWindowHours) : '');
    setAutoConfirmIfNoDispute(r.resultSubmission.autoConfirmIfNoDispute);

    setAcceptedEvidenceTypes(new Set(r.evidence.acceptedTypes));

    setAgeRestriction(r.eligibility.ageRestriction);
    setRosterNotes(r.eligibility.rosterNotes);
    setDuplicateTeamsAllowed(r.eligibility.duplicateTeamsAllowed);
    setRegistrationDeadline(r.eligibility.registrationDeadline);
    setEligibilityNotes(r.eligibility.notes);

    setEnabledFairPlayKeys(new Set(r.fairPlay.enabledStandardRuleKeys));
    setFairPlayCustomText(r.fairPlay.customRules.join('\n'));

    setDisputeWindowHours(r.disputes.disputeWindowHours > 0 ? String(r.disputes.disputeWindowHours) : '');
    setWhoCanSubmit(r.disputes.whoCanSubmit);
    setDisputeEvidenceRequired(r.disputes.evidenceRequired);
    setFinalAuthority(r.disputes.finalDecisionAuthority);
  };

  const load = async () => {
    if (!authUid || !leagueId) return;
    setLoading(true);
    setError('');
    try {
      const details = await fetchFullLeagueDetails(leagueId, authUid);
      if (!details?.isOwner) {
        setAuthorized(false);
        setLoading(false);
        return;
      }
      setAuthorized(true);

      const existing = await getCompetitionRules(leagueId);
      const defaultType: CompetitionType = details.league.footballCategory === 'localFootball' ? 'physical' : 'online';
      const rules = existing ?? competitionRulesDefaultsFor(leagueId, defaultType);

      setHadExistingDoc(existing !== null);
      setLoadedVersion(rules.version);
      seedFrom(rules);
      setLoading(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!authUid) return;
    const timer = setTimeout(() => load(), 0);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authUid, leagueId]);

  const buildRulesFromForm = (publishLocked: boolean): CompetitionRules => ({
    leagueId,
    version: loadedVersion,
    locked: publishLocked,
    competitionType,
    scheduling: {
      method: schedulingMethod,
      matchDeadlineHours: intOf(matchDeadlineHours),
      allowRescheduling,
      deadlineExtensionAllowed,
      timezone: timezone.trim(),
      venue: venue.trim(),
      notes: schedulingNotes.trim(),
    },
    matchSettings: {
      matchDurationMinutes: intOf(matchDuration),
      legs,
      extraTimeEnabled,
      penaltiesEnabled,
      condition: condition.trim(),
      substitutions: intOf(substitutions, -1),
      notes: matchSettingsNotes.trim(),
    },
    gameplay: {
      allowed: linesOf(allowedText),
      prohibited: linesOf(prohibitedText),
      customRules: linesOf(gameplayCustomText),
    },
    connection: {
      enabled: connectionEnabled,
      reconnectWindowMinutes: intOf(reconnectWindow),
      replayAllowed,
      evidenceRequired: connectionEvidenceRequired,
      decidedBy: decidedBy.trim(),
      repeatedDisconnectionConsequence: repeatedDisconnection.trim(),
    },
    noShow: {
      waitingPeriodMinutes: intOf(waitingPeriod),
      warningBeforeForfeit,
      autoForfeit,
      forfeitScore: forfeitScore.trim(),
      missedMatchesAllowed: intOf(missedMatches),
      disqualificationThreshold: intOf(disqualificationThreshold),
    },
    resultSubmission: {
      mode: resultMode,
      screenshotRequired,
      videoRequired,
      submissionDeadlineHours: intOf(submissionDeadline),
      disputeWindowHours: intOf(disputeWindow),
      autoConfirmIfNoDispute,
    },
    evidence: { acceptedTypes: Array.from(acceptedEvidenceTypes) },
    eligibility: {
      ageRestriction: ageRestriction.trim(),
      rosterNotes: rosterNotes.trim(),
      duplicateTeamsAllowed,
      registrationDeadline: registrationDeadline.trim(),
      notes: eligibilityNotes.trim(),
    },
    fairPlay: {
      enabledStandardRuleKeys: Array.from(enabledFairPlayKeys),
      customRules: linesOf(fairPlayCustomText),
    },
    disputes: {
      disputeWindowHours: intOf(disputeWindowHours),
      whoCanSubmit: whoCanSubmit.trim(),
      evidenceRequired: disputeEvidenceRequired,
      finalDecisionAuthority: finalAuthority.trim(),
    },
    updatedAtMs: 0,
    updatedBy: '',
    updatedByName: '',
  });

  const save = async (publishLocked: boolean) => {
    if (!authUid) return;
    setSaving(true);
    setError('');
    try {
      const rules = buildRulesFromForm(publishLocked);
      const saved = await saveCompetitionRules(rules, authUid);
      setSaving(false);
      setHadExistingDoc(true);
      setLoadedVersion(saved.version);
      setLocked(saved.locked);
      setNotice(publishLocked ? `Rules published and locked (v${saved.version}).` : `Rules saved as draft (v${saved.version}).`);
      setTimeout(() => setNotice(''), 4000);
    } catch (e) {
      setSaving(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  if (loading || authorized === null) {
    return (
      <div className="flex h-full items-center justify-center py-24">
        <Loader2 className="w-8 h-8 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  if (authorized === false) {
    return (
      <div className="max-w-2xl mx-auto text-center py-24">
        <p className="text-red-500 font-black">Only the organizer or allowed admins can edit competition rules.</p>
      </div>
    );
  }

  const inputCls = 'w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-[#BEF264] transition-colors';
  const labelCls = 'block text-xs font-bold text-gray-400 mb-1.5';

  return (
    <div className="max-w-3xl mx-auto space-y-4 pb-24 px-4 mt-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-2xl font-black text-white flex-1">Competition Rules</h1>
        <button onClick={load} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-gray-400 hover:text-white">
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {/* Header card */}
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 space-y-3">
        <p className="text-white font-black">{hadExistingDoc ? `Editing v${loadedVersion}` : 'New Competition Rules'}</p>
        <p className="text-xs text-gray-400 font-semibold">
          Define what participants must follow in this competition. This is separate from Organizer Discipline, which stays where it is.
        </p>
        {locked && (
          <div className="flex items-center gap-2 bg-amber-500/10 border border-amber-500/30 rounded-xl px-3 py-2">
            <Lock className="w-4 h-4 text-amber-500 shrink-0" />
            <p className="text-xs font-bold text-amber-500">
              These rules are locked. Saving changes will publish a new version and keep the old one for history.
            </p>
          </div>
        )}
        {error && <p className="text-red-500 text-sm font-bold">{error}</p>}
        <div>
          <p className={labelCls}>Competition Type</p>
          <div className="flex flex-wrap gap-2">
            {(['online', 'physical', 'hybrid'] as CompetitionType[]).map((t) => (
              <button
                key={t}
                onClick={() => setCompetitionType(t)}
                className={`px-3 py-1.5 rounded-full text-xs font-black transition-colors ${
                  competitionType === t ? 'bg-[#BEF264] text-[#0F172A]' : 'bg-[#070B14] border border-[#1E293B] text-gray-400'
                }`}
              >
                {competitionTypeDisplayName[t]}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* 1. Scheduling */}
      <Section title="1. Match Scheduling" subtitle="Do not assume a 24-hour deadline — pick what fits this competition.">
        <div>
          <label className={labelCls}>Scheduling method</label>
          <select className={inputCls} value={schedulingMethod} onChange={(e) => setSchedulingMethod(e.target.value as SchedulingMethod)}>
            {(['organizerScheduled', 'participantAgreed', 'fixedWindow'] as SchedulingMethod[]).map((m) => (
              <option key={m} value={m}>{schedulingMethodDisplayName[m]}</option>
            ))}
          </select>
        </div>
        {schedulingMethod === 'fixedWindow' && (
          <NumberField label="Match deadline (hours)" value={matchDeadlineHours} onChange={setMatchDeadlineHours} />
        )}
        <Switch label="Allow rescheduling" value={allowRescheduling} onChange={setAllowRescheduling} />
        <Switch label="Allow deadline extensions" value={deadlineExtensionAllowed} onChange={setDeadlineExtensionAllowed} />
        <TextField label="Timezone (optional)" value={timezone} onChange={setTimezone} />
        <TextField label="Venue / location (optional)" value={venue} onChange={setVenue} />
        <TextField label="Scheduling notes (optional)" value={schedulingNotes} onChange={setSchedulingNotes} rows={3} />
      </Section>

      {/* 2. Match settings */}
      <Section title="2. Match Settings" subtitle="Only fill in what applies to this competition/game type.">
        <NumberField label="Match duration (minutes)" value={matchDuration} onChange={setMatchDuration} />
        <div>
          <label className={labelCls}>Legs</label>
          <select className={inputCls} value={legs} onChange={(e) => setLegs(Number(e.target.value))}>
            <option value={1}>Single match</option>
            <option value={2}>Home & away (2 legs)</option>
          </select>
        </div>
        <Switch label="Extra time enabled" value={extraTimeEnabled} onChange={setExtraTimeEnabled} />
        <Switch label="Penalty shootout enabled" value={penaltiesEnabled} onChange={setPenaltiesEnabled} />
        <TextField label='Game condition (e.g. "Excellent", "Any")' value={condition} onChange={setCondition} />
        <TextField label="Substitutions (-1 = unlimited)" value={substitutions} onChange={setSubstitutions} />
        <TextField label="Match settings notes (optional)" value={matchSettingsNotes} onChange={setMatchSettingsNotes} rows={3} />
      </Section>

      {/* 3. Gameplay */}
      <Section title="3. Gameplay Rules" subtitle="One rule per line.">
        <TextField label="Allowed gameplay settings" value={allowedText} onChange={setAllowedText} rows={3} />
        <TextField label="Prohibited behavior / glitches / cheating" value={prohibitedText} onChange={setProhibitedText} rows={3} />
        <TextField label="Custom organizer rules" value={gameplayCustomText} onChange={setGameplayCustomText} rows={3} />
      </Section>

      {/* 4. Connection */}
      <Section title="4. Connection & Disconnection" subtitle="Leave disabled for physical/local competitions.">
        <Switch label="Applies to this competition" value={connectionEnabled} onChange={setConnectionEnabled} />
        {connectionEnabled && (
          <>
            <NumberField label="Time to reconnect (minutes)" value={reconnectWindow} onChange={setReconnectWindow} />
            <Switch label="Replay allowed" value={replayAllowed} onChange={setReplayAllowed} />
            <Switch label="Evidence required" value={connectionEvidenceRequired} onChange={setConnectionEvidenceRequired} />
            <TextField label="Who decides the outcome" value={decidedBy} onChange={setDecidedBy} />
            <TextField label="Repeated disconnection consequence" value={repeatedDisconnection} onChange={setRepeatedDisconnection} rows={2} />
          </>
        )}
      </Section>

      {/* 5. No-show */}
      <Section title="5. No-Show & Forfeit" subtitle='Works for both "missed the 24h deadline" and "failed to appear on the scheduled date".'>
        <NumberField label="Waiting period before forfeit (minutes)" value={waitingPeriod} onChange={setWaitingPeriod} />
        <Switch label="Warn before forfeit" value={warningBeforeForfeit} onChange={setWarningBeforeForfeit} />
        <Switch label="Automatic forfeit" value={autoForfeit} onChange={setAutoForfeit} />
        <TextField label='Forfeit score (e.g. "3-0")' value={forfeitScore} onChange={setForfeitScore} />
        <NumberField label="Missed matches allowed" value={missedMatches} onChange={setMissedMatches} />
        <NumberField label="Disqualification threshold" value={disqualificationThreshold} onChange={setDisqualificationThreshold} />
      </Section>

      {/* 6. Result submission */}
      <Section title="6. Result Submission" subtitle="Who submits results and how disputes are triggered.">
        <div>
          <label className={labelCls}>Submission mode</label>
          <select className={inputCls} value={resultMode} onChange={(e) => setResultMode(e.target.value as ResultSubmissionMode)}>
            {(['bothConfirm', 'eitherSubmits', 'organizerOnly'] as ResultSubmissionMode[]).map((m) => (
              <option key={m} value={m}>{resultSubmissionModeDisplayName[m]}</option>
            ))}
          </select>
        </div>
        <Switch label="Screenshot required" value={screenshotRequired} onChange={setScreenshotRequired} />
        <Switch label="Video required" value={videoRequired} onChange={setVideoRequired} />
        <Switch label="Auto-confirm if no dispute is raised" value={autoConfirmIfNoDispute} onChange={setAutoConfirmIfNoDispute} />
        <NumberField label="Submission deadline (hours)" value={submissionDeadline} onChange={setSubmissionDeadline} />
        <NumberField label="Dispute window (hours)" value={disputeWindow} onChange={setDisputeWindow} />
      </Section>

      {/* 7. Evidence */}
      <Section title="7. Evidence" subtitle="Not required for every competition by default.">
        <div className="flex flex-wrap gap-2">
          {EVIDENCE_TYPE_OPTIONS.map((type) => {
            const selected = acceptedEvidenceTypes.has(type);
            return (
              <button
                key={type}
                onClick={() =>
                  setAcceptedEvidenceTypes((prev) => {
                    const next = new Set(prev);
                    if (selected) next.delete(type); else next.add(type);
                    return next;
                  })
                }
                className={`px-3 py-1.5 rounded-full text-xs font-black transition-colors ${
                  selected ? 'bg-[#BEF264] text-[#0F172A]' : 'bg-[#070B14] border border-[#1E293B] text-gray-400'
                }`}
              >
                {type.replace(/_/g, ' ')}
              </button>
            );
          })}
        </div>
      </Section>

      {/* 8. Eligibility */}
      <Section title="8. Participant & Team Eligibility" subtitle="Free text — keep it as strict or as open as this competition needs.">
        <TextField label='Age restriction (e.g. "16+", optional)' value={ageRestriction} onChange={setAgeRestriction} />
        <TextField label="Roster / registration notes" value={rosterNotes} onChange={setRosterNotes} rows={2} />
        <Switch label="Duplicate teams allowed" value={duplicateTeamsAllowed} onChange={setDuplicateTeamsAllowed} />
        <TextField label="Registration deadline (optional)" value={registrationDeadline} onChange={setRegistrationDeadline} />
        <TextField label="Other eligibility notes" value={eligibilityNotes} onChange={setEligibilityNotes} rows={2} />
      </Section>

      {/* 9. Fair play */}
      <Section title="9. Fair Play & Conduct" subtitle="Toggle the standard rules that apply, add custom ones below.">
        {STANDARD_FAIR_PLAY_RULE_KEYS.map((key) => {
          const enabled = enabledFairPlayKeys.has(key);
          return (
            <label key={key} className="flex items-center gap-2.5 py-1 cursor-pointer">
              <input
                type="checkbox"
                checked={enabled}
                onChange={(e) =>
                  setEnabledFairPlayKeys((prev) => {
                    const next = new Set(prev);
                    if (e.target.checked) next.add(key); else next.delete(key);
                    return next;
                  })
                }
                className="w-4 h-4 accent-[#BEF264]"
              />
              <span className="text-sm font-bold text-gray-200">{FAIR_PLAY_RULE_LABELS[key]}</span>
            </label>
          );
        })}
        <TextField label="Custom fair play rules (one per line)" value={fairPlayCustomText} onChange={setFairPlayCustomText} rows={3} />
      </Section>

      {/* 10. Disputes */}
      <Section title="10. Disputes & Appeals" subtitle="Participants should know how disputes are handled before joining.">
        <NumberField label="Dispute window (hours)" value={disputeWindowHours} onChange={setDisputeWindowHours} />
        <TextField label="Who can submit a dispute" value={whoCanSubmit} onChange={setWhoCanSubmit} />
        <Switch label="Evidence required for disputes" value={disputeEvidenceRequired} onChange={setDisputeEvidenceRequired} />
        <TextField label='Final decision authority (e.g. "Organizer")' value={finalAuthority} onChange={setFinalAuthority} />
      </Section>

      {/* Publish card */}
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 space-y-3">
        <p className="text-white font-black">Review & Publish</p>
        <p className="text-xs text-gray-400 font-semibold">
          Participants will see exactly these settings on the rules screen shown when they join.
        </p>
        {notice && <p className="text-[#BEF264] text-sm font-bold">{notice}</p>}
        <button
          disabled={saving}
          onClick={() => save(false)}
          className="w-full py-3.5 border border-[#1E293B] text-[#BEF264] rounded-xl font-black text-sm hover:bg-[#1E293B] disabled:opacity-50 flex items-center justify-center gap-2"
        >
          <Save className="w-4 h-4" /> {saving ? 'Saving...' : 'Save as Draft'}
        </button>
        <button
          disabled={saving}
          onClick={() => save(true)}
          className="w-full py-4 bg-[#BEF264] text-[#0F172A] rounded-xl font-black text-sm hover:brightness-110 disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <ShieldCheck className="w-4 h-4" />}
          {saving ? 'Publishing...' : locked ? 'Save New Locked Version' : 'Publish & Lock Rules'}
        </button>
      </div>
    </div>
  );
}

function Section({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 space-y-3">
      <div>
        <p className="text-white font-black text-sm">{title}</p>
        <p className="text-xs text-gray-400 font-semibold mt-1">{subtitle}</p>
      </div>
      {children}
    </div>
  );
}

function TextField({
  label, value, onChange, rows = 1,
}: { label: string; value: string; onChange: (v: string) => void; rows?: number }) {
  return (
    <div>
      <label className="block text-xs font-bold text-gray-400 mb-1.5">{label}</label>
      {rows > 1 ? (
        <textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          rows={rows}
          className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-[#BEF264] resize-none"
        />
      ) : (
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-[#BEF264]"
        />
      )}
    </div>
  );
}

function NumberField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <label className="block text-xs font-bold text-gray-400 mb-1.5">{label}</label>
      <input
        type="number"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-2.5 text-white text-sm focus:outline-none focus:border-[#BEF264]"
      />
    </div>
  );
}

function Switch({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="flex items-center justify-between gap-4 py-1 cursor-pointer">
      <span className="text-sm font-bold text-gray-200">{label}</span>
      <button
        type="button"
        onClick={() => onChange(!value)}
        className={`relative w-11 h-6 rounded-full transition-colors shrink-0 ${value ? 'bg-[#BEF264]' : 'bg-[#1E293B]'}`}
      >
        <span className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white transition-transform ${value ? 'translate-x-5' : ''}`} />
      </button>
    </label>
  );
}
