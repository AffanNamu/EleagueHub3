'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useMasterLeagueDetail } from '@/hooks/useMasterLeagueDetail';
import { useMasterLeagueTournaments } from '@/hooks/useMasterLeagueTournaments';
import { useAnnouncements } from '@/hooks/useAnnouncements';
import { payForOrganizerVerification } from '@/lib/masterLeagues/masterLeaguePayments';
import { deleteWorkspace } from '@/lib/masterLeagues/masterLeaguesRepository';
import { joinLeagueByCode } from '@/lib/leagues/leaguesRepository';
import { cloudinaryOptimizedUrl } from '@/lib/cloudinary/cloudinaryUpload';
import { StatCard } from '@/components/masterLeagues/StatCard';
import { PanelCard } from '@/components/masterLeagues/PanelCard';
import {
  Loader2,
  ArrowLeft,
  Network,
  Trophy,
  ShieldCheck,
  Megaphone,
  MessageSquare,
  ShieldAlert,
  Heart,
  Gavel,
  Users,
  Swords,
  Sparkles,
  BadgeCheck,
  Trash2,
  Share2,
  Copy,
  Eye,
  ExternalLink
} from 'lucide-react';
import Link from 'next/link';
import { isOwner, isVerifiedOrganizer, verificationExpired } from '@/types/masterLeague';

