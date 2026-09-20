import { Users, Trophy, Building2, BadgeCheck, FileWarning, MessageCircle, ShieldCheck } from 'lucide-react';
import { getDashboardStats, getRecentEvents, getSystemHealthAlerts } from '@/lib/repositories/dashboardRepository';
import { StatCard } from '@/components/dashboard/StatCard';
import { RecentActivity } from '@/components/dashboard/RecentActivity';
import { SystemAlerts } from '@/components/dashboard/SystemAlerts';

export const dynamic = 'force-dynamic';

const EMPTY_STATS = {
  totalUsers: 0,
  totalLeagues: 0,
  totalMasterLeagues: 0,
  pendingVerifications: 0,
  pendingReports: 0,
  pendingGlobalChatRequests: 0,
  platformAdminCount: 0,
};

export default async function DashboardPage() {
  const [statsResult, recentEventsResult, alertsResult] = await Promise.allSettled([
    getDashboardStats(),
    getRecentEvents(),
    getSystemHealthAlerts(),
  ]);

  if (statsResult.status === 'rejected') {
    console.error('DashboardPage: getDashboardStats failed', statsResult.reason);
  }
  if (recentEventsResult.status === 'rejected') {
    console.error('DashboardPage: getRecentEvents failed', recentEventsResult.reason);
  }
  if (alertsResult.status === 'rejected') {
    console.error('DashboardPage: getSystemHealthAlerts failed', alertsResult.reason);
  }

  const stats = statsResult.status === 'fulfilled' ? statsResult.value : EMPTY_STATS;
  const recentEvents = recentEventsResult.status === 'fulfilled' ? recentEventsResult.value : [];
  const alerts = alertsResult.status === 'fulfilled' ? alertsResult.value : [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Operations Overview</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Live counts from the platform's Firestore database.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-3 xl:grid-cols-7">
        <StatCard label="Total Users" value={stats.totalUsers} icon={Users} tone="brand" />
        <StatCard label="Leagues" value={stats.totalLeagues} icon={Trophy} tone="info" />
        <StatCard label="Organizer Workspaces" value={stats.totalMasterLeagues} icon={Building2} tone="brand" />
        <StatCard
          label="Pending Verifications"
          value={stats.pendingVerifications}
          icon={BadgeCheck}
          tone={stats.pendingVerifications > 0 ? 'warning' : 'success'}
        />
        <StatCard
          label="Pending Reports"
          value={stats.pendingReports}
          icon={FileWarning}
          tone={stats.pendingReports > 0 ? 'danger' : 'success'}
        />
        <StatCard
          label="Pending Chat Requests"
          value={stats.pendingGlobalChatRequests}
          icon={MessageCircle}
          tone={stats.pendingGlobalChatRequests > 0 ? 'warning' : 'success'}
        />
        <StatCard label="Platform Admins" value={stats.platformAdminCount} icon={ShieldCheck} tone="info" />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <RecentActivity events={recentEvents} />
        </div>
        <SystemAlerts alerts={alerts} />
      </div>
    </div>
  );
}
