// app/api/leagues/[id]/matches/[matchId]/poster/route.tsx
//
// Generates a Match Poster PNG on the fly. Rendered server-side with
// next/og's ImageResponse (Satori) — no new dependency, ships with
// Next.js. Chosen over DOM-screenshot libraries (html2canvas etc.)
// specifically to sidestep canvas-tainting from cross-origin Cloudinary
// images and font/CSS-support gaps in those libraries.
//
// GET /api/leagues/{leagueId}/matches/{matchId}/poster
//   ?format=portrait|square|story   (default: portrait)
//   &dateTime=...                    (optional, organizer-entered, ≤40 chars)
//   &venue=...                       (optional, organizer-entered, ≤40 chars)
//
// All match/team/competition content is re-derived from Firestore using
// only leagueId + matchId — a caller cannot spoof team names/images via
// query params, only the two free-text extras above.

import { ImageResponse } from 'next/og';
import { NextRequest } from 'next/server';
import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { leagueFromRemoteMap } from '@/lib/models/league';
import { FixtureMatch, Team } from '@/lib/models/leagueDetails';
import { cloudinaryOptimizedUrl } from '@/lib/cloudinary/cloudinaryUpload';
import {
  MATCH_POSTER_SIZES,
  MatchPosterFormat,
  MatchPosterData,
  MatchPosterTeamData,
  isMatchPosterFormat,
} from '@/lib/models/matchPoster';

// Needs the Node.js runtime (not Edge) so we can reuse the existing
// Firebase client SDK the rest of the app already uses for these exact
// reads (see lib/leagues/leagueDetailsRepository.ts).
export const runtime = 'nodejs';

// TODO: replace with the real `brand-lime` hex from tailwind.config —
// Satori/ImageResponse cannot consume Tailwind classes, only literal
// style values, so this placeholder needs to match your actual brand
// color. NAVY values below ARE the real ones (confirmed in globals.css).
const LIME = '#BFFF5C';
const NAVY_TOP = '#0A0F0B';
const NAVY_MID = '#121A14';
const NAVY_BOTTOM = '#0A0F0B';
const NAVY_TEXT_ON_LIME = '#081120';

// ── category label — mirrors LeagueDetailScreenClient.tsx's
// getCategoryLabel() exactly, so the poster and the league page never
// disagree on how a footballCategory value is displayed. "Local
// Football" (the default) is intentionally omitted — not worth a chip.
function categoryLabel(cat: unknown): string | undefined {
  if (cat === 1 || cat === 'eFootball') return 'eFootball';
  if (cat === 2 || cat === 'eaSportsFc') return 'EA SPORTS FC';
  if (cat === 3 || cat === 'eaSportsFcMobile') return 'FC Mobile';
  if (cat === 4 || cat === 'dreamLeagueSoccer') return 'Dream League Soccer';
  if (cat === 5 || cat === 'totalFootball') return 'Total Football';
  return undefined;
}

async function buildData(
  leagueId: string,
  matchId: string,
  dateTimeLabel?: string,
  venueLabel?: string,
): Promise<MatchPosterData> {
  const leagueSnap = await getDoc(doc(db, 'leagues', leagueId));
  if (!leagueSnap.exists()) throw new Error('League not found');
  const league = leagueFromRemoteMap({ ...leagueSnap.data(), id: leagueSnap.id });

  const matchSnap = await getDoc(doc(db, 'leagues', leagueId, 'matches', matchId));
  if (!matchSnap.exists()) throw new Error('Match not found');
  const match = { ...matchSnap.data(), id: matchSnap.id } as FixtureMatch;

  const [homeSnap, awaySnap] = await Promise.all([
    match.homeTeamId
      ? getDoc(doc(db, 'leagues', leagueId, 'teams', match.homeTeamId))
      : Promise.resolve(null),
    match.awayTeamId
      ? getDoc(doc(db, 'leagues', leagueId, 'teams', match.awayTeamId))
      : Promise.resolve(null),
  ]);

  const homeTeam = homeSnap && homeSnap.exists() ? (homeSnap.data() as Team) : null;
  const awayTeam = awaySnap && awaySnap.exists() ? (awaySnap.data() as Team) : null;

  let roundLabel: string | undefined;
  if (match.roundNumber > 0) roundLabel = `Round ${match.roundNumber}`;
  if (match.groupId) {
    roundLabel = roundLabel ? `Group ${match.groupId} • ${roundLabel}` : `Group ${match.groupId}`;
  }

  const homeImg = homeTeam?.teamImageUrl
    ? cloudinaryOptimizedUrl(homeTeam.teamImageUrl, { width: 336, height: 336 })
    : '';
  const awayImg = awayTeam?.teamImageUrl
    ? cloudinaryOptimizedUrl(awayTeam.teamImageUrl, { width: 336, height: 336 })
    : '';
  const logoImg = league.leagueImageUrl
    ? cloudinaryOptimizedUrl(league.leagueImageUrl, { width: 144, height: 144 })
    : '';

  return {
    competitionName: league.name || 'League',
    competitionLogoUrl: logoImg,
    season: league.season || undefined,
    footballCategory: categoryLabel(league.footballCategory),
    home: { name: (homeTeam?.name || '').trim() || 'TBD', imageUrl: homeImg },
    away: { name: (awayTeam?.name || '').trim() || 'TBD', imageUrl: awayImg },
    roundLabel,
    dateTimeLabel: dateTimeLabel?.trim().slice(0, 40) || undefined,
    venueLabel: venueLabel?.trim().slice(0, 40) || undefined,
  };
}

