// types/auditLog.ts

export interface AuditLogEntry {
  id: string;
  actorUid: string;
  actorEmail: string | null;
  action: string;
  targetType: string;
  targetId: string;
  summary: string;
  createdAtMs: number;
}
