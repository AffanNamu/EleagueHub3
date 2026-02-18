const admin = require('firebase-admin');
const path = require('path');

async function main() {
  const saPath = process.argv[2];
  if (!saPath) {
    console.error('Usage: node tools/migrate_organizer_uid.js serviceAccount.json');
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.cert(
      require(path.resolve(saPath))
    ),
  });

  const db = admin.firestore();

  console.log('Fetching all leagues...');
  const leaguesSnap = await db.collection('leagues').get();
  console.log(`Total leagues: ${leaguesSnap.size}`);

  let updated = 0;
  let alreadyOk = 0;
  let fixedFromMembership = 0;
  let fixedFromShareId = 0;
  let fixedFromOtherField = 0;
  let notResolved = 0;
  let errors = 0;

  for (const doc of leaguesSnap.docs) {
    const leagueId = doc.id;
    const data = doc.data() || {};

    try {
      // ── Already has valid organizerUid ──────────────────────────────────
      const existingOrgUid = (data.organizerUid || '').toString().trim();
      const existingOwnerUid = (data.ownerUid || '').toString().trim();

      if (existingOrgUid.length > 20 && existingOwnerUid.length > 20) {
        alreadyOk++;
        continue;
      }

      // We need to find the real Firebase UID of the organizer.
      // Try sources in order of reliability.
      let resolvedUid = '';

      // ── Source 1: organizerUid already present but ownerUid missing ─────
      if (existingOrgUid.length > 20) {
        resolvedUid = existingOrgUid;
      }

      // ── Source 2: ownerUid field ─────────────────────────────────────────
      if (!resolvedUid) {
        const ownerUid = (data.ownerUid || '').toString().trim();
        if (ownerUid.length > 20) resolvedUid = ownerUid;
      }

      // ── Source 3: ownerId field ──────────────────────────────────────────
      if (!resolvedUid) {
        const ownerId = (data.ownerId || '').toString().trim();
        if (ownerId.length > 20) resolvedUid = ownerId;
      }

      // ── Source 4: memberIds[0] if only one member (solo creator) ────────
      if (!resolvedUid) {
        const memberIds = data.memberIds;
        if (Array.isArray(memberIds) && memberIds.length === 1) {
          const first = (memberIds[0] || '').toString().trim();
          if (first.length > 20) resolvedUid = first;
        }
      }

      // ── Source 5: memberships subcollection role==0 (organizer) ─────────
      if (!resolvedUid) {
        try {
          const mSnap = await db
            .collection('leagues')
            .doc(leagueId)
            .collection('memberships')
            .where('role', '==', 0)
            .limit(1)
            .get();

          if (!mSnap.empty) {
            const mData = mSnap.docs[0].data();
            // userId field first, then doc id
            const fromUserId = (mData.userId || '').toString().trim();
            const fromDocId = mSnap.docs[0].id.trim();
            const candidate = fromUserId.length > 20 ? fromUserId : fromDocId;
            if (candidate.length > 20) {
              resolvedUid = candidate;
              fixedFromMembership++;
            }
          }
        } catch (e) {
          // memberships read failed — continue to next source
        }
      }

      // ── Source 6: resolve short shareId via users collection ─────────────
      if (!resolvedUid) {
        const shareId = (data.organizerUserId || '').toString().trim();
        if (shareId && shareId.length <= 20) {
          try {
            const uSnap = await db
              .collection('users')
              .where('shareId', '==', shareId)
              .limit(1)
              .get();

            if (!uSnap.empty) {
              resolvedUid = uSnap.docs[0].id.trim();
              fixedFromShareId++;
              console.log(
                `  [shareId resolved] league=${leagueId} shareId=${shareId} → uid=${resolvedUid}`
              );
            }
          } catch (e) {
            // users query failed
          }
        }
      }

      // ── Could not resolve ────────────────────────────────────────────────
      if (!resolvedUid) {
        notResolved++;
        console.log(
          `  [NOT RESOLVED] league=${leagueId} name="${data.name || ''}" ` +
          `organizerUserId="${data.organizerUserId || ''}" — manual fix needed`
        );
        continue;
      }

      // ── Patch the league doc ─────────────────────────────────────────────
      // Only adds organizerUid / ownerUid / ownerId.
      // Does NOT touch organizerUserId (short shareId) — that stays as-is
      // for display / backward compat.
      await doc.ref.set(
        {
          organizerUid: resolvedUid,
          ownerUid: resolvedUid,
          ownerId: resolvedUid,
        },
        { merge: true }
      );

      updated++;

      if (fixedFromMembership > (updated - fixedFromShareId - 1)) {
        console.log(`  [FIXED membership] league=${leagueId} uid=${resolvedUid}`);
      } else if (fixedFromShareId > 0 && resolvedUid) {
        // already logged above
      } else {
        fixedFromOtherField++;
        console.log(`  [FIXED field] league=${leagueId} uid=${resolvedUid}`);
      }
    } catch (e) {
      errors++;
      console.error(
        `  [ERROR] league=${leagueId}`,
        e && e.message ? e.message : String(e)
      );
    }
  }

  console.log('\n════════════════════════════════');
  console.log('MIGRATION COMPLETE');
  console.log('════════════════════════════════');
  console.log(`Total leagues:       ${leaguesSnap.size}`);
  console.log(`Already correct:     ${alreadyOk}`);
  console.log(`Fixed (total):       ${updated}`);
  console.log(`  via other fields:  ${fixedFromOtherField}`);
  console.log(`  via membership:    ${fixedFromMembership}`);
  console.log(`  via shareId:       ${fixedFromShareId}`);
  console.log(`Not resolved:        ${notResolved}`);
  console.log(`Errors:              ${errors}`);

  if (notResolved > 0) {
    console.log('');
    console.log('ACTION NEEDED for [NOT RESOLVED] leagues:');
    console.log('  1. Open Firebase Console → Firestore → leagues → {leagueId}');
    console.log('  2. Add field: organizerUid = <owner Firebase UID>');
    console.log('  3. Add field: ownerUid     = <owner Firebase UID>');
    console.log('  4. Add field: ownerId      = <owner Firebase UID>');
    console.log('  Find the owner UID in: Firebase Console → Authentication → Users');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
