import { collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, runTransaction, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { KnockoutMatch } from '@/types/match';

// ── MATCH & KNOCKOUT UPDATES ─────────────────────────────────────────────────

export async function updateMatchScoreWeb(leagueId: string, matchId: string, homeScore: number, awayScore: number) {
  const matchRef = doc(db, 'leagues', leagueId, 'matches', matchId);
  await updateDoc(matchRef, {
    homeScore,
    awayScore,
    status: 'completed',
    isPlayed: true,
    updatedAtMs: Date.now()
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
