'use client';

import { useCallback, useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useMasterLeagueDetail } from '@/hooks/useMasterLeagueDetail';
import {
  addStaffByShortIdWeb,
  removeStaffWeb,
  listStaffWeb,
  MasterLeagueStaffMember,
} from '@/lib/masterLeagues/masterLeaguesRepository';
import {
  MASTER_LEAGUE_STAFF_ROLES,
  ASSIGNABLE_STAFF_ROLES,
  MasterLeagueStaffRoleId,
} from '@/lib/masterLeagues/roles';
import { PanelCard } from '@/components/masterLeagues/PanelCard';
import {
  Loader2,
  ArrowLeft,
  Users,
  UserPlus,
  UserMinus,
  ShieldOff,
  Crown,
  Wrench,
  ScrollText,
  Shield,
  type LucideIcon,
} from 'lucide-react';

const ROLE_ICON: Record<MasterLeagueStaffRoleId, LucideIcon> = {
  owner: Crown,
  admin: Wrench,
  result_manager: ScrollText,
  moderator: Shield,
};

const ROLE_TINT: Record<MasterLeagueStaffRoleId, string> = {
  owner: 'text-[#BEF264]',
  admin: 'text-sky-400',
  result_manager: 'text-purple-400',
  moderator: 'text-amber-400',
};

