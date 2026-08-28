'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { motion, AnimatePresence } from 'framer-motion';
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { 
  ArrowLeft, RefreshCw, Trash2, Mic, Wifi, Shield,
  MessageSquare, DownloadCloud, Ticket, Activity,
  CheckCircle2, X, Users, Gift, Settings, ShieldCheck, CheckCircle
} from 'lucide-react';
import { auth, db } from '@/lib/firebase';
import { fetchFullLeagueDetails, FullLeagueDetails } from '@/lib/leagues/leagueDetailsRepository';
import { 
  createPointAdjustmentWeb, sendAnnouncementWeb, 
  generateRosterCsvString, toggleSpaceStatusWeb, 
  deleteLeagueWeb, ensureCouponConfigWeb, generateCouponCodesWeb
} from '@/lib/leagues/leagueAdminRepository';

export default function LeagueAdminScreen() {
  const router = useRouter();
  const params = useParams();
  const leagueId = params?.id as string;

  const [mounted, setMounted] = useState(false);
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<FullLeagueDetails | null>(null);
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const [activeModal, setActiveModal] = useState<'none' | 'delete' | 'points' | 'announcement' | 'coupons'>('none');
  const [isProcessing, setIsProcessing] = useState(false);

  // Modal States
  const [pointTeamId, setPointTeamId] = useState('');
  const [pointType, setPointType] = useState<'addition' | 'deduction'>('addition');
  const [pointAmount, setPointAmount] = useState('');
  const [pointReason, setPointReason] = useState('');
  const [auditLogs, setAuditLogs] = useState<any[]>([]);
  const [couponCodes, setCouponCodes] = useState<any[]>([]);
  
  const [annTitle, setAnnTitle] = useState('');
  const [annMsg, setAnnMsg] = useState('');
  const [couponMode, setCouponMode] = useState<'random' | 'custom'>('random');
  const [couponCount, setCouponCount] = useState('10');
  const [couponCustom, setCouponCustom] = useState('');

  useEffect(() => { setMounted(true); }, []);

  useEffect(() => {
    if (!mounted) return;
    const unsubscribe = auth.onAuthStateChanged((user) => {
      if (!user) router.push('/login');
      else setAuthUid(user.uid);
    });
    return () => unsubscribe();
  }, [mounted, router]);

  const loadData = async () => {
    if (!authUid || !leagueId) return;
    setLoading(true);
    try {
      const details = await fetchFullLeagueDetails(leagueId, authUid);
      if (details && !details.isOwner) {
        router.push(`/leagues/${leagueId}`);
        return;
      }
      setData(details);
      if (details && Object.keys(details.teams).length > 0) {
        setPointTeamId(Object.keys(details.teams)[0]);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (mounted && authUid && leagueId) loadData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mounted, authUid, leagueId]);

  // Streams for Modals
  useEffect(() => {
    if (activeModal === 'points' && leagueId) {
      const q = query(collection(db, 'leagues', leagueId, 'pointAdjustments'), orderBy('createdAtMs', 'desc'), limit(50));
      return onSnapshot(q, (snap) => setAuditLogs(snap.docs.map(d => ({ id: d.id, ...d.data() }))));
    }
    if (activeModal === 'coupons' && leagueId) {
      const q = query(collection(db, 'leagues', leagueId, 'couponCodes'), orderBy('createdAtMs', 'desc'), limit(50));
      return onSnapshot(q, (snap) => setCouponCodes(snap.docs.map(d => ({ id: d.id, ...d.data() }))));
    }
  }, [activeModal, leagueId]);

  if (!mounted || loading || !data) {
    return (
      <div className="min-h-screen bg-[#070B14] flex items-center justify-center">
        <div className="w-12 h-12 border-4 border-[#BEF264] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const showSnack = (msg: string, isError = false) => {
    if (isError) setError(msg);
    else setSuccess(msg);
    setTimeout(() => { setError(''); setSuccess(''); }, 4000);
  };

  const handleExportRoster = async () => {
    try {
      setIsProcessing(true);
      const csv = await generateRosterCsvString(leagueId);
      const blob = new Blob([csv], { type: 'text/csv' });
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `roster_${data.league.name.replace(/\s+/g, '_')}_${leagueId.slice(0,6)}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      showSnack('Roster downloaded successfully');
    } catch (err: any) {
      showSnack(err.message || 'Export failed', true);
    } finally {
      setIsProcessing(false);
    }
  };

  const handlePointAdjustment = async () => {
    if (!authUid) return;
    const pts = parseInt(pointAmount, 10);
    if (!pointTeamId || isNaN(pts) || pts <= 0 || !pointReason.trim()) {
      showSnack('Please fill out all fields correctly', true);
      return;
    }
    setIsProcessing(true);
    try {
      await createPointAdjustmentWeb({
        leagueId, teamId: pointTeamId, type: pointType, points: pts, reason: pointReason, authUid
      });
      showSnack('Points adjusted successfully');
      setPointAmount('');
      setPointReason('');
      loadData();
    } catch (err: any) {
      showSnack(err.message || 'Adjustment failed', true);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleSendAnnouncement = async () => {
    if (!authUid) return;
    if (!annMsg.trim()) {
      showSnack('Message is required', true);
      return;
    }
    setIsProcessing(true);
    try {
      await sendAnnouncementWeb(leagueId, annTitle, annMsg, authUid);
      showSnack('Announcement sent successfully');
      setActiveModal('none');
      setAnnTitle(''); setAnnMsg('');
    } catch (err: any) {
      showSnack(err.message || 'Failed to send announcement', true);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleToggleSpace = async () => {
    if (!authUid) return;
    setIsProcessing(true);
    try {
      await toggleSpaceStatusWeb(leagueId, !data.space?.isLive, authUid, data.league.name);
      showSnack(data.space?.isLive ? 'Live Space Ended' : 'Live Space Started!');
      loadData();
    } catch (err: any) {
      showSnack(err.message || 'Failed to toggle space', true);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleDelete = async () => {
    setIsProcessing(true);
    try {
      await deleteLeagueWeb(leagueId);
      router.push('/leagues');
    } catch (err: any) {
      showSnack(err.message || 'Deletion failed', true);
      setIsProcessing(false);
    }
  };

  const handleInitCoupons = async () => {
    if (!authUid) return;
    setIsProcessing(true);
    try {
      await ensureCouponConfigWeb(leagueId, authUid);
      showSnack('Coupon config initialized. You can now generate codes.');
    } catch (err: any) {
      showSnack(err.message || 'Failed to initialize', true);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleGenerateCoupons = async () => {
    if (!authUid) return;
    setIsProcessing(true);
    try {
      const count = parseInt(couponCount, 10);
      if (couponMode === 'random' && (isNaN(count) || count <= 0)) throw new Error('Enter a valid count');
      if (couponMode === 'custom' && !couponCustom.trim()) throw new Error('Enter a valid custom code');

      const codes = await generateCouponCodesWeb(leagueId, authUid, count, couponMode === 'custom' ? couponCustom : undefined);
      showSnack(`Successfully generated ${codes.length} code(s)`);
    } catch (err: any) {
      showSnack(err.message || 'Generation failed', true);
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#070B14] text-white font-sans pb-20">
      
      <header className="sticky top-0 z-40 bg-[#070B14]/90 backdrop-blur-md border-b border-[#1E293B] px-4 md:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => router.push(`/leagues/${leagueId}`)} className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-white transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-black tracking-tight">League Administration</h1>
        </div>
        <button onClick={loadData} className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-[#BEF264] transition-colors">
          <RefreshCw className={`w-4 h-4 ${isProcessing ? 'animate-spin' : ''}`} />
        </button>
      </header>

      {/* Toast Notifications */}
      <div className="fixed top-20 left-1/2 -translate-x-1/2 z-50 w-full max-w-md px-4 pointer-events-none flex flex-col gap-2">
        <AnimatePresence>
          {error && (
            <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -20 }} className="w-full p-4 rounded-xl bg-red-500/90 backdrop-blur-md text-white font-bold text-sm shadow-xl flex items-center gap-3">
              <Shield className="w-5 h-5" /> {error}
            </motion.div>
          )}
          {success && (
            <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -20 }} className="w-full p-4 rounded-xl bg-[#BEF264]/90 backdrop-blur-md text-[#0F172A] font-black text-sm shadow-xl flex items-center gap-3">
              <CheckCircle2 className="w-5 h-5" /> {success}
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 mt-8 space-y-4">
        
        {/* Status Card */}
        <div className="p-5 rounded-3xl bg-[#0B1221] border border-[#1E293B] shadow-xl flex items-center gap-4 mb-6">
          <div className="w-12 h-12 rounded-2xl bg-[#BEF264]/10 border border-[#BEF264]/20 flex items-center justify-center shrink-0">
            <Wifi className="w-6 h-6 text-[#BEF264]" />
          </div>
          <div>
            <h3 className="text-base font-black text-white">Online & Connected</h3>
            <p className="text-xs font-semibold text-gray-400 mt-1">Changes save directly to the server instantly.</p>
          </div>
        </div>

        {/* Action List aligned with Flutter's league_admin_screen.dart */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <AdminActionCard 
            icon={Settings} title="League Settings" subtitle="Edit name, description, privacy, and banners"
            onClick={() => router.push(`/leagues/${leagueId}/admin/settings`)}
          />
          <AdminActionCard 
            icon={Ticket} title="Coupon Codes" subtitle="Initialize config or generate join codes"
            onClick={() => setActiveModal('coupons')}
          />
          <AdminActionCard 
            icon={Gift} title="Rewards" subtitle="Add or manage prize pool rewards"
            onClick={() => router.push(`/leagues/${leagueId}/rewards`)}
          />
          <AdminActionCard 
            icon={Activity} title="Point Adjustments" subtitle="Add/deduct points for fair play auditing"
            onClick={() => setActiveModal('points')}
          />
          <AdminActionCard 
            icon={Users} title="Manage Teams" subtitle="Add or remove teams from your league"
            onClick={() => router.push(`/leagues/${leagueId}/admin/teams`)}
          />
          <AdminActionCard 
            icon={DownloadCloud} title="Export Roster CSV" subtitle="Download the official participants list"
            onClick={handleExportRoster} loading={isProcessing}
          />
          <AdminActionCard 
            icon={MessageSquare} title="Send Announcement" subtitle="Push a global notification to participants"
            onClick={() => setActiveModal('announcement')}
          />
          <AdminActionCard 
            icon={Mic} title={data.space?.isLive ? 'End Live Space' : 'Start Live Space'} subtitle={data.space?.isLive ? 'Close the current audio room' : 'Host an audio room for this league'}
            onClick={handleToggleSpace} loading={isProcessing} active={data.space?.isLive}
          />
        </div>

        <div className="pt-8">
          <AdminActionCard 
            icon={Trash2} title="Delete League" subtitle="Permanently destroy this competition" destructive
            onClick={() => setActiveModal('delete')}
          />
        </div>
      </main>

      {/* ── MODALS ── */}
      <AnimatePresence>
        {activeModal !== 'none' && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
            <motion.div 
              initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.95 }}
              className="w-full max-w-lg bg-[#0F172A] border border-[#1E293B] rounded-3xl p-6 shadow-2xl relative max-h-[90vh] overflow-y-auto custom-scrollbar"
            >
              <button onClick={() => setActiveModal('none')} className="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-[#1E293B] text-gray-400 hover:text-white transition-colors">
                <X className="w-4 h-4" />
              </button>

              {activeModal === 'delete' && (
                <div className="text-center pt-4">
                  <div className="w-16 h-16 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center mx-auto mb-4">
                    <Trash2 className="w-8 h-8 text-red-500" />
                  </div>
                  <h2 className="text-xl font-black text-white mb-2">Delete League?</h2>
                  <p className="text-sm font-medium text-gray-400 mb-8 leading-relaxed">This action is irreversible. All data, teams, matches, and history will be purged completely.</p>
                  <div className="flex gap-3">
                    <button onClick={() => setActiveModal('none')} className="flex-1 py-3.5 rounded-xl border border-[#1E293B] text-white font-bold hover:bg-[#1E293B] transition-colors">Cancel</button>
                    <button onClick={handleDelete} disabled={isProcessing} className="flex-1 py-3.5 rounded-xl bg-red-500 text-white font-black hover:bg-red-600 disabled:opacity-50">
                      {isProcessing ? 'Deleting...' : 'Confirm Deletion'}
                    </button>
                  </div>
                </div>
              )}

              {activeModal === 'announcement' && (
                <>
                  <h2 className="text-xl font-black text-white mb-1">Send Announcement</h2>
                  <p className="text-xs font-semibold text-gray-400 mb-6">Broadcast a message to the league dashboard.</p>
                  <div className="space-y-4 mb-6">
                    <input type="text" placeholder="Title (Optional)" value={annTitle} onChange={e => setAnnTitle(e.target.value)} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-bold text-white outline-none focus:border-[#BEF264]" />
                    <textarea placeholder="Message (Required)" value={annMsg} onChange={e => setAnnMsg(e.target.value)} rows={4} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-medium text-white outline-none focus:border-[#BEF264] resize-none" />
                  </div>
                  <button onClick={handleSendAnnouncement} disabled={isProcessing || !annMsg.trim()} className="w-full py-3.5 rounded-xl bg-[#BEF264] text-[#0F172A] font-black hover:brightness-110 disabled:opacity-50 shadow-lg shadow-[#BEF264]/10">
                    {isProcessing ? 'Sending...' : 'Send Now'}
                  </button>
                </>
              )}

              {activeModal === 'points' && (
                <>
                  <h2 className="text-xl font-black text-white mb-1">Admin Point Adjustments</h2>
                  <p className="text-xs font-semibold text-gray-400 mb-6">{data.league.name}</p>
                  <div className="space-y-4 mb-6">
                    <select value={pointTeamId} onChange={e => setPointTeamId(e.target.value)} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-bold text-white outline-none focus:border-[#BEF264]">
                      {Object.values(data.teams).map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                    </select>
                    <div className="flex gap-3">
                      <button onClick={() => setPointType('addition')} className={`flex-1 py-2.5 rounded-xl border font-black text-xs transition-all ${pointType === 'addition' ? 'bg-[#BEF264]/10 border-[#BEF264] text-[#BEF264]' : 'bg-[#0B1221] border-[#1E293B] text-gray-500'}`}>+ ADD</button>
                      <button onClick={() => setPointType('deduction')} className={`flex-1 py-2.5 rounded-xl border font-black text-xs transition-all ${pointType === 'deduction' ? 'bg-red-500/10 border-red-500 text-red-500' : 'bg-[#0B1221] border-[#1E293B] text-gray-500'}`}>- DEDUCT</button>
                    </div>
                    <input type="number" placeholder="Points (e.g. 3)" value={pointAmount} onChange={e => setPointAmount(e.target.value)} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-bold text-white outline-none focus:border-[#BEF264]" />
                    <input type="text" placeholder="Reason (Required)" value={pointReason} onChange={e => setPointReason(e.target.value)} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-medium text-white outline-none focus:border-[#BEF264]" />
                  </div>
                  <button onClick={handlePointAdjustment} disabled={isProcessing} className="w-full py-3.5 rounded-xl bg-[#BEF264] text-[#0F172A] font-black hover:brightness-110 disabled:opacity-50 mb-6 shadow-lg shadow-[#BEF264]/10">
                    {isProcessing ? 'Applying...' : 'Apply Adjustment'}
                  </button>

                  {/* Audit Logs */}
                  <div className="border-t border-[#1E293B] pt-4">
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Audit Log</h3>
                    <div className="space-y-2 max-h-40 overflow-y-auto custom-scrollbar pr-2">
                      {auditLogs.length === 0 ? (
                        <p className="text-xs text-gray-600 font-semibold text-center py-2">No adjustments yet.</p>
                      ) : auditLogs.map(log => (
                        <div key={log.id} className="p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl flex items-center justify-between">
                          <div>
                            <p className="text-xs font-bold text-white">{data.teams[log.teamId]?.name || 'Unknown Team'} <span className={log.type === 'addition' ? 'text-[#BEF264]' : 'text-red-500'}>{log.type === 'addition' ? '+' : '-'}{log.points}</span></p>
                            <p className="text-[10px] text-gray-500 mt-1 truncate max-w-[200px]">{log.reason}</p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                </>
              )}

              {activeModal === 'coupons' && (
                <>
                  <h2 className="text-xl font-black text-white mb-1">Coupon Codes</h2>
                  <p className="text-xs font-semibold text-gray-400 mb-6">Initialize configuration before generating.</p>
                  
                  <button onClick={handleInitCoupons} disabled={isProcessing} className="w-full py-3 rounded-xl border border-sky-500/50 bg-sky-500/5 text-sky-400 font-bold text-sm hover:bg-sky-500/10 transition-colors mb-6">
                    Initialize / Reset Configuration
                  </button>
                  
                  <div className="space-y-4 mb-6">
                    <div className="flex gap-2">
                      <button onClick={() => setCouponMode('random')} className={`flex-1 py-2 rounded-xl border font-black text-xs transition-all ${couponMode === 'random' ? 'bg-[#BEF264]/10 border-[#BEF264] text-[#BEF264]' : 'bg-[#0B1221] border-[#1E293B] text-gray-500'}`}>RANDOM</button>
                      <button onClick={() => setCouponMode('custom')} className={`flex-1 py-2 rounded-xl border font-black text-xs transition-all ${couponMode === 'custom' ? 'bg-[#BEF264]/10 border-[#BEF264] text-[#BEF264]' : 'bg-[#0B1221] border-[#1E293B] text-gray-500'}`}>CUSTOM</button>
                    </div>
                    {couponMode === 'random' ? (
                      <input type="number" placeholder="How many codes?" value={couponCount} onChange={e => setCouponCount(e.target.value)} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-bold text-white outline-none focus:border-[#BEF264]" />
                    ) : (
                      <input type="text" placeholder="Custom code (e.g. BARCA)" value={couponCustom} onChange={e => setCouponCustom(e.target.value)} className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-bold text-white outline-none focus:border-[#BEF264] uppercase" />
                    )}
                  </div>
                  <button onClick={handleGenerateCoupons} disabled={isProcessing} className="w-full py-3.5 rounded-xl bg-[#BEF264] text-[#0F172A] font-black hover:brightness-110 disabled:opacity-50 mb-6 shadow-lg shadow-[#BEF264]/10">
                    {isProcessing ? 'Generating...' : 'Generate Codes'}
                  </button>

                  <div className="border-t border-[#1E293B] pt-4">
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Generated Codes</h3>
                    <div className="space-y-2 max-h-40 overflow-y-auto custom-scrollbar pr-2">
                      {couponCodes.length === 0 ? (
                        <p className="text-xs text-gray-600 font-semibold text-center py-2">No codes yet.</p>
                      ) : couponCodes.map(code => (
                        <div key={code.id} className="p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl flex items-center justify-between">
                          <div>
                            <p className="text-xs font-black text-white">{code.id}</p>
                            <p className="text-[10px] font-bold text-gray-500 mt-0.5">{code.usedBy ? 'Used' : 'Available'}</p>
                          </div>
                          {code.usedBy && <CheckCircle className="w-4 h-4 text-[#BEF264]" />}
                        </div>
                      ))}
                    </div>
                  </div>
                </>
              )}
            </motion.div>
          </div>
        )}
      </AnimatePresence>

    </div>
  );
}

function AdminActionCard({ icon: Icon, title, subtitle, onClick, destructive = false, loading = false, active = false }: any) {
  return (
    <button onClick={onClick} disabled={loading} className={`w-full flex items-start gap-4 p-5 rounded-3xl border transition-all text-left ${destructive ? 'bg-red-500/5 border-red-500/20 hover:bg-red-500/10' : active ? 'bg-[#BEF264]/5 border-[#BEF264]/30 hover:bg-[#BEF264]/10' : 'bg-[#0B1221] border-[#1E293B] hover:bg-[#1E293B]/50 hover:border-white/10'}`}>
      <div className={`w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 ${destructive ? 'bg-red-500/10 text-red-500' : active ? 'bg-[#BEF264]/20 text-[#BEF264]' : 'bg-[#1E293B] text-[#BEF264]'}`}>
        {loading ? <div className="w-5 h-5 border-2 border-current border-t-transparent rounded-full animate-spin" /> : <Icon className="w-6 h-6" />}
      </div>
      <div className="flex-1 pt-1">
        <h3 className={`text-sm font-black ${destructive ? 'text-red-500' : 'text-white'}`}>{title}</h3>
        <p className={`text-xs font-semibold mt-1 leading-relaxed ${destructive ? 'text-red-400/80' : 'text-gray-400'}`}>{subtitle}</p>
      </div>
    </button>
  );
}
