'use client';

// Mirrors lib/features/leagues/presentation/competition_rules_gate_screen.dart
// — shown right after a user joins a league AS A PARTICIPANT, before they
// land on League Detail. Informational only: no "I agree" checkbox, no
// agreement stored — a Continue button is enough. Viewer joins never route
// here. If the organizer hasn't configured any rules yet, this screen skips
// itself automatically (an unconfigured competition is a normal state, not
// an error). Read-only — editing happens at /rules-editor (organizer-only).

import { useEffect, useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { getCompetitionRules } from '@/lib/leagues/competitionRulesRepository';
import { CompetitionRules, FAIR_PLAY_RULE_LABELS, resultSubmissionModeDisplayName } from '@/lib/models/competitionRules';
import { CheckCircle2, Loader2 } from 'lucide-react';

function durationLabel(hours: number): string {
  return hours === 1 ? '1 hour' : `${hours} hours`;
}

function Card({ emoji, title, lines }: { emoji: string; title: string; lines: string[] }) {
  if (lines.length === 0) return null;
  return (
    <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 mb-3">
      <p className="text-white font-black text-sm mb-2.5">{emoji}  {title}</p>
      {lines.map((line, idx) => (
        <p key={idx} className="text-sm text-gray-300 font-semibold leading-relaxed mb-1.5 last:mb-0">{line}</p>
      ))}
    </div>
  );
}

export default function CompetitionRulesGatePage() {
  const router = useRouter();
  const params = useParams();
  const leagueId = params?.id as string;

  const [loading, setLoading] = useState(true);
  const [rules, setRules] = useState<CompetitionRules | null>(null);

  useEffect(() => {
    if (!leagueId) return;
    let cancelled = false;

    (async () => {
      try {
        const r = await getCompetitionRules(leagueId);
        if (cancelled) return;

        if (!r) {
          // Nothing configured — skip straight to League Detail.
          router.replace(`/leagues/${leagueId}`);
          return;
        }
        setRules(r);
        setLoading(false);
      } catch {
        // Don't block the user from reaching the league on a load failure.
        if (!cancelled) router.replace(`/leagues/${leagueId}`);
      }
    })();

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [leagueId]);

  const continueToLeague = () => router.replace(`/leagues/${leagueId}`);

  if (loading || !rules) {
    return (
      <div className="flex h-full items-center justify-center py-24">
        <Loader2 className="w-8 h-8 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  const r = rules;

  const schedulingLines: string[] = [];
  if (r.scheduling.method === 'fixedWindow') {
    if (r.scheduling.matchDeadlineHours > 0) schedulingLines.push(`⏰ Match deadline: ${durationLabel(r.scheduling.matchDeadlineHours)}`);
  } else if (r.scheduling.method === 'organizerScheduled') {
    schedulingLines.push('📅 Matches are scheduled by the organizer.');
  } else {
    schedulingLines.push('🤝 Teams agree on a match time between themselves.');
  }
  if (r.scheduling.venue.trim()) schedulingLines.push(`📍 Venue: ${r.scheduling.venue.trim()}`);
  if (r.scheduling.timezone.trim()) schedulingLines.push(`🌐 Timezone: ${r.scheduling.timezone.trim()}`);
  schedulingLines.push(r.scheduling.allowRescheduling ? '🔄 Rescheduling is allowed.' : '🚫 Rescheduling is not allowed.');
  if (r.scheduling.notes.trim()) schedulingLines.push(r.scheduling.notes.trim());

  const matchSettingsLines: string[] = [];
  if (r.matchSettings.matchDurationMinutes > 0) matchSettingsLines.push(`⏱️ Match duration: ${r.matchSettings.matchDurationMinutes} minutes`);
  if (r.matchSettings.legs > 1) matchSettingsLines.push(`🏟️ Legs: ${r.matchSettings.legs} (home & away)`);
  matchSettingsLines.push(r.matchSettings.extraTimeEnabled ? '➕ Extra time: Enabled' : '🚫 Extra time: Disabled');
  matchSettingsLines.push(r.matchSettings.penaltiesEnabled ? '🎯 Penalties: Enabled' : '🚫 Penalties: Disabled');
  if (r.matchSettings.condition.trim()) matchSettingsLines.push(`⚙️ Condition: ${r.matchSettings.condition.trim()}`);
  if (r.matchSettings.substitutions >= 0) matchSettingsLines.push(`🔄 Substitutions: ${r.matchSettings.substitutions}`);
  if (r.matchSettings.notes.trim()) matchSettingsLines.push(r.matchSettings.notes.trim());

  const gameplayLines: string[] = [
    ...r.gameplay.allowed.map((a) => `✅ ${a}`),
    ...r.gameplay.prohibited.map((p) => `🚫 ${p}`),
    ...r.gameplay.customRules.map((c) => `• ${c}`),
  ];

  const connectionLines: string[] = [];
  if (r.connection.enabled) {
    if (r.connection.reconnectWindowMinutes > 0) connectionLines.push(`🔌 Reconnection window: ${r.connection.reconnectWindowMinutes} minutes`);
    connectionLines.push(r.connection.replayAllowed ? '🔁 Replays are allowed.' : '🚫 Replays are not allowed.');
    if (r.connection.evidenceRequired) connectionLines.push('📸 Evidence is required.');
    if (r.connection.decidedBy.trim()) connectionLines.push(`⚖️ Outcome decided by: ${r.connection.decidedBy.trim()}`);
    if (r.connection.repeatedDisconnectionConsequence.trim()) {
      connectionLines.push(`⚠️ Repeated disconnections: ${r.connection.repeatedDisconnectionConsequence.trim()}`);
    }
  }

  const noShowLines: string[] = [];
  if (r.noShow.waitingPeriodMinutes > 0) noShowLines.push(`⏳ Waiting period before forfeit: ${r.noShow.waitingPeriodMinutes} minutes`);
  if (r.noShow.warningBeforeForfeit) noShowLines.push('⚠️ A warning is given before forfeit.');
  if (r.noShow.autoForfeit) noShowLines.push('🚫 Automatic forfeit applies.');
  if (r.noShow.forfeitScore.trim()) noShowLines.push(`📉 Forfeit score: ${r.noShow.forfeitScore.trim()}`);
  if (r.noShow.missedMatchesAllowed > 0) noShowLines.push(`🔁 Missed matches allowed: ${r.noShow.missedMatchesAllowed}`);
  if (r.noShow.disqualificationThreshold > 0) noShowLines.push(`❌ Disqualification after: ${r.noShow.disqualificationThreshold} missed matches`);

  const resultsLines: string[] = [`📝 Result submission: ${resultSubmissionModeDisplayName[r.resultSubmission.mode]}`];
  if (r.resultSubmission.screenshotRequired) resultsLines.push('📸 Screenshot required.');
  if (r.resultSubmission.videoRequired) resultsLines.push('🎥 Video evidence required.');
  if (r.resultSubmission.submissionDeadlineHours > 0) resultsLines.push(`⏰ Submission deadline: ${durationLabel(r.resultSubmission.submissionDeadlineHours)}`);
  if (r.resultSubmission.disputeWindowHours > 0) resultsLines.push(`⏳ Dispute window: ${durationLabel(r.resultSubmission.disputeWindowHours)}`);
  if (r.evidence.acceptedTypes.length > 0) {
    resultsLines.push(`📂 Accepted evidence: ${r.evidence.acceptedTypes.map((t) => t.replace(/_/g, ' ')).join(', ')}`);
  }

  const eligibilityLines: string[] = [];
  if (r.eligibility.ageRestriction.trim()) eligibilityLines.push(`🔞 Age restriction: ${r.eligibility.ageRestriction.trim()}`);
  if (r.eligibility.rosterNotes.trim()) eligibilityLines.push(`📋 ${r.eligibility.rosterNotes.trim()}`);
  if (!r.eligibility.duplicateTeamsAllowed) eligibilityLines.push('🚫 Duplicate teams are not allowed.');
  if (r.eligibility.registrationDeadline.trim()) eligibilityLines.push(`📅 Registration deadline: ${r.eligibility.registrationDeadline.trim()}`);
  if (r.eligibility.notes.trim()) eligibilityLines.push(r.eligibility.notes.trim());

  const fairPlayLines: string[] = [
    ...r.fairPlay.enabledStandardRuleKeys
      .map((key) => FAIR_PLAY_RULE_LABELS[key])
      .filter((label): label is string => Boolean(label))
      .map((label) => `✔️ ${label}`),
    ...r.fairPlay.customRules.map((c) => `• ${c}`),
  ];

  const disputesLines: string[] = [];
  if (r.disputes.disputeWindowHours > 0) disputesLines.push(`⏳ Dispute window: ${durationLabel(r.disputes.disputeWindowHours)}`);
  if (r.disputes.whoCanSubmit.trim()) disputesLines.push(`🙋 Who can dispute: ${r.disputes.whoCanSubmit.trim()}`);
  if (r.disputes.evidenceRequired) disputesLines.push('📸 Evidence required for disputes.');
  if (r.disputes.finalDecisionAuthority.trim()) disputesLines.push(`⚖️ Final decision: ${r.disputes.finalDecisionAuthority.trim()}`);

  return (
    <div className="max-w-2xl mx-auto flex flex-col h-full px-4 pt-6">
      <div className="flex-1 overflow-y-auto pb-4">
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 mb-3">
          <p className="text-white font-black text-lg">📜 Match Rules</p>
          <p className="text-xs text-gray-400 font-semibold mt-1.5">Please review this competition&apos;s rules before continuing.</p>
        </div>

        <Card emoji="⏱️" title="Scheduling" lines={schedulingLines} />
        <Card emoji="⚙️" title="Match Settings" lines={matchSettingsLines} />
        <Card emoji="🎮" title="Gameplay Rules" lines={gameplayLines} />
        <Card emoji="🔌" title="Connection & Disconnection" lines={connectionLines} />
        <Card emoji="⚖️" title="No-Show & Forfeit" lines={noShowLines} />
        <Card emoji="📋" title="Results & Evidence" lines={resultsLines} />
        <Card emoji="🧑‍🤝‍🧑" title="Eligibility" lines={eligibilityLines} />
        <Card emoji="🤝" title="Fair Play & Conduct" lines={fairPlayLines} />
        <Card emoji="📢" title="Disputes & Appeals" lines={disputesLines} />
      </div>

      <div className="py-4">
        <button
          onClick={continueToLeague}
          className="w-full py-4 bg-[#BEF264] text-[#0F172A] rounded-xl font-black text-sm hover:brightness-110 flex items-center justify-center gap-2"
        >
          <CheckCircle2 className="w-5 h-5" /> Continue to League
        </button>
      </div>
    </div>
  );
}
