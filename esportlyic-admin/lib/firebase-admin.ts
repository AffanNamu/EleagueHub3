// lib/firebase-admin.ts
//
// Server-only Firebase Admin SDK initialization. This is the ONLY code
// path in the admin workspace allowed to bypass Firestore rules and set
// custom claims — mirrors what the Cloudflare Worker's
// _setFirebaseCustomClaims does for the mobile app's entitlement flow.
//
// NEVER import this file from a Client Component. It reads a service
// account private key from environment variables and must only run in
// Next.js Route Handlers, Server Components, Server Actions, or
// middleware running on the Node.js runtime.

import { cert, getApps, getApp, initializeApp, type App } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';

function buildAdminApp(): App {
  if (getApps().length) return getApp();

  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL;
  const rawPrivateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY;

  if (!projectId || !clientEmail || !rawPrivateKey) {
    throw new Error(
      'Missing Firebase Admin credentials. Set FIREBASE_ADMIN_PROJECT_ID, ' +
        'FIREBASE_ADMIN_CLIENT_EMAIL, and FIREBASE_ADMIN_PRIVATE_KEY.',
    );
  }

  // Env vars store the private key with literal \n sequences — must be
  // unescaped back into real newlines or the PEM parser rejects it.
  const privateKey = rawPrivateKey.replace(/\\n/g, '\n');

  return initializeApp({
    credential: cert({ projectId, clientEmail, privateKey }),
  });
}

const adminApp = buildAdminApp();

export const adminAuth = getAdminAuth(adminApp);
export const adminDb = getAdminFirestore(adminApp);