function TeamColumn({ team }: { team: MatchPosterTeamData }) {
  const size = 168;
  const initial = (team.name || '?').trim().charAt(0).toUpperCase() || '?';

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        width: 380,
      }}
    >
      <div
        style={{
          display: 'flex',
          width: size,
          height: size,
          borderRadius: 999,
          border: `3px solid rgba(191,255,92,0.55)`,
          backgroundColor: 'rgba(255,255,255,0.06)',
          alignItems: 'center',
          justifyContent: 'center',
          overflow: 'hidden',
        }}
      >
        {team.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={team.imageUrl}
            width={size}
            height={size}
            style={{ objectFit: 'cover', borderRadius: 999 }}
          />
        ) : (
          <div
            style={{
              display: 'flex',
              color: 'rgba(255,255,255,0.35)',
              fontSize: 72,
              fontWeight: 900,
            }}
          >
            {initial}
          </div>
        )}
      </div>
      <div
        style={{
          display: 'flex',
          marginTop: 18,
          color: '#FFFFFF',
          fontSize: 24,
          fontWeight: 900,
          textAlign: 'center',
          letterSpacing: 0.4,
        }}
      >
        {team.name.toUpperCase()}
      </div>
    </div>
  );
}

function VsBadge() {
  return (
    <div style={{ display: 'flex', margin: '0 10px' }}>
      <div
        style={{
          display: 'flex',
          width: 64,
          height: 64,
          borderRadius: 999,
          backgroundColor: LIME,
          alignItems: 'center',
          justifyContent: 'center',
          color: NAVY_TEXT_ON_LIME,
          fontSize: 20,
          fontWeight: 900,
        }}
      >
        VS
      </div>
    </div>
  );
}

function DetailChip({ label }: { label: string }) {
  return (
    <div
      style={{
        display: 'flex',
        padding: '7px 12px',
        margin: 4,
        borderRadius: 999,
        backgroundColor: 'rgba(255,255,255,0.06)',
        border: '1px solid rgba(255,255,255,0.14)',
        color: 'rgba(255,255,255,0.85)',
        fontSize: 13,
        fontWeight: 700,
      }}
    >
      {label}
    </div>
  );
}

function renderPosterElement(data: MatchPosterData) {
  const hasDetails = Boolean(data.dateTimeLabel || data.venueLabel || data.footballCategory);

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: '64px 56px 48px 56px',
        backgroundImage: `linear-gradient(to bottom, ${NAVY_TOP} 0%, ${NAVY_MID} 50%, ${NAVY_BOTTOM} 100%)`,
        fontFamily: 'sans-serif',
      }}
    >
      {/* Header */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        {data.competitionLogoUrl ? (
          <div style={{ display: 'flex', marginBottom: 14 }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={data.competitionLogoUrl}
              width={72}
              height={72}
              style={{ borderRadius: 999 }}
            />
          </div>
        ) : null}
        <div
          style={{
            display: 'flex',
            color: '#FFFFFF',
            fontSize: 34,
            fontWeight: 900,
            letterSpacing: 1.1,
            textAlign: 'center',
          }}
        >
          {data.competitionName.toUpperCase()}
        </div>
        {data.season ? (
          <div
            style={{
              display: 'flex',
              color: 'rgba(255,255,255,0.55)',
              fontSize: 16,
              fontWeight: 700,
              marginTop: 6,
              letterSpacing: 1.4,
            }}
          >
            {data.season}
          </div>
        ) : null}
        {data.roundLabel ? (
          <div
            style={{
              display: 'flex',
              marginTop: 16,
              padding: '8px 16px',
              borderRadius: 999,
              backgroundColor: 'rgba(191,255,92,0.12)',
              border: `1px solid rgba(191,255,92,0.35)`,
              color: LIME,
              fontSize: 14,
              fontWeight: 900,
              letterSpacing: 1.2,
            }}
          >
            {data.roundLabel.toUpperCase()}
          </div>
        ) : null}
      </div>

      {/* Matchup */}
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <TeamColumn team={data.home} />
        <VsBadge />
        <TeamColumn team={data.away} />
      </div>

      {/* Footer */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        {hasDetails ? (
          <div
            style={{
              display: 'flex',
              flexDirection: 'row',
              flexWrap: 'wrap',
              justifyContent: 'center',
              marginBottom: 24,
            }}
          >
            {data.dateTimeLabel ? <DetailChip label={data.dateTimeLabel} /> : null}
            {data.venueLabel ? <DetailChip label={data.venueLabel} /> : null}
            {data.footballCategory ? <DetailChip label={data.footballCategory} /> : null}
          </div>
        ) : null}
        <div
          style={{
            display: 'flex',
            width: 120,
            height: 1,
            backgroundColor: 'rgba(255,255,255,0.14)',
            marginBottom: 14,
          }}
        />
        <div
          style={{
            display: 'flex',
            color: LIME,
            fontSize: 18,
            fontWeight: 900,
            letterSpacing: 3,
          }}
        >
          eSPORTLYIC
        </div>
      </div>
    </div>
  );
}

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; matchId: string }> },
) {
  const { id: leagueId, matchId } = await params;
  const url = new URL(req.url);

  const formatParam = url.searchParams.get('format');
  const format: MatchPosterFormat = isMatchPosterFormat(formatParam) ? formatParam : 'portrait';
  const dateTimeLabel = url.searchParams.get('dateTime') ?? undefined;
  const venueLabel = url.searchParams.get('venue') ?? undefined;

  const size = MATCH_POSTER_SIZES[format];

  let data: MatchPosterData;
  try {
    data = await buildData(leagueId, matchId, dateTimeLabel, venueLabel);
  } catch (err) {
    console.error('[match poster route] failed to build data:', err);
    return new Response('Could not generate a poster for this match.', { status: 404 });
  }

  return new ImageResponse(renderPosterElement(data), {
    width: size.width,
    height: size.height,
  });
}
