'use client';

import { useState } from 'react';
import { Lock, AlertTriangle } from 'lucide-react';
import { useCompetitionRulesSave } from '@/hooks/useCompetitionRulesSave';
import type {
  CompetitionRules,
  CompetitionType,
  SchedulingMethod,
  ResultSubmissionMode,
} from '@/types/competitionRules';

const DEFAULTS: CompetitionRules = {
  leagueId: '',
  version: 1,
  locked: false,
  competitionType: 'online',
  scheduling: { method: 'organizerScheduled', matchDeadlineHours: 0, allowRescheduling: true, deadlineExtensionAllowed: false, timezone: '', venue: '', notes: '' },
  matchSettings: { matchDurationMinutes: 0, legs: 1, extraTimeEnabled: false, penaltiesEnabled: false, condition: '', substitutions: -1, notes: '' },
  gameplay: { allowed: [], prohibited: [], customRules: [] },
  connection: { enabled: false, reconnectWindowMinutes: 0, replayAllowed: false, evidenceRequired: false, decidedBy: '', repeatedDisconnectionConsequence: '' },
  noShow: { waitingPeriodMinutes: 0, warningBeforeForfeit: true, autoForfeit: false, forfeitScore: '', missedMatchesAllowed: 0, disqualificationThreshold: 0 },
  resultSubmission: { mode: 'bothConfirm', screenshotRequired: false, videoRequired: false, submissionDeadlineHours: 0, disputeWindowHours: 0, autoConfirmIfNoDispute: false },
  evidence: { acceptedTypes: [] },
  eligibility: { ageRestriction: '', rosterNotes: '', duplicateTeamsAllowed: false, registrationDeadline: '', notes: '' },
  fairPlay: { enabledStandardRuleKeys: [], customRules: [] },
  disputes: { disputeWindowHours: 0, whoCanSubmit: '', evidenceRequired: false, finalDecisionAuthority: '' },
  updatedAtMs: 0,
  updatedBy: '',
  updatedByName: '',
};

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="mb-1.5 block text-sm text-ink-secondary">{label}</label>
      {children}
    </div>
  );
}

const inputClass = 'w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand';

