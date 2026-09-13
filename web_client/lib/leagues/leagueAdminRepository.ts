import { collection, doc, getDoc, getDocs, setDoc, deleteDoc, runTransaction, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { KnockoutMatch } from '@/lib/models/leagueDetails';

// ── MATCH & KNOCKOUT UPDATES ─────────────────────────────────────────────────
//
// Mirrors LocalLeaguesRepository (lib/features/leagues/data/leagues_repository_local.dart)'s
// updateMatchScoreAndUpdateTeamAggregates() + ensureTeamAggregatesBackfilled().
// The previous updateMatchScoreWeb only wrote homeScore/awayScore/status to
// the match doc and never touched the team docs at all — team.basePoints/
// goalDifference/goalsFor stayed frozen at whatever they were initialized to
// (usually 0) forever. StandingsTable itself is unaffected (standingsEngine.ts
// already recomputes those fields fresh from the match list), but
// knockoutGeneration.ts's group-stage seeding and admin/knockout-draw's sort
// both read team.finalPoints/goalDifference/goalsFor directly off the raw
// team doc — so knockout brackets were being seeded from stale/zeroed
// standings instead of real ones.

function statusLooksPlayed(rawStatus: unknown): boolean {
  return rawStatus === 'completed' || rawStatus === 'played';
}

function matchPlayedFromMap(m: Record<string, unknown>): boolean {
  if (m.homeScore === null || m.homeScore === undefined) return false;
  if (m.awayScore === null || m.awayScore === undefined) return false;
  return statusLooksPlayed(m.status);
}

function pointsFor(scored: number, conceded: number): number {
  if (scored > conceded) return 3;
  if (scored === conceded) return 1;
  return 0;
}

/** Backfills basePoints/adminAdjustment/finalPoints/goalDifference/goalsFor
 * from the live match list, for leagues whose team docs predate this write
 * path (or were only ever touched by createPointAdjustmentWeb, which never
 * set basePoints/goalDifference/goalsFor). No-ops once every team has all
 * five fields. */
async function ensureTeamAggregatesBackfilledWeb(leagueId: string): Promise<void> {
  const teamsSnap = await getDocs(collection(db, 'leagues', leagueId, 'teams'));
  if (teamsSnap.empty) return;

  const needsBackfill = teamsSnap.docs.some((d) => {
    const data = d.data();
    return (
      typeof data.basePoints !== 'number' ||
      typeof data.adminAdjustment !== 'number' ||
      typeof data.finalPoints !== 'number' ||
      typeof data.goalDifference !== 'number' ||
      typeof data.goalsFor !== 'number'
    );
  });
  if (!needsBackfill) return;

  const matchesSnap = await getDocs(collection(db, 'leagues', leagueId, 'matches'));

  const basePointsByTeam: Record<string, number> = {};
  const gdByTeam: Record<string, number> = {};
  const gfByTeam: Record<string, number> = {};

  for (const d of matchesSnap.docs) {
    const m = d.data();
    if (!matchPlayedFromMap(m)) continue;

    const homeId = String(m.homeTeamId || '').trim();
    const awayId = String(m.awayTeamId || '').trim();
    if (!homeId || !awayId) continue;

    const hs = Number(m.homeScore);
    const as = Number(m.awayScore);

    basePointsByTeam[homeId] = (basePointsByTeam[homeId] || 0) + pointsFor(hs, as);
    basePointsByTeam[awayId] = (basePointsByTeam[awayId] || 0) + pointsFor(as, hs);

    gfByTeam[homeId] = (gfByTeam[homeId] || 0) + hs;
    gfByTeam[awayId] = (gfByTeam[awayId] || 0) + as;

    gdByTeam[homeId] = (gdByTeam[homeId] || 0) + (hs - as);
    gdByTeam[awayId] = (gdByTeam[awayId] || 0) + (as - hs);
  }

  const now = Date.now();
  const chunkSize = 400;
  for (let i = 0; i < teamsSnap.docs.length; i += chunkSize) {
    const batch = writeBatch(db);
    for (const d of teamsSnap.docs.slice(i, i + chunkSize)) {
      const teamId = d.id;
      const base = basePointsByTeam[teamId] || 0;
      const adj = Number(d.data().adminAdjustment || 0);
      batch.set(
        d.ref,
        {
          basePoints: base,
          adminAdjustment: adj,
          finalPoints: base + adj,
          goalDifference: gdByTeam[teamId] || 0,
          goalsFor: gfByTeam[teamId] || 0,
          updatedAtMs: now,
        },
        { merge: true },
      );
    }
    await batch.commit();
  }
}

export async function updateMatchScoreWeb(leagueId: string, matchId: string, homeScore: number, awayScore: number) {
  await ensureTeamAggregatesBackfilledWeb(leagueId);

  const matchRef = doc(db, 'leagues', leagueId, 'matches', matchId);
  const now = Date.now();
  const hsNew = homeScore < 0 ? 0 : homeScore;
  const asNew = awayScore < 0 ? 0 : awayScore;

  await runTransaction(db, async (txn) => {
    const matchSnap = await txn.get(matchRef);
    if (!matchSnap.exists()) throw new Error("We couldn't find this match. Please refresh and try again.");

    const matchData = matchSnap.data();
    const homeId = String(matchData.homeTeamId || '').trim();
    const awayId = String(matchData.awayTeamId || '').trim();
    if (!homeId || !awayId) {
      throw new Error('This match is missing team information. Please refresh and try again.');
    }

    const hsOld = typeof matchData.homeScore === 'number' ? matchData.homeScore : undefined;
    const asOld = typeof matchData.awayScore === 'number' ? matchData.awayScore : undefined;
    const oldPlayed = hsOld !== undefined && asOld !== undefined && statusLooksPlayed(matchData.status);

    const oldHomePts = oldPlayed ? pointsFor(hsOld, asOld) : 0;
    const oldAwayPts = oldPlayed ? pointsFor(asOld, hsOld) : 0;
    const oldHomeGf = oldPlayed ? hsOld : 0;
    const oldAwayGf = oldPlayed ? asOld : 0;
    const oldHomeGd = oldPlayed ? hsOld - asOld : 0;
    const oldAwayGd = oldPlayed ? asOld - hsOld : 0;

    const newHomePts = pointsFor(hsNew, asNew);
    const newAwayPts = pointsFor(asNew, hsNew);
    const newHomeGf = hsNew;
    const newAwayGf = asNew;
    const newHomeGd = hsNew - asNew;
    const newAwayGd = asNew - hsNew;

    const deltaHomePts = newHomePts - oldHomePts;
    const deltaAwayPts = newAwayPts - oldAwayPts;
    const deltaHomeGf = newHomeGf - oldHomeGf;
    const deltaAwayGf = newAwayGf - oldAwayGf;
    const deltaHomeGd = newHomeGd - oldHomeGd;
    const deltaAwayGd = newAwayGd - oldAwayGd;

    const homeRef = doc(db, 'leagues', leagueId, 'teams', homeId);
    const awayRef = doc(db, 'leagues', leagueId, 'teams', awayId);

    const homeSnap = await txn.get(homeRef);
    const awaySnap = await txn.get(awayRef);
    if (!homeSnap.exists() || !awaySnap.exists()) {
      throw new Error("We couldn't find one of the teams for this match. Please refresh and try again.");
    }

    const homeData = homeSnap.data();
    const awayData = awaySnap.data();

    const homeBase = Number(homeData.basePoints || 0);
    const awayBase = Number(awayData.basePoints || 0);
    const homeAdj = Number(homeData.adminAdjustment || 0);
    const awayAdj = Number(awayData.adminAdjustment || 0);
    const homeGd = Number(homeData.goalDifference || 0);
    const awayGd = Number(awayData.goalDifference || 0);
    const homeGf = Number(homeData.goalsFor || 0);
    const awayGf = Number(awayData.goalsFor || 0);

    const nextHomeBase = Math.max(0, homeBase + deltaHomePts);
    const nextAwayBase = Math.max(0, awayBase + deltaAwayPts);
    const nextHomeGf = Math.max(0, homeGf + deltaHomeGf);
    const nextAwayGf = Math.max(0, awayGf + deltaAwayGf);
    const nextHomeGd = homeGd + deltaHomeGd;
    const nextAwayGd = awayGd + deltaAwayGd;

    txn.update(matchRef, {
      homeScore: hsNew,
      awayScore: asNew,
      status: 'completed',
      isPlayed: true,
      updatedAtMs: now,
    });

    txn.update(homeRef, {
      basePoints: nextHomeBase,
      adminAdjustment: homeAdj,
      finalPoints: nextHomeBase + homeAdj,
      goalDifference: nextHomeGd,
      goalsFor: nextHomeGf,
      updatedAtMs: now,
    });

    txn.update(awayRef, {
      basePoints: nextAwayBase,
      adminAdjustment: awayAdj,
      finalPoints: nextAwayBase + awayAdj,
      goalDifference: nextAwayGd,
      goalsFor: nextAwayGf,
      updatedAtMs: now,
    });
  });
}

export async function saveKnockoutMatchesWeb(leagueId: string, matches: Partial<KnockoutMatch>[]) {
  const batch = writeBatch(db);
  for (const m of matches) {
    if (!m.id) continue;
    const ref = doc(db, 'leagues', leagueId, 'knockout', m.id);
    batch.set(ref, m, { merge: true });
  }
  await batch.commit();
}

// ── POINT ADJUSTMENTS ────────────────────────────────────────────────────────
export async function createPointAdjustmentWeb({ leagueId, teamId, type, points, reason, authUid }: any) {
  await ensureTeamAggregatesBackfilledWeb(leagueId);

  const now = Date.now();
  const adjustmentRef = doc(collection(db, 'leagues', leagueId, 'pointAdjustments'));
  const teamRef = doc(db, 'leagues', leagueId, 'teams', teamId);

  await runTransaction(db, async (tx) => {
    const teamSnap = await tx.get(teamRef);
    if (!teamSnap.exists()) throw new Error('Team not found');

    const teamData = teamSnap.data();
    const currentAdj = Number(teamData.adminAdjustment || 0);
    const currentBase = Number(teamData.basePoints || 0);

    const delta = type === 'addition' ? points : -points;
    const newAdj = currentAdj + delta;
    const newFinal = currentBase + newAdj;

    tx.set(adjustmentRef, {
      id: adjustmentRef.id,
      leagueId,
      teamId,
      type: type === 'addition' ? 'addition' : 'deduction',
      points,
      reason,
      adjustedBy: authUid,
      createdAtMs: now,
      createdAt: new Date(now), 
    });

    tx.update(teamRef, {
      adminAdjustment: newAdj,
      finalPoints: newFinal,
      updatedAtMs: now,
    });
  });
}

// ── ANNOUNCEMENTS ────────────────────────────────────────────────────────────
export async function sendAnnouncementWeb(leagueId: string, title: string, message: string, authUid: string) {
  const annRef = doc(collection(db, 'leagues', leagueId, 'announcements'));
  const now = Date.now();
  await setDoc(annRef, {
    id: annRef.id,
    leagueId,
    masterLeagueId: '',
    scope: 'league',
    title: title.trim(),
    message: message.trim(),
    createdAtMs: now,
    authorId: authUid,
    authorName: '',
    pinned: false,
    pinnedAtMs: 0,
    pinnedBy: '',
  });
}

// ── ROSTER CSV EXPORTER ──────────────────────────────────────────────────────
export async function generateRosterCsvString(leagueId: string): Promise<string> {
  const teamsSnap = await getDocs(collection(db, 'leagues', leagueId, 'teams'));
  const membershipsSnap = await getDocs(collection(db, 'leagues', leagueId, 'memberships'));

  const teams: any[] = [];
  const teamIds = new Set<string>();
  teamsSnap.forEach(d => { teams.push(d.data()); teamIds.add(d.id); });

  const orphanIds = new Set<string>();
  membershipsSnap.forEach(d => {
    const m = d.data();
    if (m.role === 1 && (!m.teamId || m.teamId.trim() === '')) {
      if (!teamIds.has(m.userId)) orphanIds.add(m.userId);
    }
  });

  let csv = 'userIdOrShareId,teamName,group\n';
  const escape = (str: string) => {
    if (!str) return '';
    if (str.includes(',') || str.includes('"') || str.includes('\n')) return `"${str.replace(/"/g, '""')}"`;
    return str;
  };

  for (const t of teams) csv += `${escape(t.id)},${escape(t.name)},${escape(t.groupId || '')}\n`;
  for (const uid of orphanIds) csv += `${escape(uid)},,\n`;
  
  return csv;
}

// ── LIVE SPACE CONTROLLER ────────────────────────────────────────────────────
export async function toggleSpaceStatusWeb(leagueId: string, isLive: boolean, authUid: string, leagueName: string) {
  const spaceRef = doc(db, 'leagues', leagueId, 'space', 'current');
  const now = Date.now();

  if (isLive) {
    await setDoc(spaceRef, {
      leagueId, hostUserId: authUid, hostUid: authUid,
      title: `${leagueName} Live Space`, isLive: true,
      startedAtMs: now, updatedAtMs: now,
    }, { merge: true });
  } else {
    await setDoc(spaceRef, { isLive: false, endedAtMs: now, updatedAtMs: now }, { merge: true });
  }
}

export async function deleteLeagueWeb(leagueId: string) {
  await deleteDoc(doc(db, 'leagues', leagueId));
}

// ── COUPON CONFIG ────────────────────────────────────────────────────────────
export async function ensureCouponConfigWeb(leagueId: string, authUid: string) {
  const ref = doc(db, 'leagues', leagueId, 'couponConfig', 'config');
  
  await runTransaction(db, async (tx) => {
    const cfgSnap = await tx.get(ref);
    const nowMs = Date.now();

    if (cfgSnap.exists()) {
      const cfg = cfgSnap.data();
      if (typeof cfg.qtyRemaining !== 'number') {
        const prevUpdated = Number(cfg.updatedAtMs || 0);
        tx.update(ref, {
          qtyRemaining: 0,
          updatedAtMs: nowMs > prevUpdated ? nowMs : prevUpdated + 1
        });
      }
      return;
    }

    const leagueSnap = await tx.get(doc(db, 'leagues', leagueId));
    if (!leagueSnap.exists()) throw new Error("League not found.");
    const ld = leagueSnap.data();

    const isOwner = ld.organizerUid === authUid || ld.ownerUid === authUid || ld.organizerUserId === authUid || ld.ownerId === authUid;
    if (!isOwner) throw new Error("Permission denied.");

    const settings = ld.settings || {};
    let currency = (ld.currency || settings.currency || 'USD').toUpperCase();
    if (currency !== 'NGN' && currency !== 'USD') currency = 'USD';

    let seededDiscount = 0;
    if (ld.couponDiscountPercent !== undefined && ld.couponDiscountPercent >= 0) seededDiscount = ld.couponDiscountPercent;
    else if (settings.couponDiscountPercent !== undefined && settings.couponDiscountPercent >= 0) seededDiscount = settings.couponDiscountPercent;
    else if (ld.userPaysPercent !== undefined && ld.userPaysPercent >= 0) seededDiscount = 100 - ld.userPaysPercent;
    else if (settings.userPaysPercent !== undefined && settings.userPaysPercent >= 0) seededDiscount = 100 - settings.userPaysPercent;
    seededDiscount = Math.max(0, Math.min(100, seededDiscount));

    const couponsEnabled = Boolean(ld.couponsEnabled || settings.couponsEnabled);
    const couponCount = Number(ld.couponCount || settings.couponCount || 0);
    const seedQty = (couponsEnabled && couponCount > 0) ? couponCount : 0;

    tx.set(ref, {
      leagueId, organizerUserId: authUid, currency,
      unitPrice: 1.0, effectiveUnit: 1.0, threshold: null,
      thresholdDiscountPercent: 30.0, discountPercent: seededDiscount,
      userPaysPercent: 100 - seededDiscount, organizerPaysPercent: 100,
      qtyTotal: seedQty, qtyRemaining: seedQty,
      createdAtMs: nowMs, updatedAtMs: nowMs, version: 1,
    });
  });
}

// ── COUPON CODES (WITH REAL PRICING MATH) ────────────────────────────────────
export async function generateCouponCodesWeb(leagueId: string, authUid: string, count: number, customCodeStr?: string): Promise<string[]> {
  const out: string[] = [];
  const customRaw = (customCodeStr || '').trim().toUpperCase();
  const isCustom = customRaw.length > 0;
  const effectiveCount = isCustom ? 1 : count;
  if (effectiveCount <= 0) return [];

  const generateRandomCode = () => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let res = 'ESL';
    for (let i = 0; i < 12; i++) res += chars.charAt(Math.floor(Math.random() * chars.length));
    return res;
  };

  if (isCustom) {
    let base = customRaw.replace(/[\s\-]+/g, '_').replace(/%/g, '').replace(/[^A-Z0-9_]+/g, '_').replace(/^_+|_+$/g, '');
    if (base.length < 2) throw new Error('Custom name too short');
    if (base.length > 40) throw new Error('Custom name too long');

    await runTransaction(db, async (tx) => {
      const cfgSnap = await tx.get(doc(db, 'leagues', leagueId, 'couponConfig', 'config'));
      if (!cfgSnap.exists()) throw new Error('noConfig');
      const cfg = cfgSnap.data();
      const remaining = Number(cfg.qtyRemaining || 0);
      if (remaining <= 0) throw new Error('noRemaining');

      const discountPercent = Number(cfg.discountPercent !== undefined ? cfg.discountPercent : Math.max(0, 100 - Number(cfg.userPaysPercent || 0)));
      const codeId = `ESL_${base}_${discountPercent}%`;
      const codeRef = doc(db, 'leagues', leagueId, 'couponCodes', codeId);
      const codeSnap = await tx.get(codeRef);
      if (codeSnap.exists()) throw new Error('customCollision');

      const pricingSnap = await tx.get(doc(db, 'app', 'pricing'));
      const pricingMap = pricingSnap.exists() ? pricingSnap.data() : {};
      const cfgCurrency = (cfg.currency || 'USD').toUpperCase();
      
      let accessFee = 0.0;
      let currencyUsed = cfgCurrency;

      const getAccessFee = (pMap: any, curr: string) => {
        const c = curr.toLowerCase();
        if (pMap[c] && typeof pMap[c].accessFee === 'number') return pMap[c].accessFee;
        if (pMap[c] && typeof pMap[c].accessFee === 'string') return parseFloat(pMap[c].accessFee) || 0.0;
        return 0.0;
      };

      accessFee = getAccessFee(pricingMap, cfgCurrency);
      if (accessFee <= 0) {
        const other = cfgCurrency === 'NGN' ? 'USD' : 'NGN';
        const otherFee = getAccessFee(pricingMap, other);
        if (otherFee > 0) { accessFee = otherFee; currencyUsed = other; }
      }
      if (accessFee <= 0) throw new Error('pricingMissing');

      const expectedRaw = accessFee * ((100 - discountPercent) / 100.0);
      const expectedAmount = currencyUsed === 'NGN' ? Math.round(expectedRaw) : Number(expectedRaw.toFixed(2));

      const nowMs = Date.now();
      const prevUpdated = Number(cfg.updatedAtMs || 0);
      const writeNowMs = nowMs > prevUpdated ? nowMs : prevUpdated + 1;

      tx.set(codeRef, {
        leagueId, organizerUserId: authUid, currency: currencyUsed,
        discountPercent, expectedAmount, usedBy: '', usedAtMs: 0,
        createdAtMs: writeNowMs, updatedAtMs: writeNowMs, version: 1,
      });

      tx.update(cfgSnap.ref, { qtyRemaining: remaining - 1, updatedAtMs: writeNowMs });
      out.push(codeId);
    });
    return out;
  }

  for (let i = 0; i < effectiveCount; i++) {
    let attempts = 0;
    while (true) {
      if (attempts > 10) throw new Error('Could not allocate unique code.');
      attempts++;
      const codeId = generateRandomCode();

      try {
        await runTransaction(db, async (tx) => {
          const cfgSnap = await tx.get(doc(db, 'leagues', leagueId, 'couponConfig', 'config'));
          if (!cfgSnap.exists()) throw new Error('noConfig');
          const cfg = cfgSnap.data();
          const remaining = Number(cfg.qtyRemaining || 0);
          if (remaining <= 0) throw new Error('noRemaining');

          const discountPercent = Number(cfg.discountPercent !== undefined ? cfg.discountPercent : Math.max(0, 100 - Number(cfg.userPaysPercent || 0)));
          const pricingSnap = await tx.get(doc(db, 'app', 'pricing'));
          const pricingMap = pricingSnap.exists() ? pricingSnap.data() : {};
          const cfgCurrency = (cfg.currency || 'USD').toUpperCase();
          
          let accessFee = 0.0;
          let currencyUsed = cfgCurrency;

          const getAccessFee = (pMap: any, curr: string) => {
            const c = curr.toLowerCase();
            if (pMap[c] && typeof pMap[c].accessFee === 'number') return pMap[c].accessFee;
            if (pMap[c] && typeof pMap[c].accessFee === 'string') return parseFloat(pMap[c].accessFee) || 0.0;
            return 0.0;
          };

          accessFee = getAccessFee(pricingMap, cfgCurrency);
          if (accessFee <= 0) {
            const other = cfgCurrency === 'NGN' ? 'USD' : 'NGN';
            const otherFee = getAccessFee(pricingMap, other);
            if (otherFee > 0) { accessFee = otherFee; currencyUsed = other; }
          }
          if (accessFee <= 0) throw new Error('pricingMissing');

          const expectedRaw = accessFee * ((100 - discountPercent) / 100.0);
          const expectedAmount = currencyUsed === 'NGN' ? Math.round(expectedRaw) : Number(expectedRaw.toFixed(2));

          const codeRef = doc(db, 'leagues', leagueId, 'couponCodes', codeId);
          const codeSnap = await tx.get(codeRef);
          if (codeSnap.exists()) throw new Error('collision');

          const nowMs = Date.now();
          const prevUpdated = Number(cfg.updatedAtMs || 0);
          const writeNowMs = nowMs > prevUpdated ? nowMs : prevUpdated + 1;

          tx.set(codeRef, {
            leagueId, organizerUserId: authUid, currency: currencyUsed,
            discountPercent, expectedAmount, usedBy: '', usedAtMs: 0,
            createdAtMs: writeNowMs, updatedAtMs: writeNowMs, version: 1,
          });

          tx.update(cfgSnap.ref, { qtyRemaining: remaining - 1, updatedAtMs: writeNowMs });
        });
        out.push(codeId);
        break;
      } catch (err: any) {
        if (err.message === 'collision') continue;
        throw err;
      }
    }
  }

  return out;
}