export default function MasterLeagueStaffPage() {
  const params = useParams();
  const router = useRouter();
  const mlId = params.id as string;

  const { workspace, loading, uid } = useMasterLeagueDetail(mlId);

  const [staff, setStaff] = useState<MasterLeagueStaffMember[]>([]);
  const [staffLoading, setStaffLoading] = useState(true);
  const [error, setError] = useState('');

  const [showAddModal, setShowAddModal] = useState(false);
  const [shortId, setShortId] = useState('');
  const [selectedRole, setSelectedRole] = useState<MasterLeagueStaffRoleId>('admin');
  const [adding, setAdding] = useState(false);
  const [removingUid, setRemovingUid] = useState<string | null>(null);

  const isOwner = !!uid && !!workspace && uid === workspace.ownerId;

  const refreshStaff = useCallback(async () => {
    setStaffLoading(true);
    try {
      const list = await listStaffWeb(mlId);
      setStaff(list);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load staff.');
    } finally {
      setStaffLoading(false);
    }
  }, [mlId]);

  useEffect(() => {
    if (!mlId) return;
    void refreshStaff();
  }, [mlId, refreshStaff]);

  const handleAddStaff = async () => {
    if (!shortId.trim()) return setError('Enter a short id.');
    setAdding(true);
    setError('');
    try {
      await addStaffByShortIdWeb({
        mlId,
        authUid: auth.currentUser!.uid,
        shortId: shortId.trim(),
        role: selectedRole,
      });
      setShortId('');
      setShowAddModal(false);
      await refreshStaff();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add staff member.');
    } finally {
      setAdding(false);
    }
  };

  const handleRemoveStaff = async (member: MasterLeagueStaffMember) => {
    const label = member.displayName || member.userId;
    if (!confirm(`Remove ${label} as ${MASTER_LEAGUE_STAFF_ROLES[member.role].displayName}?`)) return;
    setRemovingUid(member.userId);
    setError('');
    try {
      await removeStaffWeb({ mlId, authUid: auth.currentUser!.uid, targetUid: member.userId });
      await refreshStaff();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to remove staff member.');
    } finally {
      setRemovingUid(null);
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 animate-spin text-[#BEF264]" />
      </div>
    );
  }

  if (!workspace || !isOwner) {
    return (
      <div className="text-center py-20 text-red-500 font-bold">
        Owner only — you don&apos;t have access to manage staff for this workspace.
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mt-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-xl md:text-2xl font-black text-white flex items-center gap-2">
          <Users className="w-6 h-6 text-[#0EA5E9]" /> Manage Staff
        </h1>
      </div>

      {error && (
        <div className="p-4 bg-red-500/10 border border-red-500/30 text-red-500 rounded-xl text-sm font-bold">
          {error}
        </div>
      )}

      <PanelCard
        title="Workspace Staff"
        icon={<Users className="w-4 h-4 text-[#0EA5E9]" />}
        action={
          <button
            onClick={() => setShowAddModal(true)}
            className="flex items-center gap-1.5 px-3 py-2 bg-[#BEF264] text-[#0F172A] rounded-lg text-xs font-black hover:brightness-110"
          >
            <UserPlus className="w-4 h-4" /> Add Staff
          </button>
        }
      >
        <p className="text-xs font-semibold text-gray-500 mb-4">
          Delegate competition management, result entry, or moderation without sharing full ownership.
        </p>

        {staffLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="w-6 h-6 animate-spin text-gray-500" />
          </div>
        ) : (
          <div className="space-y-3">
            {staff.map((member) => {
              const roleDef = MASTER_LEAGUE_STAFF_ROLES[member.role];
              const Icon = ROLE_ICON[member.role];
              const tint = ROLE_TINT[member.role];
              const title = member.displayName || member.userId;
              const subtitle = [
                roleDef.displayName,
                member.role === 'owner'
                  ? null
                  : member.competitionScope.length > 0
                  ? `${member.competitionScope.length} competition(s) only`
                  : 'All competitions',
              ]
                .filter(Boolean)
                .join(' • ');

              return (
                <div
                  key={member.userId}
                  className="flex items-center gap-3 p-3 bg-[#070B14] rounded-xl border border-white/5"
                >
                  <div className={`w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center ${tint}`}>
                    <Icon className="w-5 h-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-white truncate">{title}</p>
                    <p className="text-xs font-semibold text-gray-500">{subtitle}</p>
                  </div>
                  {member.role !== 'owner' && (
                    <button
                      onClick={() => handleRemoveStaff(member)}
                      disabled={removingUid === member.userId}
                      title="Remove"
                      className="p-2 text-gray-400 hover:text-red-500 hover:bg-red-500/10 rounded-lg transition-colors disabled:opacity-50"
                    >
                      {removingUid === member.userId ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <UserMinus className="w-4 h-4" />
                      )}
                    </button>
                  )}
                </div>
              );
            })}
            {staff.length === 0 && (
              <div className="text-center py-8 text-gray-500 text-sm font-semibold flex flex-col items-center gap-2">
                <ShieldOff className="w-8 h-8" />
                No staff yet.
              </div>
            )}
          </div>
        )}
      </PanelCard>

      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60">
          <div className="w-full max-w-md bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-lg font-black text-white mb-1">Add Staff</h2>
            <p className="text-xs font-semibold text-gray-500 mb-4">
              Enter the user short id (share id). Example: eS44e35f
            </p>

            <input
              value={shortId}
              onChange={(e) => setShortId(e.target.value)}
              placeholder="Short ID"
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-[#BEF264] font-mono text-sm mb-4"
            />

            <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Role</p>
            <div className="flex flex-wrap gap-2 mb-2">
              {ASSIGNABLE_STAFF_ROLES.map((roleId) => {
                const roleDef = MASTER_LEAGUE_STAFF_ROLES[roleId];
                const selected = selectedRole === roleId;
                return (
                  <button
                    key={roleId}
                    onClick={() => setSelectedRole(roleId)}
                    className={`px-4 py-2 rounded-xl text-xs font-black border transition-colors ${
                      selected
                        ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]'
                        : 'bg-[#070B14] text-gray-400 border-[#1E293B]'
                    }`}
                  >
                    {roleDef.displayName}
                  </button>
                );
              })}
            </div>
            <p className="text-xs font-semibold text-gray-500 mb-6">
              {MASTER_LEAGUE_STAFF_ROLES[selectedRole].description}
            </p>

            <div className="flex gap-3">
              <button
                onClick={() => setShowAddModal(false)}
                className="flex-1 py-3 rounded-xl bg-white/5 text-white font-black text-sm hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                onClick={handleAddStaff}
                disabled={adding || !shortId.trim()}
                className="flex-1 py-3 rounded-xl bg-[#BEF264] text-[#0F172A] font-black text-sm hover:brightness-110 disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {adding ? <Loader2 className="w-4 h-4 animate-spin" /> : <UserPlus className="w-4 h-4" />}
                Add
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