export function CompetitionRulesEditor({
  leagueId,
  initialRules,
  canManage,
}: {
  leagueId: string;
  initialRules: CompetitionRules | null;
  canManage: boolean;
}) {
  const { save, submitting, error } = useCompetitionRulesSave(leagueId);
  const [rules, setRules] = useState<CompetitionRules>(initialRules ?? { ...DEFAULTS, leagueId });
  const [saved, setSaved] = useState(false);

  function update<K extends keyof CompetitionRules>(key: K, value: CompetitionRules[K]) {
    setRules((prev) => ({ ...prev, [key]: value }));
  }

  function updateSection<K extends 'scheduling' | 'matchSettings' | 'noShow' | 'resultSubmission' | 'disputes'>(
    section: K,
    patch: Partial<CompetitionRules[K]>,
  ) {
    setRules((prev) => ({ ...prev, [section]: { ...prev[section], ...patch } }));
  }

  async function handleSave() {
    setSaved(false);
    const ok = await save({
      competitionType: rules.competitionType,
      scheduling: rules.scheduling,
      matchSettings: rules.matchSettings,
      noShow: rules.noShow,
      resultSubmission: rules.resultSubmission,
      disputes: rules.disputes,
    });
    if (ok) setSaved(true);
  }

  return (
    <div className="space-y-4">
      {!initialRules && (
        <div className="rounded-sm border border-signal-info/30 bg-signal-infoFaint px-3 py-2.5 text-sm text-ink-secondary">
          No rules configured for this league yet — this is a normal, valid state, not an error.
          {canManage ? ' Fill in the fields below and save to create the first version.' : ''}
        </div>
      )}

      {initialRules?.locked && (
        <div className="flex items-start gap-2 rounded-sm border border-signal-warning/30 bg-signal-warningFaint px-3 py-2.5">
          <Lock size={14} className="mt-0.5 flex-shrink-0 text-signal-warning" />
          <p className="text-sm text-ink-secondary">
            This ruleset is locked (v{initialRules.version}). Saving will archive the current
            version and publish a new one.
          </p>
        </div>
      )}

      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}
      {saved && (
        <div className="rounded-sm border border-signal-success/40 bg-signal-successFaint px-3 py-2 text-sm text-signal-success">
          Saved.
        </div>
      )}

      <div className="panel space-y-4 p-5">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Competition Type</h2>
        <Field label="Type">
          <select
            value={rules.competitionType}
            disabled={!canManage}
            onChange={(e) => update('competitionType', e.target.value as CompetitionType)}
            className={inputClass}
          >
            <option value="online">Online Esports</option>
            <option value="physical">Local / Physical Football</option>
            <option value="hybrid">Hybrid</option>
          </select>
        </Field>
      </div>

      <div className="panel space-y-4 p-5">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Scheduling</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Method">
            <select
              value={rules.scheduling.method}
              disabled={!canManage}
              onChange={(e) => updateSection('scheduling', { method: e.target.value as SchedulingMethod })}
              className={inputClass}
            >
              <option value="organizerScheduled">Organizer schedules matches</option>
              <option value="participantAgreed">Participants agree on a time</option>
              <option value="fixedWindow">Fixed match deadline window</option>
            </select>
          </Field>
          {rules.scheduling.method === 'fixedWindow' && (
            <Field label="Match Deadline (hours)">
              <input
                type="number"
                value={rules.scheduling.matchDeadlineHours}
                disabled={!canManage}
                onChange={(e) => updateSection('scheduling', { matchDeadlineHours: Number(e.target.value) })}
                className={inputClass}
              />
            </Field>
          )}
          <Field label="Timezone">
            <input
              value={rules.scheduling.timezone}
              disabled={!canManage}
              onChange={(e) => updateSection('scheduling', { timezone: e.target.value })}
              className={inputClass}
              placeholder="e.g. Africa/Lagos"
            />
          </Field>
          {rules.competitionType !== 'online' && (
            <Field label="Venue">
              <input
                value={rules.scheduling.venue}
                disabled={!canManage}
                onChange={(e) => updateSection('scheduling', { venue: e.target.value })}
                className={inputClass}
              />
            </Field>
          )}
        </div>
        <label className="flex items-center gap-2 text-sm text-ink-secondary">
          <input
            type="checkbox"
            checked={rules.scheduling.allowRescheduling}
            disabled={!canManage}
            onChange={(e) => updateSection('scheduling', { allowRescheduling: e.target.checked })}
            className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
          />
          Allow rescheduling
        </label>
      </div>

      <div className="panel space-y-4 p-5">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Match Settings</h2>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Field label="Duration (min)">
            <input
              type="number"
              value={rules.matchSettings.matchDurationMinutes}
              disabled={!canManage}
              onChange={(e) => updateSection('matchSettings', { matchDurationMinutes: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
          <Field label="Legs">
            <input
              type="number"
              value={rules.matchSettings.legs}
              disabled={!canManage}
              onChange={(e) => updateSection('matchSettings', { legs: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
          <Field label="Condition">
            <input
              value={rules.matchSettings.condition}
              disabled={!canManage}
              onChange={(e) => updateSection('matchSettings', { condition: e.target.value })}
              className={inputClass}
              placeholder="e.g. Excellent"
            />
          </Field>
          <Field label="Substitutions (-1 = unlimited)">
            <input
              type="number"
              value={rules.matchSettings.substitutions}
              disabled={!canManage}
              onChange={(e) => updateSection('matchSettings', { substitutions: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
        </div>
        <div className="flex gap-4">
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.matchSettings.extraTimeEnabled}
              disabled={!canManage}
              onChange={(e) => updateSection('matchSettings', { extraTimeEnabled: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Extra time enabled
          </label>
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.matchSettings.penaltiesEnabled}
              disabled={!canManage}
              onChange={(e) => updateSection('matchSettings', { penaltiesEnabled: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Penalties enabled
          </label>
        </div>
      </div>

      <div className="panel space-y-4 p-5">
        <h2 className="font-display text-sm font-semibold text-ink-primary">No-Show &amp; Forfeit</h2>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Field label="Waiting Period (min)">
            <input
              type="number"
              value={rules.noShow.waitingPeriodMinutes}
              disabled={!canManage}
              onChange={(e) => updateSection('noShow', { waitingPeriodMinutes: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
          <Field label="Forfeit Score">
            <input
              value={rules.noShow.forfeitScore}
              disabled={!canManage}
              onChange={(e) => updateSection('noShow', { forfeitScore: e.target.value })}
              className={inputClass}
              placeholder="e.g. 3-0"
            />
          </Field>
          <Field label="Missed Matches Allowed">
            <input
              type="number"
              value={rules.noShow.missedMatchesAllowed}
              disabled={!canManage}
              onChange={(e) => updateSection('noShow', { missedMatchesAllowed: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
          <Field label="Disqualification Threshold">
            <input
              type="number"
              value={rules.noShow.disqualificationThreshold}
              disabled={!canManage}
              onChange={(e) => updateSection('noShow', { disqualificationThreshold: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
        </div>
        <div className="flex gap-4">
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.noShow.warningBeforeForfeit}
              disabled={!canManage}
              onChange={(e) => updateSection('noShow', { warningBeforeForfeit: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Warning before forfeit
          </label>
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.noShow.autoForfeit}
              disabled={!canManage}
              onChange={(e) => updateSection('noShow', { autoForfeit: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Auto-forfeit
          </label>
        </div>
      </div>

      <div className="panel space-y-4 p-5">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Result Submission</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Field label="Mode">
            <select
              value={rules.resultSubmission.mode}
              disabled={!canManage}
              onChange={(e) => updateSection('resultSubmission', { mode: e.target.value as ResultSubmissionMode })}
              className={inputClass}
            >
              <option value="bothConfirm">Both participants must confirm</option>
              <option value="eitherSubmits">Either participant submits</option>
              <option value="organizerOnly">Organizer/admin only</option>
            </select>
          </Field>
          <Field label="Submission Deadline (hours)">
            <input
              type="number"
              value={rules.resultSubmission.submissionDeadlineHours}
              disabled={!canManage}
              onChange={(e) => updateSection('resultSubmission', { submissionDeadlineHours: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
          <Field label="Dispute Window (hours)">
            <input
              type="number"
              value={rules.resultSubmission.disputeWindowHours}
              disabled={!canManage}
              onChange={(e) => updateSection('resultSubmission', { disputeWindowHours: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
        </div>
        <div className="flex flex-wrap gap-4">
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.resultSubmission.screenshotRequired}
              disabled={!canManage}
              onChange={(e) => updateSection('resultSubmission', { screenshotRequired: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Screenshot required
          </label>
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.resultSubmission.videoRequired}
              disabled={!canManage}
              onChange={(e) => updateSection('resultSubmission', { videoRequired: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Video required
          </label>
          <label className="flex items-center gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={rules.resultSubmission.autoConfirmIfNoDispute}
              disabled={!canManage}
              onChange={(e) => updateSection('resultSubmission', { autoConfirmIfNoDispute: e.target.checked })}
              className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
            />
            Auto-confirm if no dispute
          </label>
        </div>
      </div>

      <div className="panel space-y-4 p-5">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Disputes</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Field label="Dispute Window (hours)">
            <input
              type="number"
              value={rules.disputes.disputeWindowHours}
              disabled={!canManage}
              onChange={(e) => updateSection('disputes', { disputeWindowHours: Number(e.target.value) })}
              className={inputClass}
            />
          </Field>
          <Field label="Who Can Submit">
            <input
              value={rules.disputes.whoCanSubmit}
              disabled={!canManage}
              onChange={(e) => updateSection('disputes', { whoCanSubmit: e.target.value })}
              className={inputClass}
              placeholder="e.g. Either participant"
            />
          </Field>
          <Field label="Final Decision Authority">
            <input
              value={rules.disputes.finalDecisionAuthority}
              disabled={!canManage}
              onChange={(e) => updateSection('disputes', { finalDecisionAuthority: e.target.value })}
              className={inputClass}
              placeholder="e.g. Organizer"
            />
          </Field>
        </div>
      </div>

      <div className="panel p-5">
        <div className="mb-2 flex items-center gap-2">
          <AlertTriangle size={14} className="text-ink-muted" />
          <h2 className="font-display text-sm font-semibold text-ink-primary">Not editable here yet</h2>
        </div>
        <p className="text-sm text-ink-secondary">
          Gameplay rules, Evidence types, Eligibility, and Fair Play sections involve list-editing
          UI (multiple free-text entries, toggleable rule catalogs) that weren't scoped into this
          batch — they're preserved as-is on save, not lost, just not editable from this screen yet.
        </p>
      </div>

      {canManage && (
        <button
          onClick={handleSave}
          disabled={submitting}
          className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
        >
          {submitting ? 'Saving…' : 'Save Rules'}
        </button>
      )}
    </div>
  );
}
