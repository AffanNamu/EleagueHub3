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

export interface SystemHealthAlert {
  id: string;
  severity: 'warning' | 'danger';
  title: string;
  detail: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Real, computed backlog-age alerts -- not a placeholder and not a
 * fabricated feed. There's no alerting pipeline (no Cloud Function, no
 * system_alerts collection) anywhere in this codebase, so rather than
 * build one, this reads the oldest still-pending item in each queue
 * already surfaced elsewhere in this admin panel (reports, verification
 * requests, Global Chat requests) directly via Admin SDK and flags it
 * when it's been waiting past a threshold. Each query is a single
 * equality filter (status == pending) plus an ascending orderBy on
 * createdAtMs/submittedAtMs, limit 1 -- the same index-free shape
 * listReports/listVerificationRequests/listGlobalChatRequests already
 * use elsewhere in this codebase, so it needs no new Firestore index.
 */
export async function getSystemHealthAlerts(): Promise<SystemHealthAlert[]> {
  const nowMs = Date.now();
  const alerts: SystemHealthAlert[] = [];

  const [oldestReport, oldestVerification, oldestChatRequest] = await Promise.all([
    adminDb.collection('reports').where('status', '==', 'pending').orderBy('createdAtMs', 'asc').limit(1).get(),
    adminDb
      .collection('master_league_verification_requests')
      .where('status', '==', 'pending')
      .orderBy('submittedAtMs', 'asc')
      .limit(1)
      .get(),
    adminDb
      .collection('globalChatRequests')
      .where('status', '==', 'pending')
      .orderBy('createdAtMs', 'asc')
      .limit(1)
      .get(),
  ]);

  const reportAgeMs = oldestReport.docs[0] ? nowMs - (oldestReport.docs[0].data().createdAtMs ?? nowMs) : 0;
  if (reportAgeMs > 2 * DAY_MS) {
    alerts.push({
      id: 'reports-backlog',
      severity: reportAgeMs > 7 * DAY_MS ? 'danger' : 'warning',
      title: 'Reports backlog is aging',
      detail: `The oldest pending report has been waiting ${Math.floor(reportAgeMs / DAY_MS)} day(s).`,
    });
  }

  const verificationAgeMs = oldestVerification.docs[0]
    ? nowMs - (oldestVerification.docs[0].data().submittedAtMs ?? nowMs)
    : 0;
  if (verificationAgeMs > 7 * DAY_MS) {
    alerts.push({
      id: 'verification-backlog',
      severity: verificationAgeMs > 14 * DAY_MS ? 'danger' : 'warning',
      title: 'Verification requests backlog is aging',
      detail: `The oldest pending verification request has been waiting ${Math.floor(verificationAgeMs / DAY_MS)} day(s).`,
    });
  }

  const chatRequestAgeMs = oldestChatRequest.docs[0]
    ? nowMs - (oldestChatRequest.docs[0].data().createdAtMs ?? nowMs)
    : 0;
  if (chatRequestAgeMs > 2 * DAY_MS) {
    alerts.push({
      id: 'chat-requests-backlog',
      severity: chatRequestAgeMs > 7 * DAY_MS ? 'danger' : 'warning',
      title: 'Global Chat requests backlog is aging',
      detail: `The oldest pending request has been waiting ${Math.floor(chatRequestAgeMs / DAY_MS)} day(s).`,
    });
  }

  return alerts;
}