export default function MasterLeagueDetailsScreen() {
  const params = useParams();
  const router = useRouter();
  const workspaceId = params.id as string;

  const { workspace, loading, error, uid, following, followBusy, toggleFollow } =
    useMasterLeagueDetail(workspaceId);
  const { leagues, loading: leaguesLoading } = useMasterLeagueTournaments(workspaceId);
  const { announcements, loading: announcementsLoading, postAnnouncement } = useAnnouncements(workspaceId);

  const [postingAnnouncement, setPostingAnnouncement] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [actionError, setActionError] = useState('');
  const [joiningId, setJoiningId] = useState<string | null>(null);

  if (loading) {
    return (
      <div className="flex justify-center items-center py-32">
        <Loader2 className="w-9 h-9 text-brand-lime animate-spin" />
      </div>
    );
  }

  if (error || !workspace) {
    return <div className="text-brand-red p-4">{error || 'Not found'}</div>;
  }

  const owner = isOwner(workspace, uid);
  const verified = isVerifiedOrganizer(workspace);
  const expired = verificationExpired(workspace);

  const handlePostAnnouncement = async () => {
    const title = window.prompt('Announcement title');
    if (!title) return;
    const message = window.prompt('Announcement message');
    if (!message) return;

    setPostingAnnouncement(true);
    try {
      await postAnnouncement(title, message);
    } catch (e: any) {
      alert(e.message || 'Failed to post announcement.');
    } finally {
      setPostingAnnouncement(false);
    }
  };

  const handleGetVerified = async () => {
    setActionError('');
    const confirmed = window.confirm(
      'A paid verification request will be submitted for manual review. Continue to payment?',
    );
    if (!confirmed) return;

    setVerifying(true);
    try {
      const result = await payForOrganizerVerification(
        workspace.id,
        workspace.name,
        workspace.verificationStatus === 'none' || workspace.verificationStatus === 'rejected'
          ? 'initial'
          : 'renewal',
      );
      if (!result.success) {
        setActionError(result.errorMessage || 'Payment failed.');
        return;
      }
      alert('Verification request submitted for review.');
    } catch (e: any) {
      setActionError(e.message || 'Something went wrong.');
    } finally {
      setVerifying(false);
    }
  };

  const handleDelete = async () => {
    const typed = window.prompt(`Type "${workspace.name}" to permanently delete this workspace.`);
    if (typed !== workspace.name) return;
    try {
      await deleteWorkspace(workspace.id);
      router.push('/master-leagues');
    } catch (e: any) {
      alert(e.message || 'Failed to delete workspace.');
    }
  };

  // Professional native sharing implementation
  const handleShare = async (league: any) => {
    const inviteCode = league.code || league.id.slice(0, 6).toUpperCase();
    // Adds an invite parameter so the league detail page knows they came from a share link
    const leagueUrl = `${window.location.origin}/leagues/${league.id}?invite=${inviteCode}`;

    const shareData = {
      title: `${league.name} | eSportlyic`,
      text: `Join the competition: ${league.name} on eSportlyic! \nInvite Code: ${inviteCode}`,
      url: leagueUrl
    };

    // This triggers the native iOS/Android sheet for WhatsApp, Twitter, etc.
    if (navigator.canShare && navigator.canShare(shareData)) {
      try {
        await navigator.share(shareData);
      } catch (err) {
        console.warn("User dismissed native share sheet.");
      }
    } else {
      // Clean fallback for Desktop browsers that don't support native sharing
      await navigator.clipboard.writeText(`${shareData.text}\n\nPlay here: ${shareData.url}`);
      alert("Competition link and code copied to clipboard!");
    }
  };

  const handleCopyCode = (code: string) => {
    navigator.clipboard.writeText(code);
    alert(`Copied Invite Code: ${code}`);
  };

  const handleJoin = async (league: any, mode: 'participant' | 'viewer') => {
    if (!uid) {
      // Professional UX: Redirect to login with a "next" parameter to bring them right back here
      router.push(`/login?redirect=/leagues/${league.id}`);
      return;
    }
    
    const inviteCode = league.code || league.id.slice(0, 6).toUpperCase();
    
    setJoiningId(league.id);
    try {
      await joinLeagueByCode(inviteCode, uid, mode);
      router.push(`/leagues/${league.id}`);
    } catch (err: any) {
      alert(err.message || 'Failed to join league.');
    } finally {
      setJoiningId(null);
    }
  };

  const planTint = workspace.plan === 'elite' ? '#F59E0B' : workspace.plan === 'pro' ? '#38BDF8' : '#B8E928';

  return (
    <div className="max-w-7xl mx-auto pb-16 space-y-6">
      {/* ── Ambient backdrop ─────────────────────────────────────────── */}
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        <div className="absolute -top-40 left-1/4 w-[500px] h-[500px] rounded-full bg-brand-lime/[0.05] blur-[120px]" />
        <div className="absolute top-40 right-1/4 w-[400px] h-[400px] rounded-full bg-[#38BDF8]/[0.05] blur-[120px]" />
      </div>

      {/* ── Top bar ──────────────────────────────────────────────────── */}
      <div className="flex items-center gap-4">
        <button
          onClick={() => router.back()}
          className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-gray-500">
          <Network className="w-3.5 h-3.5" />
          Organizer Workspace
        </div>
        {owner && (
          <Link
            href={`/master-leagues/${workspaceId}/profile`}
            className="ml-auto flex items-center gap-2 px-3.5 py-2 bg-[#0B1221] border border-[#1E293B] hover:border-brand-lime/40 rounded-xl text-xs font-bold text-gray-300 hover:text-brand-lime transition-colors"
          >
            <BadgeCheck className="w-4 h-4" />
            Edit Profile
          </Link>
        )}
      </div>

      {/* ── Hero ─────────────────────────────────────────────────────── */}
      <div className="relative rounded-3xl overflow-hidden border border-[#1E293B] shadow-2xl">
        <div className="relative h-40 md:h-56 bg-[#0B1221]">
          {workspace.organizerProfile.bannerUrl ? (
            <img
              src={cloudinaryOptimizedUrl(workspace.organizerProfile.bannerUrl, { width: 1600, height: 500, crop: 'fill' })}
              alt=""
              className="w-full h-full object-cover opacity-70"
            />
          ) : (
            <div
              className="w-full h-full"
              style={{
                background:
                  'radial-gradient(circle at 20% 20%, rgba(184,233,40,0.10), transparent 45%), radial-gradient(circle at 80% 60%, rgba(56,189,248,0.10), transparent 45%), #0B1221',
              }}
            />
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-[#070B14] via-[#070B14]/40 to-transparent" />
        </div>

        <div className="relative px-6 md:px-10 pb-8 -mt-16 md:-mt-20">
          <div className="flex flex-col md:flex-row md:items-end gap-6">
            <div className="w-24 h-24 md:w-32 md:h-32 rounded-2xl border-4 border-[#070B14] bg-[#0B1221] shrink-0 shadow-2xl overflow-hidden flex items-center justify-center relative">
              {workspace.organizerProfile.logoUrl ? (
                <img
                  src={cloudinaryOptimizedUrl(workspace.organizerProfile.logoUrl, { width: 300, height: 300, crop: 'fill' })}
                  className="w-full h-full object-cover"
                  alt=""
                />
              ) : (
                <Network className="w-10 h-10 text-gray-600" />
              )}
              {verified && (
                <div className="absolute -bottom-1 -right-1 w-8 h-8 bg-[#070B14] rounded-full flex items-center justify-center border-2 border-[#070B14]">
                  <BadgeCheck className="w-5 h-5 text-[#FEF08A] fill-[#F59E0B] drop-shadow-[0_0_5px_rgba(245,158,11,0.9)]" />
                </div>
              )}
            </div>

            <div className="flex-1 min-w-0 space-y-3">
              <div className="flex flex-wrap items-center gap-3">
                <h1 className="text-2xl md:text-4xl font-black text-white tracking-tight truncate">
                  {workspace.name}
                </h1>
                <span
                  className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-black uppercase tracking-wider border"
                  style={{ color: planTint, borderColor: `${planTint}40`, background: `${planTint}14` }}
                >
                  <Sparkles className="w-3 h-3" />
                  {workspace.plan}
                </span>
                {verified && (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-black uppercase tracking-wider text-[#F59E0B] border border-[#F59E0B]/30 bg-[#F59E0B]/10">
                    <BadgeCheck className="w-3 h-3 text-[#FEF08A] fill-[#F59E0B]" /> Verified Organizer
                  </span>
                )}
              </div>
              <p className="text-sm text-gray-400 max-w-2xl leading-relaxed">
                {workspace.organizerProfile.bio ||
                  'Official tournament organizer running competitions on eSportlyic.'}
              </p>
            </div>

            <div className="flex md:flex-col gap-3 w-full md:w-auto shrink-0">
              {!owner && (
                <button
                  onClick={toggleFollow}
                  disabled={followBusy}
                  className={`flex-1 md:w-48 flex items-center justify-center gap-2 px-6 py-3 font-black rounded-xl transition-all disabled:opacity-50 ${
                    following
                      ? 'bg-white/5 border border-white/10 text-white hover:bg-white/10'
                      : 'bg-brand-lime text-brand-navy shadow-lg shadow-brand-lime/20 hover:brightness-110'
                  }`}
                >
                  {followBusy ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Heart className="w-4 h-4" fill={following ? 'currentColor' : 'none'} />
                  )}
                  {following ? 'Following' : 'Follow'}
                </button>
              )}
              <Link
                href={`/master-leagues/${workspaceId}/chat`}
                className="flex-1 md:w-48 flex items-center justify-center gap-2 px-6 py-3 bg-[#38BDF8]/10 text-[#38BDF8] font-bold rounded-xl border border-[#38BDF8]/30 hover:bg-[#38BDF8]/20 transition-colors"
              >
                <MessageSquare className="w-4 h-4" /> Hub Chat
              </Link>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard icon={Users} label="Followers" value={workspace.followersCount} tint="#38BDF8" />
        <StatCard icon={Trophy} label="Competitions" value={leagues.length} tint="#B8E928" />
        <StatCard icon={Swords} label="Matches" value={workspace.analytics.totalMatches} tint="#38BDF8" />
        <StatCard
          icon={BadgeCheck}
          label="Trust Status"
          value={verified ? 'Verified' : workspace.verificationStatus === 'pending' ? 'Pending' : 'Unverified'}
          tint={verified ? '#F59E0B' : '#F59E0B'}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <PanelCard title="Competitions" icon={<Trophy className="w-4 h-4 text-brand-lime" />}>
            {leaguesLoading ? (
              <div className="flex justify-center py-10">
                <Loader2 className="w-7 h-7 text-brand-lime animate-spin" />
              </div>
            ) : leagues.length === 0 ? (
              <div className="text-center py-10 text-gray-500 border border-dashed border-[#1E293B] rounded-xl">
                <Trophy className="w-10 h-10 mx-auto mb-3 opacity-30" />
                <p className="text-sm">No active competitions yet.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {leagues.map((league: any) => {
                  const inviteCode = league.code || league.id.slice(0, 6).toUpperCase();
                  const isJoining = joiningId === league.id;

                  return (
                    <div key={league.id} className="bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-2xl overflow-hidden group transition-all relative flex flex-col h-full shadow-lg">
                      
                      <div className="h-20 relative bg-[#070B14]">
                        {league.coverImageUrl ? (
                          <img 
                            src={league.coverImageUrl} 
                            className="w-full h-full object-cover opacity-50" 
                            alt="" 
                          />
                        ) : (
                          <div className="w-full h-full bg-gradient-to-br from-[#1E293B] to-[#070B14]" />
                        )}
                        <div className="absolute top-2 left-2 bg-brand-lime/10 border border-brand-lime/20 text-brand-lime text-[9px] font-bold uppercase px-2 py-1 rounded">
                          {league.gameName || 'eSports'}
                        </div>
                        <div className="absolute inset-0 bg-gradient-to-t from-[#0B1221] to-transparent pointer-events-none" />
                      </div>
                      
                      <div className="p-4 flex-1 flex flex-col">
                        <div className="flex items-start justify-between gap-2 mb-1">
                          <Link href={`/leagues/${league.id}`} className="min-w-0">
                            <h3 className="font-bold text-white text-base truncate hover:text-brand-lime transition-colors">
                              {league.name}
                            </h3>
                          </Link>
                          {owner ? (
                            <span className="text-[9px] bg-brand-red/10 text-brand-red border border-brand-red/20 px-1.5 py-0.5 rounded font-black uppercase shrink-0">Owner</span>
                          ) : (
                            <button 
                              onClick={(e) => { e.preventDefault(); handleShare(league); }}
                              className="text-gray-400 hover:text-brand-lime transition-colors"
                              title="Share Competition"
                            >
                              <Share2 className="w-4 h-4" />
                            </button>
                          )}
                        </div>
                        <p className="text-[10px] text-gray-500 mb-4">{league.type || 'Classic League'} • {league.season || new Date().getFullYear()}</p>

                        <div className="bg-[#0F172A] border border-[#1E293B] rounded-xl p-3 flex flex-col sm:flex-row items-center gap-4 mb-5">
                          <div className="flex flex-col items-center gap-1.5 shrink-0">
                            <span className="text-white text-[11px] font-bold">Scan to Join</span>
                            <div className="w-20 h-20 bg-white p-1.5 rounded-xl shadow-sm">
                               <img src={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${inviteCode}`} alt="QR Code" className="w-full h-full" />
                            </div>
                          </div>

                          <div className="flex flex-col flex-1 w-full gap-2 text-center sm:text-left">
                            <span className="text-gray-400 text-[9px] font-black uppercase tracking-wider">Invite Code</span>
                            <div className="bg-[#070B14] border border-[#1E293B] rounded-lg py-1.5 px-3">
                              <span className="text-white font-mono text-lg font-black tracking-widest">{inviteCode}</span>
                            </div>
                            <button 
                              onClick={() => handleCopyCode(inviteCode)}
                              className="w-full bg-brand-lime text-brand-navy py-1.5 rounded-lg text-[10px] font-black flex items-center justify-center gap-1.5 hover:brightness-110 shadow-lg shadow-brand-lime/10 transition-all"
                            >
                              <Copy className="w-3.5 h-3.5" /> COPY
                            </button>
                            <p className="text-[9px] text-gray-500 leading-tight mt-0.5">Share this code with friends or let them scan the QR.</p>
                          </div>
                        </div>

                        <div className="mt-auto flex items-center gap-2">
                          {!owner ? (
                            <>
                              <button 
                                onClick={() => handleJoin(league, 'participant')}
                                disabled={isJoining}
                                className="flex-1 py-2.5 bg-[#070B14] hover:bg-brand-lime hover:text-brand-navy border border-[#1E293B] text-gray-300 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-1.5"
                              >
                                {isJoining ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Users className="w-3.5 h-3.5" />}
                                Join
                              </button>
                              <button 
                                onClick={() => handleJoin(league, 'viewer')}
                                disabled={isJoining}
                                className="flex-1 py-2.5 bg-[#070B14] hover:bg-[#38BDF8] hover:text-brand-navy border border-[#1E293B] text-gray-300 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-1.5"
                              >
                                {isJoining ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Eye className="w-3.5 h-3.5" />}
                                Spectate
                              </button>
                            </>
                          ) : (
                            <Link href={`/leagues/${league.id}`} className="w-full py-2.5 bg-[#070B14] hover:bg-brand-lime hover:text-brand-navy border border-[#1E293B] text-brand-lime text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-1.5">
                              <ExternalLink className="w-3.5 h-3.5" />
                              Open Competition
                            </Link>
                          )}
                        </div>
                      </div>

                    </div>
                  );
                })}
              </div>
            )}
          </PanelCard>

          {owner && (
            <PanelCard title="Owner Actions" icon={<ShieldAlert className="w-4 h-4 text-brand-red" />}>
              <div className="flex flex-wrap gap-3">
                <Link
                  href={`/master-leagues/${workspaceId}/admin/discipline`}
                  className="flex items-center gap-2 px-5 py-3 bg-brand-red/10 text-brand-red font-bold rounded-xl border border-brand-red/30 hover:bg-brand-red/20 transition-colors text-sm"
                >
                  <Gavel className="w-4 h-4" /> Discipline Panel
                </Link>
                <button
                  onClick={handleDelete}
                  className="flex items-center gap-2 px-5 py-3 bg-white/5 text-gray-400 font-bold rounded-xl border border-white/10 hover:bg-brand-red/10 hover:text-brand-red hover:border-brand-red/30 transition-colors text-sm"
                >
                  <Trash2 className="w-4 h-4" /> Delete Workspace
                </button>
              </div>
            </PanelCard>
          )}
        </div>

        <div className="space-y-6">
          {owner && (
            <PanelCard title="Trust & Verification" icon={<BadgeCheck className="w-4 h-4 text-[#F59E0B]" />}>
              {actionError && <p className="text-xs text-brand-red mb-3">{actionError}</p>}
              {verified ? (
                <div className="space-y-3">
                  <p className="text-sm text-gray-400 leading-relaxed">
                    This organizer is verified.{' '}
                    {expired ? 'Verification has expired — renew to keep the badge.' : 'Keep providing great tournaments!'}
                  </p>
                  {expired && (
                    <button
                      onClick={handleGetVerified}
                      disabled={verifying}
                      className="w-full py-3 bg-white/5 text-white font-bold rounded-xl hover:bg-white/10 border border-white/10 transition-colors disabled:opacity-50 text-sm"
                    >
                      {verifying ? <Loader2 className="w-4 h-4 animate-spin mx-auto" /> : 'Renew Verification'}
                    </button>
                  )}
                </div>
              ) : workspace.verificationStatus === 'pending' ? (
                <p className="text-sm text-amber-400">Your verification request is pending review.</p>
              ) : (
                <button
                  onClick={handleGetVerified}
                  disabled={verifying}
                  className="w-full py-3 bg-brand-lime text-brand-navy font-bold rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2 text-sm shadow-lg shadow-brand-lime/10"
                >
                  {verifying ? <Loader2 className="w-4 h-4 animate-spin" /> : <BadgeCheck className="w-4 h-4" />}
                  Get Verified
                </button>
              )}
            </PanelCard>
          )}

          <PanelCard
            title="Announcements"
            icon={<Megaphone className="w-4 h-4 text-[#38BDF8]" />}
            action={
              owner && (
                <button
                  onClick={handlePostAnnouncement}
                  disabled={postingAnnouncement}
                  className="text-xs font-bold text-[#38BDF8] hover:underline disabled:opacity-50"
                >
                  {postingAnnouncement ? '...' : '+ Post'}
                </button>
              )
            }
          >
            {announcementsLoading ? (
              <div className="flex justify-center py-4">
                <Loader2 className="w-5 h-5 animate-spin text-[#38BDF8]" />
              </div>
            ) : announcements.length === 0 ? (
              <p className="text-sm text-gray-500 text-center py-4">No recent announcements.</p>
            ) : (
              <div className="space-y-4">
                {announcements.map((ann) => (
                  <div key={ann.id} className="border-l-2 border-[#38BDF8]/50 pl-3.5 py-0.5">
                    <h4 className="text-sm font-bold text-white flex items-center gap-2">
                      {ann.title}
                      {ann.pinned && (
                        <span className="text-[9px] bg-[#38BDF8]/15 text-[#38BDF8] px-1.5 py-0.5 rounded uppercase tracking-wider">
                          Pinned
                        </span>
                      )}
                    </h4>
                    <p className="text-xs text-gray-500 mt-1 line-clamp-2 leading-relaxed">{ann.message}</p>
                  </div>
                ))}
              </div>
            )}
          </PanelCard>
        </div>
      </div>
    </div>
  );
}
