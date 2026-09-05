// lib/repositories/dashboardRepository.ts
//
// Server-only aggregation queries backing the Dashboard. Every number
// here is a real Firestore count against a confirmed collection.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';

export interface DashboardStats {
  totalUsers: number;
  totalLeagues: number;
  totalMasterLeagues: number;
  pendingVerifications: number;
  pendingReports: number;
  pendingGlobalChatRequests: number;
  platformAdminCount: number;
}

async function countCollection(path: string): Promise<number> {
  const snap = await adminDb.collection(path).count().get();
  return snap.data().count;
}

async function countWhere(
  path: string,
  field: string,
  op: FirebaseFirestore.WhereFilterOp,
  value: unknown,
): Promise<number> {
  const snap = await adminDb.collection(path).where(field, op, value).count().get();
  return snap.data().count;
}

export async function getDashboardStats(): Promise<DashboardStats> {
  const [
    totalUsers,
    totalLeagues,
    totalMasterLeagues,
    pendingVerifications,
    pendingReports,
    pendingGlobalChatRequests,
    adminsDoc,
  ] = await Promise.all([
    countCollection('users'),
    countCollection('leagues'),
    countCollection('master_leagues'),
    countWhere('master_league_verification_requests', 'status', '==', 'pending'),
    countWhere('reports', 'status', '==', 'pending'),
    countWhere('globalChatRequests', 'status', '==', 'pending'),
    adminDb.collection('app').doc('admins').get(),
  ]);

  const pricingAdmins = adminsDoc.exists ? adminsDoc.data()?.pricingAdmins : undefined;
  const listedAdminCount = Array.isArray(pricingAdmins) ? pricingAdmins.length : 0;
  const platformAdminCount = listedAdminCount + 1;

  return {
    totalUsers,
    totalLeagues,
    totalMasterLeagues,
    pendingVerifications,
    pendingReports,
    pendingGlobalChatRequests,
    platformAdminCount,
  };
}

export interface RecentEvent {
  id: string;
  kind: 'verification_request' | 'report' | 'global_chat_request';
  title: string;
  detail: string;
  timestampMs: number;
}

export async function getRecentEvents(limit = 8): Promise<RecentEvent[]> {
  const [verificationSnap, reportSnap, chatRequestSnap] = await Promise.all([
    adminDb.collection('master_league_verification_requests').orderBy('submittedAtMs', 'desc').limit(limit).get(),
    adminDb.collection('reports').orderBy('createdAtMs', 'desc').limit(limit).get(),
    adminDb.collection('globalChatRequests').orderBy('createdAtMs', 'desc').limit(limit).get(),
  ]);

  const verificationEvents: RecentEvent[] = verificationSnap.docs.map((doc) => {
    const data = doc.data();
    const orgName = typeof data.orgName === 'string' && data.orgName.trim() ? data.orgName.trim() : null;
    return {
      id: doc.id,
      kind: 'verification_request',
      title: orgName ? `Verification submitted — ${orgName}` : 'Verification submitted (legacy, no application data)',
      detail: `Status: ${String(data.status ?? 'unknown')}`,
      timestampMs: typeof data.submittedAtMs === 'number' ? data.submittedAtMs : 0,
    };
  });

  const reportEvents: RecentEvent[] = reportSnap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      kind: 'report',
      title: `Report filed — ${String(data.reason ?? 'unspecified')}`,
      detail: `Status: ${String(data.status ?? 'unknown')}`,
      timestampMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    };
  });

  const chatRequestEvents: RecentEvent[] = chatRequestSnap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      kind: 'global_chat_request',
      title: `Global Chat request — ${String(data.userName ?? 'Unknown user')}`,
      detail: `Status: ${String(data.status ?? 'unknown')}`,
      timestampMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    };
  });

  return [...verificationEvents, ...reportEvents, ...chatRequestEvents]
    .sort((a, b) => b.timestampMs - a.timestampMs)
    .slice(0, limit);
}
