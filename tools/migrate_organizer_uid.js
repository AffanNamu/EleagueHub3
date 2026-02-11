const admin = require('firebase-admin');
const path = require('path');

async function main() {
  const saPath = process.argv[2];
  if (!saPath) {
    console.error('Usage: node tools/migrate_organizer_uid.js serviceAccount.json');
    process.exit(1);
  }

  const serviceAccount = require(path.resolve(saPath));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const leaguesSnap = await db.collection('leagues').get();

  let updated = 0;
  let skipped = 0;
  let notFound = 0;
  let errors = 0;

  for (const doc of leaguesSnap.docs) {
    const data = doc.data() || {};
    const leagueId = doc.id;

    try {
      if (typeof data.organizerUid === 'string' && data.organizerUid.trim()) {
        skipped++;
        continue;
      }

      const organizerUserId = (data.organizerUserId || '').toString().trim();
      if (!organizerUserId) {
        notFound++;
        console.log(`[NOT FOUND] league=${leagueId} reason=missing organizerUserId`);
        continue;
      }

      // If organizerUserId already looks like Firebase UID
      if (organizerUserId.length > 20) {
        await doc.ref.set({ organizerUid: organizerUserId }, { merge: true });
        updated++;
        console.log(`[OK] league=${leagueId} organizerUid=${organizerUserId} (organizerUserId looked like UID)`);
        continue;
      }

      // Preferred: users.shareId == organizerUserId
      const users = await db.collection('users').where('shareId', '==', organizerUserId).limit(1).get();
      if (!users.empty) {
        const uid = users.docs[0].id;
        await doc.ref.set({ organizerUid: uid }, { merge: true });
        updated++;
        console.log(`[OK] league=${leagueId} organizerUid=${uid} (from shareId=${organizerUserId})`);
        continue;
      }

      // Fallback UID-like fields if they exist
      const ownerId = (data.ownerId || '').toString().trim();
      const ownerUid = (data.ownerUid || '').toString().trim();
      const createdByUid = (data.createdByUid || '').toString().trim();

      const fallbackUid =
        (ownerUid.length > 20 ? ownerUid : '') ||
        (ownerId.length > 20 ? ownerId : '') ||
        (createdByUid.length > 20 ? createdByUid : '');

      if (fallbackUid) {
        await doc.ref.set({ organizerUid: fallbackUid }, { merge: true });
        updated++;
        console.log(`[OK] league=${leagueId} organizerUid=${fallbackUid} (fallback; shareId=${organizerUserId} not matched)`);
        continue;
      }

      notFound++;
      console.log(`[NOT FOUND] league=${leagueId} organizerUserId=${organizerUserId} (no users.shareId match, no fallback uid fields)`);
    } catch (e) {
      errors++;
      console.log(`[ERROR] league=${leagueId} ${e && e.message ? e.message : String(e)}`);
    }
  }

  console.log('--- DONE migrate_organizer_uid ---');
  console.log({ updated, skipped, notFound, errors, total: leaguesSnap.size });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
