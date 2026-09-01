// backfill.js
// One-time bulk fix: for every user whose `user_search` doc has a blank
// displayName, resolve their real name the same way profile_screen.dart
// does (profile.teamName first, then their Auth provider's displayName)
// and write it in. Safe to re-run — only touches docs still blank.

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

async function listAllAuthUsers() {
  const users = new Map(); // uid -> displayName
  let nextPageToken;
  do {
    const result = await auth.listUsers(1000, nextPageToken);
    for (const u of result.users) {
      users.set(u.uid, (u.displayName || '').trim());
    }
    nextPageToken = result.pageToken;
  } while (nextPageToken);
  return users;
}

async function main() {
  console.log('Fetching all Firebase Auth users…');
  const authUsers = await listAllAuthUsers();
  console.log(`Found ${authUsers.size} auth users.`);

  console.log('Fetching user_search collection…');
  const searchSnap = await db.collection('user_search').get();
  console.log(`Found ${searchSnap.size} user_search docs.`);

  let fixed = 0;
  let skippedAlreadySet = 0;
  let skippedNoName = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of searchSnap.docs) {
    const uid = doc.id;
    const data = doc.data();
    const existingName = (data.displayName || '').trim();

    if (existingName.length > 0) {
      skippedAlreadySet++;
      continue;
    }

    let resolvedName = '';
    try {
      const profileDoc = await db.collection('users').doc(uid).get();
      const teamName = (profileDoc.data()?.teamName || '').trim();
      if (teamName.length > 0) {
        resolvedName = teamName;
      }
    } catch (e) {
      console.warn(`  ! could not read profile for ${uid}: ${e.message}`);
    }

    if (resolvedName.length === 0) {
      resolvedName = authUsers.get(uid) || '';
    }

    if (resolvedName.length === 0) {
      skippedNoName++;
      continue;
    }

    batch.set(
      doc.ref,
      {
        displayName: resolvedName,
        displayNameLower: resolvedName.toLowerCase(),
        updatedAtMs: Date.now(),
      },
      { merge: true }
    );
    batchCount++;
    fixed++;

    console.log(`  fixing ${uid} -> "${resolvedName}"`);

    if (batchCount >= 400) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  console.log('---');
  console.log(`Fixed:                ${fixed}`);
  console.log(`Already had a name:   ${skippedAlreadySet}`);
  console.log(`No name available:    ${skippedNoName} (never set a team name AND no Auth display name)`);
  console.log('Done.');
}

main().catch((e) => {
  console.error('Backfill failed:', e);
  process.exit(1);
});
