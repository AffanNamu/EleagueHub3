import { Users, Trophy, Building2, BadgeCheck, FileWarning, MessageCircle, ShieldCheck } from 'lucide-react';
import { getDashboardStats, getRecentEvents } from '@/lib/repositories/dashboardRepository';
import { StatCard } from '@/components/dashboard/StatCard';
import { RecentActivity } from '@/components/dashboard/RecentActivity';
import { SystemAlerts } from '@/components/dashboard/SystemAlerts';

export const dynamic = 'force-dynamic';

export default async function DashboardPage() {
  const [stats, recentEvents] = await Promise.all([getDashboardStats(), getRecentEvents()]);

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
        <SystemAlerts />
      </div>
    </div>
  );
}
